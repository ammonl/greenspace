terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    bucket         = "greenspace-2026-tfstate"
    key            = "environments/prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "greenspace-2026-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-north-1"

  default_tags {
    tags = {
      project     = "greenspace"
      season      = "2026"
      environment = "prod"
      managed_by  = "terraform"
    }
  }
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Shared-VPC tenancy contract published by infra-shared-db (infra-shared-db#82).
# Consumed at plan time so the shared VPC / subnet IDs are never hardcoded.
data "aws_ssm_parameter" "shared_vpc_id" {
  name = "/shared/network/vpc-id"
}

data "aws_ssm_parameter" "shared_private_subnet_ids" {
  name = "/shared/network/private-subnet-ids"
}

module "greenspace_stack" {
  source             = "../../modules/greenspace_stack"
  environment        = "prod"
  github_environment = "production"

  github_oidc_provider_arn = data.aws_iam_openid_connect_provider.github.arn

  vpc_cidr             = "10.1.0.0/16"
  availability_zones   = ["eu-north-1a", "eu-north-1b"]
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]
  log_retention_days   = 90

  lambda_reserved_concurrency = -1

  ses_sender_domain  = "un17hub.com"
  ses_reply_to_email = "elise7284@gmail.com"

  # Shared-tenancy mode: the API Lambda runs in the shared default VPC. The
  # dedicated VPC (10.1.0.0/16) stays in place, dormant, as the rollback net.
  shared_vpc_id             = nonsensitive(data.aws_ssm_parameter.shared_vpc_id.value)
  shared_private_subnet_ids = split(",", nonsensitive(data.aws_ssm_parameter.shared_private_subnet_ids.value))

  # Peering inputs are retained but dormant: the module tears the peering down
  # while in shared-tenancy mode. They stay set so reverting the two shared_*
  # inputs above recreates the peering and restores DB connectivity in one step.
  shared_db_vpc_id   = "vpc-908203f9"
  shared_db_vpc_cidr = "172.31.0.0/16"

  # Seasonal alarm toggle: alarms are off out of season. Flip to true to
  # re-enable the SNS topic, email subscription, and all CloudWatch alarms
  # for an active season. alarm_email is retained but ignored while disabled.
  enable_alarms = false
  alarm_email   = "ammonl@hotmail.com"

  amplify_branch_name             = "main"
  amplify_enable_auto_build       = false
  amplify_domain_prefix           = "greenspace"
  amplify_enable_preview_branches = false
}

output "alarm_sns_topic_arn" {
  value = module.greenspace_stack.alarm_sns_topic_arn
}

output "dashboard_name" {
  value = module.greenspace_stack.dashboard_name
}

# The `staging.un17hub.com` subdomain is folded into the `un17hub.com` hosted
# zone, which is owned by the un17hub repository. There is no separate staging
# hosted zone to delegate to, so no NS delegation record is managed here.

output "naming_prefix" {
  value = module.greenspace_stack.naming_prefix
}

output "vpc_id" {
  value = module.greenspace_stack.vpc_id
}

output "api_runtime_role_arn" {
  value = module.greenspace_stack.api_runtime_role_arn
}

output "ci_deploy_role_arn" {
  value = module.greenspace_stack.ci_deploy_role_arn
}

output "ci_terraform_role_arn" {
  value = module.greenspace_stack.ci_terraform_role_arn
}

output "api_function_name" {
  value = module.greenspace_stack.api_function_name
}

output "api_base_url" {
  value = module.greenspace_stack.api_base_url
}

output "ses_configuration_set_name" {
  value = module.greenspace_stack.ses_configuration_set_name
}

output "ses_sender_email" {
  value = module.greenspace_stack.ses_sender_email
}

output "ses_reply_to_email" {
  value = module.greenspace_stack.ses_reply_to_email
}

output "amplify_app_id" {
  value = module.greenspace_stack.amplify_app_id
}

output "amplify_default_domain" {
  value = module.greenspace_stack.amplify_default_domain
}

output "amplify_custom_domain" {
  value = module.greenspace_stack.amplify_custom_domain
}
