# Encryption, Grants, and Least Privilege

Three layers, and they defend against different things. Confusing them is how a system ends up with one layer three times over and the other two missing.

| Layer                               | Defends against                                                                  | Does not defend against                                          |
| :---------------------------------- | :------------------------------------------------------------------------------- | :--------------------------------------------------------------- |
| Encryption at rest (volume/cluster) | A stolen disk, a decommissioned drive, a cloud snapshot leak                     | Anyone with a working connection. Which is everyone who matters. |
| TLS in transit                      | Network interception, a compromised load balancer path                           | The endpoints                                                    |
| Column encryption                   | A leaked backup, a read-only breach, an over-broad `SELECT`, an over-curious DBA | A compromised application that holds the key                     |

## At rest and in transit: the easy ones

**At rest** is a cloud provider checkbox (RDS, Cloud SQL, or LUKS on your own hardware). Turn it on at creation - you cannot turn it on later without a rebuild - and move on. It costs nothing and satisfies a compliance question you would otherwise argue about.

**In transit** is `ssl = on` plus refusing non-TLS connections in `pg_hba.conf`:

```
# pg_hba.conf - TLS with certificate verification, no exceptions
hostssl  app_production  app_web      10.0.0.0/8  scram-sha-256
hostnossl all            all          all         reject
```

Client side, `sslmode=verify-full` is the only setting that actually verifies anything. `require` encrypts and does not check who it is talking to, which stops a passive eavesdropper and not an active one.

```
DATABASE_URL=postgres://app_web@pg-primary/app_production?sslmode=verify-full&sslrootcert=/etc/ssl/certs/pg-ca.pem
```

## Column encryption: decide what, and where

The question is not "which algorithm". It is **where the key lives**, and that determines what you are protected from.

**Application-side encryption is the default answer.** The key lives in the application's secret store (Rails credentials, `sopsy`, a KMS), the database sees ciphertext, and a database breach yields nothing. Rails ships this as Active Record Encryption:

```ruby
class Patient < ApplicationRecord
  encrypts :ssn, deterministic: true     # equality queries still work
  encrypts :diagnosis_notes              # randomized: no queries, better secrecy
end
```

`deterministic: true` means the same plaintext produces the same ciphertext, so `where(ssn: value)` works and the column can be unique-indexed. It also means an attacker holding the ciphertext can tell which rows share a value, and can confirm a guess. Use it only where you must query by the column.

**`pgcrypto` puts the key in the database, or in the query.** That is a narrower win than it appears:

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

INSERT INTO patients (ssn_encrypted)
  VALUES (pgp_sym_encrypt('123-45-6789', current_setting('app.column_key')));

SELECT pgp_sym_decrypt(ssn_encrypted, current_setting('app.column_key')) FROM patients;
```

> [!CAUTION]
> **A key passed in a query is a key in `pg_stat_statements`, in the slow query log, and in `auto_explain` output.** Use `current_setting` from a per-transaction session variable rather than a literal, never log statements on a role that decrypts, and understand that anyone who can read the logs can read the data. If the threat model includes the database administrator, `pgcrypto` does not address it and application-side encryption does.

`pgcrypto` earns its place for **hashing** rather than encryption - `crypt()` with `gen_salt('bf', 12)` for anything password-shaped - and for encrypting a column that only a database-side job ever touches.

**What to encrypt at the column level**: government identifiers, financial account numbers, health data, authentication secrets, and anything a regulation names. **What not to**: the entire table. Encrypted columns cannot be indexed usefully (except deterministically), cannot be range-queried, and cannot be joined on. Encrypting everything produces a schema nobody can query and a false sense of safety.

## Grants and least privilege

The application should not connect as the role that owns the tables. That single change turns "the application can drop a table" into "the application cannot drop a table", and it is what makes `FORCE ROW LEVEL SECURITY` meaningful.

```sql
-- Owner: migrations only, never an application process
CREATE ROLE app_owner  NOLOGIN;
CREATE ROLE app_migrator LOGIN PASSWORD '...' IN ROLE app_owner;

-- The application: DML on tables it needs, nothing else
CREATE ROLE app_web    LOGIN PASSWORD '...';
GRANT CONNECT ON DATABASE app_production TO app_web;
GRANT USAGE   ON SCHEMA public           TO app_web;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_web;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_web;

-- And for tables created later, which is the step everyone forgets
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE ON TABLES TO app_web;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT USAGE ON SEQUENCES TO app_web;

-- Read-only, for humans and agents
CREATE ROLE app_readonly LOGIN PASSWORD '...';
GRANT CONNECT ON DATABASE app_production TO app_readonly;
GRANT USAGE   ON SCHEMA public           TO app_readonly;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO app_readonly;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
  GRANT SELECT ON TABLES TO app_readonly;
ALTER ROLE app_readonly SET statement_timeout = '5min';
ALTER ROLE app_readonly SET default_transaction_read_only = on;
```

Notice what `app_web` does **not** get: `DELETE` (a `PG-strict` schema deletes logically, so the application never needs it), `TRUNCATE`, `REFERENCES`, or any privilege on `audit_log` beyond what the `SECURITY DEFINER` audit trigger exercises on its behalf.

**`PUBLIC` is a real role and it starts with privileges.** On PostgreSQL 14 and earlier, every role can create objects in `public`; from 15 that is fixed by default. Revoke it anyway, explicitly, so the schema does not depend on the server version:

```sql
REVOKE CREATE  ON SCHEMA public   FROM PUBLIC;
REVOKE CONNECT ON DATABASE app_production FROM PUBLIC;
```

## Key custody

The encryption is the easy half. The key is the part that gets lost, and a lost key is indistinguishable from deleted data.

1. **Keys live in a secret manager**, not in the repository, not in an environment file on disk, not in the database. For Rails, credentials; otherwise `sopsy` with the encrypted `.env.encrypted` committed and decrypted into the environment at boot.
1. **Plan the rotation before you need it.** Rotating means re-encrypting every affected row, which means a batched backfill and a period where both keys must decrypt. Active Record Encryption supports a previous-key list for exactly this; design for it on day one rather than discovering it during an incident.
1. **A backup of the ciphertext without the key is not a backup.** Store the key escrow separately from the database backups, and test the restore path including decryption, because the first real test should not be the first real disaster.
