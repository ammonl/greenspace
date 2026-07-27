# Terraform Layout

This directory contains environment stacks, reusable modules, and the
one-time bootstrap configuration for remote state and account-level
prerequisites.

## Directory Structure

```
infra/terraform/
├── bootstrap/          # One-time state backend provisioning
│   ├── main.tf
│   └── variables.tf
├── environments/
│   ├── prod/main.tf    # Production stack (isolated state)
│   └── staging/main.tf # Staging stack (isolated state)
└── modules/
    └── greenspace_stack/  # Shared module composing AWS resources
```

## Conventions

- Use one environment directory per deploy target.
- Keep modules focused and composable.
- Tag all resources with:
  - `project=greenspace`
  - `season=2026`
  - `environment=<env>`
  - `managed_by=terraform`

## State Backend

Remote state uses an S3 bucket with DynamoDB locking.

| Resource        | Name                       |
|-----------------|----------------------------|
| S3 bucket       | `greenspace-2026-tfstate`  |
| DynamoDB table  | `greenspace-2026-tflock`   |
| Region          | `eu-north-1`               |

State paths are isolated per environment:

- `environments/staging/terraform.tfstate`
- `environments/prod/terraform.tfstate`

Versioning is enabled on the S3 bucket so prior state can be recovered.

## Bootstrap Workflow (one-time)

The `bootstrap/` directory creates account-level prerequisites that all
other stacks depend on. Run this once before initializing environments.

### Resources created

| Resource                       | Purpose                                       |
| ------------------------------ | --------------------------------------------- |
| S3 bucket                      | Terraform remote state                        |
| DynamoDB table                 | State locking                                 |
| IAM OIDC identity provider     | GitHub Actions OIDC trust (keyless CI auth)   |

### Steps

```bash
cd infra/terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

After the bootstrap resources exist, environment stacks can be initialized
with their remote backend. No manual AWS Console steps are required.

### Importing an existing OIDC provider

If the GitHub OIDC provider was previously created manually in the AWS
Console, import it into bootstrap state before applying:

```bash
cd infra/terraform/bootstrap
terraform import aws_iam_openid_connect_provider.github \
  arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
```

## Environment Init / Apply Workflow

For each environment (`staging` or `prod`):

```bash
cd infra/terraform/environments/<env>
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### CI Workflow (`.github/workflows/terraform.yml`)

The Terraform workflow triggers on pull requests and pushes to `main` when
files under `infra/terraform/` change. AWS authentication uses GitHub OIDC
(`aws-actions/configure-aws-credentials`) — no long-lived keys.

#### Pull requests (internal)

For PRs from the same repository, the workflow runs a format check and
per-environment plan jobs in parallel:

- **Format Check** (`fmt-check`) — runs `terraform fmt -check -recursive`
  across all Terraform files. No AWS credentials required.
- **Plan (staging)** / **Plan (prod)** — each environment runs its own plan:
  1. Authenticate to AWS via OIDC using the environment-specific role.
  2. `terraform init` with the real S3 backend.
  3. `terraform validate`.
  4. `terraform plan` — output is saved as a CI artifact (retained 7 days).

#### Pull requests (forks)

Fork PRs receive no AWS credentials. A single `validate-fork` job runs:

1. `terraform fmt -check -recursive` across all Terraform files.
2. Per environment: `terraform init -backend=false` and `terraform validate`.

#### Merge to main / workflow dispatch

On push to `main` (or manual dispatch from `main`), the deploy pipeline runs:

1. **Detect changes** (`detect-staging`, `detect-prod`) — runs
   `terraform plan -detailed-exitcode` for each environment in parallel. If no
   changes are detected, downstream apply jobs are skipped.
2. **Apply staging** (`apply-staging`) — auto-applies when staging has changes.
   Uses the `staging` GitHub environment.
3. **Verify staging** (`verify-staging`) — after a staging apply, fetches the
   staging Lambda Function URL and polls `GET /public/status` until it returns
   HTTP 200 with a valid body. The endpoint performs real database reads, so
   this proves the applied stack is healthy end to end (Lambda → networking →
   RDS), not just that the apply didn't error. Skipped when staging has no
   changes.
4. **Apply production** (`apply-prod`) — runs after staging is applied *and*
   verified healthy (or when staging is skipped). Uses the `production` GitHub
   environment.

Concurrency guards (`terraform-deploy-staging`, `terraform-deploy-prod`)
prevent parallel applies to the same environment.

#### IAM roles

Each environment has a `ci-terraform` IAM role assumed via OIDC. Role ARNs
are stored in GitHub repository variables:

