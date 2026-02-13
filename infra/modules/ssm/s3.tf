# =============================================================================
# SSM Infrastructure Module — S3 Bucket
# =============================================================================
# S3 bucket for SSM-related storage:
#   - RunCommand output logs
#   - OpenSCAP scan results (XML, HTML, JSON summaries)
#   - Ansible STIG playbook packages (uploaded by package-ansible-stig.sh)
#   - Patch Manager logs
#   - Session Manager session logs
#
# Bucket is encrypted, versioned, and restricted to the owning account.
# A separate access-logging bucket captures S3 server access logs.
# =============================================================================

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "ssm" {
  bucket        = "${var.name_prefix}-ssm-${random_id.bucket_suffix.hex}"
  force_destroy = true

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
      sse_algorithm     = local.kms_enabled ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_enabled ? local.effective_kms_key_arn : null
    }
    bucket_key_enabled = local.kms_enabled
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

# =============================================================================
# S3 Access Logging Bucket
# =============================================================================
# Separate bucket to receive S3 server access logs from the primary SSM bucket.
# Uses AES256 encryption and 90-day lifecycle expiration.
# =============================================================================

resource "aws_s3_bucket" "ssm_access_logs" {
  bucket        = "${var.name_prefix}-ssm-access-logs-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ssm-access-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "ssm_access_logs" {
  bucket = aws_s3_bucket.ssm_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "ssm_access_logs" {
  bucket = aws_s3_bucket.ssm_access_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_access_logs" {
  bucket = aws_s3_bucket.ssm_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "ssm_access_logs" {
  bucket = aws_s3_bucket.ssm_access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "ssm_access_logs" {
  bucket = aws_s3_bucket.ssm_access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.ssm_access_logs.arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.ssm.arn
          }
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid       = "EnforceTLSOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.ssm_access_logs.arn,
          "${aws_s3_bucket.ssm_access_logs.arn}/*"
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

# Enable access logging on the primary SSM bucket
resource "aws_s3_bucket_logging" "ssm" {
  bucket = aws_s3_bucket.ssm.id

  target_bucket = aws_s3_bucket.ssm_access_logs.id
  target_prefix = "access-logs/"
}
