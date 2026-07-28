# Validates that IAM policies do not use wildcard resources.
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
  environment          = "test"
  vpc_cidr             = "10.99.0.0/16"
  availability_zones   = ["eu-north-1a", "eu-north-1b"]
  public_subnet_cidrs  = ["10.99.1.0/24", "10.99.2.0/24"]
  private_subnet_cidrs = ["10.99.10.0/24", "10.99.11.0/24"]

  ses_sender_domain = "test.example.com"

  github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}

run "ses_policy_uses_scoped_arns" {
  command = plan

  assert {
    # aws_iam_policy_document renders a single-element Resource as a bare
    # string rather than a list, so normalize with flatten() before checking.
    #
    # A bare "*" is only the most obvious over-broad form: an ARN can wildcard
    # its partition, region, or account segments (arn:aws:ses:*:*:identity/*)
    # and still be nothing like scoped. So require the shape that matters —
    # every resource must be a SES identity ARN in this account and this
    # region. Interpolating the data sources rather than hardcoding them keeps
    # the guard honest: a match proves the policy resolved real values instead
    # of substituting a wildcard. A wildcard remains permitted in the identity
    # resource-id, which the policy deliberately uses (see iam.tf).
    condition = alltrue([
      for resource in flatten([[for s in jsondecode(data.aws_iam_policy_document.api_ses.json).Statement : s if s.Sid == "SESSend"][0].Resource]) :
      can(regex("^arn:aws:ses:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:identity/", resource))
    ])
    error_message = "SES send policy resources must be SES identity ARNs scoped to this account and region (arn:aws:ses:<region>:<account-id>:identity/...). A bare '*', or an ARN wildcarding its partition, region, or account segment, is too broad."
  }
}

run "ses_sender_domain_reject_invalid" {
  command = plan

  variables {
    ses_sender_domain = "not a domain!"
  }

  expect_failures = [var.ses_sender_domain]
}
