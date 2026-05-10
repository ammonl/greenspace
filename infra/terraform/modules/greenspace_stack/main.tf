terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
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
}

output "naming_prefix" {
  description = "Deterministic naming prefix for environment-scoped resources."
  value       = local.naming_prefix
}
