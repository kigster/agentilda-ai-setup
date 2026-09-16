---
name: postgres-analytics
description: "Conventions and recipes for PG-analytics PostgreSQL instances - warehouses and reporting databases with batch ingestion, few concurrent users and long-running queries. Covers declarative partitioning and partition pruning, retention by DROP PARTITION, materialized views and refresh strategy, COPY-based bulk loading, staging-table upserts, BRIN indexes, and the server settings (work_mem, maintenance_work_mem, statement_timeout, parallelism) that a warehouse needs and an OLTP database does not. Use after the postgres-schema skill has classified the instance as PG-analytics, or when the work involves PARTITION BY RANGE, CREATE MATERIALIZED VIEW, REFRESH CONCURRENTLY, COPY, pg_partman, BRIN, star schema or fact and dimension tables."
---

# PG-analytics: Load It Fast, Query It Long, Drop It By Partition

> [!IMPORTANT]
> **Read [`postgres-schema/references/core.md`](../postgres-schema/references/core.md) first.** It carries the class-independent rules - naming, primary keys, migration safety, index mechanics, money, observability - and this skill does not repeat them. If you arrived here directly, invoke the `postgres-schema` skill and read its core reference before writing anything.

A `PG-analytics` instance is a different machine with a different job: a handful of concurrent users, queries measured in seconds or minutes rather than milliseconds, data arriving in batches, and almost nothing ever deleted a row at a time.

**It is a separate instance.** Running reporting queries against the OLTP primary is the most common and most expensive mistake in this area: one analyst's unbounded `GROUP BY` holds a snapshot open for twenty minutes, autovacuum accomplishes nothing while it runs, and the transaction ID horizon stops moving. Feed the warehouse from a replica or by logical replication, and let the analysts have it.

## The defaults

| Decision            | `PG-analytics` answer                                                                        |
| :------------------ | :------------------------------------------------------------------------------------------- |
| Deletes             | By partition. `DROP TABLE` the month, never `DELETE ... WHERE created_at < ?`.               |
| `ON DELETE`         | `RESTRICT`. Dimension rows are not deleted while facts reference them.                       |
| Primary key         | `bigint` identity on facts. UUIDs cost 8 bytes per row across billions and buy nothing here. |
| Isolation           | `READ COMMITTED`. Long readers, so mind `hot_standby_feedback` upstream.                     |
| `statement_timeout` | Minutes, not seconds - the opposite of the OLTP rule, and set per role.                      |
| Indexes             | Few. BRIN on the time column, B-tree on the dimension keys actually joined.                  |
| Normalization       | Star schema: narrow dimensions, wide append-only facts. Denormalize deliberately.            |

## Settings that differ from OLTP

A warehouse is not a big OLTP box, and the defaults inherited from one will make it slow:

```sql
ALTER ROLE analyst SET statement_timeout = '30min';
ALTER ROLE analyst SET work_mem = '256MB';          -- per sort/hash node, per query
ALTER ROLE analyst SET default_transaction_read_only = on;

ALTER ROLE loader  SET statement_timeout = '4h';
ALTER ROLE loader  SET maintenance_work_mem = '4GB';  -- index builds, VACUUM
ALTER ROLE loader  SET synchronous_commit = off;      -- reloadable data, bulk writes
```

> [!CAUTION]
> **`work_mem` is per node, not per query.** A query with eight hash joins and a sort can allocate `work_mem` nine times over, and ten such queries at once is ninety allocations. Set it per role rather than globally, keep the concurrent user count small, and remember that this is why a warehouse setting on an OLTP database causes an out-of-memory kill.

Also worth raising on this class of instance: `max_parallel_workers_per_gather` (the default of 2 is timid for a warehouse), `max_parallel_maintenance_workers` for index builds, and `effective_cache_size` to something honest about the machine's RAM so the planner stops preferring sequential scans.

## The references

| File                                                       | Read it when                                                                    |
| :--------------------------------------------------------- | :------------------------------------------------------------------------------ |
| [`references/partitioning.md`](references/partitioning.md) | Any table that grows forever, retention policy, partition pruning, `pg_partman` |
| [`references/ingestion.md`](references/ingestion.md)       | Bulk loads, `COPY`, staging-table upserts, materialized view refresh strategy   |
