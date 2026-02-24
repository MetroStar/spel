# SPEL Infrastructure — Root Module

OpenTofu root module that provisions all AWS infrastructure required for
[SPEL](../README.md) AMI builds. A single `tofu apply` stands up
networking, IAM, and Systems Manager (SSM) resources; a single
`tofu destroy` tears everything down.

## Architecture

```
infra/
├── main.tf                  # Wires the three submodules together
├── variables.tf             # Root-level inputs (networking + SSM toggles)
├── outputs.tf               # Values consumed by Packer / CI pipelines
├── versions.tf              # OpenTofu >= 1.0, AWS >= 5.0
├── backend.tf.example       # Copy → backend.tf and customise
├── bootstrap-backend.sh     # Idempotent S3+DynamoDB backend bootstrap
└── modules/
    ├── iam/                 # Packer builder IAM role + instance profile
    ├── networking/          # VPC, subnet, IGW, security group, Packer endpoints
    └── ssm/                 # SSM documents, associations, endpoints, KMS, S3
```

| Submodule | Purpose |
|-----------|---------|
| **iam** | Creates the IAM role, inline policy, and instance profile used by Packer-launched EC2 instances. Grants SSM, S3, and CloudWatch permissions. |
| **networking** | Creates a VPC with a single subnet (public or private), an optional internet gateway, route table, a security group for Packer instances (SSH/WinRM), and optional VPC endpoints for EC2 and STS (air-gapped builds). |
| **ssm** | Deploys account-wide SSM infrastructure — VPC endpoints, KMS CMK, S3 bucket, CloudWatch log group, SSM documents (OpenSCAP, Session Manager), State Manager associations (STIG enforcement, inventory, agent update), Patch Manager baselines, DHMC, auto-tagging, and SNS alerting. See [modules/ssm/README.md](modules/ssm/README.md) for full details. |

> The **iam** module creates the instance profile, and the **ssm** module
> receives the role name via `existing_instance_role_name` so that SSM
> policies are attached to the same role — no duplicate IAM resources.

## Prerequisites

| Requirement | Minimum Version |
|-------------|-----------------|
| OpenTofu | >= 1.0 |
| AWS Provider | >= 5.0 |
| Random Provider | >= 3.0 |
| AWS CLI | v2 (for backend bootstrapping) |

An AWS account with permissions to create VPCs, IAM roles, SSM resources,
S3 buckets, KMS keys, and DynamoDB tables.

## Quick Start

### 1. Bootstrap the Remote Backend

The helper script creates an S3 bucket (versioned, encrypted) and a
DynamoDB lock table, then generates a `backend.tf` file:

```bash
cd infra/
source bootstrap-backend.sh --prefix spel --region us-east-1
```

Override defaults with flags:

| Flag | Default | Description |
|------|---------|-------------|
| `--prefix` | `spel-offline` | Resource-name prefix |
| `--region` | `$AWS_DEFAULT_REGION` or `us-east-1` | AWS region |
| `--bucket` | `${PREFIX}-ssm-tfstate-${ACCOUNT_ID}` | S3 bucket name |
| `--table` | `${PREFIX}-ssm-tflock` | DynamoDB table name |
| `--key` | `ssm-infra/opentofu.tfstate` | State file key path |

Alternatively, copy `backend.tf.example` to `backend.tf` and fill in
values manually.

### 2. Initialise and Apply

```bash
tofu init
tofu plan -var name_prefix=spel
tofu apply -var name_prefix=spel
```

### 3. Use Outputs in Packer Builds

The root module exports the values Packer and CI pipelines need:

