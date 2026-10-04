---
name: postgres-schema
description: "PostgreSQL schema design, migration safety, and index conventions - and the router that decides which class-specific PostgreSQL skill to load. Use when designing a table, writing or reviewing a database migration, choosing a primary key type, adding an index, naming tables or columns, or deciding between logical and physical deletes. Also triggers on strong_migrations, schema_format, CREATE INDEX CONCURRENTLY, invalid index, reversible migration, irreversible migration, rollback, down migration, expand and contract, backfill, lock_timeout, NOT VALID, VALIDATE CONSTRAINT, table rewrite, uuidv7, timestamptz, soft delete, deleted_at, foreign key cascade, ON DELETE, partial index, N+1, strict_loading, connection pooling, pgbouncer, pgvector, and third-party schemas such as stripe.* or plaid.*. Start here for any PostgreSQL work, then load postgres-lax, postgres-strict or postgres-analytics as this skill directs."
---

# PostgreSQL Schema Design

This skill is the entry point for all PostgreSQL work. It does three things, in order:

1. **Classifies the application**, because every later decision leans on the class.
1. **Points you at the class-specific skill** that carries the recipes for that class.
1. **Names the handful of rules whose violation is silent and expensive**, so they are in front of you even if you read nothing else.

## Step zero, and it is not optional

**Classify the application before applying any rule.** There are three classes:

| Class          | Shape                                                                                                                                                         | Then load            |
| :------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ | :------------------- |
| `PG-lax`       | OLTP, non-critical. Speed over strictness. <br />Physical deletes, `ON DELETE CASCADE`. Scales by adding read replicas.                                       | `postgres-lax`       |
| `PG-strict`    | OLTP holding money, PII, health records or anything <br />with legal consequence. Immutability, audit trails, row-level <br />security, logical deletes only. | `postgres-strict`    |
| `PG-analytics` | Warehouse. Batch ingestion, partitions, materialized views, <br />few concurrent users running long queries.                                                  | `postgres-analytics` |

**If the project's `AGENTS.md` or `CLAUDE.md` does not state the class, stop and ask the application developers.** Then write the answer into that file so nobody has to ask again.

### The default, and the per-table escalation

**Default to `PG-lax`.** Most applications are, and pretending otherwise buys ceremony rather than safety.

**Then escalate per table, not per application.** Any table that holds money, PII, health data, or anything with a legal consequence adopts the `PG-strict` rules *for that table* - logical deletes, audit trail, explicit `ON DELETE`, locking discipline - while the rest of the schema stays lax. A social app with a `payments` table is a lax application with three strict tables, and that is the honest description of most systems.

An application is `PG-strict` as a whole when the strict tables are the point of the product rather than a corner of it.

## Routing

Once the class is settled, **invoke the matching skill by name** and read its references:

```text
PG-lax        ->  postgres-lax        (replica topology, read/write routing, physical deletes)
PG-strict     ->  postgres-strict     (RLS, audit trails, encryption, locking, logical deletes)
PG-analytics  ->  postgres-analytics  (partitioning, materialized views, batch ingestion)
```

Each of those skills assumes you have already read [`references/core.md`](references/core.md) from this one. They carry only the deltas and the class-specific recipes, not a second copy of the universal rules.

```mermaid
---
config:
  layout: elk
  theme: forest
---
flowchart TB
    A[PostgreSQL work starts] --> B[postgres-schema: read references/core.md]
    B --> C{Class stated in AGENTS.md or CLAUDE.md?}
    C -->|No| D[Ask the developers, then record it there]
    D --> C
    C -->|Yes| E{Which class?}
    E -->|PG-lax| F[postgres-lax]
    E -->|PG-strict| G[postgres-strict]
    E -->|PG-analytics| H[postgres-analytics]
    F --> I{This table holds money, PII or legal data?}
    I -->|Yes| G
    I -->|No| J[Apply lax defaults]
```

## When NOT to use

- Operating a database - backups, replicas, failover, monitoring. That is the `cloud-sql-postgresql:*` skills, which cover GCP Cloud SQL operations.
- Query tuning against a live plan. Read the Indexes section of `core.md`, but the work is `EXPLAIN (ANALYZE, BUFFERS)`, not a convention lookup.

## The rules that fail silently

Everything else is in the reference files. These are the ones where a wrong answer passes review and surfaces later as an outage, a lock, or a leak. They hold for **every** class:

