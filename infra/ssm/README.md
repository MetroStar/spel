# SPEL SSM Infrastructure Module

Terraform/OpenTofu module for deploying SSM infrastructure to support STIG-hardened AMIs built by [SPEL](../../README.md). Compatible with both HashiCorp Terraform (>= 1.0) and OpenTofu (>= 1.0).

## Overview

This module creates SSM infrastructure that attaches to an **existing VPC**. It does NOT create the VPC itself — use `infra-setup.yml` or inline temp infra in `build.yml` for that.

Architecture: **one deployment per AWS account** (not per-AMI). SSM resources persist across Packer builds.

### Resources Created

| Resource | Description | Toggle |
|----------|-------------|--------|
| KMS CMK | Customer-managed encryption key for S3, CloudWatch, SSM, SNS | `create_kms_key` |
| VPC Endpoints | `ssm`, `ssmmessages`, `ec2messages`, `logs`, `kms` (Interface) + `s3` (Gateway) | `enable_vpc_endpoints` |
| IAM Instance Profile | EC2 role with SSM, S3, CloudWatch, KMS, Parameter Store permissions | `create_instance_profile` |
| IAM Caller Policy | Permissions for CI/humans to invoke SSM operations | Always created |
| SSM Documents | Custom `RunOpenSCAPScan` + Session Manager preferences (`SSM-SessionManagerRunShell`) | Always / `enable_session_manager` |
| SSM Associations | Ansible STIG check-mode, OpenSCAP scan, Software Inventory | `enable_state_manager`, `enable_inventory` |
| Patch Baselines | Linux + Windows STIG-aligned baselines | `enable_patch_manager` |
| Maintenance Windows | Scheduled patching tasks (default Sunday 4AM UTC, 3h window) | `enable_patch_manager` |
| S3 Bucket | SSM outputs, OpenSCAP results, session logs, patch logs | Always created |
| S3 Access Logs Bucket | Server access logging for the primary S3 bucket | Always created |
| CloudWatch Log Group | SSM RunCommand and Session Manager logs (KMS-encrypted) | Always created |
| SNS Topic | Alert notifications (optional email subscription) | Always created |
| CloudWatch Alarms | SSM errors + compliance failures → SNS | Always created |

## Usage

### CI/CD (minimal — testing only)

```hcl
module "ssm" {
  source = "./infra/ssm"

  name_prefix = "spel-ci"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0"]
  vpc_cidr    = "10.0.0.0/16"

  create_kms_key         = true
  enable_vpc_endpoints   = true
  enable_state_manager   = false  # No scheduled runs for CI
  enable_patch_manager   = false  # No patching in CI
  enable_inventory       = true
  enable_session_manager = true

  tags = {
    Project     = "SPEL"
    Environment = "CI"
  }
}
```

### Production (full features)

```hcl
module "ssm" {
  source = "./infra/ssm"

  name_prefix = "spel-prod"
  vpc_id      = "vpc-prod-id"
  subnet_ids  = ["subnet-a", "subnet-b"]
  vpc_cidr    = "10.100.0.0/16"

  create_kms_key         = true
  enable_vpc_endpoints   = true
  enable_state_manager   = true
  enable_patch_manager   = true
  enable_inventory       = true
  enable_session_manager = true

  oscap_schedule   = "rate(7 days)"
  ansible_schedule = "rate(7 days)"

  log_retention_days = 365
  alert_email        = "ops@example.com"

  tags = {
    Project     = "SPEL"
    Environment = "Production"
  }
}
```

### Using an existing KMS key

```hcl
module "ssm" {
  source = "./infra/ssm"

  name_prefix    = "spel-prod"
  vpc_id         = "vpc-prod-id"
  subnet_ids     = ["subnet-a"]
  vpc_cidr       = "10.100.0.0/16"

  create_kms_key = false
  kms_key_arn    = "arn:aws-us-gov:kms:us-gov-west-1:123456789:key/..."
}
```

## CI/CD Workflows

### GitHub Actions

| Workflow | Purpose |
|----------|---------|
| `ssm-infra.yml` | Deploy/teardown SSM infrastructure (plan/apply/destroy) |
| `build.yml` | Build AMIs — supports `use_persistent_ssm` input to look up Terraform outputs |

Deploy SSM infra: **Actions → SSM Infrastructure → Run workflow → apply**

