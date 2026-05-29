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

  db_instance_class        = "db.t4g.micro"
  db_allocated_storage     = 20
  db_max_allocated_storage = 100
  db_backup_retention_days = 35
  db_multi_az              = false

  lambda_reserved_concurrency = -1

  ses_sender_domain  = "un17hub.com"
  ses_reply_to_email = "elise7284@gmail.com"

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

# ---------- Staging subdomain delegation ----------

data "terraform_remote_state" "staging" {
  backend = "s3"

  config = {
    bucket = "greenspace-2026-tfstate"
    key    = "environments/staging/terraform.tfstate"
    region = "eu-north-1"
  }
}

resource "aws_route53_record" "staging_ns" {
  zone_id = module.greenspace_stack.route53_zone_id
  name    = "staging.un17hub.com"
  type    = "NS"
  ttl     = 300
  records = data.terraform_remote_state.staging.outputs.route53_nameservers
}

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

output "db_endpoint" {
  value = module.greenspace_stack.db_endpoint
}

output "db_secret_arn" {
  value = module.greenspace_stack.db_secret_arn
}

output "app_secret_arn" {
  value = module.greenspace_stack.app_secret_arn
}

output "api_function_name" {
  value = module.greenspace_stack.api_function_name
}

output "api_base_url" {
  value = module.greenspace_stack.api_base_url
}

output "ses_domain_identity_arn" {
  value = module.greenspace_stack.ses_domain_identity_arn
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

output "route53_zone_id" {
  value = module.greenspace_stack.route53_zone_id
}

output "route53_nameservers" {
  value = module.greenspace_stack.route53_nameservers
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