1. **Migrations are production operations, not schema edits.** `add_index` on a populated table needs `algorithm: :concurrently` **and** `disable_ddl_transaction!`, alone in its own migration.
1. **`lock_timeout` is not optional on any `ALTER TABLE`.** A migration that never runs still takes the site down while it queues, because every later query queues behind its pending **`ACCESS EXCLUSIVE`** lock.
1. **Never add `null: false` to an existing column directly.** Add a `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE CONSTRAINT` separately, then `SET NOT NULL` - PG 12+ accepts the validated constraint as proof.
1. **`schema_format = :sql`.** `schema.rb` silently drops partial indexes, expression indexes, exclusion constraints, generated columns and extensions.
1. **Primary keys carry no business meaning, ever, and are never composite.** On PG 18 prefer `uuidv7()`; it keeps insert locality that `uuidv4()` destroys. Weigh one tradeoff: v7 leaks creation time to anyone holding the ID.
1. **Foreign keys on every reference, with `ON DELETE` stated explicitly.** Rails validations are not constraints. The right `ON DELETE` is class-dependent; leaving it unstated means `NO ACTION`, which is a decision nobody made.
1. **`timestamptz`, never `timestamp`.**
1. **Third-party data lives in its own schema** (`stripe.*`, `plaid.*`), never in `public`.

## Composite index ordering

The one rule worth carrying in your head rather than looking up: **equality columns first, then range/inequality, then sort.** `(account_id, created_at)` serves `WHERE account_id = ? ORDER BY created_at DESC LIMIT 20`; `(created_at, account_id)` serves it not at all. Selectivity is a tiebreaker, not the criterion.

Then read the files for the rest.

## Migrations Regardless of the Language

Most frameworks have some form of migrations. Rails has them, _sqlx for Rust has them, etc. But not all of them insist on things that are important to us:

1. Keep migrations in a folder called `db/migrations` under whatever app they are for

2. Keep the database configuration parameters in `db/config/database.yml` under whatever app they are for, just like Rails does. Rust or other languages parse the YAML file, and use liquid tags inside to allow for environment to be inserted into the YAML file using eg (for Rust: https://docs.rs/liquid/latest/liquid/) and liquid's support for environment variables.

3. **For each migration up there must be a down migration.** If the command to migrate all, migrate up one, or migration down one are complex, simplify them by providing 

   1. ###### **`just db-migrate`,**

   2. ###### `just db-migrate-up [ <migration-number> ]` 

   3. **`just db-migration-down [ <migration-number> ]`**

   4. If migration number is not specified, assume the last migration. So **`just db-migrate-down`** applies to the last applied migration.

4. Keep migrations short: no more than a single table create, modify, or backfill + constraints, indexes and foreign keys. 

5. All boolean columns are named **`is_something`** not just `something`.  For example: **`is_active`**

6. All timestamps have a datatype **timestampz**  and columns must have `_at` extension, `created_at` and `updated_at` (two columns that almost always you want to add to the tables, except for append only, they do not need `updated_at`)

7. All date columns have suffix `_on` such as `published_on` 

8. All ids use **uuidv7** unless specified otherwise. 

The rules below are the summary. `migrations.md` in this directory is the long form, and it is where reversibility, the mechanics and failure modes of concurrent index builds, transactional DDL, expand/contract and batched backfills are actually explained. Read it before migrating a table that has rows in it.

Install `strong_migrations` - it will catch the classics before your DBA (or your 3am pager) does. The non-negotiables on PostgreSQL: `add_index` on any table with real rows must be `algorithm: :concurrently` with `disable_ddl_transaction!`; never combine that migration with anything else.

Adding a column with a default is safe on PG 11+, but adding `null: false` to an existing column is not - add a `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE CONSTRAINT` in a separate migration, then `SET NOT NULL`, which PG 12+ will accept using the validated constraint as proof.

Backfills belong in their own batched migration or a rake task, never in the same transaction as DDL. Renaming and dropping columns require the ignored-column dance (`self.ignored_columns +=`, deploy, then drop) because your old app processes are still running mid-deploy.

And switch to `schema_format = :sql`; `schema.rb` silently loses partial indexes, expression indexes, exclusion constraints, generated columns, and every extension you care about.

## Where to find Additional Information

> [!IMPORTANT]
> **The class-independent conventions are not written here.** Read them in: 
>
> [`references/core.md`](references/core.md) - decades of accumulated practice, and the single source of truth for everything that is true regardless of application class. **Read that file before writing schema**
>
> [`references/migrations.md`](references/migrations.md) is the long form on migration safety: reversibility, concurrent index builds and the `INVALID` index a failed one leaves behind, transactional DDL and its edges, expand/contract, the changes that rewrite the table, and batched backfills. **Read it before writing Rails migrations that runs against a table with rows in it.**
>
> [`references/autovacuum.md`](references/autovacuum.md) covers autovacuum and transaction ID wraparound: read it before touching autovacuum settings, and before assuming a wraparound warning can wait.
