# Drift guards for the permanent `terraform-resources-bootstrap` inline policy
# attached to the CI Terraform role. The bootstrap policy is meant to stay
# small (broad reads + a curated ec2 destroy-side write allowlist) so the CI
# role doesn't silently accumulate broad write access. The same checks are
# re-run against the live policy in `.github/workflows/drift-detection.yml`.
#
# Run with: terraform test

provider "aws" {
  region                      = "eu-north-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

override_data {
  target = data.aws_caller_identity.current
  values = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:user/test"
    user_id    = "AIDATESTUSERID"
  }
}

override_data {
  target = data.aws_region.current
  values = {
    region = "eu-north-1"
    name   = "eu-north-1"
  }
}

variables {
  environment = "test"

  shared_vpc_id             = "vpc-908203f9"
  shared_private_subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]

  ses_sender_domain = "test.example.com"

  github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}

run "bootstrap_policy_statement_count_capped" {
  command = plan

  assert {
    condition     = length(jsondecode(data.aws_iam_policy_document.ci_terraform_bootstrap.json).Statement) <= 4
    error_message = "Bootstrap policy must stay small: statement count exceeds 4. If a new statement is genuinely required, raise the cap deliberately and document why in iam.tf."
  }
}

run "bootstrap_policy_action_count_capped" {
  command = plan

  assert {
    condition     = length(flatten([for s in jsondecode(data.aws_iam_policy_document.ci_terraform_bootstrap.json).Statement : tolist(s.Action)])) <= 80
    error_message = "Bootstrap policy must stay small: total action count exceeds 80. If a new action is genuinely required, raise the cap deliberately and document why in iam.tf."
  }
}

run "bootstrap_policy_only_allowlisted_writes" {
  command = plan

  assert {
    condition = length([
      for action in flatten([for s in jsondecode(data.aws_iam_policy_document.ci_terraform_bootstrap.json).Statement : tolist(s.Action)]) :
      action
      if !can(regex(":(Describe|Get|List)", action)) && !contains([
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress",
        "ec2:CreateTags",
        "ec2:DeleteTags",
      ], action)
    ]) == 0
    error_message = "Bootstrap policy may only contain Describe*/Get*/List* actions plus the curated ec2 destroy-side write allowlist. Add new write actions to the main `terraform-resources` policy instead."
  }
}
