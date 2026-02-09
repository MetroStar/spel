# SPEL SSM Infrastructure Module

Terraform/OpenTofu module for deploying SSM infrastructure to support STIG-hardened AMIs built by [SPEL](../../README.md). Compatible with both HashiCorp Terraform (>= 1.0) and OpenTofu (>= 1.0).

## Overview

This module creates SSM infrastructure that attaches to an **existing VPC**. It does NOT create the VPC itself — use `infra-setup.yml` or inline temp infra in `build.yml` for that.

### Resources Created

| Resource | Description | Toggle |
|----------|-------------|--------|
| VPC Endpoints | `ssm`, `ssmmessages`, `ec2messages`, `logs` (Interface) + `s3` (Gateway) | `enable_vpc_endpoints` |
| IAM Instance Profile | EC2 role with full SSM permissions (agent, inventory, patching, logging) | `create_instance_profile` |
| IAM Caller Policy | Permissions for CI/humans to invoke SSM operations | Always created |
| SSM Document | Custom `RunOpenSCAPScan` document | Always created |
| SSM Associations | Ansible STIG check-mode, OpenSCAP scan, Software Inventory | `enable_state_manager`, `enable_inventory` |
| Patch Baseline | Custom baselines for Linux and Windows | `enable_patch_manager` |
| S3 Bucket | SSM outputs, OpenSCAP results, Ansible playbook packages | Always created |
| CloudWatch Log Group | SSM RunCommand and Session Manager logs | Always created |

## Usage

### CI/CD (minimal — testing only)

```hcl
module "ssm" {
  source = "./infra/ssm"

  name_prefix = "spel-ci"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0"]
  vpc_cidr    = "10.0.0.0/16"

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

  enable_vpc_endpoints   = true
  enable_state_manager   = true
  enable_patch_manager   = true
  enable_inventory       = true
  enable_session_manager = true

  oscap_schedule   = "rate(7 days)"
  ansible_schedule = "rate(7 days)"

  kms_key_arn        = "arn:aws-us-gov:kms:us-gov-west-1:123456789:key/..."
  log_retention_days = 365

  tags = {
    Project     = "SPEL"
    Environment = "Production"
  }
}
```

## Backend Setup

**CI/CD pipelines handle this automatically** — both GitHub Actions (`infra-setup.yml`) and GitLab CI (`infra:ssm` job) call `bootstrap-backend.sh` which idempotently creates the S3 bucket, DynamoDB table, and `backend.tf` before running `terraform init`.

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
- Set `AWS_USE_FIPS_ENDPOINT=true` for FIPS compliance

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `name_prefix` | Prefix for all resource names | `string` | - | yes |
| `vpc_id` | Existing VPC ID | `string` | - | yes |
| `subnet_ids` | Subnet IDs for VPC endpoints | `list(string)` | - | yes |
| `vpc_cidr` | VPC CIDR block | `string` | - | yes |
| `enable_vpc_endpoints` | Create VPC endpoints | `bool` | `true` | no |
| `enable_session_manager` | Enable Session Manager | `bool` | `true` | no |
| `enable_state_manager` | Create State Manager associations | `bool` | `false` | no |
| `enable_patch_manager` | Create patch baselines | `bool` | `false` | no |
| `enable_inventory` | Create inventory association | `bool` | `true` | no |
| `create_instance_profile` | Create IAM instance profile | `bool` | `true` | no |
| `kms_key_arn` | KMS key for encryption | `string` | `""` | no |
| `log_retention_days` | CloudWatch log retention | `number` | `90` | no |
| `tags` | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_endpoint_ssm_dns` | DNS name of SSM VPC endpoint |
| `instance_profile_name` | IAM instance profile name |
| `caller_policy_arn` | IAM policy ARN for CI/human callers |
| `ssm_document_oscap_name` | Custom OpenSCAP SSM document name |
| `s3_bucket_name` | S3 bucket for SSM outputs |
| `cloudwatch_log_group_name` | CloudWatch log group name |

See [outputs.tf](outputs.tf) for full list.
