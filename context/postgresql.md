# Databases: Best Practices

This document captures various practices, dos and don'ts accumulated over decades of working with PostgreSQL in particular. While PostgreSQL is moving exceptionally fast, and new features or new behavior may override the old, you are going to ahere to these rules judiciously, and only when you find a new feature contradicting something here or a specific use case you will stop and have a conversation with your human co-author.

## Application Classifications

Before we dive into the practices, it helps to define what kind of application we are building because the rules change based on the type of application sometimes. 

For the purposes of this skill, we'll define the following classes of applications:

<dl>
  <dt><strong>PG-lax</strong></dt>
	<dd>Type: OLTP. Many small transactions from a potentially large number of concurrent users. Generally, non-critical applications, games, social apps, with an unknown (but likely small) number of users (which can grow), where the cost of invalid data reference or a missed insert is relatively low. These types of applications can be configured to perform delayed commits, and even be eventualluy consistent. Often in these cases it's more important that the development moves fast, and the database is not in the way. Physical deletes are a norm, logical deletes are not. Foreign key delete behavior is often <code>ON CASCADE DELETE</code>.</dd>
  <dt><strong>PG-traditional</strong></dt>
  <dd>Type: OLTP. Many small transactions from a potentially large number of concurrent users. Otherwise, it's design is tighter than that of <strong>PG-lax</strong>. Perhaps this database may contain PII on large amount of users, or be a backend for an e-commerce store, where referential integrity saves time and effort on tracking down problems and customer complaints. However, it may not need many encrypted fields or SSL-only connection, it maybe directly accessible by the operations staff via a VPN, and whether to apply physical deletes or logical to key tables is a production decision.</dd>
  <dt><strong>PG-strict</strong></dt>
  <dd>Type: OLTP. Many small transactions from a potentially large number of concurrent users. The opposite of <strong>PG-lax</strong>: these applications often manage money, transactions, taxes, significant amount of PII or health records, and a mistake, leak, or a data corruption in such an application, as well as any extended  downtime, will cost a significant amount of money. In addition it can be legally bound to perform security audits, penetration testing and so on. These types of applications often prefer immutability (eg. on the transactions table) with later transaction inserted to amend the previous one, instead of updating it directly in place. Many tables maintain audit trails (via the triggers), and tight security, encryption at rest, encryption of columns in real-time, and SSL-only access often using public/private key. These databases almost never allow physical deletes, and perform logical delete only by having each table carry the <code>deleted_at</code> nullable column, null value of which is usually part of some unique index. ON CASCADE behavior is typically custom, and deletions often propagate by setting <code>deleted_at</code> on the dependent columns, but almost never physically delete anything.</dd>
  <dt><strong>PG-analytics</strong></dt>
  <dd>Type: Data Warehouse. These PG instances are meant for analytics, data warehousing, and often contain large number of materialized views, injest data from multiple sources, and have small number of concurrent users performing large and long-running queries. These applications rarely perform physical deletes, are optimized for injestion of data and fast batch imports.</dd>
</dl>



> [!IMPORTANT]
>
> It is critically important to understand what type of application we are dealing with before applying the rules. If agent is engaged in designing the schema, it must first ask the user (or read in the spec) and infer the type of application this is, and record it in it's AGENTS.md file or CLAUDE.md file. This decision will guide many of the conventions and default behaviors.

## Logical vs Physical Deletes

If your application type warrants logical, and not physical deletes, there are some advantages to that. First of all, you never loose any data, so you can always restore someone's account, or provide forensic assistance to law enforcement. 

Secondly, any row that's physically deleted in PostgreSQL needs to be vacuumed at some point. Vaccuuming is a IO heavy process that, despite all the advancements in parallel vacuuming, may be addding to your database load considerably. 

Logical deletes do no such thing. Especially if the column that separates "logically deleted" rows from live rows is only indexed where it is NULL, and never index where it is NOT NULL. 

This is important because logically deleted rows will not need vacuuming just because a data was set on them, as long as it's not in the index. The indexes on the live rows will need to be updated to exclude the logically deleted row, but that's a more lightweight operation.

### If Your Backend is Ruby on Rails

You have a choice of two battle-tested gems to implement your logical deletes:

* https://github.com/jhawthorn/discard
* https://github.com/rubysherpas/paranoia

## Schema Naming

Regardless of what application we are building and in what language, we are generally going to lean on Rails conventions for database and table naming: 

1. **Tables names are plural, lower cased, underscored**
2. **Column names are also lower case, underscored and are constructed using full words**, almost never abbreviations unless it's something extremely well known, such as `llm` or `i18n`.
3. **Foreign keys are singular**, eg `users` table, maybe referenced by `profiles` with a singular. 
   1. Each foreign key MUST define `on cascade` behavior. The actual behavior depends on the application. 
4. **`profiles.user_id`** (a singular item) referencing it.

### Third Party Schemas

Whenever there is a benefit of copying a third party tables into our own database due to the active integration, webhooks being received for various events, and so on (examples of which include Stripe, Plaid, and many others) sometimes it's very beneficial to store the third party's data in the tables they might publicize and even encourage us to use. 

