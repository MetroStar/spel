# =============================================================================
# SSM Infrastructure Module — S3 Bucket
# =============================================================================
# S3 bucket for SSM-related storage:
#   - RunCommand output logs
#   - OpenSCAP scan results (XML, HTML, JSON summaries)
#   - Ansible STIG playbook packages (uploaded by package-ansible-stig.sh)
#   - Patch Manager logs
#
# Bucket is encrypted, versioned, and restricted to the owning account.
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "ssm" {
  bucket = "${var.name_prefix}-ssm-${random_id.bucket_suffix.hex}"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-bucket"
  })
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "ssm" {
  bucket = aws_s3_bucket.ssm.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for state safety
resource "aws_s3_bucket_versioning" "ssm" {
  bucket = aws_s3_bucket.ssm.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "ssm" {
  bucket = aws_s3_bucket.ssm.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != "" ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.kms_key_arn != "" ? true : false
  }
}

# Lifecycle rule to clean up old scan results
resource "aws_s3_bucket_lifecycle_configuration" "ssm" {
  bucket = aws_s3_bucket.ssm.id

  rule {
    id     = "expire-old-results"
    status = "Enabled"

    filter {
      prefix = "oscap-results/"
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "expire-ssm-output"
    status = "Enabled"

    filter {
      prefix = "ssm-output/"
    }

    expiration {
      days = var.log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Bucket policy: restrict access to owning account and SSM service
resource "aws_s3_bucket_policy" "ssm" {
  bucket = aws_s3_bucket.ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyExternalAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.ssm.arn,
          "${aws_s3_bucket.ssm.arn}/*"
        ]
        Condition = {
          StringNotEquals = {
            "aws:PrincipalAccount" = local.account_id
          }
        }
      },
      {
        Sid       = "EnforceTLSOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.ssm.arn,
          "${aws_s3_bucket.ssm.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
