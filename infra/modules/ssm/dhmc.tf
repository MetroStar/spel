# =============================================================================
# SSM Infrastructure Module — Default Host Management Configuration (DHMC)
# =============================================================================
# Enables AWS Systems Manager Default Host Management Configuration, which
# automatically registers ALL EC2 instances in the account/region with SSM
# — no instance profile required. Instances gain SSM agent connectivity on
# launch, enabling Session Manager, Run Command, and State Manager
# associations to target them immediately.
#
# DHMC uses a dedicated IAM role trusted by ssm.amazonaws.com (not
# ec2.amazonaws.com). This role provides baseline SSM permissions and the
# S3/CloudWatch/KMS access needed for STIG compliance operations.
#
# Prerequisites:
#   - SSM agent must be installed on the AMI (all Crucible AMIs include it)
#   - Instance must have network access to SSM endpoints (VPC endpoints or
#     internet gateway)
#
# Reference:
#   https://docs.aws.amazon.com/systems-manager/latest/userguide/managed-instances-default-host-management.html
# =============================================================================

# -----------------------------------------------------------------------------
# DHMC IAM Role
# -----------------------------------------------------------------------------
# Separate from the instance profile role (which trusts ec2.amazonaws.com).
# DHMC requires an IAM role that trusts ssm.amazonaws.com.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "dhmc" {
  count = var.enable_dhmc ? 1 : 0

  name = "${var.name_prefix}-ssm-dhmc-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "SSMAssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-dhmc-role"
  })
}

# Attach the AWS-managed SSM policy (required for DHMC)
resource "aws_iam_role_policy_attachment" "dhmc_core" {
  count = var.enable_dhmc ? 1 : 0

  role       = aws_iam_role.dhmc[0].name
  policy_arn = "${local.arn_prefix}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Grant DHMC-managed instances access to S3, CloudWatch, and KMS
# so STIG enforcement, Ansible playbooks, and logging work without
# an instance profile.
resource "aws_iam_role_policy" "dhmc_crucible" {
  count = var.enable_dhmc ? 1 : 0

  name = "${var.name_prefix}-ssm-dhmc-crucible"
  role = aws_iam_role.dhmc[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SSMBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${local.arn_prefix}:s3:::aws-ssm-${local.region}/*",
          "${local.arn_prefix}:s3:::aws-ssm-${local.region}",
          "${local.arn_prefix}:s3:::amazon-ssm-${local.region}/*",
          "${local.arn_prefix}:s3:::amazon-ssm-${local.region}",
          "${local.arn_prefix}:s3:::amazon-ssm-packages-${local.region}/*",
          "${local.arn_prefix}:s3:::amazon-ssm-packages-${local.region}",
          "${local.arn_prefix}:s3:::${local.region}-birdwatcher-prod/*",
          "${local.arn_prefix}:s3:::${local.region}-birdwatcher-prod",
          "${local.arn_prefix}:s3:::patch-baseline-snapshot-${local.region}/*",
          "${local.arn_prefix}:s3:::patch-baseline-snapshot-${local.region}"
        ]
      },
      {
        Sid    = "S3OutputBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketAcl"
        ]
        Resource = [
          aws_s3_bucket.ssm.arn,
          "${aws_s3_bucket.ssm.arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.ssm.arn,
          "${aws_cloudwatch_log_group.ssm.arn}:*"
        ]
      },
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = local.kms_enabled ? [local.effective_kms_key_arn] : ["*"]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# DHMC Service Setting
# -----------------------------------------------------------------------------
# Activates Default Host Management Configuration for this account/region.
# The setting_value is the IAM role name (not ARN) that SSM assumes for
# DHMC-managed instances.
# -----------------------------------------------------------------------------

resource "aws_ssm_service_setting" "dhmc" {
  count = var.enable_dhmc ? 1 : 0

  setting_id    = "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
  setting_value = aws_iam_role.dhmc[0].name
}
