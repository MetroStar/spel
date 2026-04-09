# Chimera SSM Infrastructure Module

OpenTofu module for deploying SSM infrastructure to support STIG-hardened AMIs built by [Chimera](../../README.md). Compatible with OpenTofu (>= 1.0).

## Overview

This module creates SSM infrastructure that attaches to an **existing VPC**. It does NOT create the VPC itself — use `infra-setup.yml` for that.

Architecture: **one deployment per AWS account** (not per-AMI). SSM resources persist across Packer builds.

### Resources Created

| Resource | Description | Toggle |
| -------- | ----------- | ------ |
| KMS CMK | Customer-managed encryption key for S3, CloudWatch, SSM, SNS | `create_kms_key` |
| VPC Endpoints | `ssm`, `ssmmessages`, `ec2messages`, `logs`, `kms` (Interface) + `s3` (Gateway) | `enable_vpc_endpoints` |
| IAM Instance Profile | EC2 role with SSM, S3, CloudWatch, KMS, Parameter Store permissions | `create_instance_profile` |
| IAM Caller Policy | Permissions for CI/humans to invoke SSM operations | Always created |
| SSM Documents | Custom `RunOpenSCAPScan` + `WindowsSTIGEnforce` + Session Manager preferences | Always / `enable_session_manager` |
| SSM Associations | Ansible STIG check-mode, OpenSCAP scan, Software Inventory (compliance verification) | `enable_state_manager`, `enable_inventory` |
| STIG Enforcement | Ansible Lockdown (EL) + native script (AL2023) + AWSEC2-ConfigureSTIG (Windows) enforce mode | `enable_stig_enforcement` |
| SSM Agent Update | Automatic SSM agent updates (daily, before patch window) | `enable_ssm_agent_update` |
| DHMC | Default Host Management Configuration — auto-registers all EC2 instances with SSM | `enable_dhmc` |
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
  source = "./modules/ssm"

  name_prefix = "chimera-ci"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0"]
  vpc_cidr    = "10.0.0.0/16"

  create_kms_key         = true
  enable_vpc_endpoints   = true
  enable_state_manager   = true
  enable_patch_manager   = true
  enable_inventory       = true
  enable_session_manager = true
  enable_stig_enforcement = false  # No enforcement in CI

  tags = {
    Project     = "CHIMERA"
    Environment = "CI"
  }
}
```

### Production (full features)

```hcl
module "ssm" {
  source = "./modules/ssm"

  name_prefix = "chimera-prod"
  vpc_id      = "vpc-prod-id"
  subnet_ids  = ["subnet-a", "subnet-b"]
  vpc_cidr    = "10.100.0.0/16"

  create_kms_key         = true
  enable_vpc_endpoints   = true
  enable_state_manager   = true
  enable_patch_manager   = true
  enable_inventory       = true
  enable_session_manager = true
  enable_stig_enforcement = true

  oscap_schedule   = "rate(7 days)"
  ansible_schedule = "rate(7 days)"
  stig_enforcement_schedule = "rate(7 days)"

  log_retention_days = 365
  alert_email        = "ops@example.com"

  tags = {
    Project     = "CHIMERA"
    Environment = "Production"
  }
}
```

### Using an existing KMS key

```hcl
module "ssm" {
  source = "./modules/ssm"

