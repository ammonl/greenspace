# Guards the log-encryption posture decided in ticket #500: no customer-managed
# KMS key anywhere in this module, no server-side encryption on the alarm topic,
# and no IAM grant on the CI Terraform role that would let one back in.
#
# The SNS assertion is the load-bearing one. Setting `kms_master_key_id` back —
# especially to the AWS-managed `alias/aws/sns` — looks like a strict
# improvement and is not: an AWS service event source can publish to an
# encrypted topic only through a customer-managed key whose policy names that
# service principal, and the AWS-managed key's policy cannot be edited.
# CloudWatch alarms are this topic's only publisher, so encrypting it makes
# every notification undeliverable while the alarm still transitions normally.
# Nothing surfaces the failure. Both environments currently run
# `enable_alarms = false`, but the variable defaults to true, so the regression
# would land the first season alarms are switched back on — which is why this is
# a test and not a comment.
#
# `command = plan` throughout (no real AWS credentials in CI/local runs), so
# assertions stick to values known at plan time.
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

run "alarm_topic_has_no_server_side_encryption" {
  command = plan

  variables {
    enable_alarms = true
  }

  assert {
    condition     = aws_sns_topic.alarms[0].kms_master_key_id == null
    error_message = "The alarm topic must not set kms_master_key_id. CloudWatch cannot publish to a topic encrypted under alias/aws/sns, and notifications fail silently."
  }
}

run "api_log_group_uses_default_encryption" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.api.kms_key_id == null
    error_message = "The API log group must not set kms_key_id — CloudWatch's default AWS-owned encryption is the decision recorded in the module README."
  }
}

# The CI Terraform role is what would build a replacement key, so the posture
# above is only as durable as the permissions behind it. The assertions below
# guard the grants rather than the resources: without them, the first step back
# toward a customer-managed key is a quiet one-line addition to `iam.tf` that no
# other test in this module would notice.
#
# All of them read every inline policy attached to `aws_iam_role.ci_terraform`,
# not just the one that carries the KMS statement today. IAM unions a role's
# inline policies, so a guard that reads one document proves nothing about the
# role — `terraform-state` in particular has no shape guard of its own and is the
# natural place to reach for when granting on the SSE-KMS state bucket.
# The same three-document expression opens every assertion below. It cannot be
# hoisted — `.tftest.hcl` files take no `locals` block — so it is repeated
# verbatim, and any edit to one copy belongs in all of them. Two details in it
# are load-bearing: `flatten([s.Action])`, because aws_iam_policy_document
# renders a single-element Action as a bare string rather than a list; and the
# `s.Effect == "Allow"` filter, because a guard on what the role may be
# *granted* must not reject an explicit deny (`DenySelfModify`).
#
# Every assertion below is an allowlist or an exact-match denylist over named
# actions, and a service-wide wildcard defeats both: `logs:*` confers
# `logs:AssociateKmsKey` without ever spelling it, and a bare `*` confers the
# whole key lifecycle. Reject that shape once here so the guards that follow can
# reason about names. `service:Verb*` is untouched — the bootstrap policy is
# built from `amplify:Get*`-style prefixes on purpose.
run "ci_terraform_role_grants_no_service_wide_wildcard" {
  command = plan

  assert {
    condition = length([
      for a in toset(flatten([
        for doc in [
          data.aws_iam_policy_document.ci_terraform_state.json,
          data.aws_iam_policy_document.ci_terraform_resources.json,
          data.aws_iam_policy_document.ci_terraform_bootstrap.json,
        ] : [for s in jsondecode(doc).Statement : flatten([s.Action]) if s.Effect == "Allow"]
      ])) : a if a == "*" || endswith(a, ":*")
    ]) == 0
    error_message = "The CI Terraform role must not be granted a bare '*' or a service-wide 'service:*' wildcard. Every other grant guard in this module and in iam.tftest.hcl matches on action names, so a wildcard silently confers the actions they exist to reject. Enumerate the actions instead."
  }
}

run "ci_terraform_role_cannot_manage_kms_keys" {
  command = plan

  assert {
    # `kms:Decrypt` serves the SSM SecureString read in the environment roots,
    # not a key this module owns (see iam.tf). The three read prefixes are the
    # bootstrap policy's plan-refresh grants. An allowlist rather than a
    # denylist, so `kms:CreateKey` and every key-lifecycle action nobody has
    # named here fail alike.
    condition = length(setsubtract(
      toset([
        for a in flatten([
          for doc in [
            data.aws_iam_policy_document.ci_terraform_state.json,
            data.aws_iam_policy_document.ci_terraform_resources.json,
            data.aws_iam_policy_document.ci_terraform_bootstrap.json,
          ] : [for s in jsondecode(doc).Statement : flatten([s.Action]) if s.Effect == "Allow"]
        ]) : a if startswith(a, "kms:")
      ]),
      toset(["kms:Decrypt", "kms:Describe*", "kms:Get*", "kms:List*"])
    )) == 0
    error_message = "The CI Terraform role may hold no KMS grant beyond kms:Decrypt and the bootstrap policy's kms:Describe*/Get*/List* plan-refresh reads. This module manages no key, alias, or key policy, so a key-lifecycle grant means a customer-managed key is being reintroduced — do that deliberately, alongside the resource that needs it."
  }
}

run "ci_terraform_role_cannot_bind_a_key_to_a_log_group" {
  command = plan

  assert {
    condition = length([
      for a in toset(flatten([
        for doc in [
          data.aws_iam_policy_document.ci_terraform_state.json,
          data.aws_iam_policy_document.ci_terraform_resources.json,
          data.aws_iam_policy_document.ci_terraform_bootstrap.json,
        ] : [for s in jsondecode(doc).Statement : flatten([s.Action]) if s.Effect == "Allow"]
      ])) : a if contains(["logs:AssociateKmsKey", "logs:DisassociateKmsKey"], a)
    ]) == 0
    error_message = "The CI Terraform role must not hold logs:AssociateKmsKey or logs:DisassociateKmsKey. The log groups take CloudWatch's AWS-owned key and set no kms_key_id, so these only become meaningful alongside a customer-managed key — the posture the assertions above reject."
  }
}

# The guards above cap what the role may hold. This one is the floor, and it
# guards the direction that cannot be undone by another apply: an apply can
# always take a grant away, but a role that has lost the permission its own plan
# depends on cannot restore it, because the plan that would restore it is the
# one that fails. `kms:Decrypt` is the only grant here in that position.
run "ci_terraform_role_keeps_kms_decrypt" {
  command = plan

  assert {
    condition = contains(flatten([
      for doc in [
        data.aws_iam_policy_document.ci_terraform_state.json,
        data.aws_iam_policy_document.ci_terraform_resources.json,
        data.aws_iam_policy_document.ci_terraform_bootstrap.json,
      ] : [for s in jsondecode(doc).Statement : flatten([s.Action]) if s.Effect == "Allow"]
    ]), "kms:Decrypt")
    error_message = "kms:Decrypt must stay granted until the /shared/network/* SSM parameters are confirmed to be plain String, or SecureString under alias/aws/ssm. If they are SecureString under a customer-managed key, removing this fails terraform plan in both environments and the role cannot grant it back to itself. The three commands that settle it are in the KMSDecrypt comment in iam.tf; run them before deleting this assertion."
  }
}
