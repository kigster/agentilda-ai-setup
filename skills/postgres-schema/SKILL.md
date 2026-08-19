---
name: postgres-schema
description: "PostgreSQL schema design, migration safety, and index conventions. Use when designing a table, writing or reviewing a database migration, choosing a primary key type, adding an index, naming tables or columns, or deciding between logical and physical deletes. Also triggers on strong_migrations, schema_format, concurrent index, uuidv7, timestamptz, soft delete, deleted_at, foreign key cascade, ON DELETE, partial index, N+1, strict_loading, and third-party schemas such as stripe.* or plaid.*. Useful for greenfield schema design and for reviewing a migration diff before it reaches production."
---

# PostgreSQL Schema Design

> [!IMPORTANT]
> **The conventions are not written here.** They live in
> [`~/.agents/context/postgresql.md`](../../context/postgresql.md) — decades of
> accumulated practice, and the single source of truth. **Read that file before
> writing schema or migration code.** This skill exists to make sure you do,
> and to name the handful of rules whose violation is silent and expensive.

## When to use

- Designing a new table, or changing an existing one.
- Writing a migration, or reviewing one in a diff.
- Choosing a primary key type, or an index.
- Deciding how deletes work for a table.
- Integrating a third party whose data you mirror (Stripe, Plaid, …).

## When NOT to use

- Operating a database — backups, replicas, failover, monitoring. That is the
  `cloud-sql-postgresql:*` skills, which cover GCP Cloud SQL operations.
- Query tuning against a live plan. Read the file's Indexes section, but the
  work is `EXPLAIN (ANALYZE, BUFFERS)`, not a convention lookup.

## Step zero, and it is not optional

**Classify the application before applying any rule.** The conventions change
by class, and the file is explicit that this must be settled first:

| Class | Shape |
| :---- | :---- |
| `PG-lax` | non-critical; physical deletes are the norm; speed over strictness |
| `PG-traditional` | referential integrity matters; delete strategy is a production decision |
| `PG-strict` | money, PII, health records; immutability, audit trails, **logical deletes only** |
| `PG-analytics` | warehouse; materialized views, batch ingestion, rare deletes |

Ask the user, or read it from the spec. Then **record the answer in the
project's `AGENTS.md`/`CLAUDE.md`**, because every later decision leans on it.

## The rules that fail silently

Everything else is in the file. These are the ones where a wrong answer passes
review and surfaces later as an outage, a lock, or a leak:

1. **Migrations are production operations, not schema edits.** `add_index` on a
   populated table needs `algorithm: :concurrently` **and**
   `disable_ddl_transaction!`, alone in its own migration.
2. **Never add `null: false` to an existing column directly.** Add a
   `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE CONSTRAINT` separately, then
   `SET NOT NULL` — PG 12+ accepts the validated constraint as proof.
3. **`schema_format = :sql`.** `schema.rb` silently drops partial indexes,
   expression indexes, exclusion constraints, generated columns and extensions.
4. **Primary keys carry no business meaning, ever, and are never composite.**
   On PG 18 prefer `uuidv7()`; it keeps insert locality that `uuidv4()` destroys.
   Weigh one tradeoff: v7 leaks creation time to anyone holding the ID.
5. **Foreign keys on every reference, with `ON DELETE` stated explicitly.**
   Rails validations are not constraints.
6. **`timestamptz`, never `timestamp`.**
7. **Soft-delete apps want partial indexes** — `WHERE deleted_at IS NULL` on
   nearly everything. It is the file's single most underused feature.
8. **Third-party data lives in its own schema** (`stripe.*`, `plaid.*`), never
   in `public`.

## Composite index ordering

The one rule worth carrying in your head rather than looking up: **equality
columns first, then range/inequality, then sort.** `(account_id, created_at)`
serves `WHERE account_id = ? ORDER BY created_at DESC LIMIT 20`;
`(created_at, account_id)` serves it not at all. Selectivity is a tiebreaker,
not the criterion.

Then read the file for the rest.
