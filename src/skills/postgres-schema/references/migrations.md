# PostgreSQL: Migration Safety

Everything here is engine-level and holds in any framework and any application class. `core.md` states the Rails-flavoured summary and the timeout rules; this file is the long form, and the two agree. Read this before writing a migration that runs against a table with real rows in it.

The organising idea is simple. **A migration is a production operation that happens to change schema.** It runs against a live database, alongside live traffic, while two versions of the application are deployed at once. Every rule below follows from that sentence.

## The three questions, before writing a line

1. **What lock does this take, and for how long?** A lock held for 50ms is invisible. **The same lock held for 40 seconds is an outage, because everything arriving behind it queues.**
1. **Can the currently deployed application still run against the schema this produces?** During a rolling deploy, old and new code talk to one database. A schema only the new code understands breaks the old processes that have not been replaced yet.
1. **How do I get back?** Either a `down` that works, or a forward fix. Deciding this afterwards, at 3am, is how a bad migration becomes a bad night.

## Reversibility

**Write the `down` and run it.** Not "it looks reversible" - actually apply the migration, apply the rollback, apply it again. A `down` that has never executed is a comment.

Frameworks infer the reverse of a declarative change (`add_column` reverses to `drop_column`) and that inference is reliable. It stops being reliable the moment the migration contains raw SQL or data movement, and the honest options then are two:

```ruby
# Reversible, because the reverse is stated rather than guessed.
def up
  execute "ALTER TABLE invoices ADD COLUMN currency text"
end

def down
  execute "ALTER TABLE invoices DROP COLUMN currency"
end
```

```ruby
# Not reversible, and says so, which is better than a `down` that lies.
def up
  execute "UPDATE invoices SET currency = 'USD' WHERE currency IS NULL"
end

def down
  raise ActiveRecord::IrreversibleMigration, "the original NULLs are gone"
end
```

**Some things genuinely cannot be reversed, and the correct response is to make them unnecessary rather than to fake them.** Dropping a column destroys the data in it, and no `down` brings it back. That is the entire argument for expand/contract below: the reversible step and the destructive step go in different deploys, so the only migration you ever need to roll back is a reversible one.

Three rules that keep rollback real:

- **Never mix DDL and data in one migration.** Reversing the schema is mechanical; reversing a backfill is usually impossible, because the pre-backfill values are gone.
- **A destructive migration is its own deploy, and it goes last.** By the time it runs, the application has already been running without that column or table for a full release. If something was still reading it, you found out before deleting anything.
- **On a large table, prefer a forward fix to a rollback.** Rolling back a change that took an hour to apply means an hour of the same lock pressure again, in the opposite direction, during an incident. A small corrective migration forward is faster and calmer.

## Building indexes concurrently

`CREATE INDEX` takes a lock that blocks every write to the table for the whole build. On a table of any size that is an outage. `CREATE INDEX CONCURRENTLY` exists so it is not, and it comes with four constraints that are easy to get wrong.

```sql
CREATE INDEX CONCURRENTLY idx_invoices_account_id ON invoices (account_id);
DROP INDEX CONCURRENTLY idx_invoices_legacy;
```

```ruby
class AddIndexOnInvoicesAccountId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!                              # required: see below
  def change
    add_index :invoices, :account_id, algorithm: :concurrently
  end
end
```

**It cannot run inside a transaction block.** This is the reason for `disable_ddl_transaction!`, and it is not a formality the framework invented. PostgreSQL rejects the statement outright inside an explicit transaction, because the build makes two passes over the table and has to commit between them.

**Which means the migration is not atomic, so it must contain nothing else.** With the transaction disabled, a migration that creates an index and then does one more thing can fail halfway and leave the database in a state neither the `up` nor the `down` describes. One concurrent index, one migration, nothing else in the file.

**A failed build leaves an `INVALID` index behind, and it is not free.** The index does not get used by the planner, so it gives you nothing, but it is still maintained on every write, so it costs you on every write. Nothing cleans it up automatically. Find them and drop them:

```sql
SELECT c.relname AS invalid_index, t.relname AS table_name
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_class t ON t.oid = i.indrelid
 WHERE NOT i.indisvalid;

DROP INDEX CONCURRENTLY idx_invoices_account_id;   -- then create it again
```

Make this check part of the runbook for a failed index migration. The retry is `DROP INDEX CONCURRENTLY` followed by a fresh `CREATE INDEX CONCURRENTLY`, never a plain re-run on top of the wreckage.

**It is slower, and it waits for transactions you do not control.** A concurrent build takes roughly twice the work of a plain one and will not finish until every transaction that started before it has ended. One connection left idle inside `BEGIN` stalls the build indefinitely while the build holds back the vacuum horizon behind it. Check `pg_stat_activity` for long-running and `idle in transaction` sessions before starting, not after it has been running for an hour.

`DROP INDEX` deserves the same treatment for the same reason, and `REINDEX CONCURRENTLY` rebuilds a bloated index in place without the lock.