Teardown: **Actions → SSM Infrastructure → Run workflow → destroy** (requires typing "destroy" in confirmation field)

### GitLab CI

| Job | Purpose |
|-----|---------|
| `infra:ssm` | Deploy SSM infrastructure (manual trigger, `CREATE_INFRASTRUCTURE=true`) |
| `infra:ssm:destroy` | Teardown SSM infrastructure (manual trigger, `DESTROY_SSM_INFRA=true`) |

Set `USE_PERSISTENT_SSM=true` to use persistent SSM infra in builds.

## Backend Setup

**CI/CD pipelines handle this automatically** — both GitHub Actions (`ssm-infra.yml`) and GitLab CI (`infra:ssm` job) call `bootstrap-backend.sh` which idempotently creates the S3 bucket, DynamoDB table, and `backend.tf` before running `terraform init`.

For manual / local use:

```bash
# Automatic (recommended)
source ./bootstrap-backend.sh --prefix spel-prod --region us-gov-west-1
terraform init -input=false

# Manual
# 1. Copy backend.tf.example to backend.tf and fill in values
# 2. Create S3 bucket and DynamoDB table (see comments in the example file)
# 3. terraform init
```

## GovCloud

The module is fully GovCloud-compatible:
- All ARNs use `data.aws_partition` (resolves to `aws-us-gov` automatically)
- VPC endpoint service names use `data.aws_region` (resolves to `us-gov-west-1`, etc.)
- S3 bucket names reference region-specific SSM buckets
- KMS key policy uses dynamic partition
- Set `AWS_USE_FIPS_ENDPOINT=true` for FIPS compliance

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `name_prefix` | Prefix for all resource names | `string` | - | yes |
| `vpc_id` | Existing VPC ID | `string` | - | yes |
| `subnet_ids` | Subnet IDs for VPC endpoints | `list(string)` | - | yes |
| `vpc_cidr` | VPC CIDR block | `string` | - | yes |
| `create_kms_key` | Create a new KMS CMK | `bool` | `true` | no |
| `kms_key_arn` | Existing KMS key ARN (when `create_kms_key=false`) | `string` | `""` | no |
| `enable_vpc_endpoints` | Create VPC endpoints | `bool` | `true` | no |
| `enable_session_manager` | Enable Session Manager preferences | `bool` | `true` | no |
| `enable_state_manager` | Create State Manager associations | `bool` | `false` | no |
| `enable_patch_manager` | Create patch baselines + maintenance windows | `bool` | `false` | no |
| `enable_inventory` | Create inventory association | `bool` | `true` | no |
| `create_instance_profile` | Create IAM instance profile | `bool` | `true` | no |
| `session_idle_timeout` | Session Manager idle timeout (minutes) | `number` | `20` | no |
| `alert_email` | SNS email subscription for alerts | `string` | `""` | no |
| `log_retention_days` | CloudWatch log retention | `number` | `90` | no |
| `maintenance_window_schedule` | Patch window cron expression | `string` | `cron(0 4 ? * SUN *)` | no |
| `maintenance_window_duration` | Patch window duration (hours) | `number` | `3` | no |
| `maintenance_window_cutoff` | Task scheduling cutoff (hours) | `number` | `1` | no |
| `patch_approve_after_days` | Patch auto-approval delay (days) | `number` | `7` | no |
| `tags` | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `kms_key_arn` | KMS key ARN (created or external) |
| `kms_alias_name` | KMS key alias |
| `vpc_endpoint_ssm_dns` | SSM VPC endpoint DNS |
| `vpc_endpoint_kms_dns` | KMS VPC endpoint DNS |
| `instance_profile_name` | IAM instance profile name |
| `caller_policy_arn` | CI/human caller policy ARN |
| `session_manager_document_name` | Session Manager preferences document |
| `ssm_document_oscap_name` | OpenSCAP SSM document name |
| `linux_patch_baseline_id` | Linux STIG patch baseline ID |
| `linux_maintenance_window_id` | Linux maintenance window ID |
| `s3_bucket_name` | Primary SSM S3 bucket |
| `s3_access_logs_bucket_name` | Access logging S3 bucket |
| `cloudwatch_log_group_name` | CloudWatch log group |
| `sns_topic_arn` | SNS alerts topic ARN |

See [outputs.tf](outputs.tf) for full list.
