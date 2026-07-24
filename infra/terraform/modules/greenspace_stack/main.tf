terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

  # Shared-VPC tenancy: when `shared_vpc_id` is set the API Lambda runs inside
  # the shared default VPC (its private egress subnets + shared NAT) instead of
  # this environment's dedicated VPC. In that mode the dedicated interface
  # endpoints and the shared-db peering are not created — Secrets Manager and
  # SES ride the shared NAT and the RDS SG already admits the shared VPC CIDR.
  shared_tenancy = var.shared_vpc_id != null

  lambda_subnet_ids         = local.shared_tenancy ? var.shared_private_subnet_ids : aws_subnet.private[*].id
  lambda_security_group_ids = local.shared_tenancy ? [aws_security_group.api_shared[0].id] : [aws_security_group.api.id]

  # Shared-db peering is the DB path only for the dedicated-VPC layout. It is
  # torn down while in shared-tenancy mode (the shared RDS is reachable directly
  # inside the shared VPC), but the `shared_db_vpc_id`/`shared_db_vpc_cidr`
  # inputs stay set so reverting `shared_vpc_id` alone recreates the peering and
  # restores DB connectivity — the dedicated VPC has no NAT of its own.
  peering_enabled = var.shared_db_vpc_id != null && !local.shared_tenancy
}

output "naming_prefix" {
  description = "Deterministic naming prefix for environment-scoped resources."
  value       = local.naming_prefix
}
