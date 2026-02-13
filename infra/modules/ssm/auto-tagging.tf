# =============================================================================
# SSM Infrastructure Module — AMI Tag Auto-Propagation
# =============================================================================
# Automatically propagates StigPlatform and StigManaged tags from SPEL AMIs
# to newly launched EC2 instances. This ensures that instances launched from
# hardened AMIs are automatically targeted by State Manager associations for
# STIG enforcement, compliance scanning, and inventory collection.
#
# Architecture:
#   EventBridge (instance running) → SSM Automation → EC2 CreateTags
#
# The EventBridge rule triggers on EC2 instance state changes to "running".
# The SSM Automation document checks the instance's source AMI for SPEL tags
# (StigManaged=true) and copies StigPlatform + StigManaged to the instance.
#
# Gated by: var.enable_auto_tagging (default: true)
# =============================================================================

# -----------------------------------------------------------------------------
# SSM Automation Document — AMI Tag Propagation
# -----------------------------------------------------------------------------

resource "aws_ssm_document" "ami_tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  name            = "${var.name_prefix}-AmiTagPropagation"
  document_type   = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Propagate StigPlatform and StigManaged tags from AMI to EC2 instance"
    assumeRole    = "{{AutomationAssumeRole}}"
    parameters = {
      InstanceId = {
        type        = "StringList"
        description = "EC2 Instance IDs to process"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role ARN for automation execution"
        default     = ""
      }
    }
    mainSteps = [
      {
        name   = "PropagateAmiTags"
        action = "aws:executeScript"
        inputs = {
          Runtime = "python3.11"
          Handler = "handler"
          InputPayload = {
            instance_ids = "{{InstanceId}}"
          }
          Script = join("\n", [
            "import boto3",
            "import time",
            "",
            "def handler(events, context):",
            "    ec2 = boto3.client('ec2')",
            "    instance_ids = events.get('instance_ids', [])",
            "    if isinstance(instance_ids, str):",
            "        instance_ids = [instance_ids]",
            "",
            "    # Brief delay to let instance tags propagate",
            "    time.sleep(5)",
            "",
            "    results = []",
            "    for instance_id in instance_ids:",
            "        try:",
            "            resp = ec2.describe_instances(InstanceIds=[instance_id])",
            "            if not resp['Reservations']:",
            "                results.append({'id': instance_id, 'status': 'not found'})",
            "                continue",
            "",
            "            instance = resp['Reservations'][0]['Instances'][0]",
            "            image_id = instance['ImageId']",
            "            instance_tags = {t['Key']: t['Value'] for t in instance.get('Tags', [])}",
            "",
            "            # Skip if instance already has StigPlatform tag",
            "            if 'StigPlatform' in instance_tags:",
            "                results.append({'id': instance_id, 'status': 'already tagged'})",
            "                continue",
            "",
            "            # Get AMI tags",
            "            try:",
            "                images = ec2.describe_images(ImageIds=[image_id])",
            "            except Exception:",
            "                results.append({'id': instance_id, 'status': 'AMI describe failed'})",
            "                continue",
            "",
            "            if not images['Images']:",
            "                results.append({'id': instance_id, 'status': 'AMI not found'})",
            "                continue",
            "",
            "            ami_tags = {t['Key']: t['Value'] for t in images['Images'][0].get('Tags', [])}",
            "",
            "            # Only tag instances launched from SPEL AMIs (StigManaged=true)",
            "            if ami_tags.get('StigManaged') != 'true':",
            "                results.append({'id': instance_id, 'status': 'not a SPEL AMI'})",
            "                continue",
            "",
            "            # Copy StigPlatform and StigManaged tags to the instance",
            "            tags_to_copy = []",
            "            for key in ['StigPlatform', 'StigManaged']:",
            "                if key in ami_tags and key not in instance_tags:",
            "                    tags_to_copy.append({'Key': key, 'Value': ami_tags[key]})",
            "",
            "            if tags_to_copy:",
            "                ec2.create_tags(Resources=[instance_id], Tags=tags_to_copy)",
            "                results.append({'id': instance_id, 'status': 'tagged', 'tags': str(tags_to_copy)})",
            "            else:",
            "                results.append({'id': instance_id, 'status': 'no tags to copy'})",
            "",
            "        except Exception as e:",
            "            results.append({'id': instance_id, 'status': f'error: {e}'})",
            "",
            "    return {'results': results}",
          ])
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-AmiTagPropagation"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for SSM Automation Execution
# -----------------------------------------------------------------------------

resource "aws_iam_role" "tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  name = "${var.name_prefix}-ssm-tag-propagation"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "SSMAutomationAssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-tag-propagation"
  })
}

resource "aws_iam_role_policy" "tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  name = "${var.name_prefix}-tag-propagation"
  role = aws_iam_role.tag_propagation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2DescribeAndTag"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# EventBridge Rule — Trigger on Instance Launch
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "instance_launch" {
  count = var.enable_auto_tagging ? 1 : 0

  name        = "${var.name_prefix}-ami-tag-propagation"
  description = "Propagate SPEL AMI tags to newly launched instances"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["running"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ami-tag-propagation"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for EventBridge → SSM Automation
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eventbridge_tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  name = "${var.name_prefix}-events-tag-propagation"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EventBridgeAssumeRole"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-events-tag-propagation"
  })
}

resource "aws_iam_role_policy" "eventbridge_tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  name = "${var.name_prefix}-events-invoke-automation"
  role = aws_iam_role.eventbridge_tag_propagation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartAutomation"
        Effect = "Allow"
        Action = "ssm:StartAutomationExecution"
        Resource = [
          "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:automation-definition/${var.name_prefix}-AmiTagPropagation:*",
          "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:automation-execution/*"
        ]
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.tag_propagation[0].arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# EventBridge Target — SSM Automation
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_target" "tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  rule      = aws_cloudwatch_event_rule.instance_launch[0].name
  target_id = "ami-tag-propagation"
  arn       = "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:automation-definition/${aws_ssm_document.ami_tag_propagation[0].name}:$$DEFAULT"
  role_arn  = aws_iam_role.eventbridge_tag_propagation[0].arn

  input_transformer {
    input_paths = {
      instance = "$.detail.instance-id"
    }
    input_template = "{\"InstanceId\":[\"<instance>\"],\"AutomationAssumeRole\":[\"${aws_iam_role.tag_propagation[0].arn}\"]}"
  }
}
