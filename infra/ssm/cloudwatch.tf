# =============================================================================
# SSM Infrastructure Module — CloudWatch Logs, Alarms & SNS
# =============================================================================
# Log group for SSM RunCommand output and Session Manager logs.
# Retention is configurable (default: 90 days).
#
# Optional SNS topic for alert notifications (email subscription gated by
# alert_email variable). CloudWatch alarms trigger on SSM error patterns
# and compliance failures.
# =============================================================================

resource "aws_cloudwatch_log_group" "ssm" {
  name              = "/ssm/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_enabled ? local.effective_kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-logs"
  })
}

# -----------------------------------------------------------------------------
# SNS Topic for Alerts
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "ssm_alerts" {
  name              = "${var.name_prefix}-ssm-alerts"
  kms_master_key_id = local.kms_enabled ? local.effective_kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.ssm_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -----------------------------------------------------------------------------
# Metric Filters — detect SSM errors and compliance failures in logs
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "ssm_errors" {
  name           = "${var.name_prefix}-ssm-errors"
  pattern        = "?ERROR ?Failed ?\"status\":\"Failed\""
  log_group_name = aws_cloudwatch_log_group.ssm.name

  metric_transformation {
    name          = "${var.name_prefix}-SSMErrors"
    namespace     = "SPEL/SSM"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "compliance_failures" {
  name           = "${var.name_prefix}-compliance-failures"
  pattern        = "?\"result\":\"fail\" ?NON_COMPLIANT ?\"fail\":"
  log_group_name = aws_cloudwatch_log_group.ssm.name

  metric_transformation {
    name          = "${var.name_prefix}-ComplianceFailures"
    namespace     = "SPEL/SSM"
    value         = "1"
    default_value = "0"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "ssm_errors" {
  alarm_name          = "${var.name_prefix}-ssm-errors"
  alarm_description   = "SSM command or session errors detected in ${var.name_prefix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "${var.name_prefix}-SSMErrors"
  namespace           = "SPEL/SSM"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.ssm_alerts.arn]
  ok_actions    = [aws_sns_topic.ssm_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-errors-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "compliance_failures" {
  alarm_name          = "${var.name_prefix}-compliance-failures"
  alarm_description   = "STIG compliance failures detected in ${var.name_prefix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "${var.name_prefix}-ComplianceFailures"
  namespace           = "SPEL/SSM"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.ssm_alerts.arn]
  ok_actions    = [aws_sns_topic.ssm_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-compliance-failures-alarm"
  })
}
