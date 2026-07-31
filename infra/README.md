# infra

Infrastructure as code for UN17 Village Rooftop Gardens.

All persistent AWS resources must be defined under `infra/terraform`.

Structure:
- `terraform/modules` reusable building blocks
- `terraform/environments/staging` staging stack
- `terraform/environments/prod` production stack

## CI/CD Pipeline

Terraform runs automatically via GitHub Actions:
- `infra/terraform/environments/staging/terraform.yml` - Staging (PRs + main)
- `infra/terraform/environments/prod/terraform.yml` - Production (main only)

### GitHub Variables

Set these in your repository settings:
- `TF_ROLE_ARN_STAGING` - Staging CI Terraform role ARN
- `TF_ROLE_ARN_PROD` - Production CI Terraform role ARN

### GitHub Environments

Create these environments in Settings → Environments. Both exist to scope
environment-level variables (`API_FUNCTION_NAME` and `AMPLIFY_APP_ID` — each
environment provisions its own Lambda and its own Amplify app, so the two hold
different values) and to record deployment history — the workflows'
`environment:` keys are load-bearing for that, so do not remove them. See the
deploy variable table in the root `README.md` for the full list.

- `staging` - No protection rules needed
- `production` - No protection rules either. Prod promotion is deliberately
  unattended: each prod job already waits on a verified staging, and the human
  checkpoint is the approving review branch protection requires on `main`. If an
  approval step in front of prod is ever wanted, required reviewers here is where
  it goes — and the deploy-flow descriptions in `README.md` and `AGENTS.md` need
  updating with it, since they currently state the opposite.

### Workflow Behavior

- **PRs**: `terraform plan` only (no apply)
- **Main branch**: `terraform plan` followed by `terraform apply`
- **Forks**: `terraform validate` only (no plan/apply)
- **Concurrency**: One plan/apply at a time per environment
- **Artifacts**: Plan output saved for review
