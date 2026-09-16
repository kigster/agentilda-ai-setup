# Audit Trails

An audit trail answers one question under oath: **who changed what, when, and what did it look like before?** In a `PG-strict` application that question arrives from an auditor, a regulator, or a lawyer, and "we log some of it in the application" is not an answer.

## Do it in the database, not in the application

Application-level auditing (Rails callbacks, `paper_trail`, a service object) misses every write that does not go through the application: a migration, a rake task, a console session, a support tool, a replication fix at 3am. Those are exactly the writes an auditor asks about.

**Triggers see every write.** That is the whole argument.

`paper_trail` remains useful *in addition*, because it records application-level intent - which controller, which user session, which request id - that the database cannot know. Use both if you like. Do not use only the first.

## The table

One audit table for the whole schema, partitioned by month, is easier to retain and drop than one per table:

```sql
CREATE TABLE audit_log (
  id           bigint GENERATED ALWAYS AS IDENTITY,
  table_name   text        NOT NULL,
  record_id    text        NOT NULL,
  operation    text        NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
  changed_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  actor        text        NOT NULL,
  tenant_id    uuid,
  old_values   jsonb,
  new_values   jsonb,
  changed_keys text[]
) PARTITION BY RANGE (changed_at);

CREATE TABLE audit_log_2026_09 PARTITION OF audit_log
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');

CREATE INDEX ON audit_log (table_name, record_id, changed_at DESC);
CREATE INDEX ON audit_log USING gin (changed_keys);
```

Three choices worth defending:

- **`clock_timestamp()`, not `now()`.** `now()` is the transaction start time, so every row written by one transaction gets an identical timestamp and you lose the ordering within it. `clock_timestamp()` advances.
- **`jsonb` for the values**, because the audited tables have different shapes and will change shape. Store the whole row, not a diff; `changed_keys` gives you the diff cheaply without losing the context.
- **`record_id text`**, so one table serves `uuid` and `bigint` keys alike.

## The trigger

One generic function, attached to every audited table:

```sql
CREATE FUNCTION audit_changes() RETURNS trigger
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  old_j jsonb := CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END;
  new_j jsonb := CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END;
BEGIN
  INSERT INTO audit_log (table_name, record_id, operation, actor, tenant_id,
                         old_values, new_values, changed_keys)
  VALUES (
    TG_TABLE_NAME,
    COALESCE(new_j ->> 'id', old_j ->> 'id'),
    TG_OP,
    COALESCE(nullif(current_setting('app.actor', true), ''), session_user),
    nullif(current_setting('app.tenant_id', true), '')::uuid,
    old_j,
    new_j,
    CASE WHEN TG_OP = 'UPDATE' THEN
      ARRAY(SELECT key FROM jsonb_each(new_j)
             WHERE new_j -> key IS DISTINCT FROM old_j -> key)
    END
  );
  RETURN NULL;   -- AFTER trigger: the return value is ignored
END;
$$;

CREATE TRIGGER invoices_audit
  AFTER INSERT OR UPDATE OR DELETE ON invoices
  FOR EACH ROW EXECUTE FUNCTION audit_changes();
```

Notes that matter:

- **`AFTER`, not `BEFORE`.** A `BEFORE` trigger can be skipped by a later trigger returning NULL, and it records values that may not be what was committed.
- **`SECURITY DEFINER` with an explicit `search_path`.** The function must be able to write `audit_log` even though the application role cannot write it directly. Without the pinned `search_path` that is a privilege escalation waiting for somebody to create a table with the same name in a schema earlier in the path.
- **`app.actor` comes from the same session-variable pattern as RLS** - set it per transaction with `set_config(..., true)`. Fall back to `session_user` so a console session is still attributed to somebody.

## Make the log itself append-only

An audit trail that can be edited is not evidence.

```sql
REVOKE UPDATE, DELETE ON audit_log FROM PUBLIC, app_web, app_worker;
GRANT  SELECT          ON audit_log TO   app_auditor;

CREATE TRIGGER audit_log_immutable
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION forbid_mutation();
```

The application role should not hold `INSERT` on `audit_log` either; the `SECURITY DEFINER` trigger is the only writer.

## Cost, and what to audit

Every audited write becomes two writes, and `to_jsonb(OLD)` on a wide row is not free. Measure before assuming it is fine, and be deliberate:

- **Audit** money, entitlements, PII, anything a regulator names, and anything whose change would be disputed.
- **Do not audit** high-churn operational tables - sessions, job queues, caches, read counters. They generate the majority of the volume and none of the evidence.
- **Exclude noisy columns** if a table is otherwise worth auditing: a trigger with `WHEN (OLD.* IS DISTINCT FROM NEW.*)` skips no-op updates entirely, and a column list in the `UPDATE OF` clause narrows it further.

```sql
CREATE TRIGGER invoices_audit
  AFTER UPDATE OF amount_cents, status, tenant_id ON invoices
  FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*)
  EXECUTE FUNCTION audit_changes();
```

## Retention

Partitioning by month is what makes retention a one-line operation instead of a `DELETE` that bloats the table:

```sql
ALTER TABLE audit_log DETACH PARTITION audit_log_2019_01;   -- archive it
DROP TABLE audit_log_2019_01;                               -- or drop, if policy allows
```

Write the retention period down, in the schema or next to it, and make sure it matches the one legal thinks applies. The common failure is not keeping too little - it is keeping everything forever, including the PII you told users you had deleted.
