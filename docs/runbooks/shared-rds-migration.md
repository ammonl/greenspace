# Shared-RDS Data Migration Runbook

## Overview

This runbook covers moving the Greenspace schema and data from the dedicated
per-environment RDS instances onto the centralized shared RDS owned by
`ammonlarson/infra-shared-db`. It is the data-preparation step. The
application cutover (env var flip, Lambda redeploy, smoke tests) is tracked
separately in #340 and uses this runbook as a prerequisite.

Scope:

- Backup and export of source databases (staging and prod).
- Schema deployment into the empty shared targets (`greenspace_staging`,
  `greenspace_prod`).
- Production data restore into `greenspace_prod`.
- Staging data handling — explicitly **no raw prod PII into staging**.
- Validation queries.
- Rollback plan.

Out of scope: tearing down the dedicated RDS instances (#337), wiring the
runtime to the shared-db secret contract (#342), the cutover itself (#340),
and connectivity (#338, already shipped — see ADR-0001).

## Expected duration and on-call

End-to-end runtime, from the first snapshot kicked off in Phase 1 to a
green Phase 5 validation, is roughly:

| Phase | Activity | Wall time |
|-------|----------|-----------|
| 1.1   | RDS manual snapshots (both envs) | 5–15 min (parallel) |
| 1.2   | `pg_dump` of both sources via SSM | 1–2 min each |
| 1.3   | Source row-count capture | < 1 min |
| 2     | `db:setup` against both shared targets | 1–2 min each |
| 3     | Truncate + `pg_restore` for prod | 1–2 min |
| 4     | Staging admin rotation | < 1 min |
| 5     | Validation queries + diff | 2–5 min |

Total operator time: **~30 minutes of active work**. Schedule a 60-minute
window to absorb retries.

On-call: ammonl is the primary contact. The runbook is written so a single
operator can execute it; pair only if that operator wants a second pair of
eyes on Phase 5 diffs before signalling "good to cut over" to #340.

## Prerequisites

- Operator workstation IP `/32` is currently in `allowed_ingress_cidrs` on
  the shared RDS (set in `infra-shared-db/terraform.tfvars`).
- `psql` and `pg_dump`/`pg_restore` (Postgres 16 client) available locally.
- AWS CLI logged in with permission to:
  - read `greenspace-<env>-2026-db-credentials` secrets (dedicated RDS
    master credentials).
  - read `rds/shared/greenspace_<env>` secrets (shared-db per-project
    credentials).
  - create RDS manual snapshots on `greenspace-<env>-2026-postgres`.
- Both shared-db projects exist in state (i.e. `infra-shared-db`
  PR #15 merged and applied locally per `ADDING_A_PROJECT.md`).
- Source databases are quiet enough for the export to be consistent. For
  production this means running this immediately before #340 cutover, after
  registration is closed or while traffic is gated.

## Source-DB access path

The dedicated Greenspace RDS instances are **not** publicly accessible.
Their Terraform module does not set `publicly_accessible`, so the AWS
default (`false`) applies, and the DB security group only permits ingress
from the Lambda security group. The operator laptop cannot dial them
directly. To run `pg_dump` and `psql` from the laptop, open a port-forward
through a temporary EC2 bastion in the Greenspace VPC using SSM Session
Manager.

Bastion bootstrap (do this once, in each environment that you're operating
on, before Phase 1.2):

```bash
ENV=prod   # or staging
NAMING_PREFIX=greenspace-${ENV}-2026

# Pick a private subnet in the Greenspace VPC.
PRIV_SUBNET=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=${NAMING_PREFIX}-private-*" \
  --query 'Subnets[0].SubnetId' --output text --region eu-north-1)

# Create a one-off SG that allows egress to the RDS SG on 5432.
DB_SG=$(aws rds describe-db-instances \
  --db-instance-identifier ${NAMING_PREFIX}-postgres \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text --region eu-north-1)

# Launch a t3.nano Amazon Linux 2023 instance with the SSM-managed IAM
# instance profile (AmazonSSMManagedInstanceCore). It needs no public IP.
# Add an ingress rule on $DB_SG allowing 5432 from the bastion's SG.

# Then forward the RDS endpoint to localhost:
aws ssm start-session \
  --target <bastion-instance-id> \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "host=$SRC_PROD_HOST,portNumber=5432,localPortNumber=5432" \
  --region eu-north-1
```

With the port-forward open, every command in Phases 1–3 that connects to
the source RDS uses `--host=localhost` and the credentials from Secrets
Manager. The bastion is destroyed when the migration window closes.

If two source endpoints need to be reached concurrently (staging and prod
in the same shell), forward them to different local ports (`5433` for the
second one) and adjust the `--host` / `--port` flags accordingly.

## Variables used below

```bash
# Source (dedicated) — host is fetched for completeness; actual psql/pg_dump
# connections go through the SSM port-forward at localhost.
SRC_PROD_HOST=$(aws secretsmanager get-secret-value --secret-id greenspace-prod-2026-db-credentials --query SecretString --output text | jq -r .host)
SRC_STG_HOST=$(aws secretsmanager get-secret-value --secret-id greenspace-staging-2026-db-credentials --query SecretString --output text | jq -r .host)
SRC_PROD_PASS=$(aws secretsmanager get-secret-value --secret-id greenspace-prod-2026-db-credentials --query SecretString --output text | jq -r .password)
SRC_STG_PASS=$(aws secretsmanager get-secret-value --secret-id greenspace-staging-2026-db-credentials --query SecretString --output text | jq -r .password)

# Target (shared) — the shared-db RDS is publicly accessible with the
# operator /32 in `allowed_ingress_cidrs`, so connections go direct.
SHARED_HOST=$(aws secretsmanager get-secret-value --secret-id rds/shared/greenspace_prod --query SecretString --output text | jq -r .host)
TGT_PROD_USER=$(aws secretsmanager get-secret-value --secret-id rds/shared/greenspace_prod --query SecretString --output text | jq -r .username)
TGT_PROD_PASS=$(aws secretsmanager get-secret-value --secret-id rds/shared/greenspace_prod --query SecretString --output text | jq -r .password)
TGT_PROD_DB=$(aws secretsmanager get-secret-value --secret-id rds/shared/greenspace_prod --query SecretString --output text | jq -r .dbname)

TGT_STG_USER=$(aws secretsmanager get-secret-value --secret-id rds/shared/greenspace_staging --query SecretString --output text | jq -r .username)
TGT_STG_PASS=$(aws secretsmanager get-secret-value --secret-id rds/shared/greenspace_staging --query SecretString --output text | jq -r .password)
TGT_STG_DB=$(aws secretsmanager get-secret-value --secret-id rds/shared/greenspace_staging --query SecretString --output text | jq -r .dbname)
```

The shared-RDS host is the same for both projects; only the database/role
differ.

## Phase 1 — Backup the source databases

Take both forms of backup before doing anything destructive: a manual RDS
snapshot (the rollback artifact) and a `pg_dump --format=custom` (the
migration source for prod, archive-only for staging).

### 1.1 Manual RDS snapshots

```bash
TS=$(date -u +%Y%m%d-%H%M)

aws rds create-db-snapshot \
  --db-instance-identifier greenspace-prod-2026-postgres \
  --db-snapshot-identifier greenspace-prod-2026-pre-shared-cutover-$TS \
  --region eu-north-1

aws rds create-db-snapshot \
  --db-instance-identifier greenspace-staging-2026-postgres \
  --db-snapshot-identifier greenspace-staging-2026-pre-shared-cutover-$TS \
  --region eu-north-1
```

Wait for both to reach `available`:

```bash
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier greenspace-prod-2026-pre-shared-cutover-$TS \
  --region eu-north-1

aws rds wait db-snapshot-completed \
  --db-snapshot-identifier greenspace-staging-2026-pre-shared-cutover-$TS \
  --region eu-north-1
```

These snapshots are retained independently of the source instance's
`backup_retention_period` and survive instance deletion. Keep both for at
least 30 days post-cutover.

### 1.2 `pg_dump` exports

Run with the SSM port-forward from the **Source-DB access path** section
already open. Each invocation connects to `localhost:<forwarded-port>`.

```bash
mkdir -p ./greenspace-cutover-$TS
cd ./greenspace-cutover-$TS

# Port-forward 5432 → prod RDS first.
PGPASSWORD="$SRC_PROD_PASS" pg_dump \
  --host=localhost \
  --port=5432 \
  --username=greenspace \
  --dbname=greenspace \
  --format=custom \
  --no-owner \
  --no-acl \
  --verbose \
  --file=greenspace_prod.dump

# Tear down the prod port-forward, open one for staging on 5432 (or run
# the second forward on 5433 and pass --port=5433 here).
PGPASSWORD="$SRC_STG_PASS" pg_dump \
  --host=localhost \
  --port=5432 \
  --username=greenspace \
  --dbname=greenspace \
  --format=custom \
  --no-owner \
  --no-acl \
  --verbose \
  --file=greenspace_staging.dump
```

Both files contain schema **and** data. We will use the prod dump's data
section in Phase 3. The staging dump is archived for reference only — see
Phase 4 for why staging is rebuilt rather than restored.

The Greenspace dataset is small (single-digit MB at the time of writing),
so each dump completes in well under a minute. If the run takes longer
than ~5 minutes, suspect the port-forward has stalled — restart the SSM
session.

### 1.3 Capture pre-migration baselines (prod only)

These values are diffed against the shared target in Phase 5. Run them
with the SSM port-forward to prod still open.

```bash
PGPASSWORD="$SRC_PROD_PASS" psql -h localhost -p 5432 -U greenspace -d greenspace -c "
  SELECT 'greenhouses' AS t, count(*) FROM greenhouses
  UNION ALL SELECT 'planter_boxes', count(*) FROM planter_boxes
  UNION ALL SELECT 'admins', count(*) FROM admins
  UNION ALL SELECT 'admin_credentials', count(*) FROM admin_credentials
  UNION ALL SELECT 'admin_notification_preferences', count(*) FROM admin_notification_preferences
  UNION ALL SELECT 'sessions', count(*) FROM sessions
  UNION ALL SELECT 'system_settings', count(*) FROM system_settings
  UNION ALL SELECT 'registrations', count(*) FROM registrations
  UNION ALL SELECT 'waitlist_entries', count(*) FROM waitlist_entries
  UNION ALL SELECT 'emails', count(*) FROM emails
  UNION ALL SELECT 'audit_events', count(*) FROM audit_events
  ORDER BY 1;
" | tee prod-source-counts.txt

PGPASSWORD="$SRC_PROD_PASS" psql -h localhost -p 5432 -U greenspace -d greenspace -c "
  SELECT 'max_audit_ts' AS k, max(timestamp)::text  AS v FROM audit_events
  UNION ALL SELECT 'max_reg_created', max(created_at)::text FROM registrations
  UNION ALL SELECT 'max_wait_created', max(created_at)::text FROM waitlist_entries
  UNION ALL SELECT 'max_email_created', max(created_at)::text FROM emails
  UNION ALL SELECT 'system_settings_count', count(*)::text FROM system_settings;
" | tee prod-source-baselines.txt
```

`system_settings_count` should be exactly `1` — the table is a singleton
holding the current `opening_datetime`. Anything else means the source is
in an unexpected state; investigate before proceeding.

## Phase 2 — Bring the shared targets to current schema

Both shared-db project databases are empty. Run the app's existing inline
migrator against each. There are two paths; pick the one that matches where
in the cutover sequence you are.

### 2a. From the operator laptop (recommended pre-#342)

```bash
cd <repo root>

# Production target
DB_HOST="$SHARED_HOST" \
DB_PORT=5432 \
DB_NAME="$TGT_PROD_DB" \
DB_USER="$TGT_PROD_USER" \
DB_PASSWORD="$TGT_PROD_PASS" \
DB_SSL=true \
SEED_ADMIN_PASSWORD="<set this>" \
npm run db:setup --workspace=@greenspace/api

# Staging target
DB_HOST="$SHARED_HOST" \
DB_PORT=5432 \
DB_NAME="$TGT_STG_DB" \
DB_USER="$TGT_STG_USER" \
DB_PASSWORD="$TGT_STG_PASS" \
DB_SSL=true \
SEED_ADMIN_PASSWORD="<set this>" \
npm run db:setup --workspace=@greenspace/api
```

`db:setup` runs `migrateToLatest` followed by `seed`. The seed inserts
greenhouses, the 29-box catalog, and the default admin row. The greenhouses
and boxes are reference data — they're identical in source and target. The
default admin row will be replaced by the prod admin data in Phase 3, so
`SEED_ADMIN_PASSWORD` for the prod target is irrelevant (set anything; it
will be overwritten).

For staging, the seeded admin password matters — keep it short-lived and
rotate after cutover.

### 2b. Via the Lambda one-shot (post-#342, pre-cutover)

Once #342 has wired the runtime to read `DB_SECRET_ID`:

```bash
aws lambda invoke \
  --function-name greenspace-prod-2026-api \
  --payload '{"action":"migrate"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/migrate-prod.json

aws lambda invoke \
  --function-name greenspace-staging-2026-api \
  --payload '{"action":"migrate"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/migrate-staging.json
```

Each response body (the `body` field of `LambdaResponse`) should be the
JSON `{"task":"migrate","executedMigrations":["001_initial_schema", ...],"seeded":true}`
with `statusCode` 200. On failure the body is
`{"task":"migrate","error":"<message>"}` with `statusCode` 500. See the
handler in `apps/api/src/index.ts`.

### 2.1 Verify schema landed on both targets

```bash
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" -c "\dt"
PGPASSWORD="$TGT_STG_PASS"  psql -h "$SHARED_HOST" -U "$TGT_STG_USER"  -d "$TGT_STG_DB"  -c "\dt"
```

Expected tables: `admin_credentials`, `admin_notification_preferences`,
`admins`, `audit_events`, `emails`, `greenhouses`, `kysely_migration`,
`kysely_migration_lock`, `planter_boxes`, `registrations`, `sessions`,
`system_settings`, `waitlist_entries`.

Confirm `kysely_migration` lists every entry from
`apps/api/src/db/migration-registry.ts`.

## Phase 3 — Restore production data into `greenspace_prod`

Production-only step. Staging is handled in Phase 4.

### 3.1 Truncate the seed reference rows

The Phase 2 seed put greenhouses, boxes, and a default admin into
`greenspace_prod`. Clear them so the prod data restore is the sole source
of those rows. `audit_events` is empty at this stage — no trigger conflict.

```bash
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" <<'SQL'
BEGIN;
TRUNCATE TABLE
  audit_events,
  emails,
  waitlist_entries,
  registrations,
  sessions,
  system_settings,
  admin_notification_preferences,
  admin_credentials,
  admins,
  planter_boxes,
  greenhouses
RESTART IDENTITY CASCADE;
COMMIT;
SQL
```

### 3.2 Restore data from the prod dump

```bash
PGPASSWORD="$TGT_PROD_PASS" pg_restore \
  --host="$SHARED_HOST" \
  --port=5432 \
  --username="$TGT_PROD_USER" \
  --dbname="$TGT_PROD_DB" \
  --data-only \
  --no-owner \
  --no-acl \
  --verbose \
  greenspace_prod.dump
```

Notes:

- `--data-only` skips the schema definitions in the dump (we already have
  them from Phase 2).
- The `audit_events` immutability trigger is `BEFORE UPDATE OR DELETE` and
  does **not** fire on INSERT/COPY. Because `pg_restore --data-only`
  only emits COPY and `setval()` (no UPDATE, no DELETE, no TRUNCATE), no
  trigger bypass is required. We deliberately omit `--disable-triggers`
  here: it would emit `ALTER TABLE ... DISABLE TRIGGER` which requires
  table-owner privilege, and depending on how `infra-shared-db` provisions
  ownership the `greenspace_prod_app` role may or may not own the tables
  it created in Phase 2.
- Sequences are reset by `setval` calls embedded in the data section of the
  custom-format dump. No manual sequence sync needed.

### 3.3 Re-verify trigger integrity post-restore

Confirm the audit trigger that the schema migration installed in Phase 2 is
still active for normal traffic:

```bash
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" -c "
  SELECT tgname, tgenabled FROM pg_trigger WHERE tgname = 'trg_audit_immutable';
"
```

`tgenabled` must be `O` (origin / enabled). Then confirm a forbidden
mutation actually fails:

```bash
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" -c "
  DELETE FROM audit_events WHERE id = (SELECT id FROM audit_events LIMIT 1);
"
# Expected: ERROR: audit_events table is immutable: DELETE not allowed
```

## Phase 4 — Staging data handling (no raw prod PII)

**Decision: rebuild staging from `seed.ts` against the empty target. Do
not migrate any rows from the dedicated staging RDS into `greenspace_staging`.**

Rationale:

- The dedicated staging DB is QA scratch space. Its rows are real-shaped
  test data (names, emails, addresses entered by testers) and there is no
  business value in preserving them across the cutover.
- Migrating raw production PII into staging is explicitly prohibited by the
  acceptance criteria. Even though the *current* staging dataset is not
  prod data, the cleanest invariant is "staging gets only synthetic /
  reference data" — which the seed already provides.
- The seed gives a known-good baseline (29 boxes, 2 greenhouses, default
  admin) that QA can build on top of. It's reproducible and deterministic.
- Snapshotting the dedicated staging DB in Phase 1.1 preserves any test
  history that anyone wants to reconstruct later.

What staging gets:

- Schema from Phase 2 (all migrations applied).
- Seed data from Phase 2 (greenhouses, boxes, default admin).
- **No** further data from the dedicated staging RDS.

If a sanitized prod export ever becomes useful for staging load testing,
that's a follow-up: it needs a sanitization pipeline (PII scrubbing of
`registrations.email`, `registrations.name`, address fields,
`waitlist_entries.email`, `emails.recipient_email`,
`emails.body_html`, `audit_events.before/after`) before any rows enter
staging. That is **not** in scope for this ticket.

### 4.1 Rotate the seeded staging admin password

The Phase 2 staging seed used whatever value you passed via
`SEED_ADMIN_PASSWORD` (or the default `changeme123` if unset). Rotate it
before staging gets any traffic post-cutover.

Confirm the seed admin row landed:

```bash
PGPASSWORD="$TGT_STG_PASS" psql -h "$SHARED_HOST" -U "$TGT_STG_USER" -d "$TGT_STG_DB" -c "
  SELECT a.email, ac.updated_at FROM admins a JOIN admin_credentials ac ON ac.admin_id = a.id;
"
```

After #340 cuts staging over and the admin UI is reachable, log in with
the seeded credentials and use the in-app **Account → Change password**
flow. This exercises the same code path real admins use.

Note that `seed.ts` is a no-op if an admin with the same email already
exists (`apps/api/src/db/seed.ts:86-108`); it does **not** rotate the
password for an existing admin. So a second `db:setup` run with a new
`SEED_ADMIN_PASSWORD` will not change anything. If a console-based
rotation is needed pre-cutover, write a small one-off script that calls
the same `hashPassword` helper used by the seed
(`apps/api/src/lib/password.ts`) and updates `admin_credentials` — never
write a plaintext password directly via SQL.

## Phase 5 — Validation

### 5.1 Production row-count parity

Re-run the Phase 1.3 query against the target and diff against
`prod-source-counts.txt`:

```bash
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" -c "
  SELECT 'greenhouses' AS t, count(*) FROM greenhouses
  UNION ALL SELECT 'planter_boxes', count(*) FROM planter_boxes
  UNION ALL SELECT 'admins', count(*) FROM admins
  UNION ALL SELECT 'admin_credentials', count(*) FROM admin_credentials
  UNION ALL SELECT 'admin_notification_preferences', count(*) FROM admin_notification_preferences
  UNION ALL SELECT 'sessions', count(*) FROM sessions
  UNION ALL SELECT 'system_settings', count(*) FROM system_settings
  UNION ALL SELECT 'registrations', count(*) FROM registrations
  UNION ALL SELECT 'waitlist_entries', count(*) FROM waitlist_entries
  UNION ALL SELECT 'emails', count(*) FROM emails
  UNION ALL SELECT 'audit_events', count(*) FROM audit_events
  ORDER BY 1;
" | tee prod-target-counts.txt

diff prod-source-counts.txt prod-target-counts.txt
```

Every row count must match. Any drift here blocks #340.

### 5.2 Production invariant + baseline spot-checks

```bash
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" -c "
  -- 29 boxes total
  SELECT count(*) FROM planter_boxes;
  -- One active registration per apartment_key
  SELECT apartment_key, count(*) FROM registrations
  WHERE status = 'active' GROUP BY 1 HAVING count(*) > 1;
  -- One active occupant per box
  SELECT box_id, count(*) FROM registrations
  WHERE status = 'active' GROUP BY 1 HAVING count(*) > 1;
  -- system_settings is a singleton
  SELECT count(*) FROM system_settings;
"

# Diff the latest-timestamp baselines against the source capture from 1.3.
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" -c "
  SELECT 'max_audit_ts' AS k, max(timestamp)::text  AS v FROM audit_events
  UNION ALL SELECT 'max_reg_created', max(created_at)::text FROM registrations
  UNION ALL SELECT 'max_wait_created', max(created_at)::text FROM waitlist_entries
  UNION ALL SELECT 'max_email_created', max(created_at)::text FROM emails
  UNION ALL SELECT 'system_settings_count', count(*)::text FROM system_settings;
" | tee prod-target-baselines.txt

diff prod-source-baselines.txt prod-target-baselines.txt
```

Required outcomes:

- The two duplicate-detection queries return zero rows.
- `system_settings` row count is `1`.
- The `diff` between source and target baselines is empty.

Any unmet check blocks #340 — investigate before proceeding.

### 5.3 Staging baseline check

```bash
PGPASSWORD="$TGT_STG_PASS" psql -h "$SHARED_HOST" -U "$TGT_STG_USER" -d "$TGT_STG_DB" -c "
  SELECT 'greenhouses' AS t, count(*) FROM greenhouses
  UNION ALL SELECT 'planter_boxes', count(*) FROM planter_boxes
  UNION ALL SELECT 'admins', count(*) FROM admins
  UNION ALL SELECT 'registrations', count(*) FROM registrations
  UNION ALL SELECT 'waitlist_entries', count(*) FROM waitlist_entries
  UNION ALL SELECT 'audit_events', count(*) FROM audit_events;
"
```

Expected: 2 greenhouses, 29 planter_boxes, ≥1 admin, 0 registrations,
0 waitlist_entries, 0 audit_events. Anything else in staging means a
non-seed row leaked in — investigate before cutover.

### 5.4 Connectivity smoke

Once #342 has shipped (or in parallel from the operator laptop using the
shared-db secret), run a one-shot health check from the Lambda:

```bash
aws lambda invoke \
  --function-name greenspace-staging-2026-api \
  --payload '{"action":"health"}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/health-staging.json
cat /tmp/health-staging.json
```

If the runtime hasn't been switched to shared-db yet (`DB_SECRET_ID` not
set), this validates the dedicated path and is not a true cutover signal —
only #340 owns that test.

## Phase 6 — Rollback plan

The migration is **non-destructive on the source side**. The dedicated RDS
instances are untouched by this runbook. They keep running, keep accepting
writes, and keep their automated backups. #337 (cleanup) does not run until
after #340 has stabilized, so the dedicated DBs are the rollback substrate
through the full cutover window.

Rollback scenarios:

### 6.1 Schema migration on shared target fails partway through Phase 2

`migrateToLatest` runs each migration in its own transaction. A failure
leaves the target in a known intermediate state and `kysely_migration` only
records successful migrations. There is no operator-friendly CLI for
`migrateDown` today; the function exists in `apps/api/src/db/migrate.ts`
but isn't wired to a script.

Preferred recovery: ask the shared-db operator to drop and recreate the
project database via `infra-shared-db` (taint + apply on the target
project module). Roles, secrets, and ownership stay intact, the database
comes back empty, and Phase 2 re-runs cleanly. This is the path of least
surprise because it doesn't depend on what privilege the project app role
holds inside its own database.

Fallback (if shared-db's operator is unavailable in the cutover window):
drop and recreate the `public` schema from inside the project DB and
re-run Phase 2.

```bash
PGPASSWORD="$TGT_PROD_PASS" psql -h "$SHARED_HOST" -U "$TGT_PROD_USER" -d "$TGT_PROD_DB" <<'SQL'
DROP SCHEMA public CASCADE;
CREATE SCHEMA public AUTHORIZATION current_user;
GRANT ALL ON SCHEMA public TO current_user;
SQL
```

If the role lacks privilege to recreate `public`, escalate to the
shared-db operator and fall back to the preferred path above.

### 6.2 Data restore on `greenspace_prod` fails partway through Phase 3

Truncate everything (the Phase 3.1 SQL block) and re-run `pg_restore`.
Because `--data-only` doesn't touch schema, the schema version doesn't
need to be re-applied.

If repeated restores fail with a constraint violation, capture the
`pg_restore` log, leave the target in its truncated state, and abort the
cutover. The dedicated prod RDS is still authoritative.

### 6.3 Post-Phase-5 validation finds drift

If row counts or invariant checks fail, do not proceed to #340. Options:

1. Re-run Phase 3 (truncate + restore). The prod source is still
   authoritative; the dump was taken in Phase 1.
2. If the dump itself is suspect, retake it (Phase 1.2) — the prod RDS
   should still be quiet at this point in the cutover window.
3. If neither path resolves it, abandon the cutover for this window and
   restore from the manual snapshot taken in Phase 1.1.

### 6.4 Cutover (#340) fails after the env-var flip

This is technically out of scope for #341 but the data prepared by this
runbook is the rollback target. To revert: re-deploy the API with
`DB_SECRET_ID` removed and the dedicated `DB_HOST` / `DB_USER` /
`DB_SECRET_ARN` env vars restored (revert the #342 Terraform change). The
dedicated RDS is unchanged and resumes serving as before. The shared-db
target is left as-is for a retry.

### 6.5 Recovery from the manual snapshots

The Phase 1.1 snapshots survive everything. To restore:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier greenspace-prod-2026-postgres-restored \
  --db-snapshot-identifier greenspace-prod-2026-pre-shared-cutover-<TS> \
  --db-instance-class db.t4g.micro \
  --db-subnet-group-name greenspace-prod-2026-db \
  --vpc-security-group-ids <db-security-group-id> \
  --region eu-north-1
```

See `backup-restore.md` for the full restore procedure.

## References

- Sibling tickets: #338 (connectivity), #339 (shared-db projects), #342
  (runtime secret contract), #340 (cutover), #337 (dedicated RDS cleanup).
- ADR-0001: `docs/adr/0001-shared-rds-connectivity.md`.
- App migrator: `apps/api/src/db/migration-registry.ts`,
  `apps/api/src/db/migrate.ts`.
- App seed: `apps/api/src/db/seed.ts`.
- Dedicated RDS Terraform:
  `infra/terraform/modules/greenspace_stack/database.tf`.
- Backup/restore base runbook: `docs/runbooks/backup-restore.md`.
- Shared-db operator docs: `infra-shared-db/ADDING_A_PROJECT.md`,
  `infra-shared-db/README.md`.
