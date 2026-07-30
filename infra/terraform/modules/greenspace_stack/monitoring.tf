# ---------- Module-wide data sources ----------
#
# Declared here for historical reasons; `iam.tf`, `networking.tf`, and the
# dashboard below all depend on them.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------- CloudWatch Log Groups ----------
#
# Encrypted at rest with an AWS-owned key, which is what CloudWatch applies when
# no `kms_key_id` is set.

resource "aws_cloudwatch_log_group" "api" {
  name              = "/${local.naming_prefix}/api"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.naming_prefix}-api-logs"
  }
}

# ---------- VPC Flow Logs ----------
#
# Exist only to serve the dedicated VPC, so they're destroyed alongside it on
# retirement.

resource "aws_cloudwatch_log_group" "vpc_flow" {
  count = local.dedicated_vpc_count

  name              = "/${local.naming_prefix}/vpc-flow"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.naming_prefix}-vpc-flow-logs"
  }
}

data "aws_iam_policy_document" "vpc_flow_assume" {
  count = local.dedicated_vpc_count

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_flow" {
  count = local.dedicated_vpc_count

  name               = "${local.naming_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_assume[0].json

  tags = {
    Name = "${local.naming_prefix}-vpc-flow-logs"
  }
}

data "aws_iam_policy_document" "vpc_flow_permissions" {
  count = local.dedicated_vpc_count

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow" {
  count = local.dedicated_vpc_count

  name   = "flow-log-write"
  role   = aws_iam_role.vpc_flow[0].id
  policy = data.aws_iam_policy_document.vpc_flow_permissions[0].json
}

resource "aws_flow_log" "vpc" {
  count = local.dedicated_vpc_count

  vpc_id          = aws_vpc.main[0].id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.vpc_flow[0].arn
  iam_role_arn    = aws_iam_role.vpc_flow[0].arn

  tags = {
    Name = "${local.naming_prefix}-vpc-flow"
  }
}

# ---------- SNS Topic for Alarm Notifications ----------

# Deliberately unencrypted at rest, and `alias/aws/sns` is specifically not the
# fix. An AWS service event source can publish to an encrypted topic only
# through a customer-managed key whose policy names that service principal, and
# the AWS-managed key has no editable policy. CloudWatch alarms are this topic's
# only publisher, so pointing at `alias/aws/sns` would buy encryption at rest by
# making every notification undeliverable — silently, since the alarm itself
# still transitions. The payload is an alarm name, a metric, and a state, with
# no personal data, so that is a bad trade. The default topic policy
# (`AWS:SourceOwner` equal to the account) already admits CloudWatch, so no
# compensating `aws_sns_topic_policy` is needed.
resource "aws_sns_topic" "alarms" {
  count = var.enable_alarms ? 1 : 0
  name  = "${local.naming_prefix}-alarms"

  tags = {
    Name = "${local.naming_prefix}-alarms"
  }
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.enable_alarms && var.alarm_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------- CloudWatch Alarms: Lambda ----------

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count               = var.enable_alarms ? 1 : 0
  alarm_name          = "${local.naming_prefix}-lambda-errors"
  alarm_description   = "API Lambda function errors detected"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.naming_prefix}-lambda-errors"
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  count               = var.enable_alarms ? 1 : 0
  alarm_name          = "${local.naming_prefix}-lambda-throttles"
  alarm_description   = "API Lambda function throttled"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api.function_name
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.naming_prefix}-lambda-throttles"
  }
}

# ---------- CloudWatch Alarms: SES ----------

resource "aws_cloudwatch_metric_alarm" "ses_bounces" {
  count               = var.enable_alarms ? 1 : 0
  alarm_name          = "${local.naming_prefix}-ses-bounces"
  alarm_description   = "SES bounce rate is elevated"
  namespace           = "AWS/SES"
  metric_name         = "Bounce"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.naming_prefix}-ses-bounces"
  }
}

resource "aws_cloudwatch_metric_alarm" "ses_complaints" {
  count               = var.enable_alarms ? 1 : 0
  alarm_name          = "${local.naming_prefix}-ses-complaints"
  alarm_description   = "SES complaint rate is elevated"
  namespace           = "AWS/SES"
  metric_name         = "Complaint"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.naming_prefix}-ses-complaints"
  }
}

# ---------- CloudWatch Dashboard ----------

resource "aws_cloudwatch_dashboard" "main" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "${local.naming_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${local.naming_prefix} – Operational Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations & Errors"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.api.function_name, { stat = "Sum", label = "Invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.api.function_name, { stat = "Sum", label = "Errors", color = "#d62728" }],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Duration (ms)"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "Average", label = "Avg Duration" }],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api.function_name, { stat = "p99", label = "p99 Duration", color = "#ff7f0e" }],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Throttles & Concurrent Executions"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/Lambda", "Throttles", "FunctionName", aws_lambda_function.api.function_name, { stat = "Sum", label = "Throttles" }],
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", aws_lambda_function.api.function_name, { stat = "Maximum", label = "Concurrent Executions" }],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "SES Sends, Bounces & Complaints"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/SES", "Send", { stat = "Sum", label = "Sends" }],
            ["AWS/SES", "Bounce", { stat = "Sum", label = "Bounces", color = "#d62728" }],
            ["AWS/SES", "Complaint", { stat = "Sum", label = "Complaints", color = "#ff7f0e" }],
          ]
          period = 3600
          view   = "timeSeries"
        }
      },
    ]
  })
}

# ---------- State migrations ----------
#
# These resources gained `count` to make alarms/dashboard optional per environment.
# The `moved` blocks rename any pre-existing state entries to their indexed
# addresses so a toggle flip plans as a clean create/destroy of the indexed
# resource rather than a rename churn. Alarms are now seasonally gated by
# var.enable_alarms (off out of season in prod); the dashboard by
# var.enable_dashboard.

moved {
  from = aws_sns_topic.alarms
  to   = aws_sns_topic.alarms[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.lambda_errors
  to   = aws_cloudwatch_metric_alarm.lambda_errors[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.lambda_throttles
  to   = aws_cloudwatch_metric_alarm.lambda_throttles[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.ses_bounces
  to   = aws_cloudwatch_metric_alarm.ses_bounces[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.ses_complaints
  to   = aws_cloudwatch_metric_alarm.ses_complaints[0]
}

moved {
  from = aws_cloudwatch_dashboard.main
  to   = aws_cloudwatch_dashboard.main[0]
}
