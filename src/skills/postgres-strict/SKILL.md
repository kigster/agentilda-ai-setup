---
name: postgres-strict
description: "Conventions and recipes for PG-strict PostgreSQL applications - OLTP holding money, PII, health records or anything with legal consequence. Covers logical deletes with deleted_at, partial indexes, immutable ledgers, trigger-based audit trails, row-level security and multi-tenancy, column encryption with pgcrypto, grants and least privilege, and the locking discipline (SELECT FOR UPDATE, SERIALIZABLE with retries, deadlock ordering, advisory locks) that money tables require. Use after the postgres-schema skill has classified the application or a specific table as PG-strict, or when the work involves RLS, CREATE POLICY, audit triggers, soft delete, deleted_at, tenant isolation, encryption at rest, or lost-update bugs."
---

# PG-strict: Nothing Is Lost, Nothing Is Unwatched

> [!IMPORTANT]
> **Read [`postgres-schema/references/core.md`](../postgres-schema/references/core.md) first.** It carries the class-independent rules - naming, primary keys, migration safety, timeouts, index mechanics, money, pooling, observability - and this skill does not repeat them. If you arrived here directly, invoke the `postgres-schema` skill and read its core reference before writing anything.

`PG-strict` covers applications that manage money, taxes, health records, or a significant amount of PII, where a mistake, a leak, or a corruption costs real money and may be legally actionable. It also covers **individual tables inside an otherwise `PG-lax` application** - the `payments` table in a social app is strict even if nothing else is.

Everything here is a baseline, not advanced technique. Skipping it produces bugs that appear only under load, only in production, and only in ways that cost money.

## The defaults

| Decision           | `PG-strict` answer                                                                                                 |
| :----------------- | :----------------------------------------------------------------------------------------------------------------- |
| Deletes            | Logical only. `deleted_at timestamptz`, never `DELETE FROM`.                                                       |
| `ON DELETE`        | `RESTRICT` or `NO ACTION` on the constraint; propagation is done by the application setting `deleted_at`.          |
| Mutation           | Prefer append-and-amend over update-in-place for ledgers and transactions.                                         |
| Isolation          | `SELECT ... FOR UPDATE` by default; `SERIALIZABLE` with a retry loop where the invariant spans rows.               |
| Primary key        | `uuidv7()`, unless creation time is itself sensitive, in which case `uuidv4()`.                                    |
| Replica reads      | Display paths only. Never for a read that feeds a write decision.                                                  |
| Audit trails       | Yes, per table, by trigger. See [`references/audit-trails.md`](references/audit-trails.md).                        |
| Row-level security | Yes. Tenant isolation is enforced in the database. See [`references/rls.md`](references/rls.md).                   |
| Encryption         | At rest always; per column where the data warrants it. See [`references/encryption.md`](references/encryption.md). |
| Grants             | Least privilege, per role, no `GRANT ALL`.                                                                         |

## Logical deletes

Every table carries `deleted_at timestamptz` (nullable, null meaning live). Nothing is ever physically deleted, which is what lets you restore an account, answer an auditor, or assist a lawful investigation two years later.

```sql
ALTER TABLE invoices ADD COLUMN deleted_at timestamptz;

-- live rows only, and the index stays small because most reads only want those
CREATE INDEX CONCURRENTLY index_invoices_on_account_id_live
  ON invoices (account_id, created_at DESC)
  WHERE deleted_at IS NULL;

-- uniqueness applies to live rows only, so a deleted row does not block a new one
CREATE UNIQUE INDEX CONCURRENTLY index_invoices_on_number_live
  ON invoices (account_id, number)
  WHERE deleted_at IS NULL;
```

Three consequences to hold in your head:

1. **Partial indexes on `deleted_at IS NULL` belong on nearly everything.** They are the single most underused feature in Postgres, and in a soft-delete schema they are also the smallest useful index you can build.
1. **A logical delete costs the same dead tuple a physical one would.** See the MVCC note in `core.md`. You buy the data, not a cheaper vacuum.
1. **The partial index disqualifies the update from HOT**, because HOT eligibility considers every column any index references, including a predicate. This is the tradeoff spelled out in `core.md` under Indexes, and for `PG-strict` the partial index is still nearly always correct: the read pattern dominates, and `deleted_at IS NULL` appears in essentially every query.

