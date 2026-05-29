# ---------- KMS Key for encryption ----------

resource "aws_kms_key" "logs" {
  description         = "Encryption key for ${local.naming_prefix} CloudWatch logs"
  enable_key_rotation = true

  tags = {
    Name = "${local.naming_prefix}-logs-key"
  }
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${local.naming_prefix}-logs"
  target_key_id = aws_kms_key.logs.key_id
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_kms_key_policy" "logs" {
  key_id = aws_kms_key.logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/${local.naming_prefix}/*"
          }
        }
      },
    ]
  })
}

# ---------- CloudWatch Log Groups ----------

resource "aws_cloudwatch_log_group" "api" {
  name              = "/${local.naming_prefix}/api"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name = "${local.naming_prefix}-api-logs"
  }

  depends_on = [aws_kms_key_policy.logs]
}

# ---------- VPC Flow Logs ----------

resource "aws_cloudwatch_log_group" "vpc_flow" {
  name              = "/${local.naming_prefix}/vpc-flow"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn

  tags = {
    Name = "${local.naming_prefix}-vpc-flow-logs"
  }

  depends_on = [aws_kms_key_policy.logs]
}

data "aws_iam_policy_document" "vpc_flow_assume" {
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
  name               = "${local.naming_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.vpc_flow_assume.json

  tags = {
    Name = "${local.naming_prefix}-vpc-flow-logs"
  }
}

data "aws_iam_policy_document" "vpc_flow_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "vpc_flow" {
  name   = "flow-log-write"
  role   = aws_iam_role.vpc_flow.id
  policy = data.aws_iam_policy_document.vpc_flow_permissions.json
}

resource "aws_flow_log" "vpc" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.vpc_flow.arn
  iam_role_arn    = aws_iam_role.vpc_flow.arn

  tags = {
    Name = "${local.naming_prefix}-vpc-flow"
  }
}

# ---------- SNS Topic for Alarm Notifications ----------

resource "aws_sns_topic" "alarms" {
  count             = var.enable_alarms ? 1 : 0
  name              = "${local.naming_prefix}-alarms"
  kms_master_key_id = aws_kms_key.logs.id

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

# ---------- CloudWatch Alarms: RDS ----------

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  count               = var.enable_alarms ? 1 : 0
  alarm_name          = "${local.naming_prefix}-rds-cpu"
  alarm_description   = "RDS CPU utilization above 80%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.naming_prefix}-rds-cpu"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_freeable_memory" {
  count               = var.enable_alarms ? 1 : 0
  alarm_name          = "${local.naming_prefix}-rds-freeable-memory"
  alarm_description   = "RDS freeable memory below 128 MB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 134217728
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.naming_prefix}-rds-freeable-memory"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  count               = var.enable_alarms ? 1 : 0
  alarm_name          = "${local.naming_prefix}-rds-connections"
  alarm_description   = "RDS database connections above threshold"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.alarm_rds_connections_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.identifier
  }

  alarm_actions = [aws_sns_topic.alarms[0].arn]
  ok_actions    = [aws_sns_topic.alarms[0].arn]

  tags = {
    Name = "${local.naming_prefix}-rds-connections"
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
        width  = 8
        height = 6
        properties = {
          title  = "RDS CPU Utilization"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.main.identifier, { stat = "Average", label = "CPU %" }],
          ]
          period = 300
          view   = "timeSeries"
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "RDS Freeable Memory & Connections"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", aws_db_instance.main.identifier, { stat = "Average", label = "Freeable Memory (bytes)" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier, { stat = "Average", label = "Connections", yAxis = "right" }],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "RDS Read/Write IOPS"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", aws_db_instance.main.identifier, { stat = "Average", label = "Read IOPS" }],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", aws_db_instance.main.identifier, { stat = "Average", label = "Write IOPS" }],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
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
  from = aws_cloudwatch_metric_alarm.rds_cpu
  to   = aws_cloudwatch_metric_alarm.rds_cpu[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.rds_freeable_memory
  to   = aws_cloudwatch_metric_alarm.rds_freeable_memory[0]
}

moved {
  from = aws_cloudwatch_metric_alarm.rds_connections
  to   = aws_cloudwatch_metric_alarm.rds_connections[0]
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
