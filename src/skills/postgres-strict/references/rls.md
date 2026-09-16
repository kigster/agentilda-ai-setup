# Row-Level Security and Multi-Tenancy

Row-level security (RLS) moves the `WHERE tenant_id = ?` predicate out of the application and into the database, where forgetting it is impossible rather than merely discouraged. For a `PG-strict` application holding several customers' data in one schema, it is the difference between a bug and a breach.

## The mechanism, briefly

A policy is a predicate the server silently ANDs onto every query against a table, per command, per role. Two statements turn it on, and both are required:

```sql
ALTER TABLE invoices ENABLE  ROW LEVEL SECURITY;   -- policies now apply
ALTER TABLE invoices FORCE   ROW LEVEL SECURITY;   -- they apply to the table owner too
```

> [!CAUTION]
> **`ENABLE` alone does not protect you from the table owner.** The owner, and anything running as it, bypasses every policy. Since Rails and most frameworks connect as the role that created the tables, `ENABLE` without `FORCE` is security theatre. Either `FORCE` it, or connect the application as a role that does not own the schema - the second is cleaner, and you should do both.

With RLS enabled and no policy present, the table returns zero rows. That is the correct failure direction, and it is also how a missing policy is discovered in staging rather than in production.

## The tenant pattern

Carry the current tenant in a session variable, set once per transaction, and write policies against it.

```sql
-- One reusable accessor. STABLE, not IMMUTABLE: it varies per transaction.
CREATE FUNCTION current_tenant_id() RETURNS uuid
  LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('app.tenant_id', true), '')::uuid;
$$;

CREATE POLICY invoices_tenant_isolation ON invoices
  USING      (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());
```

`USING` filters what the query can *see* (`SELECT`, `UPDATE`, `DELETE`). `WITH CHECK` constrains what it can *write* (`INSERT`, `UPDATE`). **Write both.** A policy with only `USING` lets a tenant insert a row belonging to another tenant, which it then cannot see - a silent, one-way data leak into somebody else's account.

Set the variable at the start of every transaction, never at connection time:

```ruby
class ApplicationRecord < ActiveRecord::Base
  def self.with_tenant(tenant_id)
    transaction do
      connection.exec_update(
        "SELECT set_config('app.tenant_id', $1, true)", nil, [tenant_id.to_s]
      )
      yield
    end
  end
end
```

> [!CAUTION]
> **The third argument to `set_config` must be `true`** - it scopes the setting to the transaction. With `false` the setting persists on the connection, and under a transaction-mode pooler that connection goes back to the pool still carrying the previous tenant's identity. That is the single worst bug this pattern can produce, and it does not reproduce in development where the pool is one connection per process.

## Policies beyond tenancy

Policies are per command and per role, which is how you express rules that would otherwise be scattered through application code:

```sql
-- Nobody, including the application, sees logically deleted rows by default
CREATE POLICY invoices_live_only ON invoices
  FOR SELECT TO app_web
  USING (deleted_at IS NULL);

-- Support staff read everything in their tenant but cannot write
CREATE POLICY invoices_support_read ON invoices
  FOR SELECT TO app_support
  USING (tenant_id = current_tenant_id());

-- Only the billing role may insert ledger rows
CREATE POLICY ledger_insert ON ledger_entries
  FOR INSERT TO app_billing
  WITH CHECK (tenant_id = current_tenant_id());
```

**Multiple permissive policies on the same command are ORed.** That surprises people: adding a policy widens access unless you declare it `AS RESTRICTIVE`, which ANDs it instead. Use restrictive policies for rules that must hold no matter what else is granted:

```sql
CREATE POLICY invoices_tenant_required ON invoices
  AS RESTRICTIVE
  USING (tenant_id = current_tenant_id());
```

## The escape hatches, and how to keep them small

Migrations, backfills, and admin tooling legitimately need to cross tenants. Give them a role that is allowed to, rather than disabling policies:

```sql
CREATE ROLE app_migrator LOGIN BYPASSRLS;
```

Rules for `BYPASSRLS`:

1. It is a role attribute, not a grant, and it bypasses **every** policy on **every** table. Treat it as production root.
1. No application process ever uses it. Migrations and one-off scripts only.
1. It does not go in the same secret store as the application credentials, and its use is logged.

## Performance

A policy is a predicate, and the planner treats it as one. Two things follow:

1. **Index the policy columns.** `tenant_id` belongs in the leading position of most composite indexes on a multi-tenant table: `(tenant_id, created_at DESC) WHERE deleted_at IS NULL`. Without that, every query is a full scan the policy then filters.
1. **A function in a policy must be `STABLE`, and cheap.** `current_setting()` is; a lookup joining three tables is not, and it will run per row. If the policy needs a set of ids, put them in the session variable rather than deriving them in the predicate.

Check the plan with `EXPLAIN` as the application role, not as the owner - as the owner the policy is not applied and the plan you are reading is not the plan you will get.

## Testing

RLS is only worth having if it is tested, and the test is simple: connect as the application role, set tenant A, and assert that tenant B's rows are invisible and uninsertable.

```sql
SET ROLE app_web;
SELECT set_config('app.tenant_id', '<tenant-a-uuid>', false);

SELECT count(*) FROM invoices;                       -- only tenant A
INSERT INTO invoices (tenant_id, ...) VALUES ('<tenant-b-uuid>', ...);
-- ERROR: new row violates row-level security policy for table "invoices"
```

Put that in the test suite for every table with a policy. A policy nobody tested is a policy that was silently dropped by a migration three months ago.
