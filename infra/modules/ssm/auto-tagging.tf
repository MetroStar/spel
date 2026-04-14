# =============================================================================
# SSM Infrastructure Module — AMI Tag Auto-Propagation
# =============================================================================
# Automatically propagates StigPlatform and StigManaged tags from Crucible AMIs
# to newly launched EC2 instances. This ensures that instances launched from
# hardened AMIs are automatically targeted by State Manager associations for
# STIG enforcement, compliance scanning, and inventory collection.
#
# Architecture:
#   EventBridge (instance running) → Lambda → EC2 CreateTags
#
# The EventBridge rule triggers on EC2 instance state changes to "running".
# A Lambda function checks the instance's source AMI for Crucible tags
# (StigManaged=true) and copies StigPlatform + StigManaged to the instance.
#
# Gated by: var.enable_auto_tagging (default: true)
# =============================================================================

# -----------------------------------------------------------------------------
# Lambda Function — AMI Tag Propagation
# -----------------------------------------------------------------------------

data "archive_file" "tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda/tag_propagation.zip"

  source {
    content  = <<-PYTHON
import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')

def handler(event, context):
    """Propagate StigPlatform and StigManaged tags from AMI to EC2 instance."""
    logger.info("Event: %s", json.dumps(event))

    instance_id = event.get('detail', {}).get('instance-id')
    if not instance_id:
        logger.warning("No instance-id in event")
        return {'status': 'no instance-id'}

    try:
        resp = ec2.describe_instances(InstanceIds=[instance_id])
        if not resp['Reservations']:
            logger.info("Instance %s not found", instance_id)
            return {'status': 'not found'}

        instance = resp['Reservations'][0]['Instances'][0]
        image_id = instance['ImageId']
        instance_tags = {t['Key']: t['Value'] for t in instance.get('Tags', [])}

        # Skip if instance already has StigPlatform tag
        if 'StigPlatform' in instance_tags:
            logger.info("Instance %s already tagged", instance_id)
            return {'status': 'already tagged'}

        # Get AMI tags
        try:
            images = ec2.describe_images(ImageIds=[image_id])
        except Exception as e:
            logger.error("Failed to describe AMI %s: %s", image_id, e)
            return {'status': 'AMI describe failed'}

        if not images['Images']:
            logger.info("AMI %s not found", image_id)
            return {'status': 'AMI not found'}

        ami_tags = {t['Key']: t['Value'] for t in images['Images'][0].get('Tags', [])}

        # Only tag instances launched from Crucible AMIs (StigManaged=true)
        if ami_tags.get('StigManaged') != 'true':
            logger.info("Instance %s not from Crucible AMI (AMI %s)", instance_id, image_id)
            return {'status': 'not a Crucible AMI'}

        # Copy StigPlatform and StigManaged tags to the instance
        tags_to_copy = []
        for key in ['StigPlatform', 'StigManaged']:
            if key in ami_tags and key not in instance_tags:
                tags_to_copy.append({'Key': key, 'Value': ami_tags[key]})

        if tags_to_copy:
            ec2.create_tags(Resources=[instance_id], Tags=tags_to_copy)
            logger.info("Tagged instance %s with %s", instance_id, tags_to_copy)
            return {'status': 'tagged', 'tags': str(tags_to_copy)}
        else:
            logger.info("No tags to copy for instance %s", instance_id)
            return {'status': 'no tags to copy'}

    except Exception as e:
        logger.error("Error processing instance %s: %s", instance_id, e)
        raise
PYTHON
    filename = "index.py"
  }
}

resource "aws_lambda_function" "tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  function_name    = "${var.name_prefix}-ami-tag-propagation"
  description      = "Propagate StigPlatform and StigManaged tags from Crucible AMIs to instances"
  role             = aws_iam_role.tag_propagation[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.tag_propagation[0].output_path
  source_code_hash = data.archive_file.tag_propagation[0].output_base64sha256

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ami-tag-propagation"
  })
}

# -----------------------------------------------------------------------------
# IAM Role for Lambda Execution
# -----------------------------------------------------------------------------

resource "aws_iam_role" "tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  name = "${var.name_prefix}-lambda-tag-propagation"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LambdaAssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-lambda-tag-propagation"
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
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${var.name_prefix}-ami-tag-propagation:*"
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
  description = "Propagate Crucible AMI tags to newly launched instances"

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
# EventBridge Target — Lambda
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_target" "tag_propagation" {
  count = var.enable_auto_tagging ? 1 : 0

  rule      = aws_cloudwatch_event_rule.instance_launch[0].name
  target_id = "ami-tag-propagation"
  arn       = aws_lambda_function.tag_propagation[0].arn
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  count = var.enable_auto_tagging ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tag_propagation[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_launch[0].arn
}
