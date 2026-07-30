# Validates that IAM policies do not use wildcard resources, and that the CI
# Terraform role's EC2 surface stays limited to what the stack actually owns in
# the shared VPC.
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

run "ec2_grants_limited_to_the_security_group" {
  command = plan

  # This module owns exactly one EC2 resource in the shared VPC — an egress-only
  # security group — so the CI role's whole EC2 surface is small enough to
  # enumerate. Assert the granted set against that allowlist rather than denying
  # known-bad actions: a denylist only ever catches what its author thought to
  # list, while an allowlist also rejects `ec2:*`, a wildcard prefix, and every
  # VPC/subnet/gateway/endpoint/route/peering/instance/flow-log action nobody has
  # named yet. Deny statements are exempt — a guard on what the role may be
  # *granted* must not reject an explicit deny.
  assert {
    condition = length(setsubtract(
      toset(flatten([
        for s in jsondecode(data.aws_iam_policy_document.ci_terraform_resources.json).Statement :
        [for a in flatten([s.Action]) : a if startswith(a, "ec2:")]
        if s.Effect == "Allow"
      ])),
      toset([
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags",
        "ec2:DescribeVpcs",
        "ec2:DescribeVpcAttribute",
        "ec2:DescribeSubnets",
        "ec2:DescribeNetworkInterfaces",
      ])
    )) == 0
    error_message = "CI Terraform role EC2 grants must stay limited to the shared VPC security group: its lifecycle, its tags, and the reads that resolve the Lambda's vpc_config. Everything else in that VPC belongs to `un17-infra-shared`. Widen this allowlist deliberately, alongside the resource that needs it."
  }
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
