# PostgreSQL: Core Practices, True for Every Application Class

This document is the class-independent half of the PostgreSQL conventions. It is meant to be part of the context that `AGENTS.md` (or `CLAUDE.md`) loads on demand, whenever it needs to design PostgreSQL schema, optimize queries, or propose a sub-schema to an existing application. Everything here holds no matter what kind of application you are building.

Everything that *changes* with the application class - delete strategy, `ON DELETE` behaviour, isolation levels, row-level security, replica routing, partitioning - lives in the class-specific skills. Read this file first, then the one for your class.

While PostgreSQL is moving exceptionally fast, and new features or new behavior may override the old, you are going to adhere to these rules judiciously, and only when you find a new feature contradicting something here or a specific use case you will stop and have a conversation with your human co-author.

## Application Classification: Settle It First

Before any rule below is applied, the application class must be known, because several rules below end with "and then it depends on the class".

<dl>
  <dt><strong>PG-lax</strong></dt>
  <dd>Type: OLTP. Many small transactions from a potentially large number of concurrent users. Generally, non-critical applications, games, social apps, with an unknown (but likely small) number of users (which can grow), where the cost of an invalid data reference or a missed insert is relatively low. These applications can be configured to perform delayed commits, and even be eventually consistent. Often it is more important that development moves fast and the database is not in the way. Physical deletes are the norm, logical deletes are not. Foreign key delete behavior is often <code>ON DELETE CASCADE</code>. Scaling happens by putting read replicas behind the primary. Recipes: the <code>postgres-lax</code> skill.</dd>
  <dt><strong>PG-strict</strong></dt>
  <dd>Type: OLTP. The opposite of <strong>PG-lax</strong>: these applications manage money, transactions, taxes, a significant amount of PII, or health records, and a mistake, leak, or data corruption - as well as any extended downtime - costs a significant amount of money. They can be legally bound to perform security audits and penetration testing. They prefer immutability (for instance on a transactions table) with a later row inserted to amend the previous one, rather than updating in place. Tables maintain audit trails via triggers, enforce row-level security, and use encryption at rest, column encryption in real time, and SSL-only access. These databases almost never allow physical deletes: each table carries a nullable <code>deleted_at</code> column, whose null value is usually part of some unique index. <code>ON DELETE</code> behaviour is typically custom, and deletions propagate by setting <code>deleted_at</code> on dependent rows. Recipes: the <code>postgres-strict</code> skill.</dd>
  <dt><strong>PG-analytics</strong></dt>
  <dd>Type: Data Warehouse. These instances are meant for analytics and data warehousing. They contain a large number of materialized views, ingest data from multiple sources, and serve a small number of concurrent users running large, long-running queries. They rarely perform physical deletes (they drop partitions instead), and are optimized for ingestion and fast batch imports. Recipes: the <code>postgres-analytics</code> skill.</dd>
</dl>

> [!IMPORTANT]
> **If the agent is designing schema, it must first ask the user (or read from the spec) which class this application is, and record the answer in `AGENTS.md` or `CLAUDE.md`.** This decision guides many of the conventions and default behaviors below.

**Default to `PG-lax`, then escalate per table.** Most applications are lax, and pretending otherwise buys ceremony rather than safety. Any individual table holding money, PII, health data or anything with a legal consequence adopts the `PG-strict` rules *for that table*, while the rest of the schema stays lax. An application is `PG-strict` as a whole when the strict tables are the point of the product rather than a corner of it.

> [!NOTE]
> The advice below is presented in no particular order.

## Schema, Table & Column Naming

Regardless of what application we are building and in what language, we are generally going to lean on Rails conventions for database and table naming:

