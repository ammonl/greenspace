variable "project" {
  description = "Project tag and naming prefix."
  type        = string
  default     = "greenspace"
}

variable "season" {
  description = "Season tag."
  type        = string
  default     = "2026"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

# ---------- Shared-VPC tenancy ----------

variable "shared_vpc_id" {
  description = "VPC ID of the shared default VPC owned by `ammonl/un17-infra-shared`. The API Lambda attaches to the published shared private subnets with its own egress-only security group in this VPC. Required — there is no per-environment VPC to fall back to. Consume from SSM (`/shared/network/vpc-id`) at plan time — do not hardcode."
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-f0-9]+$", var.shared_vpc_id))
    error_message = "shared_vpc_id must be a valid AWS VPC ID (vpc-...)."
  }
}

variable "shared_private_subnet_ids" {
  description = "Private egress subnet IDs in the shared VPC that the API Lambda attaches to. Required and non-empty — the Lambda's vpc_config has no other subnets to use. Consume from SSM (`/shared/network/private-subnet-ids`) at plan time — do not hardcode."
  type        = list(string)

  validation {
    condition     = length(var.shared_private_subnet_ids) > 0
    error_message = "shared_private_subnet_ids must be non-empty; the Lambda vpc_config needs subnets in the shared VPC."
  }

  validation {
    condition     = alltrue([for id in var.shared_private_subnet_ids : can(regex("^subnet-[a-f0-9]+$", id))])
    error_message = "shared_private_subnet_ids must all be valid AWS subnet IDs (subnet-...)."
  }
}

# ---------- IAM / CI ----------

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider created by the bootstrap stack."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must be a valid IAM OIDC provider ARN (arn:aws:iam::<account>:oidc-provider/...)."
  }
}

variable "github_repo" {
  description = "GitHub repository in owner/name format for OIDC trust."
  type        = string
  default     = "ammonl/greenspace"
}

variable "tf_state_bucket" {
  description = "S3 bucket name for Terraform remote state."
  type        = string
  default     = "greenspace-2026-tfstate"
}

variable "tf_lock_table" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
  default     = "greenspace-2026-tflock"
}

variable "github_environment" {
  description = "GitHub Actions environment name for OIDC trust (may differ from var.environment). Defaults to var.environment."
  type        = string
  default     = null
}

variable "ses_sender_domain" {
  description = "Domain name for SES sender identity and Route 53 hosted zone."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.ses_sender_domain))
    error_message = "ses_sender_domain must be a valid domain name (e.g. example.com)."
  }
}

variable "ses_sender_email" {
  description = "Default From address for outbound email. Defaults to greenspace@<ses_sender_domain>."
  type        = string
  default     = null
}

variable "ses_reply_to_email" {
  description = "Default Reply-To address for outbound email."
  type        = string
  default     = "elise7284@gmail.com"
}

# ---------- Amplify ----------

variable "amplify_branch_name" {
  description = "Git branch name for Amplify to build and deploy."
  type        = string
  default     = "main"
}

variable "amplify_enable_auto_build" {
  description = "Enable automatic builds on push to the configured branch."
  type        = bool
  default     = true
}

variable "amplify_enable_preview_branches" {
  description = "Enable Amplify preview environments: automatic branch creation for matching pushed branches, native pull-request previews (pr-<n> branches), and — because those branches then need reclamation — the deploy role's amplify:DeleteBranch grant on this environment's app. Enabling this hands the unattended CI deploy role branch-delete on the app serving the environment's domain, so keep it false anywhere that app is production-facing."
  type        = bool
  default     = false
}

variable "amplify_preview_branch_patterns" {
  description = "Glob patterns for branches that trigger automatic preview environments."
  type        = list(string)
  default     = ["feature/**", "fix/**"]
}

variable "amplify_domain_prefix" {
  description = "Subdomain prefix for the Amplify custom domain (e.g. 'greenspace' → greenspace.<domain>)."
  type        = string
  default     = "greenspace"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.amplify_domain_prefix))
    error_message = "amplify_domain_prefix must be a valid subdomain label."
  }
}

# ---------- Lambda ----------

variable "lambda_memory_size" {
  description = "Memory allocation for the API Lambda function in MB."
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "lambda_memory_size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the API Lambda function in seconds."
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for the API Lambda. Set to -1 for unrestricted."
  type        = number
  default     = 50

  validation {
    condition     = var.lambda_reserved_concurrency >= -1 && var.lambda_reserved_concurrency <= 1000
    error_message = "lambda_reserved_concurrency must be between -1 (unrestricted) and 1000."
  }
}

# ---------- Monitoring ----------

variable "log_retention_days" {
  description = "CloudWatch log group retention in days."
  type        = number
  default     = 30

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention value."
  }
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications. Set to null to skip subscription. Ignored when var.enable_alarms is false."
  type        = string
  default     = null
}

variable "enable_alarms" {
  description = "Seasonal toggle: whether to provision the SNS alarm topic, email subscription, and all CloudWatch metric alarms. Set false to disable alarms out of season; flip to true to re-enable for an active season."
  type        = bool
  default     = true
}

variable "enable_dashboard" {
  description = "Whether to provision the CloudWatch operational dashboard."
  type        = bool
  default     = true
}
