# Launch Readiness Checklist

## Overview

Pre-launch verification and production cutover plan for UN17 Village Rooftop Gardens. Complete all sections before the registration opening date.

**Opening date:** 2026-04-01 at 10:00 Europe/Copenhagen
**Primary contact:** Ammon Larson (ammonl@hotmail.com)

## 1. Staging Sign-Off

Complete all checks in the staging environment before proceeding to production.

### 1.1 Infrastructure

- [x] Terraform apply is clean (no pending changes)
  - Verified: [Terraform run #22752467724](https://github.com/ammonlarson/greenspace/actions/runs/22752467724) — staging detect found no changes (2026-03-06)
- [x] Drift detection workflow has run with no drift issues
  - Verified: [Drift detection run #22752397791](https://github.com/ammonlarson/greenspace/actions/runs/22752397791) — no staging drift (2026-03-06)
- [x] Lambda function is deployed and healthy (`/health` returns 200)
  - Verified: [Deploy run #22753594618](https://github.com/ammonlarson/greenspace/actions/runs/22753594618) — staging health check passed (2026-03-06)
- [x] RDS instance is running, migrations applied, seed data present
- [x] VPC networking: Lambda can reach RDS via private subnet
  - Verified: Lambda successfully queries RDS (confirmed by successful `/health` and `/public/status` responses)
- [x] NAT gateway operational (Lambda can reach SES and external services)
- [x] CloudWatch log group is receiving Lambda logs
  - Log group: `/greenspace-staging-2026/api`
- [x] KMS key is active for log encryption

### 1.2 Database & Data

- [x] Greenhouses seeded: Kronen, Søen
- [x] All 29 planter boxes seeded with correct names and greenhouse assignments
- [x] All boxes in `available` state (no stale registrations from testing)
- [x] System settings row exists with correct opening datetime
- [x] Opening datetime matches planned launch: `2026-04-01T10:00:00 Europe/Copenhagen`
- [x] Audit events table is empty or contains only seed/test data

**Verification queries (run against staging DB):**

```sql
SELECT name FROM greenhouses ORDER BY name;
-- Result: Kronen, Søen

SELECT COUNT(*) AS total_boxes,
       COUNT(*) FILTER (WHERE state = 'available') AS available
FROM planter_boxes;
-- Result: total_boxes=29, available=29

SELECT opening_datetime AT TIME ZONE 'Europe/Copenhagen' AS opens_at
FROM system_settings;
-- Result: 2026-04-01 10:00:00
```

### 1.3 API Endpoints

- [x] `GET /health` — returns 200
- [x] `GET /public/status` — returns correct `isOpen` flag (should be `false` before opening date)
- [x] `GET /public/greenhouses` — returns both greenhouses with correct box counts
- [x] `GET /public/boxes` — returns all 29 boxes with correct states
- [x] `POST /public/validate-address` — accepts eligible address, rejects ineligible
- [x] `POST /public/validate-registration` — validates complete input
- [x] `POST /public/register` — creates registration (use a test address, clean up after)
- [x] `POST /public/waitlist` — rejects when boxes are available (correct behavior pre-launch)
- [x] `POST /admin/auth/login` — admin login works with seeded credentials
- [x] `GET /admin/registrations` — returns registrations (empty or test data)
- [x] `PATCH /admin/settings/opening-time` — can update opening datetime
- [x] `POST /admin/audit-events` — returns audit trail

### 1.4 Email

- [x] SES domain identity verified (`staging.un17hub.com`)
- [x] DKIM records active and passing
- [x] Test registration triggers confirmation email
- [x] Email appears in `emails` table with status `sent`
- [x] Email sender shows `greenspace@staging.un17hub.com`
- [x] Reply-to is `elise7284@gmail.com`
- [x] Email content is bilingual (matches selected language)

### 1.5 Admin Accounts

- [x] Admin accounts created for: `ammonl@hotmail.com`
- [x] Both admins can log in and access admin endpoints
- [x] Admin passwords have been changed from seed defaults
- [x] Session expiry works (logout after inactivity)
  - Sessions expire after 8 hours (enforced by EventBridge cleanup schedule)

### 1.6 Monitoring

Staging does not provision a CloudWatch dashboard, SNS alarm topic, or metric
alarms. All alarm and dashboard verification happens in production (section 2.2).
Staging retains its CloudWatch log groups and VPC flow logs for ad-hoc
investigation.

- [x] API log group is receiving Lambda logs
  - Log group: `/greenspace-staging-2026/api`

**Staging sign-off:**

| Role | Name | Date | Approved |
|------|------|------|----------|
| Owner | Elise Larson | 2026-03-06 | ☑ |
| Developer | Claude (agent) | 2026-03-06 | ☑ |

---

## 2. Production Deploy Plan

### 2.1 Pre-Deploy

- [x] All staging sign-off items are complete and approved
- [x] No open P1/P2 issues in the repository
- [x] All CI checks pass on `main` branch
- [x] Terraform plan for production shows no unexpected changes
  - [Terraform run #22752467724](https://github.com/ammonlarson/greenspace/actions/runs/22752467724) — prod plan clean (2026-03-06). This is the same multi-environment workflow run that also verified staging (section 1.1).

### 2.2 Infrastructure Deploy

Production infrastructure is deployed via the Terraform workflow on merge to `main`.

1. Verify Terraform plan output for the `prod` environment (check CI artifacts)
2. Merge — that is the decision point. Prod applies on its own once staging has
   applied and `verify-staging` passes; the `production` environment carries no
   required reviewers, so there is no approval prompt to wait for
3. Wait for apply to complete successfully

**Completed:** [Terraform run #22752401895](https://github.com/ammonlarson/greenspace/actions/runs/22752401895) — all resources applied to prod including EventBridge session cleanup (2026-03-06)

**Post-infra verification:**

- [x] RDS instance is running with Multi-AZ enabled
  - Instance: `db-OXVJYU5AYYNQNQB7JQEQEZDDXE`
- [x] Lambda function is provisioned in VPC private subnets
  - Function: `greenspace-prod-2026-api`
- [x] SES domain identity verified (`un17hub.com`)
- [x] DKIM records active
  - 3 CNAME records in Route 53 zone `Z0699283E3XYGVO8MRFY`
- [x] CloudWatch alarms and dashboard created
  - Dashboard: `greenspace-prod-2026-dashboard`
  - Alarms: lambda-errors, lambda-throttles, rds-cpu, rds-freeable-memory, rds-connections, ses-bounces, ses-complaints
- [x] SNS alarm subscription confirmed
  - Topic: `greenspace-prod-2026-alarms`

### 2.3 Application Deploy

Application code is deployed via the Deploy API workflow on merge to `main`.

1. Merge the latest code to `main` (or trigger `workflow_dispatch`)
2. Monitor the `Deploy (staging)` job — confirm health check passes
3. Approve the `Deploy (prod)` job when staging is green
4. Monitor the production health check

**Completed:** [Deploy run #22753594618](https://github.com/ammonlarson/greenspace/actions/runs/22753594618) — staging deployed (health check passed), prod deployed (health check passed) (2026-03-06)

### 2.4 Database Setup

- [x] Run migrations against production database
- [x] Run seed script (greenhouses, boxes, system settings, admin accounts)
- [x] Verify seed data with the queries from section 1.2
- [x] Change admin passwords from seed defaults immediately

### 2.5 Post-Deploy Configuration

- [x] Set opening datetime to `2026-04-01T10:00:00 Europe/Copenhagen` via admin API
- [x] Verify `/public/status` returns `isOpen: false` (before opening)
- [x] Confirm alarm notification email is subscribed and confirmed

---

## 3. Post-Deploy Smoke Tests

Run these tests against the production API endpoint immediately after deployment.

**Smoke tests executed:** 2026-03-06

### 3.1 Health & Status

```bash
# Health check
curl -s "${PROD_API_URL}/health" | jq .

# Registration status (should show isOpen: false before opening)
curl -s "${PROD_API_URL}/public/status" | jq .
```

- [x] `/health` returns `{ "status": "ok" }`
- [x] `/public/status` returns correct opening datetime and `isOpen` flag
  - `isOpen: false`, `serverTime` in UTC, `openingDatetime: 2026-04-01T08:00:00.000Z`

### 3.2 Public Endpoints

```bash
# Greenhouse summaries
curl -s "${PROD_API_URL}/public/greenhouses" | jq .

# All boxes
curl -s "${PROD_API_URL}/public/boxes" | jq .
```

- [x] `/public/greenhouses` returns 2 greenhouses (Kronen, Søen) with correct total counts
- [x] `/public/boxes` returns 29 boxes, all in `available` state
- [x] No test or stale data present

### 3.3 Address Validation

```bash
# Eligible address
curl -s -X POST "${PROD_API_URL}/public/validate-address" \
  -H "Content-Type: application/json" \
  -d '{"street":"Else Alfelts Vej","houseNumber":130,"floor":null,"door":null}' | jq .

# Ineligible address
curl -s -X POST "${PROD_API_URL}/public/validate-address" \
  -H "Content-Type: application/json" \
  -d '{"street":"Main Street","houseNumber":1,"floor":null,"door":null}' | jq .
```

- [x] Eligible address returns `{ "eligible": true }`
- [x] Ineligible address returns `{ "eligible": false }`

### 3.4 Admin Access

```bash
# Admin login
curl -s -X POST "${PROD_API_URL}/admin/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"ammonl@hotmail.com","password":"<password>"}' \
  -c /tmp/cookies.txt | jq .

# Fetch registrations (with session cookie)
curl -s "${PROD_API_URL}/admin/registrations" \
  -b /tmp/cookies.txt | jq .
```

- [x] Admin login returns 200 with session cookie
- [x] Admin endpoints are accessible with valid session
- [x] Admin endpoints return 401 without session cookie

### 3.5 Email Delivery

- [x] Send a test registration (use a designated test address)
- [x] Confirm email appears in `emails` table with status `sent`
- [x] Confirm email is received in the test inbox
- [x] Sender shows `greenspace@un17hub.com`
- [x] Reply-to is `elise7284@gmail.com`
- [x] Clean up test registration and reset box state

### 3.6 Monitoring

- [x] CloudWatch dashboard shows Lambda invocation metrics
- [x] Log group contains entries from smoke test requests
  - Log group: `/greenspace-prod-2026/api`
- [x] No alarms in ALARM state

---

## 4. Go / No-Go Decision

### 4.1 Criteria

All items must be checked for a GO decision.

| Category | Criteria | Status |
|----------|----------|--------|
| Infrastructure | Terraform applied, no drift | ☑ |
| Database | Migrations run, seed data verified | ☑ |
| API | All smoke tests pass | ☑ |
| Email | SES verified, test email delivered | ☑ |
| Admin | Accounts created, passwords changed | ☑ |
| Monitoring | Alarms active, dashboard operational | ☑ |
| Opening datetime | Set to 2026-04-01T10:00:00 Europe/Copenhagen | ☑ |
| Stakeholder approval | Owner has reviewed and approved | ☑ |

### 4.2 Decision

| | |
|---|---|
| **Decision** | ☑ GO |
| **Date** | 2026-03-06 |
| **Decided by** | Elise Larson (Owner) |
| **Notes** | All staging sign-off items verified, production infrastructure deployed and smoke-tested. No blocking issues. System is ready for 2026-04-01 opening. |

### 4.3 No-Go Actions

If the decision is NO-GO, document:

- Blocking issue(s) and owner(s)
- Remediation plan with timeline
- Revised launch target date
- Re-assessment date for next go/no-go review

*Not applicable — decision is GO.*

---

## 5. Rollback Plan

If critical issues are discovered after launch:

1. **API rollback:** Redeploy the previous bundle onto `$LATEST`
   ```bash
   aws lambda update-function-code \
     --function-name greenspace-prod-2026-api \
     --s3-bucket <previous-artifact-bucket> \
     --s3-key <previous-artifact-key>
   ```
   Alternatively, revert the commit on `main` and let the deploy workflow run.

2. **Database rollback:** Use point-in-time restore (see [backup-restore.md](backup-restore.md))

3. **Communication:** Notify stakeholders (Elise, Lena) immediately. Update the opening datetime to a future date to pause registrations.

---

## 6. Post-Launch Monitoring

For the first 48 hours after opening:

- [ ] Monitor CloudWatch dashboard for error spikes
- [ ] Check `emails` table for any `failed` status entries
- [ ] Review audit trail for unexpected patterns
- [ ] Verify registration counts match expectations
- [ ] Confirm no SES bounce/complaint alarms
- [ ] Check RDS connection count stays within normal range

**Escalation:** See [incident-triage.md](incident-triage.md) for alarm investigation procedures.
