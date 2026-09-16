---
name: postgres-lax
description: "Conventions and recipes for PG-lax PostgreSQL applications - non-critical OLTP where development speed beats strictness: physical deletes, ON DELETE CASCADE, READ COMMITTED with optimistic locking, and scaling by putting many read replicas behind one primary. Use after the postgres-schema skill has classified the application as PG-lax, or when working on read replicas, replication lag, read/write splitting, DatabaseSelector, connected_to, replica routing, cascade deletes, or pgbouncer topology for a lax application."
---

# PG-lax: Move Fast, Scale With Replicas

> [!IMPORTANT]
> **Read [`postgres-schema/references/core.md`](../postgres-schema/references/core.md) first.** It carries the class-independent rules - naming, primary keys, migration safety, timeouts, index mechanics, money, pooling, observability - and this skill does not repeat them. If you arrived here directly, invoke the `postgres-schema` skill and read its core reference before writing anything.

`PG-lax` is the honest default for most applications: a game, a social app, an internal tool, a marketplace's non-financial half. The cost of an invalid reference or a missed insert is low, the cost of slow development is high, and the database should stay out of the way.

**It is a default, not a licence.** The moment a table holds money, PII, health data or anything with a legal consequence, that table follows the `postgres-strict` rules even though the rest of the schema stays here. See the escalation rule in `core.md`.

## The defaults

| Decision            | `PG-lax` answer                                                                                     |
| :------------------ | :-------------------------------------------------------------------------------------------------- |
| Deletes             | Physical. `DELETE FROM`. No `deleted_at` unless the product asks for undo.                          |
| `ON DELETE`         | `CASCADE` for owned children, `SET NULL` for optional references. Still written explicitly, always. |
| Isolation           | `READ COMMITTED` plus optimistic locking (`lock_version`).                                          |
| Primary key         | `bigint` identity is fine. Use `uuidv7()` when IDs appear in URLs.                                  |
| Replica reads       | The default for read paths. Retry on miss.                                                          |
| Audit trails        | No. Add them per table if a table escalates to strict.                                              |
| Row-level security  | No. Tenant scoping in the application is acceptable here.                                           |
| `statement_timeout` | 30s or lower on the web role. Non-negotiable even here.                                             |

## Physical deletes, and the one thing to get right

Physical deletes are cheap to write and honest about intent: the row is gone, no query needs a `WHERE deleted_at IS NULL` predicate, no partial index is required, and `UPDATE`s stay HOT-eligible because nothing indexes a nullable timestamp.

**The failure mode is the cascade you did not draw.** `ON DELETE CASCADE` is transitive: deleting one `users` row can walk `posts`, `comments`, `reactions`, `notifications` and take a lock on each, in one transaction, for as long as it takes. On a large graph that is a long-held lock and a large dead-tuple burst that autovacuum then has to clear.

Two habits keep it safe:

1. **Draw the cascade graph before you rely on it.** If deleting one row touches more than a few thousand rows, delete in batches from a background job instead of letting the constraint do it in one transaction.
1. **`RESTRICT` the edges you never want walked.** A `users` row that owns `invoices` should not be deletable at all; that is what `RESTRICT` says, and it says it in the database rather than in a code review comment.

```sql
-- owned children: go with the parent
ALTER TABLE comments
  ADD CONSTRAINT comments_post_id_fkey
  FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE;

-- optional reference: survive the parent
ALTER TABLE posts
  ADD CONSTRAINT posts_featured_by_id_fkey
  FOREIGN KEY (featured_by_id) REFERENCES users (id) ON DELETE SET NULL;

-- anything with consequences: refuse
ALTER TABLE invoices
  ADD CONSTRAINT invoices_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT;
```

## Locking: what lax is allowed to skip

`READ COMMITTED` and optimistic locking are fine for user-edited records where conflicts are rare and a human can retry. That is the whole policy, and it covers most of a lax schema.

**Where it stops being fine, even in a lax app:**

- Any counter or balance incremented by concurrent processes. Use `UPDATE ... SET n = n + 1` (atomic in the database) rather than read-modify-write in the application, or take `SELECT ... FOR UPDATE`.
- Any job that must not run twice. Use a transaction-scoped advisory lock, `pg_advisory_xact_lock`, never a session-scoped one behind a transaction pooler.
- Anything escalated to strict. Read the locking section of `postgres-strict`.

## Scaling: one primary, many replicas

This is the characteristic `PG-lax` shape, and the reason this skill exists. **Read [`references/replicas.md`](references/replicas.md)** before adding a replica, before routing a read, and before debugging a "the record I just created is not there" report.

The short version:

- Replication lag is never zero. Design for it rather than trying to remove it.
- Route reads to replicas by default, and fall back to the primary when the row is not there yet.
- Authoritative reads - anything feeding a write decision - go to the primary, always.
- One pooler per replica, transaction mode, sized by `(cores x 2) + spindles`, not by hope.
