# ---------- Networking ----------

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "api_security_group_id" {
  description = "Security group ID for API Lambda functions."
  value       = aws_security_group.api.id
}

output "db_security_group_id" {
  description = "Security group ID for the RDS database."
  value       = aws_security_group.db.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC. The shared-db side consumes this when adding the accepter-side route and RDS SG ingress for the peering connection."
  value       = aws_vpc.main.cidr_block
}

output "shared_db_peering_connection_id" {
  description = "ID of the VPC peering connection to the shared-RDS VPC. Null when `shared_db_vpc_id` is not set."
  value       = try(aws_vpc_peering_connection.shared_db[0].id, null)
}

# ---------- IAM ----------

output "api_runtime_role_arn" {
  description = "ARN of the Lambda execution role."
  value       = aws_iam_role.api_runtime.arn
}

output "ci_deploy_role_arn" {
  description = "ARN of the CI deploy role for GitHub Actions OIDC."
  value       = aws_iam_role.ci_deploy.arn
}

output "ci_terraform_role_arn" {
  description = "ARN of the CI Terraform role for plan/apply via GitHub Actions OIDC."
  value       = aws_iam_role.ci_terraform.arn
}

# ---------- Database ----------

output "db_endpoint" {
  description = "RDS instance endpoint address."
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "RDS instance port."
  value       = aws_db_instance.main.port
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing DB credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "app_secret_arn" {
  description = "ARN of the Secrets Manager secret for application secrets."
  value       = aws_secretsmanager_secret.app.arn
}

# ---------- SES ----------

output "ses_domain_identity_arn" {
  description = "ARN of the SES domain identity."
  value       = aws_ses_domain_identity.main.arn
}

output "ses_verification_token" {
  description = "SES domain verification token (published via Route 53)."
  value       = aws_ses_domain_identity.main.verification_token
}

output "ses_dkim_tokens" {
  description = "DKIM CNAME tokens for the SES domain (published via Route 53)."
  value       = aws_ses_domain_dkim.main.dkim_tokens
}

output "ses_configuration_set_name" {
  description = "Name of the SES configuration set for this environment."
  value       = aws_ses_configuration_set.main.name
}

output "ses_sender_email" {
  description = "Default From address for outbound email."
  value       = coalesce(var.ses_sender_email, "greenspace@${var.ses_sender_domain}")
}

output "ses_reply_to_email" {
  description = "Default Reply-To address."
  value       = var.ses_reply_to_email
}

# ---------- DNS ----------

output "route53_zone_id" {
  description = "Route 53 hosted zone ID for the sender domain."
  value       = aws_route53_zone.main.zone_id
}

output "route53_nameservers" {
  description = "Nameservers for the Route 53 hosted zone. Delegate these from your registrar."
  value       = aws_route53_zone.main.name_servers
}

# ---------- Amplify ----------

output "amplify_app_id" {
  description = "ID of the Amplify app."
  value       = aws_amplify_app.web.id
}

output "amplify_app_arn" {
  description = "ARN of the Amplify app."
  value       = aws_amplify_app.web.arn
}

output "amplify_default_domain" {
  description = "Default domain for the Amplify app (*.amplifyapp.com)."
  value       = aws_amplify_app.web.default_domain
}

output "amplify_custom_domain" {
  description = "Custom domain URL for the Amplify-hosted frontend."
  value       = "${var.amplify_domain_prefix}.${var.ses_sender_domain}"
}

# ---------- API Runtime ----------

output "api_function_name" {
  description = "Name of the API Lambda function."
  value       = aws_lambda_function.api.function_name
}

output "api_function_arn" {
  description = "ARN of the API Lambda function."
  value       = aws_lambda_function.api.arn
}

output "api_base_url" {
  description = "Public base URL for the API (Lambda Function URL)."
  value       = aws_lambda_function_url.api.function_url
}

# ---------- Monitoring ----------

output "api_log_group_name" {
  description = "CloudWatch log group name for the API."
  value       = aws_cloudwatch_log_group.api.name
}

output "logs_kms_key_arn" {
  description = "ARN of the KMS key used for log encryption."
  value       = aws_kms_key.logs.arn
}

output "alarm_sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarm notifications. Null when var.enable_alarms is false."
  value       = try(aws_sns_topic.alarms[0].arn, null)
}

output "dashboard_name" {
  description = "Name of the CloudWatch operational dashboard. Null when var.enable_dashboard is false."
  value       = try(aws_cloudwatch_dashboard.main[0].dashboard_name, null)
}