| Variable              | Purpose                              |
| --------------------- | ------------------------------------ |
| `TF_ROLE_ARN_STAGING` | OIDC role ARN for staging plan/apply |
| `TF_ROLE_ARN_PROD`    | OIDC role ARN for prod plan/apply    |

The `ci-terraform` role carries two managed inline policies:

| Inline policy                    | Purpose                                                                 |
| -------------------------------- | ----------------------------------------------------------------------- |
| `terraform-resources`            | Least-privilege actions actually used to manage the stack's resources.  |
| `terraform-resources-bootstrap`  | Permanent broad reads + a small curated ec2 destroy-write allowlist.    |

The bootstrap policy exists to break the chicken-and-egg cycle that recurred
each time a new resource type was added: `terraform plan` refresh fails on
an unauthorized read before any apply can grant the missing permissions, so
an operator had to attach a temporary inline policy by hand. With the
permanent bootstrap in place, plan refresh keeps working when a new resource
type is added; the next apply still updates `terraform-resources` to grant
the least-privilege subset that resource type needs at runtime.

The bootstrap policy is meant to stay small. Two guards enforce that:

1. **`terraform test`** — `iam.tftest.hcl` asserts the policy stays under 4
   statements / 80 actions and that every action is either a Describe/Get/List
   prefix or in the curated ec2 destroy-write allowlist.
2. **Daily drift check** — the `Validate bootstrap policy` job in
   `.github/workflows/drift-detection.yml` re-runs the same checks against
   the live policy fetched from AWS via `aws iam get-role-policy`. Catches
   both code-side bloat that slipped past PR review and AWS-side tampering.

When a guard fires, intentionally raise the cap (in both
`iam_bootstrap.tftest.hcl` and the workflow) only after a brief review of
whether the new action genuinely belongs in the bootstrap policy or in
`terraform-resources`.

The first apply that lands the bootstrap policy may overwrite a stale
`terraform-resources-bootstrap` inline policy left over from a manual
bootstrap dance (the name is intentionally reused). This is safe:
`aws_iam_role_policy` upserts, so the live policy converges to the
Terraform-managed contents.

## Amplify Hosting

Each environment provisions an AWS Amplify app for the Next.js frontend
(`apps/web`). Amplify builds from source using the `WEB_COMPUTE` platform
(SSR support).

### Custom Domains

| Environment | Domain                              |
| ----------- | ----------------------------------- |
| staging     | `greenspace.staging.un17hub.com`    |
| production  | `greenspace.un17hub.com`            |

### TLS

Amplify provisions and auto-renews ACM certificates via the domain
association. When the Route 53 hosted zone is in the same AWS account,
Amplify automatically creates DNS validation records—no manual certificate
management is required.

### Build Configuration

Amplify uses the build spec embedded in the Terraform configuration:

- **App root**: `apps/web`
- **Install**: `npm ci`
- **Build**: `npm run build`
- **Artifacts**: `.next/**/*`

The `API_URL` environment variable is automatically set to the Lambda function
URL from the same stack, so Next.js API rewrites point to the correct backend.

### Deployment Modes

| Environment | Auto-build | Trigger                                    |
| ----------- | ---------- | ------------------------------------------ |
| staging     | enabled    | Push to `main` triggers automatic build    |
| production  | disabled   | Manual deployment via Amplify console / CI |

#### Required PR status checks

The following status checks should be required in the `main` branch
protection rule:

| Workflow  | Job name          | Purpose                                  |
| --------- | ----------------- | ---------------------------------------- |
| CI        | `infra-checks`    | `terraform fmt` + `validate` (backend-disabled) |
| CI        | `app-checks`      | Lint, test, build for application code   |
| Terraform | `Format Check`    | `terraform fmt -check -recursive` on infra changes |

The Terraform `Format Check` job runs on all PRs that touch
`infra/terraform/**`. It requires no AWS credentials and blocks merge when
formatting is invalid. Because the Terraform workflow only triggers on
`infra/terraform/**` path changes, configure this check in branch protection
with "Do not require this check to have run" so non-infra PRs are not blocked.

#### How to verify

- **PR plans**: check the `Plan (staging)` and `Plan (prod)` job logs, or
  download the `tfplan-staging` / `tfplan-prod` artifacts from the workflow
  run.
- **Deploy plans**: download `deploy-tfplan-staging` / `deploy-tfplan-prod`
  artifacts from the workflow run to review what will be applied.
- **Apply runs**: check the `Apply (staging)` and `Apply (prod)` job logs
  under the Actions tab for the merge commit on `main`.
- **Prod apply**: the `Apply (prod)` job runs after the staging apply and the
  `Verify (staging)` health check both succeed (or when staging has no changes
  and both are skipped).
- **No-change plans**: when `terraform plan` detects no changes, the detect
  job outputs `has_changes=false` and the apply job is skipped entirely.
