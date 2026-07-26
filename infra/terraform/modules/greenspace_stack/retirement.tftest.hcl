# Validates the `retire_dedicated_vpc` gate (ticket #472): retirement requires
# shared-tenancy mode to already be active, and once retired the dedicated VPC
# and everything that exists only to serve it drop out of the plan while
# module outputs stay null-safe.
#
# `command = plan` throughout (no real AWS credentials in CI/local runs), so
# assertions stick to values known at plan time: resource counts (a function
# of input variables, not provider-assigned IDs) and outputs that resolve to a
# literal `null` via `try()` rather than an AWS-computed value.
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

run "retire_requires_shared_tenancy" {
  command = plan

  variables {
    retire_dedicated_vpc = true
    # shared_vpc_id left at its default (null): not yet migrated to shared tenancy.
  }

  expect_failures = [terraform_data.retire_dedicated_vpc_gate]

  # The precondition failure above is expected to block apply, but it does not
  # stop `terraform plan` from resolving the rest of the graph — so this is the
  # scenario that actually matters for `dedicated_vpc_count`'s AND-gate: if
  # `retire_dedicated_vpc = true` alone tore down the subnets (as it did before
  # this was fixed — see #481 review), the Lambda would be left with an empty
  # `vpc_config.subnet_ids` even though the precondition also fails. Both must
  # hold: the plan errors out AND the network path stays intact.
  assert {
    condition     = length(aws_subnet.private) == length(var.private_subnet_cidrs)
    error_message = "Dedicated-VPC subnets must not be destroyed by retire_dedicated_vpc alone — dedicated_vpc_count requires shared_tenancy too, so misconfiguration can't strand the Lambda even though the precondition also fails this plan."
  }

  assert {
    condition     = length(local.lambda_subnet_ids) == length(var.private_subnet_cidrs)
    error_message = "The Lambda must keep a non-empty vpc_config.subnet_ids even when retire_dedicated_vpc is set without shared_vpc_id."
  }
}

run "dedicated_vpc_created_by_default" {
  command = plan

  assert {
    condition     = length(aws_vpc.main) == 1
    error_message = "The dedicated VPC must be planned when retire_dedicated_vpc is false (the default)."
  }

  assert {
    condition     = length(aws_subnet.public) == length(var.public_subnet_cidrs)
    error_message = "Public subnets must be created when retire_dedicated_vpc is false."
  }

  assert {
    condition     = length(aws_security_group.db) == 1
    error_message = "The dedicated-VPC DB security group must be planned when retire_dedicated_vpc is false."
  }

  assert {
    condition     = length(aws_flow_log.vpc) == 1
    error_message = "VPC flow logs must be planned when retire_dedicated_vpc is false."
  }
}

run "dedicated_vpc_survives_shared_tenancy_alone" {
  command = plan

  variables {
    shared_vpc_id             = "vpc-908203f9"
    shared_private_subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
    # retire_dedicated_vpc left at its default (false): tenancy mode alone must
    # not tear down the dedicated VPC — it stays as the rollback net.
  }

  assert {
    condition     = length(aws_vpc.main) == 1
    error_message = "Shared-tenancy mode alone must not retire the dedicated VPC; it stays dormant as the rollback net until retire_dedicated_vpc is set."
  }
}

run "retirement_clears_dedicated_vpc_resources" {
  command = plan

  variables {
    shared_vpc_id             = "vpc-908203f9"
    shared_private_subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
    retire_dedicated_vpc      = true
  }

  assert {
    condition     = length(aws_vpc.main) == 0
    error_message = "The dedicated VPC must not be planned once retire_dedicated_vpc has retired it."
  }

  assert {
    condition     = length(aws_subnet.public) == 0 && length(aws_subnet.private) == 0
    error_message = "Dedicated VPC subnets must not be planned once retire_dedicated_vpc is true."
  }

  assert {
    condition     = length(aws_internet_gateway.main) == 0
    error_message = "The internet gateway must not be planned once retire_dedicated_vpc is true."
  }

  assert {
    condition     = length(aws_route_table.public) == 0 && length(aws_route_table.private) == 0
    error_message = "Dedicated-VPC route tables must not be planned once retire_dedicated_vpc is true."
  }

  assert {
    condition     = length(aws_security_group.api) == 0
    error_message = "The dedicated-VPC API security group must not be planned once retire_dedicated_vpc is true."
  }

  assert {
    condition     = length(aws_security_group.db) == 0
    error_message = "The dedicated-VPC DB security group must not be planned once retire_dedicated_vpc is true."
  }

  assert {
    condition     = length(aws_flow_log.vpc) == 0
    error_message = "VPC flow logs must not be planned once retire_dedicated_vpc is true."
  }

  assert {
    condition     = output.vpc_id == null
    error_message = "vpc_id must be null once retire_dedicated_vpc has destroyed the dedicated VPC."
  }

  assert {
    condition     = output.db_security_group_id == null
    error_message = "db_security_group_id must be null once retire_dedicated_vpc has destroyed the dedicated VPC."
  }

  assert {
    condition     = length(aws_security_group.api_shared) == 1
    error_message = "The API Lambda must still resolve a security group (the shared-VPC egress-only SG) once retired."
  }

  assert {
    condition     = length(local.lambda_subnet_ids) == length(var.shared_private_subnet_ids)
    error_message = "The API Lambda must keep a non-empty vpc_config.subnet_ids (the shared VPC's subnets) once the dedicated VPC is retired."
  }
}