  name_prefix    = "chimera-prod"
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
| -------- | ------- |
| `infra-setup.yml` | Deploy/teardown all infrastructure including SSM (plan/apply/destroy) |
| `build.yml` | Build AMIs — calls `infra-setup.yml` with `infra_prefix` to ensure infrastructure exists |

Deploy infra: **Actions → Infrastructure Setup → Run workflow → apply**

Teardown: **Actions → Infrastructure Setup → Run workflow → destroy** (requires typing "destroy" in confirmation field)

### GitLab CI

| Job | Purpose |
| --- | ------- |  
| `infra:create` | Deploy all infrastructure including SSM via OpenTofu (manual trigger, from `.gitlab/infra.gitlab-ci.yml`) |
| `infra:destroy` | Teardown all OpenTofu-managed infrastructure (manual trigger, from `.gitlab/infra.gitlab-ci.yml`) |

All SSM infrastructure is persistent by default — provisioned via the OpenTofu root module at `infra/`.

## Backend Setup

**CI/CD pipelines handle this automatically** — both GitHub Actions (`infra-setup.yml`) and GitLab CI (`infra:create` job) call `bootstrap-backend.sh` which idempotently creates the S3 bucket, DynamoDB table, and `backend.tf` before running `tofu init`.

For manual / local use:

```bash
# Automatic (recommended)
source ./bootstrap-backend.sh --prefix chimera-prod --region us-gov-west-1
tofu init -input=false

# Manual
# 1. Copy backend.tf.example to backend.tf and fill in values
# 2. Create S3 bucket and DynamoDB table (see comments in the example file)
# 3. tofu init
```

## GovCloud

The module is fully GovCloud-compatible:

- All ARNs use `data.aws_partition` (resolves to `aws-us-gov` automatically)
- VPC endpoint service names use `data.aws_region` (resolves to `us-gov-west-1`, etc.)
- S3 bucket names reference region-specific SSM buckets
- KMS key policy uses dynamic partition
- Set `AWS_USE_FIPS_ENDPOINT=true` for FIPS compliance

## Air-Gapped / Disconnected Environments

This module is designed for air-gapped environments with no internet access. All communication routes through VPC endpoints:

| Service | Endpoint Type | Purpose |
| --------- | --------------- | --------- |
| `ssm` | Interface | SSM agent ↔ service communication |
| `ssmmessages` | Interface | Session Manager WebSocket channels |
| `ec2messages` | Interface | SSM message delivery |
| `logs` | Interface | CloudWatch Logs delivery |
| `kms` | Interface | Encryption key operations |
| `s3` | Gateway | S3 playbook downloads + result uploads |

### Key settings for air-gapped deployments

```hcl
module "ssm" {
  source = "./modules/ssm"

  # ...
  enable_vpc_endpoints = true    # Required — creates all VPC endpoints
  install_dependencies = false   # Default — DO NOT set true without internet
}
```

### Pre-installed requirements

Since `install_dependencies = false` (default), these must be on the AMI:

| Package | Required By | Chimera AMI Status |
| --------- | --------------- | --------- |
| `ansible-core` | Ansible STIG playbook execution | Pre-installed |
| `openscap-scanner` | OpenSCAP compliance scans | Pre-installed |
| `scap-security-guide` | SCAP data streams (benchmarks) | Pre-installed |
| `unzip`, `wget` | SSM document dependencies | Pre-installed |

All packages are pre-installed on Chimera-built AMIs, so no internet access is needed at runtime.

### S3 URL format

All SourceInfo URLs use region-aware virtual-hosted-style format (`https://<bucket>.s3.<region>.amazonaws.com/`) instead of the global `s3.amazonaws.com` path. This ensures S3 downloads route correctly through the S3 VPC gateway endpoint.

## Instance Targeting

SSM associations use **platform-specific targeting** via the `StigPlatform` tag for platform-specific operations, and the `StigManaged=true` tag (configurable via `target_tag_key`/`target_tag_value`) for cross-platform operations.

### Targeting by association type

| Association | Tag Key | Tag Values | Rationale |
| ----------- | ------- | ---------- | --------- |
| **EL STIG enforcement** | `StigPlatform` | `EL8`, `EL9` | Linux Ansible playbook — not compatible with Windows/AL2023 |
| **EL STIG check-mode** | `StigPlatform` | `EL8`, `EL9` | Same playbook in `--check` mode |
| **OpenSCAP scan** | `StigPlatform` | `EL8`, `EL9` | OpenSCAP content is Linux-specific |
| **AL2023 enforcement** | `StigPlatform` | `AL2023` | AL2023 uses its own native script |
| **Windows enforcement** | `StigPlatform` | `Win2019`, `Win2022` | Custom wrapper: AWSEC2-ConfigureSTIG + admin rename (SID-500 → maintuser) |
| **SSM agent update** | `StigManaged` | `true` | All platforms need agent updates |
| **Software inventory** | `StigManaged` | `true` | Collect inventory from all platforms |

### EL8 FIPS boot repair

The upstream RHEL8-STIG role (`ansible-lockdown/RHEL8-STIG`) templates `/etc/default/grub` wholesale via `etc_default_grub.j2`, replacing `GRUB_CMDLINE_LINUX` and stripping the `boot=UUID=<uuid>` parameter required for FIPS boot integrity on EL8 systems with a separate `/boot` partition.

The S3 playbook package includes `boot-fips-wrapper.sh` alongside the roles. The wrapper `site.yml` runs it as pre/post tasks:

- **pre**: Installs `dracut-fips`, rebuilds initramfs, inserts `boot=UUID` for the correct device
- **post**: Validates `boot=UUID` matches the actual kernel device, checks HMAC files, rebuilds initramfs

In `--check` mode (compliance scans), `ansible.builtin.script` is naturally skipped, so the wrapper does not run during check-only scans.

### How instances get tagged

All Chimera hardened AMIs are built with these AMI-level tags:

- `StigManaged = "true"` — all platforms
- `StigPlatform` — platform identifier (`EL8`, `EL9`, `AL2023`, `Win2019`, `Win2022`)

To propagate these tags to launched instances, use **one** of:

1. **EC2 account setting**: Enable "Copy AMI tags to instances" in EC2 → Account Settings → Default Settings
2. **Launch Template**: Add `TagSpecification` blocks that copy the AMI tags
3. **Manual tagging**: Apply `StigManaged=true` and `StigPlatform=<platform>` to instances at launch

### S3 Playbook Packaging

The EL STIG enforcement and check-mode associations expect a .zip archive at the `ansible_s3_key` path (default: `ansible/stig-playbook.zip`). CI/CD pipelines handle this automatically. To build manually, use `tests/package-ansible-stig.sh`:

```bash
# Package all platforms (default)
./tests/package-ansible-stig.sh --output ./dist

# Package and upload to S3
./tests/package-ansible-stig.sh --s3-bucket <bucket-name> --s3-prefix ansible
```

The resulting zip contains:

```text
stig-playbook.zip
├── site.yml                # Wrapper playbook (auto-detects OS, includes FIPS pre/post)
├── boot-fips-wrapper.sh    # EL8 FIPS boot repair script
├── roles/
│   ├── RHEL8-STIG/         # Ansible Lockdown RHEL8 STIG role
│   └── RHEL9-STIG/         # Ansible Lockdown RHEL9 STIG role
├── collections/            # Pre-packaged Ansible collections (if present)
└── requirements.yml        # Collection metadata
```

### Default Host Management Configuration (DHMC)

When `enable_dhmc = true` (default), all EC2 instances in the account/region automatically register with SSM without needing an instance profile. DHMC provides a dedicated IAM role trusted by `ssm.amazonaws.com` with permissions for S3, CloudWatch, and KMS access.

## Inputs

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `name_prefix` | Prefix for all resource names | `string` | - | yes |
| `vpc_id` | Existing VPC ID | `string` | - | yes |
| `subnet_ids` | Subnet IDs for VPC endpoints | `list(string)` | - | yes |
| `vpc_cidr` | VPC CIDR block | `string` | - | yes |
| `create_kms_key` | Create a new KMS CMK | `bool` | `true` | no |
| `kms_key_arn` | Existing KMS key ARN (when `create_kms_key=false`) | `string` | `""` | no |
| `enable_vpc_endpoints` | Create VPC endpoints | `bool` | `true` | no |
| `enable_session_manager` | Enable Session Manager preferences | `bool` | `true` | no |
| `enable_state_manager` | Create State Manager associations | `bool` | `true` | no |
| `enable_patch_manager` | Create patch baselines + maintenance windows | `bool` | `true` | no |
| `enable_inventory` | Create inventory association | `bool` | `true` | no |
| `enable_stig_enforcement` | Enable STIG enforcement (Ansible Lockdown for EL, native script for AL2023, AWSEC2-ConfigureSTIG for Windows) | `bool` | `true` | no |
| `enable_ssm_agent_update` | Enable automatic SSM agent updates | `bool` | `true` | no |
| `enable_dhmc` | Enable Default Host Management Configuration (auto-registers all instances) | `bool` | `true` | no |
| `install_dependencies` | Let SSM install Ansible via pip (set false for air-gapped) | `bool` | `false` | no |
| `target_tag_key` | Instance tag key for SSM association targeting | `string` | `StigManaged` | no |
| `target_tag_value` | Instance tag value for SSM association targeting | `string` | `true` | no |
| `create_instance_profile` | Create IAM instance profile | `bool` | `true` | no |
| `session_idle_timeout` | Session Manager idle timeout (minutes) | `number` | `20` | no |
| `alert_email` | SNS email subscription for alerts | `string` | `""` | no |
| `log_retention_days` | CloudWatch log retention | `number` | `90` | no |
| `maintenance_window_schedule` | Patch window cron expression | `string` | `cron(0 4 ? * SUN *)` | no |
| `maintenance_window_duration` | Patch window duration (hours) | `number` | `3` | no |
| `maintenance_window_cutoff` | Task scheduling cutoff (hours) | `number` | `1` | no |
| `patch_approve_after_days` | Patch auto-approval delay (days) | `number` | `7` | no |
| `stig_enforcement_schedule` | Schedule for STIG enforcement runs | `string` | `rate(7 days)` | no |
| `ansible_timeout` | Timeout in seconds for Ansible STIG playbook execution via SSM | `number` | `7200` | no |
| `stig_al2023_s3_key` | S3 key for AL2023 STIG script package | `string` | `ansible/al2023-stig-script.zip` | no |
| `windows_stig_level` | STIG severity level for Windows (AWSEC2-ConfigureSTIG) | `string` | `High` | no |
| `windows_admin_username` | Name for the built-in Administrator account (SID-500) on Windows | `string` | `maintuser` | no |
| `ssm_agent_update_schedule` | Schedule for SSM agent updates | `string` | `cron(0 3 ? * * *)` | no |
| `tags` | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| --- | --- |
| `kms_key_arn` | KMS key ARN (created or external) |
| `kms_alias_name` | KMS key alias |
| `vpc_endpoint_ssm_dns` | SSM VPC endpoint DNS |
| `vpc_endpoint_kms_dns` | KMS VPC endpoint DNS |
| `instance_profile_name` | IAM instance profile name |
| `caller_policy_arn` | CI/human caller policy ARN |
| `session_manager_document_name` | Session Manager preferences document |
| `ssm_document_oscap_name` | OpenSCAP SSM document name |
| `ssm_document_windows_stig_enforce_name` | Windows STIG enforce SSM document name |
| `linux_patch_baseline_id` | Linux STIG patch baseline ID |
| `linux_maintenance_window_id` | Linux maintenance window ID |
| `stig_enforce_el_association_id` | EL STIG enforcement association ID |
| `stig_enforce_al2023_association_id` | AL2023 STIG enforcement association ID |
| `ssm_agent_update_association_id` | SSM agent update association ID |
| `stig_enforce_windows_association_ids` | Map of Windows version to STIG enforcement association IDs |
| `dhmc_role_name` | DHMC IAM role name |
| `dhmc_role_arn` | DHMC IAM role ARN |
| `s3_bucket_name` | Primary SSM S3 bucket |
| `s3_access_logs_bucket_name` | Access logging S3 bucket |
| `cloudwatch_log_group_name` | CloudWatch log group |
| `sns_topic_arn` | SNS alerts topic ARN |

See [outputs.tf](outputs.tf) for full list.
