# UN17 Village Rooftop Gardens

UN17 Village Rooftop Gardens is the UN17 rooftop greenhouse registration platform for the 2026 season.

Primary product specification:
- [UN17 Village Rooftop Gardens Spec](docs/specs/greenspace-2026-spec.md)
- [Architecture Overview](docs/architecture.md)

## Repository Layout

- [`apps/web`](apps/web/) - Next.js 15 frontend for public and admin UI.
- [`apps/api`](apps/api/) - API services (registration, admin operations, email workflows).
- [`packages/shared`](packages/shared/) - Shared types, validation schemas, and i18n/domain constants.
- [`infra/`](infra/) - AWS infrastructure as code.
  - [`infra/terraform`](infra/terraform/) - Terraform modules and environment stacks.
  - [`infra/terraform/modules/greenspace_stack`](infra/terraform/modules/greenspace_stack/) - Shared AWS resource module.
- [`docs/`](docs/) - Product specs, architecture, ADRs, API contracts, and data model docs.
  - [`docs/architecture.md`](docs/architecture.md) - System architecture with diagrams.
  - [`docs/api/openapi.yaml`](docs/api/openapi.yaml) - OpenAPI 3.1 contract.
  - [`docs/data/schema.md`](docs/data/schema.md) - Data contract and invariants.
  - [`docs/adr/`](docs/adr/) - Architecture Decision Records.
  - [`docs/runbooks/`](docs/runbooks/) - Operational runbooks.
    - [`incident-triage.md`](docs/runbooks/incident-triage.md) - Alarm investigation and incident response.
    - [`backup-restore.md`](docs/runbooks/backup-restore.md) - RDS backup and point-in-time restore.
    - [`launch-checklist.md`](docs/runbooks/launch-checklist.md) - Pre-launch verification, production cutover, and go/no-go decision.
- `.github` - CI workflows and contribution templates.

## Local Development

### Prerequisites

- Node.js >= 22
- PostgreSQL 16 (via Docker or a local install)

### 1. Start PostgreSQL

**Docker:**

```bash
docker run -d --name greenspace-db \
  -e POSTGRES_DB=greenspace \
  -e POSTGRES_USER=greenspace \
  -e POSTGRES_PASSWORD=localdev \
  -p 5432:5432 \
  postgres:16
```

**Homebrew (macOS):**

```bash
brew install postgresql@16
brew services start postgresql@16
createuser greenspace
createdb -O greenspace greenspace
```

### 2. Install dependencies

```bash
npm install
```

### 3. Run database migrations and seed data

```bash
DB_PASSWORD=localdev npm run db:setup --workspace=@greenspace/api
```

This runs all Kysely migrations and seeds greenhouses, planter boxes, system settings, and an initial admin account. The default admin password is `changeme123` (override with `SEED_ADMIN_PASSWORD`).

### 4. Start the API dev server

```bash
DB_PASSWORD=localdev npm run dev --workspace=@greenspace/api
```

The API starts on `http://localhost:3001` by default (override with `API_PORT`).

### 5. Start the frontend

```bash
npm run dev --workspace=@greenspace/web
```

The Next.js dev server starts on `http://localhost:3000` and proxies API routes (`/public/*`, `/admin/*`, `/health`) to the API dev server.

### Environment variables (API)

| Variable              | Default       | Description                     |
| --------------------- | ------------- | ------------------------------- |
| `DB_HOST`             | `localhost`   | PostgreSQL host                 |
| `DB_PORT`             | `5432`        | PostgreSQL port                 |
| `DB_NAME`             | `greenspace`  | Database name                   |
| `DB_USER`             | `greenspace`  | Database user                   |
| `DB_PASSWORD`         | (empty)       | Database password               |
| `DB_SSL`              | `false`       | Enable SSL for DB connection    |
| `API_PORT`            | `3001`        | Local dev server port           |
| `SEED_ADMIN_PASSWORD` | `changeme123` | Initial admin password for seed |

## Working Agreement

- Follow [CLAUDE.md](CLAUDE.md) for all task execution.
- Keep work issue-driven and scoped.
- Prefer contract-first changes:
  1. spec/ADR/API/data contract
  2. implementation
  3. tests/validation

## API Deployment

