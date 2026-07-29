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

## Provider Versions

Every Terraform directory here — `bootstrap/`, both `environments/`, and
`modules/greenspace_stack/` — commits its own `.terraform.lock.hcl`, so
provider resolution is pinned and any bump shows up as a reviewable diff
rather than happening silently on the next `terraform init`. All four are
currently on `hashicorp/aws` 6.34.0; keep them in step so the module's
offline `terraform test` run exercises the same provider version that
`plan` and `apply` use.

The environment stacks and the shared module require `aws >= 6.0`: the
module reads `data.aws_region.current.region`, which the v5 provider does
not expose (it spells that attribute `name`). `bootstrap/` composes no
modules and uses no v6-only attributes, so it stays on `>= 5.0`.

They also require `terraform >= 1.7.0`, because the module's tests use
`override_data`. The environments compose the module, so they declare the
same floor rather than understating it. `bootstrap/` stands alone and stays
on `>= 1.5.0`. CI runs 1.7.5 everywhere.

To bump a provider, run `terraform init -upgrade` in each directory and
commit the resulting lock files together.

### Enforcement

The `Lock check` job in `.github/workflows/ci.yml` enforces the convention.
It needs no AWS credentials, so it also runs on fork PRs.

It lives in the CI workflow rather than the Terraform one deliberately. The
Terraform workflow is filtered to `infra/terraform/**`, and a required status
check whose workflow never triggers leaves a PR sitting at *"Expected —
Waiting for status to be reported"* forever. To be requireable in branch
protection, the job has to run on every PR and do the filtering itself: its
first step diffs the PR against its base and, when nothing under
`infra/terraform` changed, skips the remaining steps and reports success.

The directories it checks are discovered, not listed: every directory under
`infra/terraform` whose `*.tf` files declare `required_providers`. Adding a
directory therefore puts it under the guard automatically, and one that
declares providers but commits no lock fails the job. Then two guards, because
no single terraform command covers both failure modes:

1. `terraform init -backend=false -input=false -lockfile=readonly` in each
   directory, plus an assertion that no two directories pin different
   versions of the same provider. `readonly` fails when terraform wants to
   write the lock at all — a missing lock, one lacking hashes for the
   runner's platform, or one whose recorded version no longer satisfies the
   configured constraint. It says nothing about the other directories, which
   is why agreement is asserted separately. A provider only one directory
   uses never conflicts.
2. A regenerated-constraints comparison. Terraform only rewrites a lock's
   `constraints` line when the selected version changes, so raising a
   `required_providers` floor leaves the lock asserting a constraint the
   configuration no longer declares — and *no* init objects, not
   `-lockfile=readonly`, not a plain one, not `-upgrade`. The job therefore
   snapshots the tree, deletes each lock, re-runs `init`, and compares the
   resulting `provider`/`constraints` lines against the committed ones. The
   committed locks are never touched, and the regenerated versions and
   hashes are ignored.

Both guards cover every provider in the lock, not just `hashicorp/aws`.

When guard 2 fires, delete that directory's `.terraform.lock.hcl` and re-run
`terraform init` to regenerate it — editing the `constraints` line by hand
works too, but regenerating is what terraform itself would produce.

### Lock file platforms

The committed locks carry hashes for `linux_amd64` and `darwin_arm64` only.
CI is `linux_amd64` and Apple Silicon is `darwin_arm64`, so both are covered.
On any other platform — an Intel Mac, most notably — a `-lockfile=readonly`
init fails because the lock has no hash for that platform, which is unrelated
to whether the lock is actually in step. Either run the check on a covered
platform or extend every lock:

```bash
terraform providers lock \
  -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
```

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

For PRs from the same repository, the workflow runs credential-free checks
and per-environment plan jobs in parallel:

- **Test (module)** (`test-module`) — runs the module's self-contained
  `*.tftest.hcl` files, which mock the AWS provider. No AWS credentials
  required.
- **Plan (staging)** / **Plan (prod)** — each environment runs its own plan:
  1. Authenticate to AWS via OIDC using the environment-specific role.
  2. `terraform init` with the real S3 backend.
  3. `terraform validate`.
  4. `terraform plan` — output is saved as a CI artifact (retained 7 days).

#### Pull requests (forks)

Fork PRs receive no AWS credentials. The `validate-fork` job runs:

1. `terraform fmt -check -recursive` across all Terraform files.
2. Per environment: `terraform init -backend=false` and `terraform validate`.

`Test (module)` needs no credentials either, so it runs on fork PRs as well.
Note that `validate-fork` is the only job in this workflow that runs
`terraform fmt`; on internal PRs the format check comes from CI's
`infra-checks` job instead. The provider lock guard lives in CI too — see
*Provider Versions → Enforcement* above.

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
| CI        | `Lock check`      | Provider lock files complete and in step |

All three live in the CI workflow, which has no path filter, so each reports
on every PR and is safe to require. Do **not** require a check from the
Terraform workflow: that workflow only triggers on `infra/terraform/**`, so on
any other PR its checks never report and the PR is blocked indefinitely at
*"Expected — Waiting for status to be reported"*. There is no per-check
"treat as passed if it never ran" option in either rulesets or classic branch
protection — the only fix is for the job to always run, which is why
`Lock check` filters internally instead.

Until `Lock check` is added to the branch protection rule it reports but
blocks nothing; nothing in the workflows gates the apply jobs on it.

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