1. **Table names are plural, lower cased, underscored**
1. **Column names are singular (unless it's an array), also lower case, underscored and are constructed using proper English words**, almost never abbreviations unless it's something extraordinarily well known, such as `llm` or `i18n`.
1. **Foreign keys are also singular**, eg `users` table, may be referenced by `profiles` with a singular column **`profiles.user_id`**.
1. Each foreign key MUST state its `ON DELETE` behaviour explicitly - `CASCADE`, `RESTRICT`, `SET NULL` or `NO ACTION`. The right answer depends on the application class (see above). Leaving it unstated means `NO ACTION`, which is a decision nobody made.

### PolyMorphic Tables & STI (Single Table Inheritance) Table

If you are dealing with Rails, Django, or similar frameworks, you have very likely come across both polymorphic tables (for instance - `edibles` with `edible_id` and `edible_type` mapping to a class in your language such as `strawberries` and `bananas`), where each class may use only a fraction of the columns of the entire table.

STI is another way to have many classes map to a single table, this time using class inheritance, implemented in the database as a `type` column which typically by default carries the class name that needs to be instantiated upon read.

As a complimentary approach to STI, Rails recently introduced so-called "Delegated Types", which are kind of like STI, but where the mapping between classes and the tables is actually 1-1, and there is a polymorphic table in the middle joining them all into one happy family. So it's more like a polymorphic table, honestly, than it is an STI table. For a reference please see [this blog post by Vincent, an Iterative Thinker](https://dev.to/vincentgithinji/single-table-inheritance-vs-delegated-types-in-rails-whats-the-deal-32oe).

There are a couple of important points you should know about these mappings between classes and database tables.

1. **The polymorphic column pair can never be a real foreign key.** A FK constraint targets exactly one table, and `edibles.edible_id` targets whichever table `edible_type` names on that particular row. There is no SQL for that. This is the actual limitation, and it is why Delegated Types help: each concrete type gets its own table, and the join row carries a genuine, enforced FK to it.
1. **STI is the opposite problem, and subtler.** An STI table is one real table with one real primary key, so other tables *can* declare a foreign key onto it - the database accepts `carts.id` as a target without complaint. What the FK cannot do is constrain *which subclass* was referenced: Postgres will let `smoothies.banana_id` point at a row whose `type` is `strawberry`. If that distinction matters, enforce it with a `CHECK` constraint, a partial unique index, or a different design - not a foreign key.
1. With STI you have a single column - typically `type`, that differentiates the classes, and contains the fully qualified actual classname. **And that is the problem.** Imagine you decided to refactor your codebase, and `Shloopify::Checkout::Cart` became `AmazonBoughtUs::Checkout::Cart`, and the `carts` are stored in the STI table because why not, there are many kinds of shopping carts, some roll, some you have to carry, some charge you before you give them your credit card. Jokes aside, this is a gnarly data migration. So the advice is simple: use a single word in lower case designated to each class to tell which class this row belongs to. And in Rails the magical method that helps you resolve all that is called `find_sti_class`. If instead of the first classname we simply stored `shloop`, we could change the codebase to now resolve `shloop` to the second class, bypassing the need for a giant multi-day data migration.
1. Do index the `type` column. By itself, and in a composite index with `id, type` → this will be used for joins.
1. With polymorphic tables, the same exact concept applies to polymorphic tables: you do not want the fully qualified classname to be in the `edible_type`, you want it to contain `banana` and `strawberry`. The trick in this case is much simpler, you merely need to define a class method `polymorphic_name` on each class you don't want to participate in the polymorphic table using its fully qualified classname.
1. And for the love of god, please create the index on ID first and sort the type so that in the index similar objects are next to each other: `create index on edibles (edible_id, edible_type desc)`;

### Third Party Schemas

Whenever there is a benefit of copying third party tables into our own database due to the active integration, webhooks being received for various events, and so on (examples of which include Stripe, Plaid, and many others) sometimes it's very beneficial to store the third party's data in the tables they might publicize and even encourage us to use.

This can be very useful and can provide a good additional source of information about what's going on in the application, useful in audits, debugging, troubleshooting, and so on, especially if the application is receiving a lot of webhooks from the third party, each of a different schema mapped to a potential table.

**In those cases, the following rules apply:**

1. Store third party tables always in their dedicated schema named after the third party, eg `stripe.*` or `plaid.*` and so on.

1. Our own code, typically, will default to the `public` schema, which is the default schema in PostgreSQL.

1. The default schema search path is often set to `"$user", public` (you can find that out with `SHOW SEARCH_PATH;`)

1. If you use `psql` you can list the schema with `\dn` command.

1. Whenever a new schema is added to the mix, it is imperative that the search path is updated either for the user:

   `ALTER USER <USERNAME> SET SEARCH_PATH TO $user, public, stripe, plaid;` NOTE: this statement would require the user to logout and log back in, and the search path will be updated and persisted.

   Search Path can also be set or reset temporarily, per current session, and so on. Decide the most appropriate method but beware that if there are name collisions between the vendors, the first schema's object wins.

1. It's very easy to do cross-schema joins in PostgreSQL, just don't forget to add the schema prefix before the dot for any schema not in the search path. For this reason you may choose to NOT modify your search path, because that will require you to reference any Stripe or Plaid table with the `stripe.transactions` prefix.

## Deletes: Logical or Physical

**This is the single most class-dependent decision in the schema, and it is not made here.**

- `PG-lax` deletes physically and cascades. See the `postgres-lax` skill.
- `PG-strict` never deletes physically; every table carries `deleted_at` and deletions propagate by setting it. See the `postgres-strict` skill.
- `PG-analytics` deletes by dropping a partition. See the `postgres-analytics` skill.

What is true regardless of the choice, and is worth knowing before you make it:

> [!CAUTION]
> **A logical delete does not avoid vacuum cost, and it is worth being precise about why.** Under MVCC, an `UPDATE` writes a *new* row version and marks the old one dead - exactly the dead tuple a `DELETE` would have produced. Setting `deleted_at` on a million rows creates a million dead tuples. What you actually buy with a logical delete is the *data*, the audit trail, and the ability to undo. You do not buy your way out of vacuum.

What genuinely reduces the cost is a **HOT update** (Heap-Only Tuple): when an `UPDATE` to a row (especially one with a large number of columns) changes only the columns that are **not indexed**. This allows the previous physical row version and the new version to fit on the same disk page. In that case PostgreSQL skips the index write entirely and the dead tuple can be reclaimed by opportunistic page pruning rather than waiting for a vacuum cycle.

## Indexes

**Fewer, wider, deliberate.** Every index is a write tax, a bloat source, and a HOT-update killer - updating an indexed column forces a new index tuple even when nothing else changed. So index from actual query plans, not from a feeling that a column "seems searchable." Then audit: `pg_stat_user_indexes` with `idx_scan = 0` over a meaningful window is your kill list. On composite column ordering, the rule that actually matters is *equality columns first, then range/inequality, then sort columns* - an index on `(account_id, created_at)` serves `WHERE account_id = ? ORDER BY created_at DESC LIMIT 20` beautifully, while `(created_at, account_id)` serves it not at all. Selectivity is a tiebreaker, not the primary criterion; access-pattern shape wins.

**The shared-leading-column question is where most Rails apps get fat.** If you have `(account_id)` and `(account_id, created_at)`, the first is redundant - B-tree leftmost-prefix means the composite answers everything the single-column index answers, so drop it unless you need it for a unique constraint or the size difference genuinely matters for an index-only scan on a huge table. This happens constantly because `add_reference`/`belongs_to` auto-creates the single-column index and then you add the composite three sprints later and never look back. But `(account_id, created_at)` and `(account_id, status)` are *not* redundant with each other - neither is a prefix of the other, and PG can bitmap-AND them if it wants. Before adding the second one, though, ask whether a partial index (`WHERE status = 'pending'`) is smaller and better, because it usually is. Partial indexes are the single most underused feature in Postgres: soft-delete apps should have `WHERE deleted_at IS NULL` on nearly everything.

### Index Types, Briefly

- **B-tree** for basically everything ordered and comparable.
- **GIN** for `jsonb` containment, arrays, and `tsvector` full-text. Use `jsonb_path_ops` if you only ever use `@>` - it is meaningfully smaller and faster.
- **GiST** for ranges, geometry, and exclusion constraints (`tstzrange` + `EXCLUDE` is how you prevent double-booking correctly, rather than with an application-level race condition you'll discover in production).
- **BRIN** for append-only, naturally-ordered giants - an events table with a monotonic `created_at` gets a usable index at roughly 1/1000th the size.
- **Expression indexes** for `lower(email)`, though `citext` is cleaner.
- **`pg_trgm`** for fuzzy matching and `LIKE '%foo%'`, which no B-tree will ever serve.
- **Hash indexes**: still almost never the answer.

And here is the trap, because it is exactly backwards from what intuition suggests: **a partial index `WHERE deleted_at IS NULL` disqualifies the update from HOT.** HOT eligibility considers every column any index *references*, and that includes a partial index's predicate. Setting `deleted_at` from NULL to a timestamp changes the predicate's answer, so the row must leave the index, so the update rewrites index tuples. Measured on PostgreSQL 18 with page headroom, 200 soft deletes produced 174 HOT updates when `deleted_at` was in no index at all, and **zero** when the recommended `WHERE deleted_at IS NULL` partial index was present. Both produced 200 dead tuples.

That does not mean skip the partial index. It stays small because it only covers live rows, and on a table where most rows are deleted that is a large read win. It means the tradeoff is real and should be chosen deliberately: a small, hot index on the read path, paid for with non-HOT updates and index churn on the write path. For `PG-strict` the partial index is nearly always still correct - the read pattern dominates, and `deleted_at IS NULL` appears in essentially every query.

## Money and Other Exact Numbers

> [!CAUTION]
> **Never store money in `float`, `double precision`, or Ruby's `Float`.** Binary floating point cannot represent 0.10, and a tax engine that is off by a hundredth of a cent on ten million line items is off by real money in a real audit. This is not a style preference.

**The default is integer minor units - cents - in a `bigint`.** `amount_cents bigint NOT NULL`, paired with `currency char(3) NOT NULL` holding an ISO 4217 code. Integers add, subtract and compare exactly, they are 8 bytes, they survive every serialization boundary between Postgres, Ruby, JSON and JavaScript without a single rounding surprise, and `bigint` cents tops out at 9,223,372,036,854,775,807 - 9.2 quintillion cents, or about 92 quadrillion dollars - which is more than any of us will need.

Name the column for what it holds. `amount_cents`, not `amount` - the suffix is what stops somebody assigning `19.99` to it three years from now and being wrong by two orders of magnitude.

**The exception is genuine fractional quantities**: crypto (satoshis are 1e-8, wei are 1e-18), FX rates, per-unit tax rates, commodity weights. There, use `numeric(p, s)` with the precision and scale written down, because `numeric` is arbitrary-precision decimal and arithmetic on it is exact. It is slower than integer arithmetic and stored as a variable-length value, and that is the correct price to pay.

```sql
amount_cents   bigint         NOT NULL,   -- money: exact, fast, boring
currency       char(3)        NOT NULL,
tax_rate       numeric(9, 6)  NOT NULL,   -- a rate is not money
btc_amount     numeric(24, 8)             -- fractional by nature
```

**Rounding is a specified behaviour, not an implementation detail.** Tax jurisdictions state their rounding rule in law, and the rules differ - half-up, half-even, round-per-line versus round-per-invoice. Postgres's `round()` on `numeric` is half-away-from-zero; on `double precision` it is half-to-even and therefore doubly wrong for this purpose. Decide the rule per jurisdiction, write it down in the schema or the code that owns it, and test it against the published examples rather than against your intuition.

In Rails, `t.bigint :amount_cents` plus a value object (or `money-rails`) beats `t.decimal`. If you do use `decimal`, always state precision and scale - an unqualified `numeric` accepts anything and silently stores whatever it is given.

## Migrations

Treat the migration as a production operation, not a schema edit.

> The rules below are the summary. `migrations.md` in this directory is the long form, and it is where reversibility, the mechanics and failure modes of concurrent index builds, transactional DDL, expand/contract and batched backfills are actually explained. Read it before migrating a table that has rows in it.

Install `strong_migrations` - it will catch the classics before your DBA (or your 3am pager) does. The non-negotiables on PostgreSQL: `add_index` on any table with real rows must be `algorithm: :concurrently` with `disable_ddl_transaction!`; never combine that migration with anything else.

Adding a column with a default is safe on PG 11+, but adding `null: false` to an existing column is not - add a `CHECK (col IS NOT NULL) NOT VALID`, `VALIDATE CONSTRAINT` in a separate migration, then `SET NOT NULL`, which PG 12+ will accept using the validated constraint as proof.

Backfills belong in their own batched migration or a rake task, never in the same transaction as DDL. Renaming and dropping columns require the ignored-column dance (`self.ignored_columns +=`, deploy, then drop) because your old app processes are still running mid-deploy.

And switch to `schema_format = :sql`; `schema.rb` silently loses partial indexes, expression indexes, exclusion constraints, generated columns, and every extension you care about.

### Timeouts, and why a migration takes the site down without ever running

`strong_migrations` catches the dangerous *statements*. It does not save you from the dangerous *wait*, and the wait is what actually causes the outage.

`ALTER TABLE` needs an `ACCESS EXCLUSIVE` lock. If any transaction is currently reading that table - a long analytics query, an idle-in-transaction connection somebody left open in `psql` - your `ALTER` cannot start, so it queues. **And every query that arrives after it queues behind it**, because lock requests are FIFO and a pending `ACCESS EXCLUSIVE` request blocks the `ACCESS SHARE` locks that ordinary `SELECT`s need. Your migration never ran, changed nothing, and took the site down for as long as it was willing to wait.

**So `lock_timeout` is not optional.** Set it low, fail fast, and retry:

```ruby
class AddCurrencyToInvoices < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      execute "SET lock_timeout = '3s'"   # fail fast rather than queue the world
      add_column :invoices, :currency, :string
    end
  end
end
```

Three seconds is a reasonable default for a table under load: either you get the lock almost immediately or something is holding it and you want to know now, not after the pager has gone off. Retry the migration in a loop if you must; a failed attempt that changed nothing costs you nothing.

**`statement_timeout` is the same argument at the application level, and it is equally non-negotiable.** A web application serving many concurrent users must cap it at **60 seconds at the very most**, and lower is usually better. Nothing good happens to a web request at 60 seconds - the user left, the load balancer gave up, the client retried - and yet the query keeps running, keeps holding its snapshot, keeps pinning the rows autovacuum wants to reclaim, and keeps occupying a connection that the pool needs back. Without the cap, one bad query plan does not degrade the site; it takes it down and holds it there.

Set it per role, not per connection, so nobody can forget:

```sql
ALTER ROLE app_web        SET statement_timeout = '30s';
ALTER ROLE app_background SET statement_timeout = '10min';   -- jobs may take longer
ALTER ROLE app_readonly   SET statement_timeout = '5min';
```

Round it out with `idle_in_transaction_session_timeout` (kill the `psql` session somebody abandoned inside `BEGIN` - it blocks vacuum and holds locks indefinitely) and, on the pooled roles, a sane `idle_session_timeout`.

## Primary Keys

Primary keys should never be made composite or based on business-value columns. This is because business requirements change over time. Always create an ID column on all tables, and do not assign it any meaning other than a unique ID that may be referenced from elsewhere.

You have two choices in choosing the datatype for primary keys, which depends on the application you are building once again.

> [!CAUTION]
> The default datatype for auto-incrementing primary key is `integer` which is 32-bit and signed, and is therefore capped at 2,147,483,647 - a shade over 2.1 billion. Therefore modern applications almost never use the default data type.

### Data Types for Primary Keys

Primary keys often leak out to the web front-end in unexpected ways. You may be calling a REST API, and calling `/users/:id/settings` which anyone with Chrome Dev Tools can watch and realize that their user id is for instance, 10,000. Imagine using a web app that's 10 years old, and realizing you are only the 10,000th user on the entire system? That's not good. It also allows your competitors to inspect the sizes of your key tables by watching the RESTful API URLs and deducing it from there.

#### Bigint

If you do not care about any of the above, then use `bigint`, which tops out around 9.2 quintillion and will therefore never trouble you. And to confuse your competitors you don't even have to start at 1. You can always start the sequence at 1M, throwing anyone assuming they are auto-incrementing from 1 off. This data type is fast, compact (64-bits), but remembering to always start from some high random number may get tedious.

#### UUIDv7

**The answer to this nonsense is - UUID.** Be precise about the history: an extension has not been required to *generate* a UUID since PostgreSQL 13, when `gen_random_uuid()` moved into core and `pgcrypto` stopped being a prerequisite. What PostgreSQL 18 adds is `uuidv7()`, which is what makes a UUID primary key the most secure and modern data-independent ID strategy to reach for by default.

**What landed in 18:**

- `uuidv7()` - time-ordered UUIDs per RFC 9562. Postgres's implementation stuffs a 12-bit sub-millisecond timestamp fraction right after the millisecond timestamp (permitted, not required, by the spec), which gives you guaranteed monotonicity within a single backend process rather than just approximate ordering.
- `uuidv4()` - an alias for `gen_random_uuid()`, purely so your schema reads honestly about which version you asked for.
- `uuid_extract_timestamp()` (which arrived in 17) now understands v7, so you can recover the creation time from the key itself.

Also: use `uuid` primary keys, and `timestamptz` not `timestamp` - note that Rails does **not** do this for you; the PostgreSQL adapter still maps `t.datetime` to `timestamp without time zone`. Rails 7.0 added the opt-in, so set `ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.datetime_type = :timestamptz` in an initializer. Then real foreign keys with `add_foreign_key ... validate: false` then validate separately, and `citext` or a `CHECK` rather than three layers of Ruby validation pretending to be a constraint.

> [!NOTE]
> Early versions of Rails pretended that Rails validations are enough, and you do not need foreign keys. This was mostly motivated by the challenges in creating test fixtures in the right order (when FKs were enabled), and DHH's lack of understanding of databases deep enough to grok why that was a misnomer. **Do use foreign keys on ALL of your tables that have them.**

#### The Size of UUID

**Bytes:** a Postgres `uuid` is **16 bytes** (128 bits, twice the width of `bigint`), fixed-width, stored as a raw 128-bit value - not the 36-character text form you see in `psql`. Its alignment is char, so it doesn't force padding. Compare to `bigint` at 8 bytes. So the honest accounting is: +8 bytes per row in the heap, +8 per entry in the primary key index, and +8 in every single foreign key column and every index covering one. On a table with five FK references to it, you're paying that toll five times over. If anyone ever suggests storing UUIDs as `varchar(36)`, that's 37 bytes plus alignment slop, and you should look at them the way you'd look at someone who tunes a kick drum by ear at 3am.

**Why v7 matters more than the 8 bytes.** UUIDv4 is uniformly random, so every insert lands in a random B-tree leaf page. On a table bigger than `shared_buffers` that means a page fault per insert, catastrophic index bloat as pages split at ~50% fill instead of packing right-to-left, and a working set that is effectively the whole index. UUIDv7's leading timestamp restores the sequential insert locality that made `bigserial` fast - you get right-hand-side page splits, ~90% fill factor, and a hot tail that stays cached. Benchmarks vary wildly by workload, but the insert-throughput gap between v4 and v7 on large tables is routinely an order of magnitude, ***which dwarfs 8 bytes of width.***

**The tradeoff you should actually weigh:** v7 leaks creation timestamps to anyone holding the ID. If your IDs appear in URLs, that's an information disclosure - an attacker learns exactly when a record was created, and with enough IDs, your creation *rate*. For most apps that's fine. For anything where row-creation timing is sensitive, it isn't, and you want v4 (or a random surrogate for external exposure and a v7 internal key), despite the index performance penalty.

For your Rails work - this is the right moment to go UUID:

```ruby
create_table :boomerangs, id: :uuid, default: -> { "uuidv7()" } do |t|
  t.string :name, null: false
  t.timestamps
end
```

## N+1 Queries

Turn on `strict_loading` - per-association at first, then `config.active_record.strict_loading_by_default = true` in dev/test once you've cleaned up - so the failure is a raised exception at development time instead of 400 queries in production. `bullet` in dev is complementary and catches the inverse case (eager-loading you don't use).

Know the three loaders: `preload` does separate queries and is usually what you want; `eager_load` forces one `LEFT OUTER JOIN` and is right when you filter or order on the association; `includes` guesses between them and will silently switch to `eager_load` the moment you add `references` or a hash condition, which is how a fast page becomes a Cartesian explosion.

Use `joins` when you're only filtering and don't need the objects. Counter caches for `.count` in loops; `Model.where(id: ids).index_by(&:id)` when the association graph is awkward. And check your serializers and view partials - that's where N+1s hide, not in the controller where everyone looks. Finally, `ORDER BY ... LIMIT` on a joined query is the one shape where `preload` and `eager_load` differ semantically, so read the SQL rather than trusting the DSL.

## Concurrency Control and Locking

**PostgreSQL defaults to `READ COMMITTED`, and it is weaker than most people assume.** Each *statement* sees a fresh snapshot, so two `SELECT`s in one transaction can return different answers. A read-modify-write across statements - read the balance, compute, write it back - is a lost-update bug with a race window as wide as your application latency.

That much is universal. **What you do about it is class-dependent**, and the full treatment, including `SELECT ... FOR UPDATE`, `SERIALIZABLE` with retry loops, deadlock ordering and advisory locks, is in the `postgres-strict` skill, where it is mandatory. For a `PG-lax` application, `READ COMMITTED` plus optimistic locking is fine and the rest is ceremony; see the `postgres-lax` skill for where that stops being true.

## Connection Pooling

Postgres allocates a full backend process per connection. A few hundred of them is not concurrency, it is a scheduler thrashing, and the memory is real. Applications open far more connections than the database should ever see, which is why a pooler is not optional infrastructure at any meaningful scale.

**pgBouncer has been the answer for well over a decade and has been remarkably, boringly reliable** - a single small C process that does one thing and does not fall over. Its one long-standing wart was that transaction mode could not carry protocol-level prepared statements, which meant Rails users had to run with `prepared_statements: false` and give up the plan cache. Recent pgBouncer versions support prepared statements in transaction mode (via `max_prepared_statements`), so that objection has largely expired - check your deployed version before assuming either way.

It now has a growing field of competitors - pgcat, Supavisor, Odyssey, and the managed poolers baked into RDS and Cloud SQL - most offering multi-threading, better observability, or read/write splitting that pgBouncer deliberately never attempted. Evaluate them on operational maturity rather than feature lists; the reason pgBouncer endures is that it has already failed in every way it is going to.

### Pooling modes

| Mode            | Connection released to pool | Ratio you get                                | What breaks                                                                  |
| :-------------- | :-------------------------- | :------------------------------------------- | :--------------------------------------------------------------------------- |
| **Session**     | On client disconnect        | ~1:1. Basically useless as pooling.          | Nothing. Also saves you nothing.                                             |
| **Transaction** | On `COMMIT`/`ROLLBACK`      | 10:1 to 100:1. **This is the one you want.** | Advisory locks, `LISTEN`/`NOTIFY`, `SET`, temp tables, cursors outside a txn |
| **Statement**   | After each statement        | Highest                                      | Multi-statement transactions. Don't.                                         |

Transaction mode is the product. The breakage column is the price, and it is mostly avoidable: use *transaction-scoped* advisory locks, move `LISTEN`/`NOTIFY` to a dedicated unpooled connection, and set role-level defaults with `ALTER ROLE ... SET` instead of per-session `SET`.

### Sizing math

The number that matters isn't `max_connections`, it's:

```
pool_size ≈ (core_count × 2) + effective_spindle_count
```

For an 8-core box on NVMe that's roughly **16-20 server-side connections**. Everything above that is queueing, not concurrency. People routinely set `default_pool_size = 100` and then wonder why p99 got worse - you have just moved the queue from the pooler into Postgres, where it is more expensive and considerably less observable.

Client side you can accept thousands. **That asymmetry is the entire product.**

## Replicas and Replication Lag

Read replicas are the cheapest way to take load off the primary, and they introduce exactly one new class of bug: **you write to the primary and immediately read from a replica that has not caught up yet.** Lag is normally sub-millisecond and occasionally seconds, and it is never zero. Do not try to eliminate it - handle it.

Two rules hold for every class:

1. **Reads that must be authoritative do not go to a replica at all.** A balance you are about to debit, a uniqueness check, anything feeding a write decision - read it from the primary, under `FOR UPDATE` if it matters. Retry-on-miss is for display paths, not for correctness paths.
1. **Measure the lag, do not assume it.** `pg_last_xact_replay_timestamp()` on the replica and `pg_stat_replication` on the primary tell you what it actually is. Alert on it. A replica hours behind because a replication slot filled the disk is a different incident from the one you think you are debugging.

**The topology, the routing code and the retry patterns live in the `postgres-lax` skill**, in `references/replicas.md`, because a primary with many replicas is the characteristic `PG-lax` scaling shape. A `PG-strict` application uses replicas too, but far more narrowly; read that file, then read the constraints the `postgres-strict` skill puts on it.

## Observability

You cannot tune what you cannot see, and the single highest-value thing you can do is make the database *readable* - safely - by the people and tools trying to understand it.

Of course I'd love for you to use Datadog, NewRelic, HoneyComb, and so on and so forth. But, if you know where to look, or if you played with `pganalyze` before, then you know how deep performance tuning of PG queries can go.

### A read-only role, and let the agents use it

Create a genuinely read-only production role. Not "a role we agreed not to write with" - one that cannot write:

```sql
CREATE ROLE app_readonly LOGIN PASSWORD '...';
GRANT CONNECT ON DATABASE app_production TO app_readonly;
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_readonly;
ALTER ROLE app_readonly SET statement_timeout = '5min';
ALTER ROLE app_readonly SET default_transaction_read_only = on;
```

Point it at a replica if you have one, so an exploratory query cannot compete with production traffic.

**Then give those credentials - and only those - to a trusted PostgreSQL MCP server.** An agent that can read `pg_stat_statements`, `EXPLAIN` a plan and inspect the schema is dramatically more useful at diagnosing a slow endpoint than one being fed pasted query text. And a read-only role plus a statement timeout plus `default_transaction_read_only` means the worst outcome is a wasted five minutes rather than a destroyed table. Vet the MCP server itself the way you would vet anything holding production credentials.

### What to read once you are in

`pg_stat_statements` first, always. It is an extension, it costs nearly nothing, and it answers the only question that matters at the start: *what is actually consuming the time?* Sort by `total_exec_time`, not `mean_exec_time` - the query that takes 3ms and runs two million times is your problem, and it never appears in a slow query log.

PostgreSQL 18 ships roughly **forty-six** `pg_stat*` views, and the useful ones beyond the obvious are:

- **`pg_stat_activity`** - what is running *right now*, and crucially `wait_event_type` / `wait_event`, which tell you whether you are CPU-bound, lock-bound or IO-bound instead of guessing.
- **`pg_stat_io`** - reads, writes, extends and evictions broken out by backend type and context. This is how you learn that your "slow queries" are actually checkpoint storms.
- **`pg_stat_user_tables`** - `n_dead_tup`, `n_tup_hot_upd`, and `last_autovacuum`. The HOT ratio here is what the Deletes section above is really about, and a table where autovacuum has not run in weeks is a bloat incident waiting to be discovered.
- **`pg_stat_user_indexes`** - `idx_scan = 0` over a meaningful window is your kill list, as noted in the Indexes section.
- **`pg_stat_progress_create_index`** and **`pg_stat_progress_vacuum`** - how far along that `CREATE INDEX CONCURRENTLY` actually is, rather than staring at a hung terminal.
- **`pg_stat_replication`** - lag, per replica, in bytes and in time.

Add `auto_explain` with a threshold (`auto_explain.log_min_duration = '500ms'`, `log_analyze = on`) so the plan for a slow query is in the log at the moment it was slow, rather than the plan you get re-running it later against a warm cache and different statistics. And when you do explain by hand, it is `EXPLAIN (ANALYZE, BUFFERS)` - without `BUFFERS` you cannot distinguish "read from memory" from "read from disk", which is usually the entire question. On PostgreSQL 18 `BUFFERS` is included automatically whenever `ANALYZE` is used, so the explicit option only matters on 17 and older.

## Vector Search

`pgvector` is the reason you do not need a separate vector database for most workloads: keeping embeddings in the same transaction as the row they describe removes an entire class of consistency bug, and the join back to your relational data is free.

**Store the dimension in the type** - `vector(1536)` - because a mismatched dimension should be a constraint violation at insert, not a confusing distance result at query time. Above 2000 dimensions a `vector` cannot be indexed at all; use `halfvec` (16-bit floats, half the size, indexable to 4000 dimensions) which costs almost nothing in recall for typical embeddings.

**Match the operator class to your distance function or the index is silently ignored.** `vector_cosine_ops` with `<=>`, `vector_l2_ops` with `<->`, `vector_ip_ops` with `<#>`. This is the single most common pgvector mistake: the index exists, the query is a sequential scan, and nothing warns you. Check with `EXPLAIN`.

**HNSW over IVFFlat** for essentially every new build. HNSW gives better recall at a given speed, does not need to be rebuilt as data changes, and - decisively - can be built on an empty table, whereas IVFFlat must be built *after* the data is loaded because its centroids are derived from it. IVFFlat's remaining advantage is faster build time and smaller index size, which matters at very large scale.

```sql
CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE documents ADD COLUMN embedding vector(1536);

CREATE INDEX CONCURRENTLY ON documents
  USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

Tuning, briefly: `m` and `ef_construction` are build-time and trade index size and build time for recall; `hnsw.ef_search` (default 40) is query-time and trades latency for recall - raise it until recall is acceptable, then stop. Build indexes with a large `maintenance_work_mem`, because an HNSW build that does not fit in memory takes hours instead of minutes.

Two things people discover late. **Filtered vector search is the hard part**: `WHERE tenant_id = ? ORDER BY embedding <=> ?` may over-filter after the index scan and return fewer rows than `LIMIT` asked for. Partial HNSW indexes per high-cardinality filter, or raising `ef_search`, are the usual answers. And **embeddings are large** - 1536 dimensions at 4 bytes is 6KB per row, which will be TOASTed out of line and quietly dominate your table size. `halfvec` halves it.
