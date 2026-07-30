# Guards the log-encryption posture decided in ticket #500: no customer-managed
# KMS key anywhere in this module, and no server-side encryption on the alarm
# topic.
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
  environment          = "test"
  vpc_cidr             = "10.99.0.0/16"
  availability_zones   = ["eu-north-1a", "eu-north-1b"]
  public_subnet_cidrs  = ["10.99.1.0/24", "10.99.2.0/24"]
  private_subnet_cidrs = ["10.99.10.0/24", "10.99.11.0/24"]

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
