# Declarative Partitioning

Partitioning solves exactly two problems, and it is worth naming them because people reach for it expecting a third.

1. **Retention becomes free.** `DROP TABLE events_2024_01` returns the disk instantly, takes no vacuum, and produces no dead tuples. A `DELETE FROM events WHERE created_at < ...` on the same data writes millions of dead tuples, bloats the table and the indexes, and is followed by a vacuum that cannot return the space without a rewrite.
1. **Partition pruning narrows the scan.** A query with a predicate on the partition key touches only the partitions that can contain matching rows, and the planner knows this before executing anything.

**What it does not do is make an unindexed query fast.** Ten partitions of a badly indexed table are ten badly indexed tables. Partition for retention and pruning; index for speed.

## When to partition

- The table grows without bound and old data has a retirement date. Events, logs, metrics, facts.
- The table is large enough that maintenance is painful - roughly north of 100GB, where a `VACUUM FULL` or an index rebuild stops being an option.
- Queries reliably filter on the partition key. If they do not, pruning never happens and you have added complexity for retention alone, which is sometimes still worth it.

**Do not partition** a dimension table, a table of a few million rows, or a table whose access pattern has no shared key. The overhead - planning time across partitions, one more thing for every migration to handle - is real.

## Range partitioning by time

The default shape for a fact table:

```sql
CREATE TABLE events (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  occurred_at timestamptz NOT NULL,
  account_id  bigint      NOT NULL,
  kind        text        NOT NULL,
  payload     jsonb       NOT NULL,
  PRIMARY KEY (id, occurred_at)      -- the partition key must be in the PK
) PARTITION BY RANGE (occurred_at);

CREATE TABLE events_2026_09 PARTITION OF events
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE events_2026_10 PARTITION OF events
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');

-- A default partition catches rows outside every range, so an insert never fails.
CREATE TABLE events_default PARTITION OF events DEFAULT;
```

> [!CAUTION]
> **The partition key must be part of every unique constraint, including the primary key.** That is a hard limitation of declarative partitioning, not a convention: Postgres cannot enforce uniqueness across partitions without it. So the primary key becomes `(id, occurred_at)`, and this is the one place where the "never composite" rule from `core.md` yields - `id` is still the identifier, `occurred_at` is there because the engine requires it.

> [!CAUTION]
> **A default partition makes adding new partitions expensive.** Creating a partition whose range overlaps rows already sitting in the default requires scanning the default partition under an `ACCESS EXCLUSIVE` lock. Keep the default empty and alert when it is not - it should be a tripwire, not a destination.

Indexes are declared on the parent and propagate to every partition, including ones created later:

```sql
CREATE INDEX ON events (account_id, occurred_at DESC);
CREATE INDEX ON events USING brin (occurred_at);
```

## Pruning, and how to check it

Pruning happens when the planner can prove a partition cannot match. It requires a predicate on the **partition key**, with a constant or a parameter it can evaluate:

```sql
-- prunes: one partition scanned
SELECT count(*) FROM events WHERE occurred_at >= '2026-09-01' AND occurred_at < '2026-09-15';

-- does not prune: the function hides the key from the planner
SELECT count(*) FROM events WHERE date_trunc('month', occurred_at) = '2026-09-01';
```

Check with `EXPLAIN` and count the partitions in the plan. `enable_partition_pruning` is on by default; if a plan touches every partition, the predicate is the problem, not the setting.

Run-time pruning (for parameters not known at plan time) works too, and shows up as `Subplans Removed: N` in `EXPLAIN ANALYZE` output. If you see the partition count in the plan but `Subplans Removed` accounts for the rest, pruning is working.

## Retention

```sql
-- Detach first if anything might still be reading it, then drop.
ALTER TABLE events DETACH PARTITION events_2024_01 CONCURRENTLY;
DROP TABLE events_2024_01;
```

`DETACH ... CONCURRENTLY` avoids the `ACCESS EXCLUSIVE` lock on the parent that a plain `DETACH` takes, which matters if anything is querying while you retire data. Archive to object storage before dropping if the retention policy says archive rather than delete; `COPY events_2024_01 TO PROGRAM 'gzip > /archive/events_2024_01.csv.gz' CSV HEADER` is enough.

## Automation

Creating next month's partition by hand works until the one month somebody forgets, and then every insert lands in the default partition (or fails, if there is none). Automate it:

- **`pg_partman`** is the mature answer: it creates partitions ahead of time, retires old ones on a retention policy, and handles the default-partition tripwire. Use it unless you have a reason not to.
- **A scheduled job** calling a function that creates the next N partitions is a reasonable minimal alternative. Create several months ahead, not one, so a failed run is not an incident.

Either way, **alert on "the newest partition ends less than 30 days from now"**. That is the check that catches the automation having quietly stopped.

## Sub-partitioning, and when not to

A partition can itself be partitioned - by month, then by `account_id` hash, for instance. It is occasionally correct for very large multi-tenant fact tables and usually a mistake: planning time grows with the total partition count, and a thousand partitions is where that starts to hurt. Reach for a second level only after measuring that the first level is not enough.
