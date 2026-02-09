# =============================================================================
# SSM Infrastructure Module — CloudWatch Logs
# =============================================================================
# Log group for SSM RunCommand output and Session Manager logs.
# Retention is configurable (default: 90 days).
# =============================================================================

resource "aws_cloudwatch_log_group" "ssm" {
  name              = "/ssm/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-logs"
  })
}
