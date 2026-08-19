Speaking of Auto-Vacuum, you probably know that it's kind of important, right? So why is this important? (Great interview question if you want to break your candidate).

#### TX Wraparound And a Very Bad Long Day (Week?) @ The Office

Well, very very briefly, each transaction in PostgreSQL is tagged with a unique 32-bit integer, so you'd think you have roughly 5B of them (negative + positive) and you'd be wrong. The XID space is 2³² ≈ 4.295B, but only half of it (2³¹ ≈ 2.147B) can "live in the past" at any given moment, which is where the actual ~2.1B horizon comes from, and this number if per table, btw, so unique per table, and generally a problem on your largest tables only (the ones that are 27Tb and counting).

So, in the happy scenario, your default auto-vacuum is running with a decent parallelization (max_parallel_workers, max_parallel_maintenance_workers, etc define how many can run concurrently). What this does is take the oldest transactions that are still holding on to the XID, and wipe the XID replacing it with some dummy value (pretend it's "👍🏼"). This reclaims the number previously held by that row, and now, when XIDs reach the upper limit and wrap back to zero, those zeros will be all thums up and plenty of free XIDs will be available around to assign to transactions. You can think of this mechanism as if "PostgreSQL creatorsa had thought that in some very extreme cases you might want to open, and then either commit or rollback around 2.1B transactions ***simultaneously***, so let this XID be a 32-bit integer. Let's just hope it's enough for anybody."

So what might prevent a DB from reclaiming old XIDs? Typically, something pretty stupid. Like maybe you turned off your auto-vacuum entirely on that table because "oh the IOPS on that RDS instance are costing us a lot!", and every single transaction from the last nine months is still holding on to this unique TX ID, until XID reaches the upper limit (defined by `autovacuum_freeze_max_age`) and then something very unfunny happens: the database restarts in a single-user mode and performs a forced vacuum on that entire table. And if the table is 27Tb and you were skimping on IOPS expect days of downtime.

Long story short — respect autovacuum. Don't fuck with it. And if you fuck with it, do it in the opposite direction, but increasing parallel maintenance workers. Setup alerts and alarms and lower the artificial limit so that god forbit you get close to it, the real physical limit is still far away.

### Analyze

One often forgotten feature of PostgreSQL is `analyze` command, which collects statistics on all tables by the default, or a given table if you pass it as an argument. It sort of does a full-table scan (seq-scan) of the table and randomly samples the data to identify it's distribution. Why? So it the query optimizer can use this to figure out whether or not to apply your dumb index on the boolean column `is_active` where 90% of records are, and only 10% are not active. Given this distribution, a query that has `and is_active is TRUE` in the where clause will execute as a sequential scan on the entire table, while the `FALSE` one just might use your index. In general, B-Tree indexes on boolean columns... not a very good idea.

Why do you need to care? Well, sometimes, you see, when you or your coworkers have prematurely added a new index to the table with each new column added, and you get something like 12 indexes, in groups of 4, where each group has the same leading column, but different composite columns. Sounds familiar? In the apps I've seen this, unfortunately, the default amature behavior, and it hurts your database more than it helps.

If you run the following query, you'll get to see all of your indexes that HAVE NEVER been used on this instance since the stats counter started:

```sql
❯  select schemaname || '.' || relname || '.' || indexrelname as name 
   from pg_stat_user_indexes where  idx_tup_read + idx_tup_fetch = 0 order by name;
```

I dare you. If the list that comes back is more than 500 rows... somebody should get fired.

