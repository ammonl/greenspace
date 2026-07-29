# ---------- Networking ----------

output "vpc_id" {
  description = "ID of the dedicated VPC. Null once `retire_dedicated_vpc` has destroyed it."
  value       = try(aws_vpc.main[0].id, null)
}

output "public_subnet_ids" {
  description = "IDs of the public subnets. Empty once `retire_dedicated_vpc` has destroyed them."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets. Empty once `retire_dedicated_vpc` has destroyed them."
  value       = aws_subnet.private[*].id
}

output "api_security_group_id" {
  description = "Security group ID the API Lambda actually runs behind: the shared-VPC egress-only SG in shared-tenancy mode, otherwise the dedicated-VPC API SG."
  value       = local.lambda_security_group_ids[0]
}

output "db_security_group_id" {
  description = "Security group ID for the RDS database. Null once `retire_dedicated_vpc` has destroyed it."
  value       = try(aws_security_group.db[0].id, null)
}

output "vpc_cidr" {
  description = "CIDR block of the dedicated VPC. The shared-db side consumes this when adding the accepter-side route and RDS SG ingress for the peering connection. Null once `retire_dedicated_vpc` has destroyed the VPC (the peering it served is torn down first, in shared-tenancy mode). Account ID and region are not exposed; the shared-db side derives them from its own provider under the same-account assumption."
  value       = try(aws_vpc.main[0].cidr_block, null)
}

output "shared_db_peering_connection_id" {
  description = "ID of the VPC peering connection to the shared-RDS VPC. Null when `shared_db_vpc_id` is not set or while in shared-tenancy mode (peering is torn down)."
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

# ---------- SES ----------
# Domain identity, verification token, and DKIM tokens are owned by the un17hub
# repository (see ses.tf); this module only exposes its own configuration set
# and the resolved sender/reply-to addresses.

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
  description = "ARN of the legacy logs KMS key. Nothing encrypts under it any more; it is retained only to decrypt log events written before the switch to AWS-managed encryption, and is removed once those have aged out."
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
