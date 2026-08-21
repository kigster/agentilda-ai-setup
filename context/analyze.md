# PostgreSQL Analyze Command

Why we Auto-Vacuum.

## TX Wraparound And a Very Bad Long Day (Week?) @ The Office

Well, very very briefly, each transaction in PostgreSQL is tagged with a 32-bit integer, and unlike nearly every other integer in this database it is **unsigned** — so there is no "2 billion in each direction", the space is 2³² ≈ 4.295B, full stop. Only half of it (2³¹ ≈ 2.147B) can "live in the past" at any given moment, which is where the real ~2.1B horizon comes from.

One correction to the way this is usually retold: **the XID counter is cluster-wide, not per table.** There is exactly one per instance. What lives per table is `pg_class.relfrozenxid` — the oldest XID that table still depends on — and therefore what is per table is the *age*. That is why this surfaces on your largest, busiest tables first (the ones that are 27Tb and counting) rather than everywhere at once.

So, in the happy scenario, your default auto-vacuum is running with a decent parallelization (max_parallel_workers, max_parallel_maintenance_workers, etc define how many can run concurrently). What this does is find rows old enough that nobody will ever again need to compare their XID against anything, and **freeze** them — which since 9.4 means setting a hint bit meaning "visible to everyone, stop asking" rather than literally overwriting `xmin` with a magic value (pretend the bit is a "👍🏼"). A frozen row stops holding the horizon back, so that table's `relfrozenxid` can advance and the ~2.1B window slides forward with it.

Note what is *not* happening, because this is where the folk explanation goes wrong: no individual XID number is returned to a free list for reuse. There is no free list. The counter marches forward forever and eventually laps the track; freezing only guarantees nothing is still standing on the track when it does. You can think of this mechanism as if "PostgreSQL creators had thought that in some very extreme cases you might want to open, and then either commit or rollback around 2.1B transactions ***simultaneously***, so let this XID be a 32-bit integer. Let's just hope it's enough for anybody."

So what might stop that horizon from advancing? Typically something stupid — but not the thing most people name first.

**Turning autovacuum off does not cause this.** PostgreSQL launches an anti-wraparound autovacuum on any table past `autovacuum_freeze_max_age` (200 million by default) whether autovacuum is enabled or not; the manual states it plainly: *"(This will happen even if autovacuum is disabled.)"* It cannot be switched off globally or per table.

What actually pins the horizon is something holding a snapshot open so the freeze cannot proceed:

- a long-running reporting query;
- an `idle in transaction` session left open in `psql`;
- an orphaned replication slot for a decommissioned replica that was never dropped;
- a prepared transaction from a two-phase commit that was never committed or rolled back.

Autovacuum wakes, finds it cannot freeze anything newer than that snapshot, accomplishes nothing, and sleeps. Repeat for months.

The real escalation ladder, which is widely misquoted:

1. At `autovacuum_freeze_max_age` (**200 million** by default) an anti-wraparound autovacuum is *forced* on the table.
1. At **40 million** XIDs remaining the server warns in the log: `WARNING: database "mydb" must be vacuumed within 39985967 transactions`.
1. At **3 million** remaining it stops: `ERROR: database is not accepting commands that assign new transaction IDs to avoid wraparound data loss`.

And the part almost everyone gets wrong: **the database does not restart itself into single-user mode.** It refuses transactions that would assign a new XID; reads continue to work. The documentation explicitly warns against the folklore remedy: *"contrary to what was sometimes recommended in earlier releases, it is not necessary or desirable to stop the postmaster or enter single user-mode in order to restore normal operation."* Connect normally, find whatever holds the snapshot, terminate it, and `VACUUM`. If the table is 27Tb and IOPS were skimped on, that vacuum still takes days, and writes are down for all of them.

Long story short — respect autovacuum. Don't fuck with it. And if you fuck with it, do it in the opposite direction, by increasing parallel maintenance workers. Set up alerts and alarms and lower the artificial limit so that, god forbid you get close to it, the real physical limit is still far away.

The query worth putting on a dashboard is not about autovacuum at all — it is about what is standing in its way:

```sql
-- Oldest XID age per table. Alert well before autovacuum_freeze_max_age (200M).
SELECT c.oid::regclass AS table_name,
       greatest(age(c.relfrozenxid), age(t.relfrozenxid)) AS xid_age
  FROM pg_class c
  LEFT JOIN pg_class t ON c.reltoastrelid = t.oid
 WHERE c.relkind IN ('r', 'm')
 ORDER BY xid_age DESC
 LIMIT 20;
```

Pair it with `pg_stat_activity` filtered to `idle in transaction`, and `pg_replication_slots` filtered to `active = false`. Those three queries are the whole early-warning system.

### Analyze

One often forgotten feature of PostgreSQL is the `analyze` command, which collects statistics on all tables by default, or a given table if you pass it as an argument. It sort of does a full-table scan (seq-scan) of the table and randomly samples the data to identify its distribution. Why? So that the query optimizer can use this to figure out whether or not to apply your dumb index on the boolean column `is_active` where 90% of records are active, and only 10% are not. Given this distribution, a query that has `and is_active is TRUE` in the where clause will execute as a sequential scan on the entire table, while the `FALSE` one just might use your index. In general, B-Tree indexes on boolean columns... not a very good idea.

Why do you need to care? Well, sometimes, you see, when you or your coworkers have prematurely added a new index to the table with each new column added, and you get something like 12 indexes, in groups of 4, where each group has the same leading column, but different composite columns. Sounds familiar? In the apps I've seen, this is, unfortunately, the default amateur behavior, and it hurts your database more than it helps.

If you run the following query, you'll get to see all of your indexes that HAVE NEVER been used on this instance since the stats counter started:

```sql
❯  select schemaname || '.' || relname || '.' || indexrelname as name 
   from pg_stat_user_indexes where  idx_tup_read + idx_tup_fetch = 0 order by name;
```

I dare you. If the list that comes back is more than 500 rows... somebody should get fired.