The API runs as an AWS Lambda function with a public Function URL.

- **Build**: `npm run bundle --workspace=@greenspace/api` produces a single-file ESM bundle via esbuild.
- **Deploy workflow** (`deploy.yml`): Triggers on push to `main` when `apps/api/**` or `packages/shared/**` change. Builds the bundle, deploys to staging Lambda, runs a health check, then promotes to production. Promotion is automatic — `deploy-prod` declares `needs: deploy-staging`, so a failed staging health check stops it, but nothing waits for a human. The `production` environment scopes that environment's variables and records deployment history; it is not an approval gate, and no required reviewers are configured.
- **Lambda Function URL**: Terraform provisions the Lambda function and Function URL. The `api_base_url` output contains the public endpoint for each environment.
- **No Lambda versions**: deploys update `$LATEST` only — the Function URL and the EventBridge schedule both invoke the unqualified function, and there is no alias or provisioned concurrency to serve a numbered version. Roll back by reverting the commit on `main` (or redeploying the previous artifact onto `$LATEST`); see [`docs/runbooks/launch-checklist.md`](docs/runbooks/launch-checklist.md).

### GitHub environment variables (deploy)

Each GitHub environment (`staging`, `production`) needs these variables:

| Variable                  | Purpose                                  |
| ------------------------- | ---------------------------------------- |
| `DEPLOY_ROLE_ARN_STAGING` | OIDC role ARN for staging API deployment (repo-level) |
| `DEPLOY_ROLE_ARN_PROD`    | OIDC role ARN for production API deployment (repo-level) |
| `API_FUNCTION_NAME`       | Lambda function name (environment-level, e.g. `greenspace-staging-2026-api`) |

## CI / Terraform Pipeline

Four workflows handle CI, infrastructure, deployment, and drift detection:

- **CI (`ci.yml`)** - Runs on every PR and push to main. Validates guardrail files, runs app checks (test/lint/build), performs lightweight `terraform fmt -check` + `terraform validate` with the backend disabled, and verifies the committed provider lock files (`Lock check`, which no-ops when `infra/terraform` is untouched).
- **Terraform (`terraform.yml`)** - Runs when `infra/terraform/**` files change. Authenticates to AWS via GitHub OIDC and operates per environment.
- **Deploy (`deploy.yml`)** - Runs when `apps/api/**` or `packages/shared/**` change on main. Builds the Lambda bundle, deploys to staging, runs a health smoke test, then deploys to production.
- **Drift Detection (`drift-detection.yml`)** - Runs daily on a cron schedule. Runs `terraform plan` for each environment and creates a GitHub issue if drift is detected.

### Pull requests (internal)

Credential-free checks and per-environment plan jobs run in parallel. The `Test (module)` job runs the module's provider-mocking `*.tftest.hcl` files. Each environment gets its own plan job with output uploaded as a CI artifact. The `terraform fmt` check for internal PRs comes from CI's `infra-checks` job, and the provider lock guard from CI's `Lock check`.

### Pull requests (forks)

Fork PRs receive no AWS credentials. The workflow falls back to backend-disabled `terraform fmt` + `validate`, plus the credential-free module test. CI's `Lock check` runs on fork PRs too.

### Merge to main

Staging is applied first. Production applies after staging succeeds — specifically after `verify-staging`, which checks `GET /public/status` and so exercises the database path rather than mere reachability. `apply-prod` lists that job in its `needs:`, so a failed verification stops the promotion.

There is no approval step. The `production` environment scopes variables and records deployment history, but carries no required reviewers; the human checkpoint is the pull request, since branch protection means a change reaches prod only through an approved PR.

Concurrency guards prevent simultaneous applies to the same environment.

### IAM setup

Each environment defines a `ci-terraform` IAM role assumed via GitHub OIDC (`aws-actions/configure-aws-credentials`). Role ARNs are stored in GitHub repository variables:

| Variable              | Purpose                                 |
| --------------------- | --------------------------------------- |
| `TF_ROLE_ARN_STAGING` | OIDC role ARN for staging plan/apply    |
| `TF_ROLE_ARN_PROD`    | OIDC role ARN for production plan/apply |

