# Manual SSM Setup for Air-Gapped Environments

Step-by-step guide to provisioning all SSM infrastructure **without
OpenTofu**. This replicates everything in the
[`infra/modules/ssm/`](../infra/modules/ssm/) module using AWS CLI
commands.

> **When to use this guide:**
> You are in an air-gapped (disconnected) AWS account where you cannot or
> choose not to run OpenTofu. You have AWS CLI v2 and `jq` available on
> a workstation with IAM permissions to create KMS keys, S3 buckets, IAM
> roles, VPC endpoints, SSM documents, and Lambda functions.
>
> If you *can* run OpenTofu, use `tofu apply` instead — see the
> [Infrastructure README](../infra/README.md).

---

## Table of Contents

1. [Prerequisites & Variables](#1-prerequisites--variables)
2. [KMS Key](#2-kms-key)
3. [S3 Buckets](#3-s3-buckets)
4. [CloudWatch Log Group & SNS Topic](#4-cloudwatch-log-group--sns-topic)
5. [VPC Endpoints](#5-vpc-endpoints)
6. [IAM — Instance Role & Profile](#6-iam--instance-role--profile)
7. [IAM — DHMC Role](#7-iam--dhmc-role)
8. [IAM — Caller Policy (CI / Operator)](#8-iam--caller-policy-ci--operator)
9. [Default Host Management Configuration (DHMC)](#9-default-host-management-configuration-dhmc)
10. [Session Manager Preferences](#10-session-manager-preferences)
11. [SSM Documents](#11-ssm-documents)
    - [OpenSCAP Scan](#11a-openscap-scan-document)
    - [Windows STIG Enforce](#11b-windows-stig-enforce-document)
12. [Upload STIG Playbooks to S3](#12-upload-stig-playbooks-to-s3)
13. [SSM Associations — Compliance Verification](#13-ssm-associations--compliance-verification)
14. [SSM Associations — STIG Enforcement](#14-ssm-associations--stig-enforcement)
15. [SSM Agent Auto-Update](#15-ssm-agent-auto-update)
16. [Patch Manager — Baselines & Maintenance Windows](#16-patch-manager--baselines--maintenance-windows)
17. [Auto-Tagging (EventBridge + Lambda)](#17-auto-tagging-eventbridge--lambda)
18. [CloudWatch Alarms](#18-cloudwatch-alarms)
19. [Verification](#19-verification)
20. [Teardown](#20-teardown)

---

## 1. Prerequisites & Variables

Set these shell variables before running any commands. Later sections
reference them by name.

```bash
# ── Required ──────────────────────────────────────────────────────────
export AWS_REGION="us-east-1"        # or us-gov-west-1 for GovCloud
export PREFIX="chimera"                 # resource name prefix
export VPC_ID="vpc-XXXXXXXXX"        # your existing VPC
export SUBNET_IDS="subnet-AAA subnet-BBB"  # private subnets (space-separated)
export VPC_CIDR="10.0.0.0/16"       # VPC CIDR block

# ── Derived (auto-detected) ──────────────────────────────────────────
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export PARTITION=$(aws sts get-caller-identity --query Arn --output text | cut -d: -f2)
# PARTITION will be "aws" or "aws-us-gov"

# ── Configurable defaults ────────────────────────────────────────────
export LOG_RETENTION_DAYS=90         # CloudWatch log retention
export SESSION_IDLE_TIMEOUT=20       # Session Manager idle timeout (min)
export PATCH_APPROVE_DAYS=7          # Days before auto-approving patches
export STIG_SCHEDULE="rate(7 days)"  # STIG enforcement + scan schedule
export MAINT_WINDOW_CRON="cron(0 4 ? * SUN *)"  # Patch window
export MAINT_WINDOW_DURATION=3       # Hours
export MAINT_WINDOW_CUTOFF=1         # Hours before window end to stop tasks
export WINDOWS_STIG_LEVEL="High"     # High | Medium | Low
export ADMIN_USERNAME="maintuser"    # Windows SID-500 account name
export ALERT_EMAIL=""                # SNS email (leave empty to skip)
export ANSIBLE_S3_KEY="ansible/stig-playbook.zip"
export AL2023_STIG_S3_KEY="ansible/al2023-stig-script.zip"
```

> **GovCloud:** Set `export AWS_USE_FIPS_ENDPOINT=true` before running
> any `aws` commands. All ARNs in this guide use `$PARTITION` so they
> resolve to `aws-us-gov` automatically.

---

## 2. KMS Key

Creates a customer-managed key for encrypting S3, CloudWatch Logs,
Session Manager, and SNS data.

> Corresponds to: [`modules/ssm/kms.tf`](../infra/modules/ssm/kms.tf)

```bash
# Create key policy document
cat > /tmp/kms-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Id": "${PREFIX}-ssm-key-policy",
  "Statement": [
    {
      "Sid": "EnableRootPermissions",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:${PARTITION}:iam::${ACCOUNT_ID}:root"},
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowEC2ForEBS",
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:CallerAccount": "${ACCOUNT_ID}",
          "kms:ViaService": "ec2.${AWS_REGION}.amazonaws.com"
        }
      }
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Principal": {"Service": "logs.${AWS_REGION}.amazonaws.com"},
      "Action": [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "ArnLike": {
          "kms:EncryptionContext:aws:logs:arn":
            "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/ssm/${PREFIX}*"
        }
      }
    },
    {
      "Sid": "AllowSNSEncryption",
      "Effect": "Allow",
      "Principal": {"Service": "sns.amazonaws.com"},
      "Action": ["kms:Decrypt", "kms:GenerateDataKey*"],
      "Resource": "*"
    },
    {
      "Sid": "AllowSSMService",
      "Effect": "Allow",
      "Principal": {"Service": "ssm.amazonaws.com"},
      "Action": ["kms:Decrypt", "kms:GenerateDataKey"],
      "Resource": "*"
    }
  ]
}
POLICY

# Create the key
KMS_KEY_ID=$(aws kms create-key \
  --description "${PREFIX} SSM encryption key" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS \
  --policy file:///tmp/kms-policy.json \
  --tags TagKey=Name,TagValue="${PREFIX}-ssm-key" \
         TagKey=ManagedBy,TagValue=manual \
         TagKey=Module,TagValue=chimera-ssm \
  --query KeyMetadata.KeyId --output text)

KMS_KEY_ARN=$(aws kms describe-key --key-id "$KMS_KEY_ID" \
  --query KeyMetadata.Arn --output text)

echo "KMS Key ID:  $KMS_KEY_ID"
echo "KMS Key ARN: $KMS_KEY_ARN"

# Enable automatic key rotation (STIG SC-12)
aws kms enable-key-rotation --key-id "$KMS_KEY_ID"

# Create alias
aws kms create-alias \
  --alias-name "alias/${PREFIX}-ssm" \
  --target-key-id "$KMS_KEY_ID"
```

---

## 3. S3 Buckets

Two buckets: a primary bucket for SSM outputs / playbook storage, and
an access-logging bucket for S3 server access logs.

> Corresponds to: [`modules/ssm/s3.tf`](../infra/modules/ssm/s3.tf)

```bash
# Generate a random suffix (8 hex chars)
BUCKET_SUFFIX=$(openssl rand -hex 4)
S3_BUCKET="${PREFIX}-ssm-${BUCKET_SUFFIX}"
S3_LOGS_BUCKET="${PREFIX}-ssm-access-logs-${BUCKET_SUFFIX}"

echo "Primary bucket:     $S3_BUCKET"
echo "Access logs bucket: $S3_LOGS_BUCKET"
```

### 3a. Primary SSM Bucket

```bash
aws s3api create-bucket \
  --bucket "$S3_BUCKET" \
  --region "$AWS_REGION"

# Block all public access
aws s3api put-public-access-block \
  --bucket "$S3_BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "$S3_BUCKET" \
  --versioning-configuration Status=Enabled

# Default KMS encryption
aws s3api put-bucket-encryption \
  --bucket "$S3_BUCKET" \
  --server-side-encryption-configuration "{
    \"Rules\": [{
      \"ApplyServerSideEncryptionByDefault\": {
        \"SSEAlgorithm\": \"aws:kms\",
        \"KMSMasterKeyID\": \"${KMS_KEY_ID}\"
      },
      \"BucketKeyEnabled\": true
    }]
  }"

# Lifecycle rules — expire old scan results and SSM output
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$S3_BUCKET" \
  --lifecycle-configuration "{
    \"Rules\": [
      {
        \"ID\": \"expire-old-results\",
        \"Status\": \"Enabled\",
        \"Filter\": {\"Prefix\": \"oscap-results/\"},
        \"Expiration\": {\"Days\": ${LOG_RETENTION_DAYS}},
        \"NoncurrentVersionExpiration\": {\"NoncurrentDays\": 30}
      },
      {
        \"ID\": \"expire-ssm-output\",
        \"Status\": \"Enabled\",
        \"Filter\": {\"Prefix\": \"ssm-output/\"},
        \"Expiration\": {\"Days\": ${LOG_RETENTION_DAYS}},
        \"NoncurrentVersionExpiration\": {\"NoncurrentDays\": 30}
      }
    ]
  }"

# Bucket policy — deny external accounts, enforce TLS
cat > /tmp/s3-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyExternalAccess",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:${PARTITION}:s3:::${S3_BUCKET}",
        "arn:${PARTITION}:s3:::${S3_BUCKET}/*"
      ],
      "Condition": {
        "StringNotEquals": {"aws:PrincipalAccount": "${ACCOUNT_ID}"}
      }
    },
    {
      "Sid": "EnforceTLSOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:${PARTITION}:s3:::${S3_BUCKET}",
        "arn:${PARTITION}:s3:::${S3_BUCKET}/*"
      ],
      "Condition": {
        "Bool": {"aws:SecureTransport": "false"}
      }
    }
  ]
}
POLICY

aws s3api put-bucket-policy \
  --bucket "$S3_BUCKET" \
  --policy file:///tmp/s3-policy.json
```

### 3b. Access Logging Bucket

```bash
aws s3api create-bucket \
  --bucket "$S3_LOGS_BUCKET" \
  --region "$AWS_REGION"

aws s3api put-public-access-block \
  --bucket "$S3_LOGS_BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-versioning \
  --bucket "$S3_LOGS_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$S3_LOGS_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-bucket-lifecycle-configuration \
  --bucket "$S3_LOGS_BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-access-logs",
      "Status": "Enabled",
      "Filter": {"Prefix": ""},
      "Expiration": {"Days": 90},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 30}
    }]
  }'

# Access logging bucket policy
cat > /tmp/s3-logs-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ServerAccessLogsPolicy",
      "Effect": "Allow",
      "Principal": {"Service": "logging.s3.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:${PARTITION}:s3:::${S3_LOGS_BUCKET}/*",
      "Condition": {
        "ArnLike": {"aws:SourceArn": "arn:${PARTITION}:s3:::${S3_BUCKET}"},
        "StringEquals": {"aws:SourceAccount": "${ACCOUNT_ID}"}
      }
    },
    {
      "Sid": "EnforceTLSOnly",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:${PARTITION}:s3:::${S3_LOGS_BUCKET}",
        "arn:${PARTITION}:s3:::${S3_LOGS_BUCKET}/*"
      ],
      "Condition": {
        "Bool": {"aws:SecureTransport": "false"}
      }
    }
  ]
}
POLICY

aws s3api put-bucket-policy \
  --bucket "$S3_LOGS_BUCKET" \
  --policy file:///tmp/s3-logs-policy.json

# Enable access logging on the primary bucket
aws s3api put-bucket-logging \
  --bucket "$S3_BUCKET" \
  --bucket-logging-status "{
    \"LoggingEnabled\": {
      \"TargetBucket\": \"${S3_LOGS_BUCKET}\",
      \"TargetPrefix\": \"access-logs/\"
    }
  }"
```

---

## 4. CloudWatch Log Group & SNS Topic

> Corresponds to: [`modules/ssm/cloudwatch.tf`](../infra/modules/ssm/cloudwatch.tf)

```bash
# Log group (KMS-encrypted)
aws logs create-log-group \
  --log-group-name "/ssm/${PREFIX}" \
  --kms-key-id "$KMS_KEY_ARN" \
  --tags Name="${PREFIX}-ssm-logs",ManagedBy=manual,Module=chimera-ssm

aws logs put-retention-policy \
  --log-group-name "/ssm/${PREFIX}" \
  --retention-in-days "$LOG_RETENTION_DAYS"

export LOG_GROUP="/ssm/${PREFIX}"

# SNS topic (KMS-encrypted)
SNS_TOPIC_ARN=$(aws sns create-topic \
  --name "${PREFIX}-ssm-alerts" \
  --attributes "KmsMasterKeyId=${KMS_KEY_ARN}" \
  --tags Key=Name,Value="${PREFIX}-ssm-alerts" \
         Key=ManagedBy,Value=manual \
         Key=Module,Value=chimera-ssm \
  --query TopicArn --output text)

echo "SNS Topic: $SNS_TOPIC_ARN"

# Optional email subscription
if [[ -n "$ALERT_EMAIL" ]]; then
  aws sns subscribe \
    --topic-arn "$SNS_TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "$ALERT_EMAIL"
  echo "Confirm the subscription via the email sent to $ALERT_EMAIL"
fi
```

---

## 5. VPC Endpoints

Creates Interface endpoints (PrivateLink) for SSM services and a
Gateway endpoint for S3. **Required** in air-gapped environments where
instances have no internet access.

> Corresponds to:
> [`modules/ssm/vpc-endpoints.tf`](../infra/modules/ssm/vpc-endpoints.tf)

> **Note — Packer endpoints**: If you are running Packer builds without
> an Internet Gateway, you also need Interface endpoints for **EC2** and
> **STS**. The OpenTofu networking module creates these when
> `enable_packer_endpoints = true`. To create them manually, add `ec2`
> and `sts` to the Interface Endpoints loop below (or create them in a
> separate security group as the OpenTofu module does).

```bash
# Security group for VPC endpoints
ENDPOINT_SG=$(aws ec2 create-security-group \
  --group-name "${PREFIX}-ssm-endpoints-sg" \
  --description "Allow HTTPS from VPC CIDR to SSM VPC endpoints" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[
    {Key=Name,Value=${PREFIX}-ssm-endpoints-sg},
    {Key=ManagedBy,Value=manual},
    {Key=Module,Value=chimera-ssm}]" \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$ENDPOINT_SG" \
  --protocol tcp --port 443 \
  --cidr "$VPC_CIDR" \
  --tag-specifications "ResourceType=security-group-rule,Tags=[
    {Key=Description,Value=HTTPS from VPC CIDR for SSM agent communication}]"

aws ec2 authorize-security-group-egress \
  --group-id "$ENDPOINT_SG" \
  --protocol -1 --port -1 \
  --cidr "0.0.0.0/0" 2>/dev/null || true  # default egress rule may already exist
```

### Interface Endpoints

```bash
for SERVICE in ssm ssmmessages ec2messages logs kms; do
  echo "Creating ${SERVICE} endpoint..."
  aws ec2 create-vpc-endpoint \
    --vpc-id "$VPC_ID" \
    --vpc-endpoint-type Interface \
    --service-name "com.amazonaws.${AWS_REGION}.${SERVICE}" \
    --subnet-ids $SUBNET_IDS \
    --security-group-ids "$ENDPOINT_SG" \
    --private-dns-enabled \
    --tag-specifications "ResourceType=vpc-endpoint,Tags=[
      {Key=Name,Value=${PREFIX}-${SERVICE}-endpoint},
      {Key=ManagedBy,Value=manual},
      {Key=Module,Value=chimera-ssm}]"
done
```

### S3 Gateway Endpoint

```bash
# Collect route table IDs for the VPC
ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'RouteTables[*].RouteTableId' --output text)

aws ec2 create-vpc-endpoint \
  --vpc-id "$VPC_ID" \
  --vpc-endpoint-type Gateway \
  --service-name "com.amazonaws.${AWS_REGION}.s3" \
  --route-table-ids $ROUTE_TABLE_IDS \
  --tag-specifications "ResourceType=vpc-endpoint,Tags=[
    {Key=Name,Value=${PREFIX}-s3-endpoint},
    {Key=ManagedBy,Value=manual},
    {Key=Module,Value=chimera-ssm}]"
```

---

## 6. IAM — Instance Role & Profile

Attached to EC2 instances. Grants the SSM agent permissions to
communicate with SSM, read S3 playbooks, write CloudWatch logs, and
decrypt KMS-encrypted data.

> Corresponds to: [`modules/ssm/iam.tf`](../infra/modules/ssm/iam.tf)
> (instance role section)

```bash
# Trust policy for EC2
cat > /tmp/ec2-trust.json << 'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "EC2AssumeRole",
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
TRUST

aws iam create-role \
  --role-name "${PREFIX}-ssm-instance-role" \
  --assume-role-policy-document file:///tmp/ec2-trust.json \
  --tags Key=Name,Value="${PREFIX}-ssm-instance-role" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm

# Inline policy — SSM core, messaging, S3, CloudWatch, KMS
cat > /tmp/ssm-instance-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SSMCoreAgent",
      "Effect": "Allow",
      "Action": [
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
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMMessaging",
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2Messaging",
      "Effect": "Allow",
      "Action": [
        "ec2messages:AcknowledgeMessage",
        "ec2messages:DeleteMessage",
        "ec2messages:FailMessage",
        "ec2messages:GetEndpoint",
        "ec2messages:GetMessages",
        "ec2messages:SendReply"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3SSMBuckets",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:${PARTITION}:s3:::aws-ssm-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::aws-ssm-${AWS_REGION}",
        "arn:${PARTITION}:s3:::amazon-ssm-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::amazon-ssm-${AWS_REGION}",
        "arn:${PARTITION}:s3:::amazon-ssm-packages-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::amazon-ssm-packages-${AWS_REGION}",
        "arn:${PARTITION}:s3:::${AWS_REGION}-birdwatcher-prod/*",
        "arn:${PARTITION}:s3:::${AWS_REGION}-birdwatcher-prod",
        "arn:${PARTITION}:s3:::patch-baseline-snapshot-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::patch-baseline-snapshot-${AWS_REGION}"
      ]
    },
    {
      "Sid": "S3STIGDownloads",
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": [
        "arn:${PARTITION}:s3:::aws-windows-downloads-${AWS_REGION}/STIG/*",
        "arn:${PARTITION}:s3:::aws-windows-downloads/STIG/*"
      ]
    },
    {
      "Sid": "S3OutputBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject",
        "s3:ListBucket", "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:${PARTITION}:s3:::${S3_BUCKET}",
        "arn:${PARTITION}:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream", "logs:PutLogEvents",
        "logs:DescribeLogGroups", "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}",
        "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"
      ]
    },
    {
      "Sid": "SSMParameters",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter"],
      "Resource": "arn:${PARTITION}:ssm:${AWS_REGION}:${ACCOUNT_ID}:parameter/${PREFIX}/*"
    },
    {
      "Sid": "KMSDecrypt",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
      "Resource": "${KMS_KEY_ARN}"
    }
  ]
}
POLICY

aws iam put-role-policy \
  --role-name "${PREFIX}-ssm-instance-role" \
  --policy-name "${PREFIX}-ssm-instance-core" \
  --policy-document file:///tmp/ssm-instance-policy.json

# Instance profile
aws iam create-instance-profile \
  --instance-profile-name "${PREFIX}-ssm-instance-profile" \
  --tags Key=Name,Value="${PREFIX}-ssm-instance-profile" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm

aws iam add-role-to-instance-profile \
  --instance-profile-name "${PREFIX}-ssm-instance-profile" \
  --role-name "${PREFIX}-ssm-instance-role"
```

---

## 7. IAM — DHMC Role

Separate from the instance profile role. Trusted by `ssm.amazonaws.com`
(not `ec2.amazonaws.com`). Used by Default Host Management
Configuration to auto-register instances without an instance profile.

> Corresponds to: [`modules/ssm/dhmc.tf`](../infra/modules/ssm/dhmc.tf)
> (IAM section)

```bash
cat > /tmp/ssm-trust.json << 'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "SSMAssumeRole",
    "Effect": "Allow",
    "Principal": {"Service": "ssm.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
TRUST

aws iam create-role \
  --role-name "${PREFIX}-ssm-dhmc-role" \
  --assume-role-policy-document file:///tmp/ssm-trust.json \
  --tags Key=Name,Value="${PREFIX}-ssm-dhmc-role" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm

# Attach AWS-managed SSM policy
aws iam attach-role-policy \
  --role-name "${PREFIX}-ssm-dhmc-role" \
  --policy-arn "arn:${PARTITION}:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"

# Inline policy — S3, CloudWatch, KMS access
cat > /tmp/dhmc-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3SSMBuckets",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": [
        "arn:${PARTITION}:s3:::aws-ssm-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::aws-ssm-${AWS_REGION}",
        "arn:${PARTITION}:s3:::amazon-ssm-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::amazon-ssm-${AWS_REGION}",
        "arn:${PARTITION}:s3:::amazon-ssm-packages-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::amazon-ssm-packages-${AWS_REGION}",
        "arn:${PARTITION}:s3:::${AWS_REGION}-birdwatcher-prod/*",
        "arn:${PARTITION}:s3:::${AWS_REGION}-birdwatcher-prod",
        "arn:${PARTITION}:s3:::patch-baseline-snapshot-${AWS_REGION}/*",
        "arn:${PARTITION}:s3:::patch-baseline-snapshot-${AWS_REGION}"
      ]
    },
    {
      "Sid": "S3OutputBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject", "s3:PutObject", "s3:ListBucket",
        "s3:GetBucketLocation", "s3:GetEncryptionConfiguration",
        "s3:GetBucketAcl"
      ],
      "Resource": [
        "arn:${PARTITION}:s3:::${S3_BUCKET}",
        "arn:${PARTITION}:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Sid": "CloudWatchLogsWrite",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}",
        "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"
      ]
    },
    {
      "Sid": "CloudWatchLogsDescribe",
      "Effect": "Allow",
      "Action": ["logs:DescribeLogGroups"],
      "Resource": "*"
    },
    {
      "Sid": "KMSAccess",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt", "kms:Encrypt",
        "kms:GenerateDataKey", "kms:DescribeKey"
      ],
      "Resource": "${KMS_KEY_ARN}"
    }
  ]
}
POLICY

aws iam put-role-policy \
  --role-name "${PREFIX}-ssm-dhmc-role" \
  --policy-name "${PREFIX}-ssm-dhmc-chimera" \
  --policy-document file:///tmp/dhmc-policy.json
```

---

## 8. IAM — Caller Policy (CI / Operator)

Grants CI runners and human operators permissions to invoke SSM
operations (SendCommand, StartSession, manage associations, etc.).

> Corresponds to: [`modules/ssm/iam.tf`](../infra/modules/ssm/iam.tf)
> (caller policy section)

```bash
cat > /tmp/caller-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SSMRunCommand",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand", "ssm:GetCommandInvocation",
        "ssm:ListCommands", "ssm:ListCommandInvocations",
        "ssm:CancelCommand"
      ],
      "Resource": [
        "arn:${PARTITION}:ssm:${AWS_REGION}:${ACCOUNT_ID}:document/*",
        "arn:${PARTITION}:ssm:${AWS_REGION}::document/AWS-*",
        "arn:${PARTITION}:ec2:${AWS_REGION}:${ACCOUNT_ID}:instance/*"
      ]
    },
    {
      "Sid": "SSMSessionManager",
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession", "ssm:TerminateSession",
        "ssm:ResumeSession", "ssm:DescribeSessions"
      ],
      "Resource": [
        "arn:${PARTITION}:ssm:${AWS_REGION}:${ACCOUNT_ID}:session/*",
        "arn:${PARTITION}:ec2:${AWS_REGION}:${ACCOUNT_ID}:instance/*",
        "arn:${PARTITION}:ssm:${AWS_REGION}:${ACCOUNT_ID}:document/${PREFIX}-*",
        "arn:${PARTITION}:ssm:${AWS_REGION}::document/AWS-StartPortForwardingSession"
      ]
    },
    {
      "Sid": "SSMStateManager",
      "Effect": "Allow",
      "Action": [
        "ssm:CreateAssociation", "ssm:UpdateAssociation",
        "ssm:DeleteAssociation", "ssm:DescribeAssociation",
        "ssm:ListAssociations"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMInventoryAndCompliance",
      "Effect": "Allow",
      "Action": [
        "ssm:GetInventory", "ssm:GetInventorySchema",
        "ssm:ListInventoryEntries", "ssm:ListComplianceItems",
        "ssm:ListComplianceSummaries", "ssm:ListResourceComplianceSummaries"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMDescribe",
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeInstanceInformation", "ssm:DescribeInstanceProperties",
        "ssm:GetConnectionStatus", "ssm:DescribeDocument",
        "ssm:ListDocuments", "ssm:GetDocument"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSMPatchManager",
      "Effect": "Allow",
      "Action": [
        "ssm:DescribePatchBaselines", "ssm:GetPatchBaseline",
        "ssm:DescribePatchGroups", "ssm:DescribeInstancePatches",
        "ssm:DescribeInstancePatchStates"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3OutputAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:${PARTITION}:s3:::${S3_BUCKET}",
        "arn:${PARTITION}:s3:::${S3_BUCKET}/*"
      ]
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:GetLogEvents", "logs:FilterLogEvents",
        "logs:DescribeLogGroups", "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}",
        "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP}:*"
      ]
    }
  ]
}
POLICY

CALLER_POLICY_ARN=$(aws iam create-policy \
  --policy-name "${PREFIX}-ssm-caller-policy" \
  --description "Permissions for CI runners and operators to invoke SSM operations on Chimera instances" \
  --policy-document file:///tmp/caller-policy.json \
  --tags Key=Name,Value="${PREFIX}-ssm-caller-policy" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm \
  --query Policy.Arn --output text)

echo "Caller Policy ARN: $CALLER_POLICY_ARN"
echo "Attach this policy to your CI runner role or IAM user."
```

---

## 9. Default Host Management Configuration (DHMC)

Activates DHMC so **all** EC2 instances in the account/region
auto-register with SSM without needing an instance profile.

> Corresponds to: [`modules/ssm/dhmc.tf`](../infra/modules/ssm/dhmc.tf)
> (service setting)

```bash
aws ssm update-service-setting \
  --setting-id "arn:${PARTITION}:ssm:${AWS_REGION}:${ACCOUNT_ID}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role" \
  --setting-value "${PREFIX}-ssm-dhmc-role"

echo "DHMC enabled with role: ${PREFIX}-ssm-dhmc-role"
```

---

## 10. Session Manager Preferences

Configures Session Manager with KMS encryption, S3/CloudWatch logging,
and STIG-aligned idle timeout.

> Corresponds to:
> [`modules/ssm/ssm-documents.tf`](../infra/modules/ssm/ssm-documents.tf)
> (Session Manager section)

```bash
cat > /tmp/session-prefs.json << PREFS
{
  "schemaVersion": "1.0",
  "description": "Session Manager preferences for ${PREFIX}",
  "sessionType": "Standard_Stream",
  "inputs": {
    "kmsKeyId": "${KMS_KEY_ARN}",
    "s3BucketName": "${S3_BUCKET}",
    "s3KeyPrefix": "session-logs",
    "s3EncryptionEnabled": true,
    "cloudWatchLogGroupName": "${LOG_GROUP}",
    "cloudWatchEncryptionEnabled": true,
    "cloudWatchStreamingEnabled": true,
    "idleSessionTimeout": "${SESSION_IDLE_TIMEOUT}",
    "maxSessionDuration": "",
    "runAsEnabled": false,
    "shellProfile": {
      "linux": "echo '*** STIG-hardened instance — Session Manager ***'; echo ''",
      "windows": ""
    }
  }
}
PREFS

# Try to update existing document first, fall back to create
aws ssm update-document \
  --name "SSM-SessionManagerRunShell" \
  --document-version "\$LATEST" \
  --content file:///tmp/session-prefs.json 2>/dev/null \
|| aws ssm create-document \
  --name "SSM-SessionManagerRunShell" \
  --document-type "Session" \
  --document-format JSON \
  --content file:///tmp/session-prefs.json
```

---

## 11. SSM Documents

### 11a. OpenSCAP Scan Document

Runs OpenSCAP `xccdf eval` with the DISA STIG profile and uploads
results (XML, HTML, JSON summary) to S3. Auto-detects OS (RHEL 8/9,
OL 8/9) and selects the correct data stream.

> Corresponds to:
> [`modules/ssm/ssm-documents.tf`](../infra/modules/ssm/ssm-documents.tf)
> (OpenSCAP section)

Save this as `/tmp/doc-oscap.yaml`:

```bash
cat > /tmp/doc-oscap.yaml << 'DOC'
schemaVersion: "2.2"
description: "Run OpenSCAP STIG compliance scan and upload results to S3"
parameters:
  Profile:
    type: String
    description: "OpenSCAP XCCDF profile to evaluate"
    default: "xccdf_org.ssgproject.content_profile_stig"
  S3Bucket:
    type: String
    description: "S3 bucket for results upload"
  S3KeyPrefix:
    type: String
    description: "S3 key prefix for results"
    default: "oscap-results"
mainSteps:
  - action: aws:runShellScript
    name: RunOpenSCAPScan
    precondition:
      StringEquals:
        - platformType
        - Linux
    inputs:
      timeoutSeconds: "600"
      runCommand:
        - "#!/bin/bash"
        - "set -euo pipefail"
        - ""
        - "PROFILE='{{ Profile }}'"
        - "S3_BUCKET='{{ S3Bucket }}'"
        - "S3_PREFIX='{{ S3KeyPrefix }}'"
        - "INSTANCE_ID=$(ec2-metadata -i 2>/dev/null | awk '{print $2}' || { TOKEN=$(curl -sf -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600') && curl -sf -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/instance-id; })"
        - "TIMESTAMP=$(date +%Y%m%d-%H%M%S)"
        - "RESULTS_DIR=$(mktemp -d)"
        - ""
        - "echo '=== OpenSCAP STIG Compliance Scan ==='"
        - "echo \"Instance: $INSTANCE_ID\""
        - "echo \"Profile:  $PROFILE\""
        - ""
        - "if ! command -v oscap &>/dev/null; then"
        - "  echo 'ERROR: openscap-scanner not installed. In air-gapped environments it must be pre-installed on the AMI.'"
        - "  exit 1"
        - "fi"
        - ""
        - "SCAP_DS=''"
        - "if [ -f /etc/os-release ]; then"
        - "  . /etc/os-release"
        - "  case \"$ID\" in"
        - "    rhel|centos) case \"$VERSION_ID\" in 9*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml ;; 8*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-rhel8-ds.xml ;; esac ;;"
        - "    ol) case \"$VERSION_ID\" in 9*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-ol9-ds.xml ;; 8*) SCAP_DS=/usr/share/xml/scap/ssg/content/ssg-ol8-ds.xml ;; esac ;;"
        - "    amzn) echo 'No DISA STIG benchmark for Amazon Linux. Skipping.'; exit 0 ;;"
        - "    *) echo \"Unsupported OS: $ID\"; exit 1 ;;"
        - "  esac"
        - "fi"
        - ""
        - "[ ! -f \"$SCAP_DS\" ] && echo \"SCAP data stream not found: $SCAP_DS\" && exit 1"
        - ""
        - "oscap xccdf eval --profile \"$PROFILE\" --results \"$RESULTS_DIR/oscap-results.xml\" --report \"$RESULTS_DIR/oscap-report.html\" \"$SCAP_DS\" || true"
        - ""
        - "PASS=$(grep -c 'result=\"pass\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null || echo 0)"
        - "FAIL=$(grep -c 'result=\"fail\"' $RESULTS_DIR/oscap-results.xml 2>/dev/null || echo 0)"
        - "SCORE=0; [ $((PASS + FAIL)) -gt 0 ] && SCORE=$((PASS * 100 / (PASS + FAIL)))"
        - "echo \"Score: ${SCORE}% (${PASS} pass, ${FAIL} fail)\""
        - ""
        - "aws s3 cp $RESULTS_DIR/oscap-results.xml s3://$S3_BUCKET/$S3_PREFIX/$INSTANCE_ID/$TIMESTAMP/"
        - "aws s3 cp $RESULTS_DIR/oscap-report.html s3://$S3_BUCKET/$S3_PREFIX/$INSTANCE_ID/$TIMESTAMP/"
        - "rm -rf $RESULTS_DIR"
DOC
```

```bash
aws ssm create-document \
  --name "${PREFIX}-RunOpenSCAPScan" \
  --document-type "Command" \
  --document-format YAML \
  --content file:///tmp/doc-oscap.yaml \
  --tags Key=Name,Value="${PREFIX}-RunOpenSCAPScan" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm
```

### 11b. Windows STIG Enforce Document

Two-step document: Step 1 calls AWS-managed `AWSEC2-ConfigureSTIG`.
Step 2 restores the built-in Administrator rename (SID-500 → maintuser)
that `ConfigureSTIG` resets in Local Security Policy.

> Corresponds to:
> [`modules/ssm/ssm-documents.tf`](../infra/modules/ssm/ssm-documents.tf)
> (Windows STIG section)

```bash
cat > /tmp/doc-windows-stig.yaml << 'DOC'
schemaVersion: "2.2"
description: "Apply AWSEC2-ConfigureSTIG then restore built-in admin rename (SID-500)"
parameters:
  Level:
    type: String
    description: "STIG severity level"
    default: "High"
    allowedValues:
      - "High"
      - "Medium"
      - "Low"
  AdminUsername:
    type: String
    description: "Name for the built-in Administrator account (SID-500)"
    default: "maintuser"
mainSteps:
  - action: aws:runDocument
    name: ApplyAWSConfigureSTIG
    precondition:
      StringEquals:
        - platformType
        - Windows
    inputs:
      documentType: SSMDocument
      documentPath: AWSEC2-ConfigureSTIG
      documentParameters: '{"Level":"{{ Level }}"}'
  - action: aws:runPowerShellScript
    name: RestoreAdminRename
    precondition:
      StringEquals:
        - platformType
        - Windows
    inputs:
      timeoutSeconds: "120"
      runCommand:
        - "$adminName = '{{ AdminUsername }}'"
        - ""
        - "# Find built-in Administrator (SID-500)"
        - "$builtinAdmin = Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }"
        - "if (-not $builtinAdmin) {"
        - "    Write-Warning 'Could not find built-in administrator account (SID ending in -500)'"
        - "    exit 0"
        - "}"
        - ""
        - "$currentName = $builtinAdmin.Name"
        - "Write-Output \"Current built-in admin name: $currentName\""
        - ""
        - "# Set via Local Security Policy (secedit) to persist across gpupdate"
        - "$tempDir = Join-Path $env:TEMP 'stig-admin-fixup'"
        - "$null = New-Item -ItemType Directory -Path $tempDir -Force"
        - "$cfgFile = Join-Path $tempDir 'secpol.cfg'"
        - "$dbFile = Join-Path $tempDir 'secpol.sdb'"
        - ""
        - "secedit /export /cfg $cfgFile /quiet"
        - ""
        - "$content = Get-Content $cfgFile -Raw"
        - "$pattern = 'NewAdministratorName\\s*=\\s*\"[^\"]*\"'"
        - "$replacement = 'NewAdministratorName = \"' + $adminName + '\"'"
        - "$content = [regex]::Replace($content, $pattern, $replacement)"
        - "$content | Set-Content $cfgFile"
        - ""
        - "secedit /configure /db $dbFile /cfg $cfgFile /areas SECURITYPOLICY /quiet"
        - ""
        - "# Immediate rename"
        - "if ($currentName -ne $adminName) {"
        - "    Rename-LocalUser -SID $builtinAdmin.SID -NewName $adminName"
        - "    Write-Output \"Renamed '$currentName' to '$adminName'\""
        - "} else {"
        - "    Write-Output \"Already named '$adminName' - no action needed\""
        - "}"
        - ""
        - "Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue"
        - "Write-Output \"Admin account secured as '$adminName'\""
DOC

aws ssm create-document \
  --name "${PREFIX}-WindowsSTIGEnforce" \
  --document-type "Command" \
  --document-format YAML \
  --content file:///tmp/doc-windows-stig.yaml \
  --tags Key=Name,Value="${PREFIX}-WindowsSTIGEnforce" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm
```

---

## 12. Upload STIG Playbooks to S3

The EL STIG associations expect playbook packages at specific S3 keys.
Build these using `tests/package-ansible-stig.sh` or assemble manually.

```bash
# EL STIG playbook (Ansible Lockdown roles + site.yml + boot-fips-wrapper.sh)
# Build: ./tests/package-ansible-stig.sh --output ./dist
aws s3 cp dist/stig-playbook.zip \
  "s3://${S3_BUCKET}/${ANSIBLE_S3_KEY}"

# AL2023 STIG script package
aws s3 cp dist/al2023-stig-script.zip \
  "s3://${S3_BUCKET}/${AL2023_STIG_S3_KEY}"
```

The playbook zip must contain:

```
stig-playbook.zip
├── site.yml                 # Wrapper (auto-detects EL8 vs EL9, includes FIPS pre/post)
├── boot-fips-wrapper.sh     # EL8 FIPS boot repair script
├── roles/
│   ├── RHEL8-STIG/          # Ansible Lockdown RHEL8 STIG role
│   └── RHEL9-STIG/          # Ansible Lockdown RHEL9 STIG role
├── collections/             # Pre-packaged Ansible collections (if present)
└── requirements.yml
```

---

## 13. SSM Associations — Compliance Verification

Read-only associations that **verify** compliance without modifying
instances.

> Corresponds to:
> [`modules/ssm/ssm-associations.tf`](../infra/modules/ssm/ssm-associations.tf)

### 13a. Ansible STIG Check-Mode (EL8/EL9)

```bash
# Get the S3 regional domain for SourceInfo
S3_DOMAIN="${S3_BUCKET}.s3.${AWS_REGION}.amazonaws.com"

aws ssm create-association \
  --name "AWS-ApplyAnsiblePlaybooks" \
  --association-name "${PREFIX}-stig-ansible-check" \
  --schedule-expression "${STIG_SCHEDULE}" \
  --max-concurrency "25%" \
  --max-errors "25%" \
  --targets "Key=tag:StigPlatform,Values=EL8,EL9" \
  --parameters "{
    \"SourceType\": [\"S3\"],
    \"SourceInfo\": [\"{\\\"path\\\":\\\"https://${S3_DOMAIN}/${ANSIBLE_S3_KEY}\\\"}\"],
    \"PlaybookFile\": [\"site.yml\"],
    \"ExtraVariables\": [\"SSM=true system_is_ec2=true ansible_python_interpreter=/usr/libexec/platform-python\"],
    \"Check\": [\"True\"],
    \"InstallDependencies\": [\"False\"],
    \"Verbose\": [\"-v\"],
    \"TimeoutSeconds\": [\"7200\"]
  }" \
  --output-location "{
    \"S3Location\": {
      \"OutputS3BucketName\": \"${S3_BUCKET}\",
      \"OutputS3KeyPrefix\": \"ssm-output/ansible-stig-check\"
    }
  }"
```

### 13b. OpenSCAP Scheduled Scan (EL8/EL9)

```bash
aws ssm create-association \
  --name "${PREFIX}-RunOpenSCAPScan" \
  --association-name "${PREFIX}-oscap-scheduled-scan" \
  --schedule-expression "${STIG_SCHEDULE}" \
  --targets "Key=tag:StigPlatform,Values=EL8,EL9" \
  --parameters "{
    \"Profile\": [\"xccdf_org.ssgproject.content_profile_stig\"],
    \"S3Bucket\": [\"${S3_BUCKET}\"],
    \"S3KeyPrefix\": [\"oscap-results\"]
  }" \
  --output-location "{
    \"S3Location\": {
      \"OutputS3BucketName\": \"${S3_BUCKET}\",
      \"OutputS3KeyPrefix\": \"ssm-output/oscap-scan\"
    }
  }"
```

### 13c. Software Inventory Collection (all instances)

```bash
aws ssm create-association \
  --name "AWS-GatherSoftwareInventory" \
  --association-name "${PREFIX}-software-inventory" \
  --schedule-expression "rate(12 hours)" \
  --targets "Key=InstanceIds,Values=*" \
  --parameters '{
    "applications": ["Enabled"],
    "awsComponents": ["Enabled"],
    "customInventory": ["Enabled"],
    "instanceDetailedInformation": ["Enabled"],
    "networkConfig": ["Enabled"],
    "services": ["Enabled"],
    "windowsRoles": ["Enabled"],
    "windowsUpdates": ["Enabled"]
  }'
```

---

## 14. SSM Associations — STIG Enforcement

These associations **apply** STIG hardening (not check-mode).

> Corresponds to:
> [`modules/ssm/ssm-stig-enforcement.tf`](../infra/modules/ssm/ssm-stig-enforcement.tf)

### 14a. EL (RHEL/OL/CentOS) STIG Enforcement via Ansible Lockdown

```bash
aws ssm create-association \
  --name "AWS-ApplyAnsiblePlaybooks" \
  --association-name "${PREFIX}-stig-enforce-el" \
  --schedule-expression "${STIG_SCHEDULE}" \
  --max-concurrency "25%" \
  --max-errors "25%" \
  --targets "Key=tag:StigPlatform,Values=EL8,EL9" \
  --parameters "{
    \"SourceType\": [\"S3\"],
    \"SourceInfo\": [\"{\\\"path\\\":\\\"https://${S3_DOMAIN}/${ANSIBLE_S3_KEY}\\\"}\"],
    \"PlaybookFile\": [\"site.yml\"],
    \"ExtraVariables\": [\"SSM=true system_is_ec2=true ansible_python_interpreter=/usr/libexec/platform-python\"],
    \"Check\": [\"False\"],
    \"InstallDependencies\": [\"False\"],
    \"Verbose\": [\"-v\"],
    \"TimeoutSeconds\": [\"7200\"]
  }" \
  --output-location "{
    \"S3Location\": {
      \"OutputS3BucketName\": \"${S3_BUCKET}\",
      \"OutputS3KeyPrefix\": \"ssm-output/stig-enforce-el\"
    }
  }"
```

### 14b. Amazon Linux 2023 STIG Enforcement

```bash
aws ssm create-association \
  --name "AWS-RunShellScript" \
  --association-name "${PREFIX}-stig-enforce-al2023" \
  --schedule-expression "${STIG_SCHEDULE}" \
  --max-concurrency "25%" \
  --max-errors "25%" \
  --targets "Key=tag:StigPlatform,Values=AL2023" \
  --parameters "{
    \"commands\": [\"set -eu\nWORK_DIR=\$(mktemp -d)\ntrap 'rm -rf \\\"\$WORK_DIR\\\"' EXIT\naws s3 cp s3://${S3_BUCKET}/${AL2023_STIG_S3_KEY} \\\"\$WORK_DIR/stig-package.zip\\\"\ncd \\\"\$WORK_DIR\\\"\nunzip -q stig-package.zip\nchmod +x apply-stig.sh\nbash apply-stig.sh\"],
    \"executionTimeout\": [\"3600\"],
    \"workingDirectory\": [\"/tmp\"]
  }" \
  --output-location "{
    \"S3Location\": {
      \"OutputS3BucketName\": \"${S3_BUCKET}\",
      \"OutputS3KeyPrefix\": \"ssm-output/stig-enforce-al2023\"
    }
  }"
```

### 14c. Windows STIG Enforcement (AWSEC2-ConfigureSTIG + Admin Rename)

```bash
aws ssm create-association \
  --name "${PREFIX}-WindowsSTIGEnforce" \
  --association-name "${PREFIX}-stig-enforce-windows" \
  --schedule-expression "${STIG_SCHEDULE}" \
  --max-concurrency "25%" \
  --max-errors "25%" \
  --targets "Key=tag:StigPlatform,Values=Win2019,Win2022" \
  --parameters "{
    \"Level\": [\"${WINDOWS_STIG_LEVEL}\"],
    \"AdminUsername\": [\"${ADMIN_USERNAME}\"]
  }" \
  --output-location "{
    \"S3Location\": {
      \"OutputS3BucketName\": \"${S3_BUCKET}\",
      \"OutputS3KeyPrefix\": \"ssm-output/stig-enforce-windows\"
    }
  }"
```

---

## 15. SSM Agent Auto-Update

```bash
aws ssm create-association \
  --name "AWS-UpdateSSMAgent" \
  --association-name "${PREFIX}-ssm-agent-update" \
  --schedule-expression "cron(0 3 ? * * *)" \
  --max-concurrency "50%" \
  --max-errors "25%" \
  --targets "Key=InstanceIds,Values=*"
```

---

## 16. Patch Manager — Baselines & Maintenance Windows

> Corresponds to:
> [`modules/ssm/ssm-patching.tf`](../infra/modules/ssm/ssm-patching.tf)

### 16a. Patch Baselines

```bash
# Linux baseline (RHEL-family)
LINUX_BASELINE_ID=$(aws ssm create-patch-baseline \
  --name "${PREFIX}-linux-stig-baseline" \
  --description "Patch baseline for STIG-hardened Linux instances (RHEL, OL, AL2023)" \
  --operating-system "REDHAT_ENTERPRISE_LINUX" \
  --approval-rules '{
    "PatchRules": [{
      "PatchFilterGroup": {
        "PatchFilters": [
          {"Key": "CLASSIFICATION", "Values": ["Security", "Bugfix"]},
          {"Key": "SEVERITY", "Values": ["Critical", "Important", "Moderate"]}
        ]
      },
      "ApproveAfterDays": '"${PATCH_APPROVE_DAYS}"',
      "ComplianceLevel": "CRITICAL"
    }]
  }' \
  --rejected-patches-action "ALLOW_AS_DEPENDENCY" \
  --tags Key=Name,Value="${PREFIX}-linux-stig-baseline" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm \
  --query BaselineId --output text)

echo "Linux Baseline: $LINUX_BASELINE_ID"

# Windows baseline
WINDOWS_BASELINE_ID=$(aws ssm create-patch-baseline \
  --name "${PREFIX}-windows-stig-baseline" \
  --description "Patch baseline for STIG-hardened Windows instances" \
  --operating-system "WINDOWS" \
  --approval-rules '{
    "PatchRules": [{
      "PatchFilterGroup": {
        "PatchFilters": [
          {"Key": "CLASSIFICATION", "Values": ["SecurityUpdates", "CriticalUpdates"]},
          {"Key": "MSRC_SEVERITY", "Values": ["Critical", "Important"]}
        ]
      },
      "ApproveAfterDays": '"${PATCH_APPROVE_DAYS}"',
      "ComplianceLevel": "CRITICAL"
    }]
  }' \
  --tags Key=Name,Value="${PREFIX}-windows-stig-baseline" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm \
  --query BaselineId --output text)

echo "Windows Baseline: $WINDOWS_BASELINE_ID"
```

### 16b. Patch Groups

```bash
aws ssm register-patch-baseline-for-patch-group \
  --baseline-id "$LINUX_BASELINE_ID" \
  --patch-group "${PREFIX}-linux"

aws ssm register-patch-baseline-for-patch-group \
  --baseline-id "$WINDOWS_BASELINE_ID" \
  --patch-group "${PREFIX}-windows"
```

### 16c. Maintenance Windows

```bash
# Linux maintenance window
LINUX_MW_ID=$(aws ssm create-maintenance-window \
  --name "${PREFIX}-linux-patch-window" \
  --description "Maintenance window for Linux patching" \
  --schedule "$MAINT_WINDOW_CRON" \
  --schedule-timezone "UTC" \
  --duration "$MAINT_WINDOW_DURATION" \
  --cutoff "$MAINT_WINDOW_CUTOFF" \
  --no-allow-unassociated-targets \
  --tags Key=Name,Value="${PREFIX}-linux-patch-window" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm \
  --query WindowId --output text)

# Register targets
LINUX_MW_TARGET=$(aws ssm register-target-with-maintenance-window \
  --window-id "$LINUX_MW_ID" \
  --resource-type INSTANCE \
  --name "${PREFIX}-linux-targets" \
  --description "Linux instances for patching" \
  --targets "Key=tag:PatchGroup,Values=${PREFIX}-linux" \
  --query WindowTargetId --output text)

# Register patch task
aws ssm register-task-with-maintenance-window \
  --window-id "$LINUX_MW_ID" \
  --task-type RUN_COMMAND \
  --task-arn "AWS-RunPatchBaseline" \
  --name "${PREFIX}-linux-patch-task" \
  --description "Apply approved patches to Linux instances" \
  --priority 1 \
  --max-concurrency "25%" \
  --max-errors "25%" \
  --targets "Key=WindowTargetIds,Values=${LINUX_MW_TARGET}" \
  --task-invocation-parameters "{
    \"RunCommand\": {
      \"Parameters\": {
        \"Operation\": [\"Install\"],
        \"RebootOption\": [\"RebootIfNeeded\"]
      },
      \"TimeoutSeconds\": 3600,
      \"OutputS3BucketName\": \"${S3_BUCKET}\",
      \"OutputS3KeyPrefix\": \"ssm-output/patch-linux\"
    }
  }"

# Windows maintenance window (same pattern)
WINDOWS_MW_ID=$(aws ssm create-maintenance-window \
  --name "${PREFIX}-windows-patch-window" \
  --description "Maintenance window for Windows patching" \
  --schedule "$MAINT_WINDOW_CRON" \
  --schedule-timezone "UTC" \
  --duration "$MAINT_WINDOW_DURATION" \
  --cutoff "$MAINT_WINDOW_CUTOFF" \
  --no-allow-unassociated-targets \
  --tags Key=Name,Value="${PREFIX}-windows-patch-window" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm \
  --query WindowId --output text)

WINDOWS_MW_TARGET=$(aws ssm register-target-with-maintenance-window \
  --window-id "$WINDOWS_MW_ID" \
  --resource-type INSTANCE \
  --name "${PREFIX}-windows-targets" \
  --description "Windows instances for patching" \
  --targets "Key=tag:PatchGroup,Values=${PREFIX}-windows" \
  --query WindowTargetId --output text)

aws ssm register-task-with-maintenance-window \
  --window-id "$WINDOWS_MW_ID" \
  --task-type RUN_COMMAND \
  --task-arn "AWS-RunPatchBaseline" \
  --name "${PREFIX}-windows-patch-task" \
  --description "Apply approved patches to Windows instances" \
  --priority 1 \
  --max-concurrency "25%" \
  --max-errors "25%" \
  --targets "Key=WindowTargetIds,Values=${WINDOWS_MW_TARGET}" \
  --task-invocation-parameters "{
    \"RunCommand\": {
      \"Parameters\": {
        \"Operation\": [\"Install\"],
        \"RebootOption\": [\"RebootIfNeeded\"]
      },
      \"TimeoutSeconds\": 3600,
      \"OutputS3BucketName\": \"${S3_BUCKET}\",
      \"OutputS3KeyPrefix\": \"ssm-output/patch-windows\"
    }
  }"
```

---

## 17. Auto-Tagging (EventBridge + Lambda)

Automatically propagates `StigPlatform` and `StigManaged` tags from
Chimera AMIs to newly launched EC2 instances, so State Manager associations
target them automatically.

> Corresponds to:
> [`modules/ssm/auto-tagging.tf`](../infra/modules/ssm/auto-tagging.tf)

### 17a. Lambda Function

```bash
mkdir -p /tmp/tag-propagation

cat > /tmp/tag-propagation/index.py << 'PYTHON'
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
            return {'status': 'not found'}

        instance = resp['Reservations'][0]['Instances'][0]
        image_id = instance['ImageId']
        instance_tags = {t['Key']: t['Value'] for t in instance.get('Tags', [])}

        if 'StigPlatform' in instance_tags:
            logger.info("Instance %s already tagged", instance_id)
            return {'status': 'already tagged'}

        try:
            images = ec2.describe_images(ImageIds=[image_id])
        except Exception as e:
            logger.error("Failed to describe AMI %s: %s", image_id, e)
            return {'status': 'AMI describe failed'}

        if not images['Images']:
            return {'status': 'AMI not found'}

        ami_tags = {t['Key']: t['Value'] for t in images['Images'][0].get('Tags', [])}

        if ami_tags.get('StigManaged') != 'true':
            return {'status': 'not a Chimera AMI'}

        tags_to_copy = []
        for key in ['StigPlatform', 'StigManaged']:
            if key in ami_tags and key not in instance_tags:
                tags_to_copy.append({'Key': key, 'Value': ami_tags[key]})

        if tags_to_copy:
            ec2.create_tags(Resources=[instance_id], Tags=tags_to_copy)
            logger.info("Tagged instance %s with %s", instance_id, tags_to_copy)
            return {'status': 'tagged', 'tags': str(tags_to_copy)}

        return {'status': 'no tags to copy'}

    except Exception as e:
        logger.error("Error processing instance %s: %s", instance_id, e)
        raise
PYTHON

cd /tmp/tag-propagation && zip -q ../tag-propagation.zip index.py && cd -
```

### 17b. Lambda IAM Role

```bash
cat > /tmp/lambda-trust.json << 'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "LambdaAssumeRole",
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
TRUST

aws iam create-role \
  --role-name "${PREFIX}-lambda-tag-propagation" \
  --assume-role-policy-document file:///tmp/lambda-trust.json \
  --tags Key=Name,Value="${PREFIX}-lambda-tag-propagation" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm

cat > /tmp/lambda-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2DescribeAndTag",
      "Effect": "Allow",
      "Action": ["ec2:DescribeInstances", "ec2:DescribeImages", "ec2:CreateTags"],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:${PARTITION}:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/lambda/${PREFIX}-ami-tag-propagation:*"
    }
  ]
}
POLICY

aws iam put-role-policy \
  --role-name "${PREFIX}-lambda-tag-propagation" \
  --policy-name "${PREFIX}-tag-propagation" \
  --policy-document file:///tmp/lambda-policy.json

# Wait for role propagation
sleep 10
```

### 17c. Deploy Lambda

```bash
LAMBDA_ROLE_ARN=$(aws iam get-role \
  --role-name "${PREFIX}-lambda-tag-propagation" \
  --query Role.Arn --output text)

aws lambda create-function \
  --function-name "${PREFIX}-ami-tag-propagation" \
  --description "Propagate StigPlatform and StigManaged tags from Chimera AMIs to instances" \
  --runtime python3.12 \
  --handler index.handler \
  --role "$LAMBDA_ROLE_ARN" \
  --timeout 30 \
  --memory-size 128 \
  --zip-file fileb:///tmp/tag-propagation.zip \
  --tags Name="${PREFIX}-ami-tag-propagation",ManagedBy=manual,Module=chimera-ssm
```

### 17d. EventBridge Rule

```bash
aws events put-rule \
  --name "${PREFIX}-ami-tag-propagation" \
  --description "Propagate Chimera AMI tags to newly launched instances" \
  --event-pattern '{
    "source": ["aws.ec2"],
    "detail-type": ["EC2 Instance State-change Notification"],
    "detail": {"state": ["running"]}
  }' \
  --tags Key=Name,Value="${PREFIX}-ami-tag-propagation" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm

LAMBDA_ARN=$(aws lambda get-function \
  --function-name "${PREFIX}-ami-tag-propagation" \
  --query Configuration.FunctionArn --output text)

aws events put-targets \
  --rule "${PREFIX}-ami-tag-propagation" \
  --targets "Id=ami-tag-propagation,Arn=${LAMBDA_ARN}"

aws lambda add-permission \
  --function-name "${PREFIX}-ami-tag-propagation" \
  --statement-id AllowEventBridgeInvoke \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn "arn:${PARTITION}:events:${AWS_REGION}:${ACCOUNT_ID}:rule/${PREFIX}-ami-tag-propagation"
```

---

## 18. CloudWatch Alarms

Metric filters detect SSM errors and compliance failures in the log
group, and alarms send notifications via the SNS topic.

> Corresponds to: [`modules/ssm/cloudwatch.tf`](../infra/modules/ssm/cloudwatch.tf)

```bash
# Metric filter: SSM errors
aws logs put-metric-filter \
  --log-group-name "$LOG_GROUP" \
  --filter-name "${PREFIX}-ssm-errors" \
  --filter-pattern "?ERROR ?Failed" \
  --metric-transformations \
    metricName="${PREFIX}-SSMErrors",metricNamespace="CHIMERA/SSM",metricValue=1,defaultValue=0

# Metric filter: Compliance failures
aws logs put-metric-filter \
  --log-group-name "$LOG_GROUP" \
  --filter-name "${PREFIX}-compliance-failures" \
  --filter-pattern "?NON_COMPLIANT ?fail" \
  --metric-transformations \
    metricName="${PREFIX}-ComplianceFailures",metricNamespace="CHIMERA/SSM",metricValue=1,defaultValue=0

# Alarm: SSM errors
aws cloudwatch put-metric-alarm \
  --alarm-name "${PREFIX}-ssm-errors" \
  --alarm-description "SSM command or session errors detected in ${PREFIX}" \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --metric-name "${PREFIX}-SSMErrors" \
  --namespace "CHIMERA/SSM" \
  --period 300 \
  --statistic Sum \
  --threshold 0 \
  --treat-missing-data notBreaching \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --ok-actions "$SNS_TOPIC_ARN" \
  --tags Key=Name,Value="${PREFIX}-ssm-errors-alarm" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm

# Alarm: Compliance failures
aws cloudwatch put-metric-alarm \
  --alarm-name "${PREFIX}-compliance-failures" \
  --alarm-description "STIG compliance failures detected in ${PREFIX}" \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --metric-name "${PREFIX}-ComplianceFailures" \
  --namespace "CHIMERA/SSM" \
  --period 300 \
  --statistic Sum \
  --threshold 0 \
  --treat-missing-data notBreaching \
  --alarm-actions "$SNS_TOPIC_ARN" \
  --ok-actions "$SNS_TOPIC_ARN" \
  --tags Key=Name,Value="${PREFIX}-compliance-failures-alarm" \
         Key=ManagedBy,Value=manual Key=Module,Value=chimera-ssm
```

---

## 19. Verification

```bash
echo "=== SSM Infrastructure Verification ==="
echo ""

# 1. KMS key
echo "── KMS Key ──"
aws kms describe-key --key-id "alias/${PREFIX}-ssm" \
  --query 'KeyMetadata.{KeyId:KeyId,Enabled:Enabled,Rotation:KeyRotationStatus}' \
  --output table 2>/dev/null || echo "  NOT FOUND"

# 2. S3 buckets
echo "── S3 Buckets ──"
for BUCKET in "$S3_BUCKET" "$S3_LOGS_BUCKET"; do
  aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null \
    && echo "  $BUCKET: exists" \
    || echo "  $BUCKET: NOT FOUND"
done

# 3. VPC endpoints
echo "── VPC Endpoints ──"
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'VpcEndpoints[*].{Service:ServiceName,State:State}' \
  --output table

# 4. IAM roles
echo "── IAM Roles ──"
for ROLE in "${PREFIX}-ssm-instance-role" "${PREFIX}-ssm-dhmc-role" "${PREFIX}-lambda-tag-propagation"; do
  aws iam get-role --role-name "$ROLE" --query 'Role.RoleName' --output text 2>/dev/null \
    && true || echo "  $ROLE: NOT FOUND"
done

# 5. SSM documents
echo "── SSM Documents ──"
for DOC in "${PREFIX}-RunOpenSCAPScan" "${PREFIX}-WindowsSTIGEnforce" "SSM-SessionManagerRunShell"; do
  STATUS=$(aws ssm describe-document --name "$DOC" --query 'Document.Status' --output text 2>/dev/null || echo "NOT FOUND")
  echo "  $DOC: $STATUS"
done

# 6. SSM associations
echo "── SSM Associations ──"
aws ssm list-associations \
  --association-filter-list "key=AssociationName,value=${PREFIX}" \
  --query 'Associations[*].{Name:AssociationName,Status:Overview.Status}' \
  --output table

# 7. DHMC
echo "── DHMC ──"
aws ssm get-service-setting \
  --setting-id "arn:${PARTITION}:ssm:${AWS_REGION}:${ACCOUNT_ID}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role" \
  --query 'ServiceSetting.SettingValue' --output text

# 8. Online instances
echo "── Managed Instances ──"
aws ssm describe-instance-information \
  --filters "Key=PingStatus,Value=Online" \
  --query 'InstanceInformationList[*].[InstanceId,PlatformName,PlatformVersion]' \
  --output table

echo ""
echo "=== Verification Complete ==="
```

---

## 20. Teardown

To remove all resources created by this guide, run these commands **in
reverse order** of creation. Delete associations first, then documents,
then supporting resources.

```bash
# Associations
for ASSOC in stig-ansible-check oscap-scheduled-scan software-inventory \
             stig-enforce-el stig-enforce-al2023 stig-enforce-windows \
             ssm-agent-update; do
  ASSOC_ID=$(aws ssm list-associations \
    --association-filter-list "key=AssociationName,value=${PREFIX}-${ASSOC}" \
    --query 'Associations[0].AssociationId' --output text 2>/dev/null)
  [[ "$ASSOC_ID" != "None" ]] && aws ssm delete-association --association-id "$ASSOC_ID"
done

# Maintenance windows
for MW_NAME in linux-patch-window windows-patch-window; do
  MW_ID=$(aws ssm describe-maintenance-windows \
    --filters "Key=Name,Values=${PREFIX}-${MW_NAME}" \
    --query 'WindowIdentities[0].WindowId' --output text 2>/dev/null)
  [[ "$MW_ID" != "None" ]] && aws ssm delete-maintenance-window --window-id "$MW_ID"
done

# Patch baselines (deregister groups first)
for PG in linux windows; do
  BL_ID=$(aws ssm describe-patch-baselines \
    --filters "Key=NAME_PREFIX,Values=${PREFIX}-${PG}" \
    --query 'BaselineIdentities[0].BaselineId' --output text 2>/dev/null)
  if [[ "$BL_ID" != "None" ]]; then
    aws ssm deregister-patch-baseline-for-patch-group \
      --baseline-id "$BL_ID" --patch-group "${PREFIX}-${PG}" 2>/dev/null || true
    aws ssm delete-patch-baseline --baseline-id "$BL_ID"
  fi
done

# SSM documents
for DOC in RunOpenSCAPScan WindowsSTIGEnforce; do
  aws ssm delete-document --name "${PREFIX}-${DOC}" 2>/dev/null || true
done
aws ssm delete-document --name "SSM-SessionManagerRunShell" 2>/dev/null || true

# DHMC — reset to empty
aws ssm reset-service-setting \
  --setting-id "arn:${PARTITION}:ssm:${AWS_REGION}:${ACCOUNT_ID}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"

# EventBridge + Lambda
aws events remove-targets --rule "${PREFIX}-ami-tag-propagation" --ids ami-tag-propagation 2>/dev/null || true
aws events delete-rule --name "${PREFIX}-ami-tag-propagation" 2>/dev/null || true
aws lambda delete-function --function-name "${PREFIX}-ami-tag-propagation" 2>/dev/null || true

# CloudWatch alarms + metric filters
aws cloudwatch delete-alarms --alarm-names "${PREFIX}-ssm-errors" "${PREFIX}-compliance-failures"
aws logs delete-metric-filter --log-group-name "$LOG_GROUP" --filter-name "${PREFIX}-ssm-errors" 2>/dev/null || true
aws logs delete-metric-filter --log-group-name "$LOG_GROUP" --filter-name "${PREFIX}-compliance-failures" 2>/dev/null || true

# SNS
aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"

# CloudWatch log group
aws logs delete-log-group --log-group-name "$LOG_GROUP"

# IAM
aws iam remove-role-from-instance-profile \
  --instance-profile-name "${PREFIX}-ssm-instance-profile" \
  --role-name "${PREFIX}-ssm-instance-role" 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name "${PREFIX}-ssm-instance-profile" 2>/dev/null || true
for ROLE in ssm-instance-role ssm-dhmc-role lambda-tag-propagation; do
  ROLE_NAME="${PREFIX}-${ROLE}"
  # Delete inline policies
  for POL in $(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null); do
    aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$POL"
  done
  # Detach managed policies
  for ARN in $(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null); do
    aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$ARN"
  done
  aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true
done
aws iam delete-policy --policy-arn "$CALLER_POLICY_ARN" 2>/dev/null || true

# S3 buckets (force-destroy contents)
for BUCKET in "$S3_BUCKET" "$S3_LOGS_BUCKET"; do
  aws s3 rb "s3://${BUCKET}" --force 2>/dev/null || true
done

# VPC endpoints
for VPCE in $(aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Module,Values=chimera-ssm" \
  --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null); do
  aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$VPCE"
done
aws ec2 delete-security-group --group-id "$ENDPOINT_SG" 2>/dev/null || true

# KMS key (schedule deletion in 30 days)
aws kms schedule-key-deletion --key-id "$KMS_KEY_ID" --pending-window-in-days 30

echo "Teardown complete. KMS key ${KMS_KEY_ID} scheduled for deletion in 30 days."
```

---

## Resource Mapping

Cross-reference between this guide and the OpenTofu module files:

| Section | OpenTofu File |
|---------|---------------|
| §2 KMS Key | [`modules/ssm/kms.tf`](../infra/modules/ssm/kms.tf) |
| §3 S3 Buckets | [`modules/ssm/s3.tf`](../infra/modules/ssm/s3.tf) |
| §4 CloudWatch & SNS | [`modules/ssm/cloudwatch.tf`](../infra/modules/ssm/cloudwatch.tf) |
| §5 VPC Endpoints | [`modules/ssm/vpc-endpoints.tf`](../infra/modules/ssm/vpc-endpoints.tf) |
| §6-8 IAM | [`modules/ssm/iam.tf`](../infra/modules/ssm/iam.tf), [`modules/ssm/dhmc.tf`](../infra/modules/ssm/dhmc.tf) |
| §9 DHMC | [`modules/ssm/dhmc.tf`](../infra/modules/ssm/dhmc.tf) |
| §10-11 SSM Documents | [`modules/ssm/ssm-documents.tf`](../infra/modules/ssm/ssm-documents.tf) |
| §13 Compliance Associations | [`modules/ssm/ssm-associations.tf`](../infra/modules/ssm/ssm-associations.tf) |
| §14-15 Enforcement Associations | [`modules/ssm/ssm-stig-enforcement.tf`](../infra/modules/ssm/ssm-stig-enforcement.tf) |
| §16 Patch Manager | [`modules/ssm/ssm-patching.tf`](../infra/modules/ssm/ssm-patching.tf) |
| §17 Auto-Tagging | [`modules/ssm/auto-tagging.tf`](../infra/modules/ssm/auto-tagging.tf) |
| §18 Alarms | [`modules/ssm/cloudwatch.tf`](../infra/modules/ssm/cloudwatch.tf) |

---

## Instance Tagging Requirements

For SSM associations to target instances correctly, launched instances
must have these tags:

| Tag | Values | Set By |
|-----|--------|--------|
| `StigManaged` | `true` | AMI tag → propagated by auto-tagging Lambda (§17) or launch template |
| `StigPlatform` | `EL8`, `EL9`, `AL2023`, `Win2019`, `Win2022` | AMI tag → propagated by auto-tagging Lambda (§17) or launch template |
| `PatchGroup` | `${PREFIX}-linux` or `${PREFIX}-windows` | Set manually or via launch template (for patch maintenance windows) |

---

## GovCloud Notes

- All ARNs use `$PARTITION` — resolves to `aws-us-gov` automatically.
- VPC endpoint service names use `$AWS_REGION` — resolves to
  `us-gov-west-1` etc.
- Set `AWS_USE_FIPS_ENDPOINT=true` before running any commands.
- S3 regional domain names resolve correctly in GovCloud partitions.
- The `AWSEC2-ConfigureSTIG` document and Windows STIG downloads are
  available in GovCloud regions.