This can be very useful and can provide a good additional source of information about what's going on in the application, useful in audits, debugging, troubleshooting, and so on, especially if the applicaiton is receiving a lot of webhooks from the third party, each of a different schema mapped to a potential table.

**In those cases, the following rules apply:**

1. Store third party tables always in their dedicated schema named after the third party, eg `stripe.*` or `plaid.*` and so on. 

2. Our own code, typically, will default to the `public` schema, which is the default schema in PostgreSQL.

3. The default schema search path is often set to `"$user", public` (you can find that out with `SHOW SEARCH_PATH;`)

4. If you use `psql` you can list the schema with `\dn` command.

5. Whenever a new schema is added to the mix, it is imperative that the search path is updated either for the user:

   `ALTER USER <USERNAME> SET SEARCH_PATH TO $user, public, stripe, plaid;` 
   NOTE: this statement would require the user to logout and log back in, and the search path will be updated and persisted. 

   Search Path can also be set or reset temporarily, per current session, and so on. Decide the most appopriate method but beware that if there are name collisions between the vendors, the first schema's object wins.

6. It's very easy to do cross-schema joins in PostgreSQL, just don't forget to add the schema prefix before the dot for any schema not in the search path.  For this reason you may choose to NOT modify your search path, because that will require you to reference any Stripe or Plaid table with the `stripe.transactions` prefix.

## Migrations, Performance & Indexes

### Database Migrations

Treat the migration as a production operation, not a schema edit. 

Install `strong_migrations` — it will catch the classics before your DBA (or your 3am pager) does. The non-negotiables on PostgreSQL: `add_index` on any table with real rows must be `algorithm: :concurrently` with `disable_ddl_transaction!`; never combine that migration with anything else. 

Adding a column with a default is safe on PG 11+, but adding `null: false` to an existing column is not — add a `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE CONSTRAINT` in a separate migration, then `SET NOT NULL`, which PG 12+ will accept using the validated constraint as proof. 

Backfills belong in their own batched migration or a rake task, never in the same transaction as DDL. Renaming and dropping columns require the ignored-column dance (`self.ignored_columns +=`, deploy, then drop) because your old app processes are still running mid-deploy. 

And switch to `schema_format = :sql`; `schema.rb` silently loses partial indexes, expression indexes, exclusion constraints, generated columns, and every extension you care about. 

### Primary Keys

Primary keys should never be made composite or based on business-value columns. This is beceause businss requirements change over time. Always create an ID column on all tables, and do not assign it any meaning other than a unique ID that may be referenced from elsewhere. 

You have two choices in choosing the datatype for primary keys, which depends on the application you are building once again.

> [!CAUTION]
>
> The default datatype for auto-incrementing primary key is `integer` which is 32-bit and is therefore capped at 2.5B. Therefore modern application almost never use the default data type. 

#### Data Types for Primary Keys

Primary keys often leak out to the web front-end in unexpected ways. You maybe calling a REST API, and calling `/users/:id/settings` which anyone with Chrome Dev Tools can watch and realize that their user id is for instance, 10,000. Imagine using a web app that's 10 years old, and realizing you are only the 10,000s user on the entire system? That's not good. It also allows your competitors to inspect the sizes of your key tables by watching the RESTFUL API urls and deducing it from there.

##### Bigint

If you do not care about any of the above, then use `bigint` which is not 2.6B capped, and can grow as much as you like. And to confuse your competitors you don't even have to start at 1. You can alwasy start the sequence at 1M, throwing anyone assuming they are auto-incrementing from 1 off. This data type is fast, compact (64-bits), but remembering to always start from some high random number may get tedious.

##### UUIDv7

**The answer to this nonesense is — UUID. With PostgreSQL18 embracing UUID and no longer requiring a custom extension to load to use it, this is likely the most secure and modern data-independent ID strategy you should use.**

**What landed in 18:**

- `uuidv7()` — time-ordered UUIDs per RFC 9562. Postgres's implementation stuffs a 12-bit sub-millisecond timestamp fraction right after the millisecond timestamp (permitted, not required, by the spec), which gives you guaranteed monotonicity within a single backend process rather than just approximate ordering.
- `uuidv4()` — an alias for `gen_random_uuid()`, purely so your schema reads honestly about which version you asked for.
- `uuid_extract_timestamp()` (which arrived in 17) now understands v7, so you can recover the creation time from the key itself.

Also: use ` primary keys`, `timestamptz` not `timestamp` (Rails 7.0+ does this by default), real foreign keys with `add_foreign_key ... validate: false` then validate separately, and `citext` or a `CHECK` rather than three layers of Ruby validation pretending to be a constraint.

> [!NOTE]
>
> Early versions of Rails pretended that Rails validations are enough, and you do not need foreign keys. This was mostly motivated by the challenges in creating text fixtures in the right order (when FKs were enabled), and DHH's lack of understanding of databases deep enough to grok why that was a misnomer. **Do use foreign keys on ALL of your tables that have them.**

##### The Size of UUID

