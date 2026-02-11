# =============================================================================
# SSM Infrastructure Module — KMS Key
# =============================================================================
# Optional CMK for encrypting SSM data at rest:
#   - S3 bucket (SSM output, OpenSCAP results)
#   - CloudWatch log group
#   - Session Manager sessions
#   - SNS topic (alert notifications)
#
# Toggle: set create_kms_key = true (default) to create a new key, or
# pass an existing key ARN via kms_key_arn + create_kms_key = false.
# =============================================================================

resource "aws_kms_key" "ssm" {
  count = var.create_kms_key ? 1 : 0

  description             = "${var.name_prefix} SSM encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "${var.name_prefix}-ssm-key-policy"
    Statement = [
      {
        Sid    = "EnableRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "${local.arn_prefix}:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEC2ForEBS"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = local.account_id
            "kms:ViaService"    = "ec2.${local.region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${local.region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:/ssm/${var.name_prefix}"
          }
        }
      },
      {
        Sid    = "AllowSNSEncryption"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowSSMService"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-key"
  })
}

resource "aws_kms_alias" "ssm" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.name_prefix}-ssm"
  target_key_id = aws_kms_key.ssm[0].key_id
}

# -----------------------------------------------------------------------------
# Effective KMS key ARN — resolves to the created key or the external one
# -----------------------------------------------------------------------------

locals {
  effective_kms_key_arn = var.create_kms_key ? aws_kms_key.ssm[0].arn : var.kms_key_arn
  kms_enabled           = var.create_kms_key || var.kms_key_arn != ""
}
