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
# above is only as durable as the permissions behind it. Both assertions below
# guard the grants rather than the resources: without them, the first step back
# toward a customer-managed key is a quiet one-line addition to `iam.tf` that no
# other test in this module would notice.
#
# Both read `local.ci_terraform_granted_actions` — every action the role holds
# across all three of its inline policies, defined once in `iam.tf`. A guard that
# read a single policy document would prove nothing about the role, since IAM
# unions them. They also rely on `ci_terraform_role_grants_no_service_wide_wildcard`
# in `iam.tftest.hcl` to reject `*` and `service:*`, which would otherwise confer
# what these reject without ever naming it.
run "ci_terraform_role_holds_no_kms_key_grants" {
  command = plan

  assert {
    # The three read prefixes are the bootstrap policy's plan-refresh grants and
    # are the role's entire remaining `kms:` surface. An allowlist rather than a
    # denylist, so `kms:CreateKey` and every key-lifecycle action nobody has
    # named here fail alike.
    condition = length(setsubtract(
      toset([for a in local.ci_terraform_granted_actions : a if startswith(a, "kms:")]),
      toset(["kms:Describe*", "kms:Get*", "kms:List*"])
    )) == 0
    error_message = "The CI Terraform role may hold no KMS grant beyond the bootstrap policy's kms:Describe*/Get*/List* plan-refresh reads. This module manages no key, alias, or key policy; the state bucket, lock table, log groups, and Lambda environment variables all sit under AWS-owned or AWS-managed keys that need no IAM-side grant; and the /shared/network/* SSM parameters are String and StringList, so nothing decrypts. A grant here means one of those changed — restore it out of band first, per the note in iam.tf."
  }
}

run "ci_terraform_role_cannot_bind_a_key_to_a_log_group" {
  command = plan

  assert {
    condition = length([
      for a in local.ci_terraform_granted_actions :
      a if contains(["logs:AssociateKmsKey", "logs:DisassociateKmsKey"], a)
    ]) == 0
    error_message = "The CI Terraform role must not hold logs:AssociateKmsKey or logs:DisassociateKmsKey. The log groups take CloudWatch's AWS-owned key and set no kms_key_id, so these only become meaningful alongside a customer-managed key — the posture the assertions above reject."
  }
}