**Bytes:** a Postgres `uuid` is **16 bytes** (128 bits, twice larger than `bigint`), fixed-width, stored as a raw 128-bit value — not the 36-character text form you see in `psql`. Its alignment is char, so it doesn't force padding. Compare to `bigint` at 8 bytes. So the honest accounting is: +8 bytes per row in the heap, +8 per entry in the primary key index, and +8 in every single foreign key column and every index covering one. On a table with five FK references to it, you're paying that toll five times over. If anyone ever suggests storing UUIDs as `varchar(36)`, that's 37 bytes plus alignment slop, and you should look at them the way you'd look at someone who tunes a kick drum by ear at 3am.

**Why v7 matters more than the 8 bytes.** UUIDv4 is uniformly random, so every insert lands in a random B-tree leaf page. On a table bigger than `shared_buffers` that means a page fault per insert, catastrophic index bloat as pages split at ~50% fill instead of packing right-to-left, and a working set that is effectively the whole index. UUIDv7's leading timestamp restores the sequential insert locality that made `bigserial` fast — you get right-hand-side page splits, ~90% fill factor, and a hot tail that stays cached. Benchmarks vary wildly by workload, but the insert-throughput gap between v4 and v7 on large tables is routinely an order of magnitude, ***which dwarfs 8 bytes of width.***

**The tradeoff you should actually weigh:** v7 leaks creation timestamps to anyone holding the ID. If your IDs appear in URLs, that's an information disclosure — an attacker learns exactly when a record was created, and with enough IDs, your creation *rate*. For most apps that's fine. For anything where row-creation timing is sensitive, it isn't, and you want v4 (or a random surrogate for external exposure and a v7 internal key), despite the index performance penalty.

For your Rails work — this is the right moment to go UUID:

ruby

```ruby
create_table :boomerangs, id: :uuid, default: -> { "uuidv7()" } do |t|
```

#### Indexes

Fewer, wider, deliberate.** Every index is a write tax, a bloat source, and a HOT-update killer — updating an indexed column forces a new index tuple even when nothing else changed. So index from actual query plans, not from a feeling that a column "seems searchable." Then audit: `pg_stat_user_indexes` with `idx_scan = 0` over a meaningful window is your kill list. On composite column ordering, the rule that actually matters is *equality columns first, then range/inequality, then sort columns* — an index on `(account_id, created_at)` serves `WHERE account_id = ? ORDER BY created_at DESC LIMIT 20` beautifully, while `(created_at, account_id)` serves it not at all. Selectivity is a tiebreaker, not the primary criterion; access-pattern shape wins.

**The shared-leading-column question is where most Rails apps get fat.** If you have `(account_id)` and `(account_id, created_at)`, the first is redundant — B-tree leftmost-prefix means the composite answers everything the single-column index answers, so drop it unless you need it for a unique constraint or the size difference genuinely matters for an index-only scan on a huge table. This happens constantly because `add_reference`/`belongs_to` auto-creates the single-column index and then you add the composite three sprints later and never look back. But `(account_id, created_at)` and `(account_id, status)` are *not* redundant with each other — neither is a prefix of the other, and PG can bitmap-AND them if it wants. Before adding the second one, though, ask whether a partial index (`WHERE status = 'pending'`) is smaller and better, because it usually is. Partial indexes are the single most underused feature in Postgres: soft-delete apps should have `WHERE deleted_at IS NULL` on nearly everything.

##### Index Types, Briefly

* **B-tree** for basically everything ordered and comparable. 

* GIN for `jsonb` containment, arrays, and 
* `tsvector` full-text. 
* use `jsonb_path_ops` if you only ever use `@>`, it's meaningfully smaller and faster. 
* GiST for ranges, geometry, and exclusion constraints (`tstzrange` + `EXCLUDE` is how you prevent double-booking correctly, rather than with an application-level race condition you'll discover in production). 
* BRIN for append-only, naturally-ordered giants — an events table with a monotonic `created_at` gets a usable index at roughly 1/1000th the size. 
* Expression indexes for `lower(email)`, though `citext` is cleaner. 
* Hash indexes: still almost never the answer.

#### N+1s 

Turn on `strict_loading` — per-association at first, then `config.active_record.strict_loading_by_default = true` in dev/test once you've cleaned up — so the failure is a raised exception at development time instead of 400 queries in production. `bullet` in dev is complementary and catches the inverse case (eager-loading you don't use). 

Know the three loaders: `preload` does separate queries and is usually what you want; `eager_load` forces one `LEFT OUTER JOIN` and is right when you filter or order on the association; `includes` guesses between them and will silently switch to `eager_load` the moment you add `references` or a hash condition, which is how a fast page becomes a Cartesian explosion. 

Use `joins` when you're only filtering and don't need the objects. Counter caches for `.count` in loops; `Model.where(id: ids).index_by(&:id)` when the association graph is awkward. And check your serializers and view partials — that's where N+1s hide, not in the controller where everyone looks. Finally, `ORDER BY ... LIMIT` on a joined query is the one shape where `preload` and `eager_load` differ semantically, so read the SQL rather than trusting the DSL.
