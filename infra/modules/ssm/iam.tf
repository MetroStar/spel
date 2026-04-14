# =============================================================================
# SSM Infrastructure Module — IAM
# =============================================================================
# Two distinct IAM constructs:
#
# 1. Instance Role/Profile: Attached to EC2 instances (Packer-built AMIs).
#    Grants the SSM agent permissions to communicate with SSM services,
#    report inventory, apply patches, and write logs.
#
# 2. Caller Policy: Attached to CI runners / human operators. Grants
#    permissions to invoke SSM operations (SendCommand, StartSession, etc.).
#
# All ARNs use data.aws_partition for GovCloud compatibility.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Instance Role + Policy + Profile
# -----------------------------------------------------------------------------

resource "aws_iam_role" "ssm_instance" {
  count = var.create_instance_profile ? 1 : 0

  name = "${var.name_prefix}-ssm-instance-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EC2AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-instance-role"
  })
}

resource "aws_iam_role_policy" "ssm_instance_core" {
  count = var.create_instance_profile ? 1 : 0

  name = "${var.name_prefix}-ssm-instance-core"
  role = aws_iam_role.ssm_instance[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMCoreAgent"
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForNode",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameters",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMMessaging"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Messaging"
        Effect = "Allow"
        Action = [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
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
        Sid    = "S3STIGDownloads"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${local.arn_prefix}:s3:::aws-windows-downloads-${local.region}/STIG/*",
          "${local.arn_prefix}:s3:::aws-windows-downloads/STIG/*"
        ]
      },
      {
        Sid    = "S3OutputBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.ssm.arn,
          "${aws_s3_bucket.ssm.arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.ssm.arn,
          "${aws_cloudwatch_log_group.ssm.arn}:*"
        ]
      },
      {
        Sid    = "SSMParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:parameter/${var.name_prefix}/*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = local.kms_enabled ? [local.effective_kms_key_arn] : ["*"]
      }
    ]
  })
}

# Attach SSM managed policy to existing role if not creating a new profile
resource "aws_iam_role_policy_attachment" "ssm_existing_role" {
  count = var.create_instance_profile ? 0 : 1

  role       = var.existing_instance_role_name
  policy_arn = "${local.arn_prefix}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  count = var.create_instance_profile ? 1 : 0

  name = "${var.name_prefix}-ssm-instance-profile"
  role = aws_iam_role.ssm_instance[0].name

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-instance-profile"
  })
}

# -----------------------------------------------------------------------------
# 2. Caller Policy (for CI runners / human operators)
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "ssm_caller" {
  name        = "${var.name_prefix}-ssm-caller-policy"
  description = "Permissions for CI runners and operators to invoke SSM operations on Crucible instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMRunCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:CancelCommand"
        ]
        Resource = [
          "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:document/*",
          "${local.arn_prefix}:ssm:${local.region}::document/AWS-*",
          "${local.arn_prefix}:ec2:${local.region}:${local.account_id}:instance/*"
        ]
      },
      {
        Sid    = "SSMSessionManager"
        Effect = "Allow"
        Action = [
          "ssm:StartSession",
          "ssm:TerminateSession",
          "ssm:ResumeSession",
          "ssm:DescribeSessions"
        ]
        Resource = [
          "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:session/*",
          "${local.arn_prefix}:ec2:${local.region}:${local.account_id}:instance/*",
          "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:document/${var.name_prefix}-*",
          "${local.arn_prefix}:ssm:${local.region}::document/AWS-StartPortForwardingSession"
        ]
      },
      {
        Sid    = "SSMStateManager"
        Effect = "Allow"
        Action = [
          "ssm:CreateAssociation",
          "ssm:UpdateAssociation",
          "ssm:DeleteAssociation",
          "ssm:DescribeAssociation",
          "ssm:ListAssociations"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMInventoryAndCompliance"
        Effect = "Allow"
        Action = [
          "ssm:GetInventory",
          "ssm:GetInventorySchema",
          "ssm:ListInventoryEntries",
          "ssm:ListComplianceItems",
          "ssm:ListComplianceSummaries",
          "ssm:ListResourceComplianceSummaries"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMDescribe"
        Effect = "Allow"
        Action = [
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstanceProperties",
          "ssm:GetConnectionStatus",
          "ssm:DescribeDocument",
          "ssm:ListDocuments",
          "ssm:GetDocument"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMPatchManager"
        Effect = "Allow"
        Action = [
          "ssm:DescribePatchBaselines",
          "ssm:GetPatchBaseline",
          "ssm:DescribePatchGroups",
          "ssm:DescribeInstancePatches",
          "ssm:DescribeInstancePatchStates"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3OutputAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.ssm.arn,
          "${aws_s3_bucket.ssm.arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.ssm.arn,
          "${aws_cloudwatch_log_group.ssm.arn}:*"
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-caller-policy"
  })
}