## Transactional DDL, and its edges

PostgreSQL wraps DDL in transactions, which most databases do not. A migration that adds three columns either adds all three or none, and a failure halfway leaves nothing behind. That is a real advantage and worth relying on.

The edges are worth knowing precisely:

- `CREATE INDEX CONCURRENTLY`, `DROP INDEX CONCURRENTLY`, `REINDEX CONCURRENTLY`, `VACUUM`, `CREATE DATABASE` and `ALTER SYSTEM` cannot run inside a transaction at all.
- A long migration inside one transaction holds every lock it has taken until it commits. Ten quick `ALTER TABLE`s in one transaction hold ten `ACCESS EXCLUSIVE` locks for the duration of the slowest one. Splitting them into separate migrations releases each lock as it finishes.
- A transaction that runs for a long time holds back the vacuum horizon for the whole cluster. See `autovacuum.md`.

So: rely on transactional DDL for a handful of related, fast statements, and split anything slow.

## Expand and contract, which is how the risky changes get made

Any change that removes or renames something has to be done in stages, because a rolling deploy runs old and new code against one schema. The pattern is the same every time:

| Deploy | Step         | What happens                                                                              |
| :----- | :----------- | :---------------------------------------------------------------------------------------- |
| 1      | **Expand**   | Add the new column or table. Nullable, no default that rewrites, additive only.           |
| 2      | **Backfill** | Populate it in batches, outside DDL. The application still reads the old thing.           |
| 3      | **Migrate**  | Write to both, read from the new one. Old processes keep working off the old column.      |
| 4      | **Contract** | Stop referencing the old thing in code, ship it, and only then drop it in its own deploy. |

Renaming a column is this pattern, not a `RENAME`. A bare `ALTER TABLE ... RENAME COLUMN` is instant and cheap at the database level and still breaks the site, because every already-running application process is still selecting the old name.

In Rails the contract step needs `self.ignored_columns += ["old_name"]` deployed and live **before** the drop, so that the running processes stop putting the column in their `SELECT` lists.

## The changes that rewrite the table

A rewrite means every row is copied under an `ACCESS EXCLUSIVE` lock. Assume minutes to hours on a large table, and assume the site is down for it.

- **Changing a column type** usually rewrites. `varchar(50)` to `varchar(100)` and `varchar` to `text` do not. `integer` to `bigint` does, on versions before it was optimised, and the safe route on a big table is a new column plus expand/contract.
- **Adding a column with a volatile default** rewrites. A constant default does not on PG 11 and later, which stores it in the catalog; `DEFAULT now()` is not constant.
- **Adding `NOT NULL` to an existing column** scans the whole table under the lock. The safe route is three steps:

```sql
ALTER TABLE invoices ADD CONSTRAINT invoices_currency_not_null
  CHECK (currency IS NOT NULL) NOT VALID;       -- instant, no scan

ALTER TABLE invoices VALIDATE CONSTRAINT invoices_currency_not_null;
                                                -- scans without blocking writes

ALTER TABLE invoices ALTER COLUMN currency SET NOT NULL;
                                                -- PG 12+ uses the constraint as proof
```

`NOT VALID` plus `VALIDATE CONSTRAINT` is the general shape and applies to foreign keys too: add the key `NOT VALID` so it takes effect for new rows immediately without scanning, then validate the existing rows in a second migration under a weaker lock.

## Backfills

A backfill is not a migration, whatever directory it lives in. `UPDATE invoices SET currency = 'USD'` on ten million rows is one transaction, one long-held snapshot, a great deal of WAL, dead tuples autovacuum cannot touch until it commits, and replication lag on every replica.

Batch it, commit each batch, and pause between them:

```sql
UPDATE invoices SET currency = 'USD'
 WHERE id IN (SELECT id FROM invoices WHERE currency IS NULL LIMIT 5000);
```

Run it from a task or a job, not from a migration, so it can be stopped, resumed and re-run. Make it idempotent, which the `WHERE currency IS NULL` above does for free. On an application with replicas, check replication lag between batches and slow down when it grows.

## Locks and timeouts

Covered in full in `core.md` under "Timeouts, and why a migration takes the site down without ever running", and it is the single most important section for migration safety. The summary: set `lock_timeout` low so a migration that cannot get its lock fails immediately instead of queueing every query in the application behind it, and retry rather than wait.

## Checklist

- [ ] The `down` has been executed, or the migration declares itself irreversible.
- [ ] No DDL and data change share a migration.
- [ ] `lock_timeout` is set.
- [ ] A concurrent index build is alone in its migration, with the DDL transaction disabled.
- [ ] Nothing dropped or renamed in the same deploy that stopped using it.
- [ ] Anything that rewrites the table has been identified as such, and sized against the real row count.
- [ ] Backfills are batched, idempotent, and run outside the migration.
- [ ] `schema_format` is `:sql`, so partial indexes, expression indexes and extensions survive the dump.