```bash
export SUBNET_ID=$(tofu output -raw subnet_id)
export VPC_ID=$(tofu output -raw vpc_id)
export SECURITY_GROUP_ID=$(tofu output -raw security_group_id)
export INSTANCE_PROFILE=$(tofu output -raw instance_profile_name)
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name_prefix` | `string` | — (**required**) | Prefix for all resource names (alphanumeric + hyphens) |
| `vpc_cidr` | `string` | `10.0.0.0/16` | CIDR block for the VPC |
| `subnet_cidr` | `string` | `10.0.1.0/24` | CIDR block for the subnet |
| `public_subnet` | `bool` | `true` | Auto-assign public IPs on launch |
| `enable_internet_gateway` | `bool` | `true` | Create an Internet Gateway and default route. Set to `false` for air-gapped builds. |
| `enable_packer_endpoints` | `bool` | `false` | Create VPC endpoints for EC2 and STS (required when `enable_internet_gateway = false`) |
| `enable_vpc_endpoints` | `bool` | `true` | Create VPC endpoints for SSM (required for air-gapped networks) |
| `enable_session_manager` | `bool` | `true` | Enable Session Manager with KMS encryption and logging |
| `enable_state_manager` | `bool` | `true` | Create State Manager associations for scheduled scans |
| `enable_patch_manager` | `bool` | `true` | Create patch baselines and maintenance windows |
| `enable_inventory` | `bool` | `true` | Create SSM Inventory association for data collection |
| `enable_stig_enforcement` | `bool` | `true` | Create State Manager associations to enforce STIG hardening |
| `enable_ssm_agent_update` | `bool` | `true` | Keep the SSM Agent up to date via State Manager |
| `enable_dhmc` | `bool` | `true` | Enable Default Host Management Configuration |
| `enable_auto_tagging` | `bool` | `true` | Propagate StigPlatform/StigManaged tags from AMIs to instances |
| `create_kms_key` | `bool` | `true` | Create a new KMS CMK for SSM encryption |
| `kms_key_arn` | `string` | `""` | ARN of an existing KMS key (when `create_kms_key = false`) |
| `alert_email` | `string` | `""` | Email for SNS alert notifications (empty = skip subscription) |
| `tags` | `map(string)` | `{}` | Additional tags merged with `Project=SPEL` and `ManagedBy=opentofu` |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC |
| `subnet_id` | ID of the subnet |
| `security_group_id` | ID of the Packer security group |
| `instance_profile_name` | Name of the Packer builder instance profile |
| `instance_profile_arn` | ARN of the Packer builder instance profile |
| `instance_role_name` | Name of the Packer builder IAM role |
| `kms_key_arn` | ARN of the KMS key for EBS/SSM encryption |
| `kms_key_id` | ID of the KMS key (only when `create_kms_key = true`) |
| `s3_bucket_name` | Name of the S3 bucket for SSM outputs |
| `cloudwatch_log_group_name` | Name of the CloudWatch log group for SSM |
| `ssm_document_oscap_name` | Name of the OpenSCAP SSM document |
| `caller_policy_arn` | ARN of the IAM policy for CI runners to invoke SSM operations |
| `session_manager_document_name` | Name of the Session Manager preferences document |
| `sns_topic_arn` | ARN of the SNS topic for SSM alerts |

## Air-Gapped / Disconnected Usage

To run Packer builds without an Internet Gateway, disable the IGW and
enable VPC endpoints for all AWS API traffic:

```hcl
module "spel_infra" {
  source = "./infra"

  name_prefix             = "spel"
  public_subnet           = false
  enable_internet_gateway = false
  enable_packer_endpoints = true     # EC2 + STS endpoints
  enable_vpc_endpoints    = true     # SSM + S3 + KMS + Logs endpoints
}
```

### What this changes

| Resource | IGW enabled (default) | IGW disabled |
|----------|----------------------|--------------|
| Internet Gateway | Created | **Not created** |
| Default route (`0.0.0.0/0`) | Points to IGW | **No default route** |
| SSH / WinRM ingress | `0.0.0.0/0` | **VPC CIDR only** |
| Packer endpoints (ec2, sts) | Not created | **Created** |
| SSM endpoints | Per `enable_vpc_endpoints` | Per `enable_vpc_endpoints` |
| Route table | Always created | Always created |

### VPC Endpoints summary

When both `enable_packer_endpoints` and `enable_vpc_endpoints` are `true`,
the following endpoints are provisioned:

| Endpoint | Type | Module |
|----------|------|--------|
| `ec2` | Interface | networking |
| `sts` | Interface | networking |
| `ssm` | Interface | ssm |
| `ssmmessages` | Interface | ssm |
| `ec2messages` | Interface | ssm |
| `logs` | Interface | ssm |
| `kms` | Interface | ssm |
| `s3` | Gateway | ssm |

### Package repositories

Disabling the IGW also cuts off access to internet-hosted yum/dnf
repositories. Supply an S3-based or internally-hosted mirror via the
Packer `repo_mirror_baseurl` variable, or pre-populate the build
subnet with the required packages.

See the [SSM module README](modules/ssm/README.md) for endpoint details
and required security-group rules.

## GovCloud Notes

- Set `AWS_USE_FIPS_ENDPOINT=true` before running `bootstrap-backend.sh`.
- The IAM module uses `aws_partition` to construct ARNs, so policies
  resolve correctly in both Commercial and GovCloud partitions.

## Related Documentation

- [SSM Module README](modules/ssm/README.md) — full SSM resource
  reference, STIG association details, and troubleshooting
- [Manual SSM Setup](../docs/Manual-SSM-Setup.md) — step-by-step AWS CLI
  guide for provisioning all SSM resources without OpenTofu (air-gapped)
- [CI/CD Setup](../docs/CI-CD-Setup.md) — CodeBuild / GitLab CI
  pipeline configuration and IAM requirements
- [SPEL README](../README.md) — project overview and AMI build process
