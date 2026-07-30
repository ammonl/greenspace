terraform {
  # >= 1.7.0: the `*.tftest.hcl` suites use `override_data`, introduced in 1.7.
  required_version = ">= 1.7.0"

  # >= 6.0: iam.tf and monitoring.tf read `data.aws_region.current.region`,
  # which the v5 provider does not expose (it spells that attribute `name`).
  # Against v5 the module fails `terraform validate` outright, so the floor has
  # to be v6 to be honest.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

locals {
  naming_prefix = "${var.project}-${var.environment}-${var.season}"

  # Shared-db Secrets Manager secret consumed by the API runtime. The shared-db
  # repo creates one secret per project/environment with this fixed name; the
  # ARN includes a random AWS-generated suffix that this module does not know,
  # so callers reference the name and IAM uses a `name-*` resource pattern.
  shared_db_secret_name = "rds/shared/${var.project}_${var.environment}"

  # The API Lambda's network placement: the shared default VPC's private egress
  # subnets, behind this module's own egress-only security group in that VPC.
  # There is no per-environment VPC to fall back to (see networking.tf), so both
  # shared-VPC inputs are required.
  lambda_subnet_ids         = var.shared_private_subnet_ids
  lambda_security_group_ids = [aws_security_group.api_shared.id]
}

output "naming_prefix" {
  description = "Deterministic naming prefix for environment-scoped resources."
  value       = local.naming_prefix
}