Deletion **propagates in the application**, not in the constraint: setting `deleted_at` on a parent means setting it on the dependent rows in the same transaction. The foreign key stays `RESTRICT` so that a physical delete, if anybody ever writes one, fails loudly.

### If your backend is Ruby on Rails

Two battle-tested gems implement this:

- <https://github.com/jhawthorn/discard>
- <https://github.com/rubysherpas/paranoia>

`discard` is the safer default: it does not override `destroy`, so nothing deletes by accident when a caller forgets which gem is loaded.

## Immutability beats locking where it fits

The characteristic `PG-strict` pattern is an append-only ledger: to correct a transaction you insert a compensating one rather than updating the original. Inserts do not conflict with each other, so the contention disappears entirely and the audit trail is the table itself.

Enforce it rather than documenting it:

```sql
CREATE FUNCTION forbid_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'ledger_entries is append-only (attempted %)', TG_OP;
END;
$$;

CREATE TRIGGER ledger_entries_immutable
  BEFORE UPDATE OR DELETE ON ledger_entries
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
```

Where the domain does not permit append-only, fall back to the locking discipline below.

## Concurrency control, and why it is mandatory here

`READ COMMITTED` gives each *statement* a fresh snapshot, so a read-modify-write across statements is a lost-update bug with a race window as wide as your application latency. The three ways out, in the order you should reach for them:

1. **`SELECT ... FOR UPDATE`** - take the row lock as part of the read. The second transaction blocks until the first commits, then sees the committed value. In Rails this is `record.lock!` or `Model.lock.find(id)`. This is the right answer the overwhelming majority of the time.
1. **`SERIALIZABLE`** - Postgres implements true serializable snapshot isolation, and it is genuinely correct. The price is that transactions can fail at `COMMIT` with a serialization failure, so **every** `SERIALIZABLE` transaction needs a retry loop. No retry loop, no serializable isolation; you have merely moved the bug into an error class.
1. **Optimistic locking** - a `lock_version` column, Rails' default. Fine for user-edited records where a conflict is rare and a human can retry. Wrong for machine-driven contention, where you get a retry storm.

```ruby
# The balance is read and written under the same lock
ApplicationRecord.transaction do
  account = Account.lock.find(account_id)          # SELECT ... FOR UPDATE
  account.update!(balance_cents: account.balance_cents - amount_cents)
end
```

**Deadlocks are an ordering problem, not a locking problem.** Two transactions that lock rows A then B, and B then A, will eventually deadlock; Postgres detects it and kills one after `deadlock_timeout`. The fix is a rule the whole codebase follows - always lock in ascending primary key order, always parent before child - not a bigger lock.

**Advisory locks** (`pg_advisory_xact_lock`) are for mutual exclusion over something that is not a row: a nightly job that must not run twice, a per-tenant serialization point. Use the transaction-scoped variant so the lock releases on commit or rollback rather than leaking when a process dies. Session-scoped advisory locks and transaction pooling are incompatible.

## Reads that must be authoritative do not go to a replica

A balance you are about to debit, a uniqueness check, an entitlement check - these read from the primary, under `FOR UPDATE` if the answer feeds a write. Retry-on-miss against a replica is a display-path pattern; using it on a correctness path converts replication lag into a money bug. The replica topology itself is in the `postgres-lax` skill, `references/replicas.md`.

## The references

| File                                                       | Read it when                                                                                             |
| :--------------------------------------------------------- | :------------------------------------------------------------------------------------------------------- |
| [`references/rls.md`](references/rls.md)                   | Multi-tenant data, per-row access control, `CREATE POLICY`, `BYPASSRLS`, connection-pooling interactions |
| [`references/audit-trails.md`](references/audit-trails.md) | Recording who changed what and when, trigger patterns, retention                                         |
| [`references/encryption.md`](references/encryption.md)     | Column encryption, `pgcrypto`, key custody, TLS, grants and least privilege                              |
