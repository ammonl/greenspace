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

# Every allowlist below matches on action names, so a wildcard defeats all of
# them at once: `ec2:*` confers the whole VPC surface without naming any of it,
# and a bare `*` confers that plus every KMS key-lifecycle action the guards in
# `log_encryption.tftest.hcl` exist to reject. Reject that shape once here, and
# the name-matching guards can be read at face value. `service:Verb*` is left
# alone deliberately — the bootstrap policy is built from `amplify:Get*`-style
# prefixes on purpose.
run "ci_terraform_role_grants_no_service_wide_wildcard" {
  command = plan

  assert {
    condition = length([
      for a in local.ci_terraform_granted_actions : a if a == "*" || endswith(a, ":*")
    ]) == 0
    error_message = "The CI Terraform role must not be granted a bare '*' or a service-wide 'service:*' wildcard. Every other grant guard in this module matches on action names, so a wildcard silently confers exactly what they exist to reject. Enumerate the actions instead."
  }
}

run "ec2_grants_limited_to_the_security_group" {
  command = plan

  # This module owns exactly one EC2 resource in the shared VPC — an egress-only
  # security group — so the CI role's whole EC2 surface is small enough to
  # enumerate. Assert the granted set against that allowlist rather than denying
  # known-bad actions: a denylist only ever catches what its author thought to
  # list, while an allowlist also rejects a wildcard prefix and every
  # VPC/subnet/gateway/endpoint/route/peering/instance/flow-log action nobody has
  # named yet.
  #
  # The last five entries come from the bootstrap policy rather than the security
  # group: `Describe*`/`Get*` are its plan-refresh reads, and the address and tag
  # actions are its curated destroy-side writes. They are listed because this
  # reads the role's whole granted surface (`local.ci_terraform_granted_actions`,
  # defined in `iam.tf`) and not one policy document — IAM unions every policy
  # on the role, so a guard that read only `ci_terraform_resources` would pass
  # on `ec2:` grants added to `terraform-state`, which carries no shape guard of
  # its own.
  assert {
    condition = length(setsubtract(
      toset([for a in local.ci_terraform_granted_actions : a if startswith(a, "ec2:")]),
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
        "ec2:Describe*",
        "ec2:Get*",
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress",
      ])
    )) == 0
    error_message = "CI Terraform role EC2 grants must stay limited to the shared VPC security group: its lifecycle, its tags, and the reads that resolve the Lambda's vpc_config, plus the bootstrap policy's refresh reads and curated destroy-side writes. Everything else in that VPC belongs to `un17-infra-shared`. Widen this allowlist deliberately, alongside the resource that needs it."
  }
}

# This module manages no Secrets Manager secret — #397 deleted `database.tf`,
# taking both of them with it — so the role's whole `secretsmanager:` surface is
# the bootstrap policy's refresh reads. The shared-db secret the stack does read
# belongs to `un17-infra-shared` and is granted on the API runtime role, at
# runtime, not on this one at plan time.
#
# Worth guarding rather than leaving to review: a secret is the natural thing to
# reach for when adding a credential, and `CreateSecret` + `GetSecretValue` on
# `${naming_prefix}-*` is a quiet grant to re-add. Add it alongside the resource
# that needs it, and widen this list in the same change.
run "secretsmanager_grants_limited_to_refresh_reads" {
  command = plan

  assert {
    condition = length(setsubtract(
      toset([for a in local.ci_terraform_granted_actions : a if startswith(a, "secretsmanager:")]),
      toset([
        "secretsmanager:Describe*",
        "secretsmanager:List*",
        "secretsmanager:GetResourcePolicy",
      ])
    )) == 0
    error_message = "The CI Terraform role may hold no secretsmanager grant beyond the bootstrap policy's refresh reads. This module manages no secret, so create/write/delete grants here act on an empty namespace. Grant them alongside the resource that needs them."
  }
}

# The guards above are ceilings — they cap what the role may hold. This one is a
# floor, and it covers the direction another apply cannot fix: a grant can always
# be taken away by the next apply, but a role that has lost a permission its own
# plan depends on cannot get it back, because the plan that would restore it is
# the one that fails. Recovery is the out-of-band `put-role-policy` in `iam.tf`.
#
# `kms:Decrypt` used to sit in that position and had a floor guard of its own
# until it turned out to be dead (#509). These two SSM reads now occupy it: both
# environment roots resolve `/shared/network/*` through `data.aws_ssm_parameter`
# on every plan. The state-access grants in `terraform-state` are in the same
# position and are worth covering the same way if this is ever extended.
run "ci_terraform_role_keeps_the_shared_network_ssm_read" {
  command = plan

  assert {
    condition = length(setsubtract(
      toset(["ssm:GetParameter", "ssm:GetParameters"]),
      local.ci_terraform_granted_actions
    )) == 0
    error_message = "The CI Terraform role must keep ssm:GetParameter and ssm:GetParameters. Both environment roots read /shared/network/vpc-id and /shared/network/private-subnet-ids via data.aws_ssm_parameter on every plan, so dropping either action fails terraform plan in both environments — and the role cannot grant it back to itself. Remove this only alongside the last data source that reads SSM."
  }
}

# The keys of `local.ci_terraform_policies` are AWS-facing identifiers, not
# internal labels: `aws_iam_role_policy.ci_terraform` sets `name = each.key`, so
# editing a key plans a DeleteRolePolicy + PutRolePolicy on the CI role.
# `DenySelfModify` does not deny that pair — it is what lets these applies work
# at all — so an apply that dies between the delete and the put of
# `terraform-resources` leaves the role unable to restore itself, and recovery
# is the out-of-band `put-role-policy` in `iam.tf`. Two consumers also depend on
# the literal names: the `Validate bootstrap policy` job in
# `drift-detection.yml` fetches `terraform-resources-bootstrap` by name and
# would fail with NoSuchEntity, and the two-phase note in `iam.tf` warns
# operators against reusing that name for temporary grants. Widen this list
# deliberately when adding a policy; rename an existing key only with the same
# care as deleting and recreating the policy it names.
run "ci_terraform_policy_names_are_pinned" {
  command = plan

  assert {
    condition = toset(keys(local.ci_terraform_policies)) == toset([
      "terraform-state",
      "terraform-resources",
      "terraform-resources-bootstrap",
    ])
    error_message = "The CI Terraform role's inline policy names changed. These keys are live AWS policy names (name = each.key): a rename plans a delete-and-recreate of the policy on the role — mid-apply failure on terraform-resources is the lockout scenario in iam.tf's two-phase note — and drift-detection.yml fetches terraform-resources-bootstrap by name. Add new names here deliberately; rename existing ones only with an out-of-band recovery path ready."
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
