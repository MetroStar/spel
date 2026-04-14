# =============================================================================
# IAM Module — Packer Builder Role, Policy, and Instance Profile
# =============================================================================
# Creates the IAM role and instance profile used by Packer-launched EC2
# instances. The role gets:
#   1. A custom inline policy for basic SSM agent communication
#   2. The AmazonSSMManagedInstanceCore managed policy
#
# All ARNs use data.aws_partition for GovCloud compatibility.
# =============================================================================

data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  arn_prefix = "arn:${data.aws_partition.current.partition}"
  region     = data.aws_region.current.id
}

# -----------------------------------------------------------------------------
# IAM Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "packer_builder" {
  name                 = "${var.name_prefix}-packer-builder-role"
  description          = "Role for Crucible Packer builder EC2 instances"
  max_session_duration = 21600 # 6 hours

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

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-packer-builder-role"
  })
}

# -----------------------------------------------------------------------------
# IAM Policy — SSM Agent Communication
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy" "ssm_access" {
  name = "${var.name_prefix}-packer-builder-ssm"
  role = aws_iam_role.packer_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
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
          "${local.arn_prefix}:s3:::${local.region}-birdwatcher-prod/*",
          "${local.arn_prefix}:s3:::${local.region}-birdwatcher-prod"
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
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Managed Policy — AmazonSSMManagedInstanceCore
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.packer_builder.name
  policy_arn = "${local.arn_prefix}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# -----------------------------------------------------------------------------
# Instance Profile
# -----------------------------------------------------------------------------

resource "aws_iam_instance_profile" "packer_builder" {
  name = "${var.name_prefix}-packer-builder-profile"
  role = aws_iam_role.packer_builder.name

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-packer-builder-profile"
  })
}
