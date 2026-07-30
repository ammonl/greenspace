terraform {
  # >= 1.7.0: the `removed` block below needs it.
  required_version = ">= 1.7.0"

  # >= 6.0: the state bucket's encryption rule sets `blocked_encryption_types`,
  # which the v5 provider does not know about.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      project    = "greenspace"
      season     = "2026"
      managed_by = "terraform"
    }
  }
}

# ---------- S3 bucket for Terraform state ----------

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true

    # Reject SSE-C uploads outright. Nothing writes state with a caller-supplied
    # key, and a bucket that accepts them can hold objects this account cannot
    # decrypt. Declared rather than left to the provider default (`[]`), which
    # would silently relax the setting the live bucket already carries.
    blocked_encryption_types = ["SSE-C"]
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- DynamoDB table for state locking ----------

resource "aws_dynamodb_table" "tflock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    purpose = "terraform-state-lock"
  }
}

# ---------- GitHub Actions OIDC Provider ----------
#
# Read, not managed. IAM allows exactly one OIDC provider per URL per account,
# so `token.actions.githubusercontent.com` is a single account-wide resource
# shared by every UN17 repo — this one, un17hub, un17-resources, loppemarked,
# un17-calendar, and un17-infra-shared. It is created and owned by whichever
# stack bootstraps the account (its live `project` tag says un17hub), and the
# environment stacks here have always read it rather than declared it.
#
# It used to be declared as a resource in this file too, which meant two repos
# claiming one resource: each apply rewrote the other's `project` tag, and each
# side's drift detection reported the other's work as drift. Worse, the declared
# `thumbprint_list` was a placeholder (`ffff...`) on the theory that AWS ignores
# the thumbprint for GitHub's provider, so applying it overwrote the real
# thumbprints with a dummy value on the root of trust for all keyless CI auth.
#
# Consequence worth knowing: bootstrapping a brand-new account requires this
# provider to exist first. Create it once from the account-level stack that owns
# it, then run this one.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Drops the provider from any bootstrap state that still tracks it as a managed
# resource, without touching the live resource. `destroy = false` is the whole
# point: deleting the resource block alone would plan a destroy — and because
# `prevent_destroy` lives in configuration, removing the block removes the guard
# along with it, so nothing would stop the delete that breaks CI auth for six
# repos. A no-op for state that never tracked it.
removed {
  from = aws_iam_openid_connect_provider.github

  lifecycle {
    destroy = false
  }
}

# ---------- Outputs ----------

output "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state."
  value       = aws_s3_bucket.tfstate.bucket
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "DynamoDB table used for state locking."
  value       = aws_dynamodb_table.tflock.name
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider. Read from the account, not managed here."
  value       = data.aws_iam_openid_connect_provider.github.arn
}