The roles grant least-privilege access to the S3 state backend, DynamoDB lock table, and the specific AWS resources managed by Terraform (the Lambda's security group in the shared VPC, IAM, CloudWatch Logs, Lambda, RDS, Secrets Manager).

### Required PR status checks

These checks should be required in the `main` branch protection rule:

| Workflow  | Job name          | Purpose                                         |
| --------- | ----------------- | ----------------------------------------------- |
| CI        | `app-checks`      | Lint, test, build for application code          |
| CI        | `infra-checks`    | `terraform fmt` + `validate` (backend-disabled) |
| CI        | `Lock check`      | Provider lock files complete and in step        |

All three live in `ci.yml`, which has no path filter, so each reports on every PR and is safe to require. Do **not** require a check from the Terraform workflow: it only triggers on `infra/terraform/**`, so on any other PR its checks never report and the PR is blocked indefinitely at "Expected — Waiting for status to be reported". Neither rulesets nor classic branch protection has a per-check "treat as passed if it never ran" option, which is why `Lock check` runs on every PR and filters internally. Until it is required in the branch protection rule it reports but blocks nothing.

### Operational safeguards

- Fork PRs never receive privileged credentials.
- `concurrency` groups prevent parallel applies per environment.
- Prod apply is gated behind staging success — the staging apply *and* the `verify-staging` check that follows it, both listed in `apply-prod`'s `needs:`. Not behind an approval: the `production` environment carries no required reviewers.
- Plan output is saved as an artifact for audit.

## Monitoring & Alerting

CloudWatch alarms cover the major failure modes:

| Alarm | Metric | Threshold |
|-------|--------|-----------|
| Lambda errors | Errors > 0 | 2 consecutive 5-min periods |
| Lambda throttles | Throttles > 0 | 1 period |
| RDS CPU | CPUUtilization > 80% | 3 consecutive 5-min periods |
| RDS memory | FreeableMemory < 128 MB | 2 consecutive periods |
| RDS connections | DatabaseConnections > 80 | 2 consecutive periods |
| SES bounces | Bounce > 5/hr | 1 period |
| SES complaints | Complaint > 1/hr | 1 period |

Alarm notifications are delivered via SNS email subscription (configured via `alarm_email`).

A CloudWatch dashboard aggregates Lambda, RDS, and SES metrics.

Alarms and the dashboard are provisioned only in production. Staging sets `enable_alarms = false` and `enable_dashboard = false` on the shared module, so it ships with the API log group only.

**Drift detection** runs daily via `.github/workflows/drift-detection.yml`. If Terraform detects infrastructure drift, a GitHub issue is created automatically.

**Session cleanup** runs hourly via an EventBridge scheduled rule that invokes the API Lambda. Expired sessions (8-hour TTL) are bulk-deleted to prevent unbounded table growth.

See [docs/runbooks/](docs/runbooks/) for incident triage and backup restore procedures.

## Time Source & Registration Gate

Registration opening is **server-authoritative**. The server (`Date.now()`) is the sole source of truth for whether registration is open.

- **`GET /public/status`** returns `isOpen` (boolean) and `serverTime` (ISO 8601 UTC). The `isOpen` flag is computed by comparing the configured `opening_datetime` (stored as `timestamptz` in PostgreSQL) against the server's current time.
- **`POST /public/register`** independently re-checks the same server-side gate before accepting any submission. A client cannot bypass this by manipulating request data.
- **Frontend behavior**: The UI relies on the server's `isOpen` flag from `/public/status`. When the API is unreachable, the frontend defaults to the pre-open state (denying early access). While in pre-open, the frontend polls `/public/status` every 30 seconds to auto-transition when the server reports the opening.
- **Timezone**: The opening datetime is stored as an absolute UTC timestamp. Display formatting uses `Europe/Copenhagen` (via `OPENING_TIMEZONE` constant and `Intl.DateTimeFormat`). The admin UI labels the input as Copenhagen time.
- **Client clock**: The client's system clock is never used for gate decisions. Changing the browser/device clock cannot reveal the registration UI early or submit registrations before the server-determined opening time.

## Guardrails

- No manual AWS infrastructure drift: persistent resources are Terraform-managed.
- Small PRs with explicit acceptance criteria mapping.
- CI checks are required before merge.
