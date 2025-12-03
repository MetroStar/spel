# CI/CD Setup for NIPR Transfers

This guide explains how to set up and use the automated CI/CD pipelines for NIPR SPEL deployments.

## Overview

The NIPR transfer workflow is split across two CI/CD systems:

1. **GitHub Actions** (Internet-connected) - Prepares optimized transfer archives
2. **GitLab CI** (NIPR air-gapped) - Extracts archives and builds AMIs

```
Internet System (GitHub)          NIPR System (GitLab)
┌─────────────────────┐          ┌──────────────────────┐
│ 1. Vendor Roles     │          │ 7. Extract Archives  │
│ 2. Vendor Colls     │          │ 8. Setup Environment │
│ 3. Download Pkgs    │   -->    │ 9. Validate          │
│ 4. Create Archives  │ Transfer │ 10. Build AMIs       │
│ 5. Verify Checksums │          │                      │
│ 6. Upload Artifacts │          │                      │
└─────────────────────┘          └──────────────────────┘
```

## GitHub Actions Setup (Internet-Connected)

### Workflow File

Location: `.github/workflows/nipr-prepare.yml`

### Features

- **Automated Scheduling**: Runs monthly on the 15th at 6:00 AM UTC
- **Manual Triggers**: Run on-demand with customizable options
- **Storage Optimization**: Reduces transfer size by 70%
- **Artifact Upload**: Stores archives in GitHub for 90 days
- **Checksum Verification**: Generates SHA256 checksums for all archives

### Usage

#### Automatic Monthly Run

The workflow runs automatically on the 15th of each month to prepare archives for monthly SPEL builds.

#### Manual Trigger

1. Go to **Actions** → **Prepare NIPR Transfer Archives**
2. Click **Run workflow**
3. Select options:
   - **Vendor roles**: Clone Ansible roles (default: true)
   - **Vendor collections**: Download Ansible collections (default: true)
   - **Download packages**: Get offline AWS utilities (default: true)
   - **Create archives**: Build transfer archives (default: true)
   - **Upload artifacts**: Upload to GitHub (default: true)
4. Click **Run workflow**

#### Download Artifacts

After workflow completes:

1. Go to workflow run summary
2. Scroll to **Artifacts** section
3. Download:
   - `spel-nipr-transfer-YYYYMMDD` - Complete transfer package
   - `spel-nipr-base-YYYYMMDD` - Base code only (for updates)

### Environment Variables

All optimization settings are pre-configured:

```bash
SPEL_ROLES_REMOVE_GIT=true        # Remove .git dirs (saves 50%)
SPEL_ROLES_COMPRESS=true          # Compress roles archive
SPEL_OFFLINE_COMPRESS=true        # Compress offline packages
SPEL_ARCHIVE_SEPARATE=true        # Create separate archives
SPEL_ARCHIVE_COMBINED=true        # Also create combined archive
```

### Workflow Steps

1. **Checkout** - Clone repository with submodules
2. **Install dependencies** - Python, pip, ansible-galaxy
3. **Set environment** - Configure optimization variables
4. **Vendor roles** - Clone Ansible roles without git history (4 MB)
5. **Vendor collections** - Download Ansible collections as tarballs (3.5 MB)
6. **Download packages** - Get AWS utilities and Packer (183 MB: 86 MB offline + 97 MB Packer)
7. **Download Packer plugins** - Get required Packer plugins (241 MB)
8. **Create archives** - Build compressed transfer archives (1.1 GB total)
9. **Verify checksums** - Validate all archives with SHA256
10. **Generate manifest** - Create transfer documentation
11. **Upload artifacts** - Store in GitHub for download (90 day retention)

### Expected Output

```
Archives created:
  spel-base-20251202.tar.gz                  118 MB
  spel-tools-20251202.tar.gz                 289 MB
  spel-nipr-complete-20251202.tar.gz         694 MB

Total archive size: 1.1 GB

Workflow duration: 2-3 minutes (typical: 2:25)

Files ready for transfer:
  - spel-nipr-20251202-checksums.txt
  - spel-nipr-20251202-manifest.txt
  - spel-*.tar.gz
```

## GitLab CI Setup (NIPR)

### Configuration File

Location: `.gitlab-ci.yml`

### Pipeline Stages

The GitLab CI pipeline consists of 5 stages:

1. **extract** - Extract transferred archives and verify checksums (manual, 2-3 min)
2. **infra** - Create AWS infrastructure resources (optional, manual, 2-3 min)
3. **setup** - Prepare build environment and verify dependencies (automatic, 4-5 min)
4. **validate** - Validate Packer templates (automatic, 1 min)
5. **build** - Build AMI images (manual, 2-5 hours per OS)

### Prerequisites

#### GitLab Runner

Install and configure a GitLab Runner on NIPR system:

```bash
# Install GitLab Runner
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | sudo bash
sudo dnf install gitlab-runner

# Register runner
sudo gitlab-runner register \
  --url https://your-gitlab-nipr-instance.mil \
  --registration-token YOUR_TOKEN \
  --executor shell \
  --description "SPEL NIPR Builder" \
  --tag-list "spel-nipr-runner"
```

#### Infrastructure Requirements

**AWS GovCloud Resources** (choose setup method below):

- VPC with Internet Gateway (for RHUI repository access)
- Public subnet in the VPC
- Security group allowing Packer builder access (SSH/WinRM)
- IAM role with EC2 permissions for Packer
- IAM instance profile attached to the role

**System Requirements**:
- Disk space: 50+ GB free (verified by `verify:resources` job)
- Memory: 2+ GB available (verified by `verify:resources` job)
- Network: Access to AWS GovCloud API endpoints
- Credentials: AWS GovCloud access key and secret key

#### Infrastructure Setup

**Option 1: Automated Setup (Recommended)**

Use the pipeline's infrastructure stage to automatically create resources:

1. Set GitLab variable: `CREATE_INFRASTRUCTURE=true`
2. Run pipeline and manually trigger infrastructure jobs:
   - `infra:network` - Creates VPC, IGW, subnet, route table
   - `infra:security_group` - Creates Packer builder security group
   - `infra:iam` - Creates IAM role, policy, instance profile
3. Infrastructure IDs saved to artifacts: `infra.env`, `iam.env` (90-day retention)
4. Subsequent builds automatically use created resources

**Option 2: Manual Setup**

Create resources manually using AWS console or CLI, then configure variables:
- `PKR_VAR_aws_vpc_id` - VPC ID with Internet Gateway
- `PKR_VAR_aws_subnet_id` - Public subnet ID
- `PKR_VAR_aws_security_group_id` - Security group ID
- `PKR_VAR_aws_instance_profile_name` - IAM instance profile name

See "Infrastructure Setup Details" section below for complete manual setup instructions.

#### Required GitLab CI/CD Variables

Configure in GitLab project settings (**Settings** → **CI/CD** → **Variables**):

**Required Variables**:

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_GOVCLOUD_ACCESS_KEY_ID` | NIPR GovCloud access key | `AKIA...` |
| `AWS_GOVCLOUD_SECRET_ACCESS_KEY` | NIPR GovCloud secret key | `secret` |
| `PKR_VAR_aws_nipr_account_id` | NIPR AWS account ID for source AMI filters | `123456789012` |
| `PKR_VAR_aws_vpc_id` | VPC ID in NIPR (if not using infra stage) | `vpc-abc123` |
| `PKR_VAR_aws_subnet_id` | Subnet ID in NIPR (if not using infra stage) | `subnet-xyz789` |

**Optional Build Control Variables**:

| Variable | Description | Default |
|----------|-------------|---------|
| `EXTRACT_ARCHIVES` | Enable archive extraction | `false` |
| `RUN_AMZN2023` | Build Amazon Linux 2023 | `false` |
| `RUN_RHEL9` | Build RHEL 9 | `false` |
| `RUN_RHEL8` | Build RHEL 8 | `false` |
| `RUN_OL9` | Build Oracle Linux 9 | `false` |
| `RUN_OL8` | Build Oracle Linux 8 | `false` |
| `RUN_WS2016` | Build Windows Server 2016 | `false` |
| `RUN_WS2019` | Build Windows Server 2019 | `false` |
| `RUN_WS2022` | Build Windows Server 2022 | `false` |

**Optional Infrastructure Variables**:

| Variable | Description | Default |
|----------|-------------|---------|
| `CREATE_INFRASTRUCTURE` | Enable infrastructure creation jobs | `false` |
| `INFRA_PREFIX` | Prefix for created resources | `spel-packer` |
| `INFRA_TAGS` | JSON tags for AWS resources | `{"Project":"SPEL"}` |
| `PKR_VAR_aws_nipr_ami_regions` | Target regions for AMI copy | `["us-gov-east-1"]` |

### Usage Workflows

#### Scenario 1: Initial Setup (First Time)

**Step 1: Transfer archives to NIPR GitLab**:
```bash
# On transfer workstation
git clone https://your-gitlab-nipr-instance.mil/your-group/spel.git
cd spel/

# Copy transferred archives
cp /path/to/transferred/spel-*.tar.gz .
cp /path/to/transferred/spel-nipr-*-checksums.txt .

# Commit archives (if using Git LFS)
git lfs track "*.tar.gz"
git add .gitattributes spel-*.tar.gz spel-nipr-*-checksums.txt
git commit -m "Add NIPR transfer archives for $(date +%Y%m)"
git push
```

**Step 2: Extract archives**:
- Go to **CI/CD** → **Pipelines** → **Run pipeline**
- Set variable: `EXTRACT_ARCHIVES=true`
- Click **Run pipeline**
- Manually click **▶** on `extract:archives` job
- Wait for extraction to complete (2-3 minutes)

**Step 3: Create AWS infrastructure (one-time)**:
- Set variable: `CREATE_INFRASTRUCTURE=true`
- Run pipeline again
- Manually trigger infrastructure jobs in order:
  1. `infra:network` - Creates VPC, IGW, subnet (1 min)
  2. `infra:security_group` - Creates security group (30 sec)
  3. `infra:iam` - Creates IAM role and instance profile (1 min)
- Infrastructure IDs are saved to `infra.env` and `iam.env` artifacts
- These artifacts are used automatically by future builds (90-day retention)

**Step 4: Verify setup**:
- Setup stage runs automatically after infrastructure stage:
  - `verify:resources` - Checks disk (50+ GB), memory (2+ GB), commands
  - `aws:verify` - Tests AWS credentials, verifies VPC/subnet connectivity
  - `setup` - Initializes git submodules, detects offline Packer
  - `python:setup` - Creates venv, installs offline Python packages
  - `packer:init` - Initializes Packer plugins for all templates
  - `verify:dependencies` - Checks vendor/amigen8, vendor/amigen9 submodules
- All setup jobs complete in 4-5 minutes total

**Step 5: Validate and build**:
- Validate stage runs automatically (1 minute)
- Build stage jobs are manual - click **▶** on desired `build:*` job
- Each OS build takes 2-5 hours depending on hardening level

#### Scenario 2: Monthly AMI Builds (After Initial Setup)

After infrastructure is created and archives are extracted:

1. **Update archives** (if new transfer available):
   ```bash
   # Replace old archives with new ones
   rm spel-*.tar.gz spel-nipr-*-checksums.txt
   cp /path/to/new/spel-*.tar.gz .
   cp /path/to/new/spel-nipr-*-checksums.txt .
   git add spel-*.tar.gz spel-nipr-*-checksums.txt
   git commit -m "Update NIPR archives for $(date +%Y%m)"
   git push
   
   # Run pipeline with EXTRACT_ARCHIVES=true to re-extract
   ```

2. **Run build pipeline**:
   - Go to **CI/CD** → **Pipelines** → **Run pipeline**
   - Set build variables (e.g., `RUN_RHEL9=true`, `RUN_OL9=true`)
   - Click **Run pipeline**
   - Setup and validate stages run automatically (5-6 minutes)
   - Manually click **▶** on `build:rhel9` or `build:ol9` to start builds

3. **Monitor builds**:
   - Check job logs for progress
   - Builds complete in 2-5 hours per OS
   - AMI IDs are output in build job logs

#### Scenario 3: Quick Rebuild (No Archive Updates)

If archives and infrastructure are already set up and you just need to rebuild an AMI:

1. **Run pipeline**:
   - Go to **CI/CD** → **Pipelines** → **Run pipeline**
   - Set only the OS you want: `RUN_RHEL9=true`
   - Click **Run pipeline**

2. **Skip to build**:
   - Setup and validate run automatically (5-6 minutes)
   - Click **▶** on `build:rhel9` to start build
   - No extract or infrastructure jobs needed

#### Scenario 4: Full Release Build

For tagged releases that build all supported operating systems:

1. **Create and push tag**:
   ```bash
   git tag -a v2025.12.1 -m "December 2025 release"
   git push origin v2025.12.1
   ```

2. **Tagged pipeline**:
   - All OS builds are enabled automatically on tags
   - `build:all` job becomes available (runs all OS builds in parallel)
   - Requires significant resources (20+ GB disk per concurrent build)

### Stage Details

#### Stage 1: Extract

**Job**: `extract:archives`

Extracts transferred archives and verifies checksums.

**Trigger**: Manual (only when `EXTRACT_ARCHIVES=true`)
**Duration**: 2-3 minutes
**Artifacts**: Extracted tools, packages, roles, collections (90-day retention)

**What it does**:
- Runs `scripts/extract-nipr-archives.sh`
- Verifies SHA256 checksums before extraction
- Extracts to proper directory structure:
  - `tools/` - Packer binaries (Linux + Windows), Python packages
  - `offline-packages/` - SPEL offline installation packages
  - `vendor/ansible-roles/` - Ansible roles for amigen
  - `vendor/ansible-collections/` - Ansible collection tarballs
- Creates artifact for use by subsequent stages

**Run when**:
- Initial setup
- Monthly archive updates
- After transferring new archives to NIPR

#### Stage 2: Infrastructure (Optional)

**Jobs**: `infra:network`, `infra:security_group`, `infra:iam`

Creates AWS infrastructure resources needed for Packer builds.

**Trigger**: Manual (only when `CREATE_INFRASTRUCTURE=true`)
**Duration**: 2-3 minutes total (all jobs)
**Artifacts**: `infra.env`, `iam.env` (90-day retention)

**What it does**:

**`infra:network`**:
- Creates VPC with DNS support
- Attaches Internet Gateway (required for RHUI access)
- Creates public subnet
- Creates route table with IGW route
- Outputs: VPC_ID, IGW_ID, SUBNET_ID, ROUTE_TABLE_ID to `infra.env`

**`infra:security_group`**:
- Creates security group in VPC
- Allows SSH (22) and WinRM (5985, 5986) from anywhere (customize as needed)
- Allows all outbound traffic
- Outputs: SECURITY_GROUP_ID to `infra.env`

**`infra:iam`**:
- Creates IAM role with EC2 assume role policy
- Attaches policy with permissions:
  - EC2: DescribeImages, CreateImage, CreateTags, etc.
  - SSM: GetParameters (for Windows builds)
- Creates instance profile
- Outputs: ROLE_ARN, INSTANCE_PROFILE_NAME to `iam.env`

**Configuration**:
- Set `INFRA_PREFIX` to customize resource names (default: `spel-packer`)
- Set `INFRA_TAGS` JSON to add custom tags (default: `{"Project":"SPEL"}`)

**Run when**:
- Initial setup (one-time)
- Infrastructure refresh (if resources deleted)
- Never needed for monthly builds (artifacts retained for 90 days)

**Manual setup alternative**: If you prefer manual AWS resource creation, skip this stage and set these variables instead:
- `PKR_VAR_aws_vpc_id`
- `PKR_VAR_aws_subnet_id`
- `PKR_VAR_aws_security_group_id`
- `PKR_VAR_aws_instance_profile_name`

#### Stage 3: Setup

**Jobs**: `verify:resources`, `aws:verify`, `setup`, `python:setup`, `packer:init`, `verify:dependencies`

Prepares build environment and verifies all dependencies.

**Trigger**: Automatic
**Duration**: 4-5 minutes total (all jobs run in parallel where possible)
**Artifacts**: None (configuration stored in pipeline variables)

**What it does**:

**`verify:resources`** (runs first, parallel with `aws:verify`):
- Checks available disk space (requires 50+ GB free)
- Checks available memory (requires 2+ GB)
- Verifies required commands: git, tar, packer, ansible-galaxy, python3
- Exits with error if any check fails

**`aws:verify`** (runs first, parallel with `verify:resources`):
- Tests AWS credentials using `aws sts get-caller-identity`
- Verifies VPC exists and has Internet Gateway (required for RHUI)
- Verifies subnet exists and is in VPC
- Checks EC2 AMI quotas (warns if <10 AMIs available)
- Exits with error if credentials or network setup is invalid

**`setup`** (runs after verify jobs):
- Initializes git submodules (vendor/amigen8, vendor/amigen9)
- Detects offline Packer installation in `tools/packer-linux/`
- Sets `PACKER_PLUGIN_PATH` and `PATH` for offline Packer
- Runs `build/ci-setup.sh` in offline mode

**`python:setup`** (runs in parallel with `setup`):
- Creates Python virtual environment in `.venv/`
- Installs offline Python packages from `tools/python-deps/` wheels
- Verifies installations: boto3, ansible-core, etc.

**`packer:init`** (runs after `setup` and `python:setup`):
- Initializes Packer plugins for all templates
- Uses offline plugin cache in `tools/packer-plugins/`
- Runs `packer init` for Linux templates (RHEL, OL, Amazon Linux)
- Runs `packer init` for Windows templates (2016, 2019, 2022)
- Verifies all required plugins are available offline

**`verify:dependencies`** (runs in parallel with `packer:init`):
- Checks vendor/amigen8 submodule exists and has content
- Checks vendor/amigen9 submodule exists and has content
- Lists key files to verify submodules are properly initialized
- Exits with error if submodules are missing or empty

**Run when**:
- Every pipeline run (automatic)
- Ensures clean environment before validation and builds

#### Stage 4: Validate

**Jobs**: `validate:minimal`, `validate:hardened`

Validates Packer templates for syntax and configuration errors.

**Trigger**: Automatic (after setup stage)
**Duration**: 1 minute total (jobs run in parallel)
**Dependencies**: Requires `packer:init` artifacts

**What it does**:
- Runs `packer validate` on all templates
- Uses offline Packer plugins from `tools/packer-plugins/`
- Validates minimal builds (base OS without STIG hardening)
- Validates hardened builds (with STIG hardening enabled)
- Exits with error if any template has validation errors

**Run when**:
- Every pipeline run (automatic)
- Catches template errors before starting long builds

#### Stage 5: Build

**Jobs**: `build:amzn2023`, `build:rhel9`, `build:rhel8`, `build:ol9`, `build:ol8`, `build:windows2016`, `build:windows2019`, `build:windows2022`, `build:all`

Builds AMI images for specific operating systems.

**Trigger**: Manual (click **▶** to run)
**Duration**: 2-5 hours per OS (depends on instance type and STIG level)
**Artifacts**: Build logs, AMI IDs in job output
**Dependencies**: Requires all `setup` and `validate` artifacts

**What it does**:
- Activates Python venv (`.venv/bin/activate`)
- Loads infrastructure configuration (`infra.env`, `iam.env`)
- Sets offline Packer paths
- Runs `make spel-{os}-{variant}` for specific OS
- Packer workflow:
  1. Launches EC2 instance from source AMI
  2. Connects via SSH (Linux) or WinRM (Windows)
  3. Runs Ansible playbooks for hardening
  4. Creates AMI from instance
  5. Cleans up instance
- Outputs AMI ID and region on success

**Build jobs**:
- `build:amzn2023` - Amazon Linux 2023 (minimal and hardened)
- `build:rhel9` - RHEL 9 (minimal and hardened)
- `build:rhel8` - RHEL 8 (minimal and hardened)
- `build:ol9` - Oracle Linux 9 (minimal and hardened)
- `build:ol8` - Oracle Linux 8 (minimal and hardened)
- `build:windows2016` - Windows Server 2016
- `build:windows2019` - Windows Server 2019
- `build:windows2022` - Windows Server 2022
- `build:all` - All OS builds in parallel (only on tagged releases)

**Run when**:
- Monthly AMI builds
- Ad-hoc rebuilds for specific OS
- Full release builds (on tags)

### Offline Mode

The GitLab CI pipeline runs in **offline mode** (`SPEL_OFFLINE_MODE=true`), which means:

- **No internet access** during builds - completely air-gapped operation
- **Pre-vendored dependencies** - all components included in transfer archives:
  - Packer v1.11.2 (Linux and Windows binaries)
  - Packer plugins (Amazon, Ansible, PowerShell)
  - Python packages as wheels
  - Ansible collections as tarballs (ansible.windows:1.14.0, community.windows:1.13.0, community.general:7.5.0)
  - Ansible roles cloned locally
  - AWS CLI utilities and tools
- **RHUI Repositories**: Uses AWS GovCloud RHUI repos (no local mirrors needed)
- **Local installation** - collections installed to `~/.ansible/collections/` during `setup` job
- **Version compatibility** - Ansible Core 2.15.13 with collection versions tested for compatibility
- **Reproducible builds** - same vendored components ensure consistent results

This ensures builds are completely independent of external networks and reproducible across different NIPR environments.

## Complete Workflow Example

### Month 1: Initial Setup

**Internet System (GitHub Actions)**:
```bash
# Automatic on 15th of month, or manually trigger
# Downloads: roles, collections, packages, tools
# Creates: spel-*.tar.gz archives (~1 GB)
# Uploads to GitHub artifacts
# Typically completes in 5-10 minutes
```

**Transfer**:
```bash
# Download from GitHub Actions artifacts
# Transfer to NIPR using approved method (DVD, secure transfer, etc.)
# Verify checksums after transfer
sha256sum -c spel-nipr-20251115-checksums.txt
```

**NIPR System (GitLab CI)**:
```bash
# Upload archives to GitLab repository
git lfs track "*.tar.gz"
git add spel-*.tar.gz spel-nipr-*-checksums.txt
git commit -m "Add November 2025 NIPR transfer archives"
git push

# Set variable: EXTRACT_ARCHIVES=true
# Run pipeline
# Manually trigger extract:archives job
# configure:repos runs automatically
# Repository setup complete!
```

### Month 2+: Updates Only

**Internet System (GitHub Actions)**:
```bash
# Automatic monthly run creates new archives
# Only changed components need transfer (usually just roles/collections)
```

**Transfer**:
```bash
# Transfer only updated archives (e.g., roles or tools only)
# Smaller transfer size for incremental updates (~200-600 MB)
```

**NIPR System (GitLab CI)**:
```bash
# Update only changed archives in repository
# Re-run extract:archives if needed
# Build AMIs with existing setup
```

## Troubleshooting

### Extract Stage Issues

**Problem**: Extract job fails - no archives found
```bash
Solution: Ensure archives are in repository root
ls -lh spel-*.tar.gz

# Expected files:
# spel-nipr-YYYYMMDD-base.tar.gz (SPEL packages, roles)
# spel-nipr-YYYYMMDD-tools.tar.gz (Packer, Python)
# spel-nipr-YYYYMMDD-complete.tar.gz (Everything, optional)
```

**Problem**: Checksum verification fails
```bash
Solution: Re-transfer archives, verify file integrity
sha256sum -c spel-nipr-*-checksums.txt

# If checksums don't match, archives were corrupted during transfer
# Re-download from GitHub Actions and transfer again
```

**Problem**: Extraction succeeds but files missing
```bash
Solution: Check extraction script logs
cat scripts/extract-nipr-archives.sh

# Verify archives were extracted to correct paths:
ls -lh tools/packer-linux/
ls -lh tools/python-deps/
ls -lh vendor/ansible-roles/
ls -lh offline-packages/
```

### Infrastructure Stage Issues

**Problem**: VPC creation fails - quota exceeded
```bash
Solution: Check VPC quota in AWS account
aws ec2 describe-account-attributes --attribute-names vpc-quota

# If at limit, delete unused VPCs or request quota increase
```

**Problem**: IAM role creation fails - permission denied
```bash
Solution: Verify AWS credentials have IAM permissions
aws iam get-user

# Required permissions:
# - iam:CreateRole
# - iam:CreatePolicy
# - iam:AttachRolePolicy
# - iam:CreateInstanceProfile
# - iam:AddRoleToInstanceProfile
```

**Problem**: Infrastructure artifacts not found in later stages
```bash
Solution: Check artifact retention (90 days) and dependencies

# Verify infra.env artifact exists:
cat infra.env  # Should show VPC_ID, SUBNET_ID, etc.

# Verify iam.env artifact exists:
cat iam.env  # Should show INSTANCE_PROFILE_NAME, ROLE_ARN

# If missing, re-run infrastructure jobs or set variables manually
```

### Setup Stage Issues

**Problem**: `verify:resources` fails - insufficient disk space
```bash
Solution: Clean up old build artifacts and Packer cache
df -h  # Check available space

# Clean Packer cache
rm -rf ~/.packer.d/tmp/*

# Clean old artifacts
rm -rf spel-artifacts-*

# Require 50+ GB free space for builds
```

**Problem**: `verify:resources` fails - insufficient memory
```bash
Solution: Close unnecessary processes or increase system memory
free -h  # Check available memory

# Stop other services
sudo systemctl stop <service>

# Require 2+ GB available memory
```

**Problem**: `aws:verify` fails - VPC has no Internet Gateway
```bash
Solution: VPC must have Internet Gateway for RHUI access
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=vpc-xxxxx"

# If no IGW found:
# 1. Create IGW: aws ec2 create-internet-gateway
# 2. Attach to VPC: aws ec2 attach-internet-gateway --vpc-id vpc-xxxxx --internet-gateway-id igw-xxxxx
# 3. Update route table to use IGW for 0.0.0.0/0

# Or re-run infra:network job to create properly configured VPC
```

**Problem**: `aws:verify` fails - subnet not in VPC
```bash
Solution: Verify subnet belongs to specified VPC
aws ec2 describe-subnets --subnet-ids subnet-xxxxx

# Output should show VpcId matching PKR_VAR_aws_vpc_id
# If mismatch, update PKR_VAR_aws_subnet_id with correct subnet
```

**Problem**: `python:setup` fails - missing wheels
```bash
Solution: Verify Python packages were extracted
ls -lh tools/python-deps/

# Should contain .whl files for:
# - boto3
# - ansible-core
# - pywinrm (for Windows builds)

# If missing, re-run extract:archives job
```

**Problem**: `packer:init` fails - plugins not found
```bash
Solution: Verify Packer plugins were extracted
ls -lh tools/packer-plugins/

# Should contain plugin binaries:
# - packer-plugin-amazon_*
# - packer-plugin-ansible_*
# - packer-plugin-powershell_*

# If missing, re-run extract:archives job
```

**Problem**: `verify:dependencies` fails - submodule empty
```bash
Solution: Reinitialize git submodules
git submodule update --init --recursive

# Verify submodules have content:
ls -lh vendor/amigen8/
ls -lh vendor/amigen9/

# Should contain shell scripts: MkChrootTree.sh, OSpackages.sh, etc.
```

### Validate Stage Issues

**Problem**: Template validation fails - syntax error
```bash
Solution: Check Packer template for errors
packer validate spel/minimal-linux.pkr.hcl

# Fix syntax errors in template files
# Common issues:
# - Missing required variables
# - Invalid HCL syntax
# - Incorrect provisioner configuration
```

**Problem**: Validation fails - plugin not initialized
```bash
Solution: Verify packer:init job completed successfully
packer init spel/minimal-linux.pkr.hcl

# Should show "Installed plugin" messages
# If plugins missing, check PACKER_PLUGIN_PATH:
echo $PACKER_PLUGIN_PATH
ls -lh $PACKER_PLUGIN_PATH
```

### Build Stage Issues

**Problem**: Build fails - cannot access repositories
```bash
Solution: Verify RHUI repositories are accessible
# SSH into Packer builder instance (check build logs for IP)
ssh -i <key> ec2-user@<instance-ip>

# Test repository access
sudo dnf repolist
sudo dnf makecache

# If repos fail:
# 1. Verify VPC has Internet Gateway
# 2. Verify subnet route table has 0.0.0.0/0 -> IGW route
# 3. Verify security group allows outbound HTTPS (443)
```

**Problem**: Build fails - Ansible connection timeout
```bash
Solution: Check security group and network connectivity

# Verify security group allows SSH (22) for Linux or WinRM (5985, 5986) for Windows
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Verify subnet is public (has IGW route)
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-xxxxx"

# Check Packer logs for connection errors
```

**Problem**: Build fails - AMI quota exceeded
```bash
Solution: Clean up old AMIs or request quota increase
aws ec2 describe-images --owners self | grep ami-

# Deregister old AMIs:
aws ec2 deregister-image --image-id ami-xxxxx

# Check AMI quota:
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-XXXXXX
```

**Problem**: Build succeeds but AMI not in expected region
```bash
Solution: Verify PKR_VAR_aws_nipr_ami_regions is set correctly

# Check variable value
echo $PKR_VAR_aws_nipr_ami_regions

# Should be JSON array: ["us-gov-east-1", "us-gov-west-1"]
# Packer copies AMI to all regions after build completes
```

### GitHub Actions Issues

**Problem**: Archive too large for GitHub artifacts
```bash
Solution: Archives are split into base, tools, complete

# Base archive (~700 MB): SPEL packages, offline packages, roles
# Tools archive (~400 MB): Packer, Python, collections
# Complete archive (~1.1 GB): Everything combined (optional)

# Maximum artifact size: 2 GB per file
# Current archives are well within limits
```

**Problem**: Workflow timeout
```bash
Solution: Increase timeout-minutes in workflow file

# Current timeout: 10 minutes (default)
# Typical runtime: 2-3 minutes
# If timing out, check for:
# - Slow network downloads
# - Large role/collection downloads
# - Slow Packer binary downloads
```

## Performance Metrics

### GitHub Actions (nipr-prepare.yml)

- **Typical Runtime**: 2-3 minutes (measured: 2:25)
- **Timeout**: 10 minutes
- **Archives Created**: 1.1 GB total
  - Base archive: ~700 MB (SPEL packages, offline packages, roles)
  - Tools archive: ~400 MB (Packer binaries, Python wheels, collections)
  - Complete archive: ~1.1 GB (everything combined, optional)

### GitLab CI Pipeline Stages

| Stage | Jobs | Duration | Trigger |
|-------|------|----------|---------|
| Extract | 1 | 2-3 min | Manual |
| Infrastructure | 3 | 2-3 min | Manual (one-time) |
| Setup | 6 | 4-5 min | Automatic |
| Validate | 2 | 1 min | Automatic |
| Build | 1-9 per run | 2-5 hr each | Manual |

**Total pipeline time**:
- Initial setup: ~10 minutes (extract + infra + setup + validate)
- Monthly builds: ~6 minutes (setup + validate) + build time
- Quick rebuild: ~6 minutes (setup + validate) + build time

### Build Times by OS

| OS | Minimal Build | Hardened Build |
|----|---------------|----------------|
| Amazon Linux 2023 | 30-45 min | 2-3 hr |
| RHEL 9 | 45-60 min | 3-4 hr |
| RHEL 8 | 45-60 min | 3-4 hr |
| Oracle Linux 9 | 45-60 min | 3-4 hr |
| Oracle Linux 8 | 45-60 min | 3-4 hr |
| Windows Server 2016 | 60-90 min | 4-5 hr |
| Windows Server 2019 | 60-90 min | 4-5 hr |
| Windows Server 2022 | 60-90 min | 4-5 hr |

*Build times vary based on instance type, network speed, and STIG hardening level*

## Best Practices

### Archive Management

1. **Use complete archive for initial setup**: Contains everything needed
2. **Use split archives for monthly updates**: Transfer only changed components
3. **Verify checksums immediately after transfer**: Catch corruption early
4. **Keep archives in Git LFS if >50 MB**: Prevents repository bloat
5. **Clean old archives after successful extraction**: Save storage space

### Infrastructure Setup

1. **Use automated infrastructure stage**: Reduces manual errors, ensures consistency
2. **Tag resources appropriately**: Use `INFRA_TAGS` for project/owner tracking
3. **Save infrastructure artifacts**: 90-day retention allows rebuilds without recreation
4. **Document manual changes**: If creating resources manually, track in separate document
5. **Test connectivity before builds**: `aws:verify` job catches most issues early

### Build Optimization

1. **Run setup jobs in parallel**: Most setup jobs can run concurrently
2. **Use specific OS builds**: Don't run `build:all` unless needed for release
3. **Build during off-hours**: Long-running builds won't block interactive work
4. **Monitor resource usage**: Check disk space and memory before starting builds
5. **Limit concurrent builds**: Running too many builds in parallel exhausts disk space

### Pipeline Maintenance

1. **Update archives monthly**: Keep dependencies current (security patches)
2. **Verify infrastructure quarterly**: Check for resource drift or changes
3. **Clean Packer cache regularly**: Prevent disk space exhaustion
4. **Review build logs**: Catch warnings and deprecation notices early
5. **Test in dev environment first**: Validate changes before production builds

### Security

1. **Rotate AWS credentials regularly**: Update GitLab variables quarterly
2. **Use minimal IAM permissions**: Follow principle of least privilege
3. **Verify checksums always**: Never skip checksum verification
4. **Audit infrastructure access**: Review security group rules periodically
5. **Keep GitLab variables protected**: Mark all credentials as "Protected" and "Masked"

## Infrastructure Setup Details (Manual Alternative)

If you prefer not to use the automated infrastructure stage, follow these steps:

### VPC and Networking

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=spel-packer-vpc}]' \
  --query 'Vpc.VpcId' --output text)

# Enable DNS hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=spel-packer-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

# Attach IGW to VPC
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# Create public subnet
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=spel-packer-subnet}]' \
  --query 'Subnet.SubnetId' --output text)

# Create route table
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=spel-packer-rt}]' \
  --query 'RouteTable.RouteTableId' --output text)

# Add route to IGW
aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# Associate route table with subnet
aws ec2 associate-route-table \
  --route-table-id $ROUTE_TABLE_ID \
  --subnet-id $SUBNET_ID
```

### Security Group

```bash
# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name spel-packer-sg \
  --description "Security group for SPEL Packer builders" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

# Allow SSH (Linux)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0

# Allow WinRM (Windows)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 5985 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 5986 \
  --cidr 0.0.0.0/0
```

### IAM Role and Instance Profile

```bash
# Create trust policy
cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name spel-packer-role \
  --assume-role-policy-document file://trust-policy.json

# Create IAM policy
cat > policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CopyImage",
      "ec2:CreateImage",
      "ec2:CreateKeypair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeImageAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeRegions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "ec2:GetPasswordData",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances"
    ],
    "Resource": "*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name spel-packer-role \
  --policy-name spel-packer-policy \
  --policy-document file://policy.json

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name spel-packer-profile

# Add role to instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name spel-packer-profile \
  --role-name spel-packer-role
```

### Set GitLab Variables

After creating resources manually, configure these GitLab CI/CD variables:

```bash
# Network resources
PKR_VAR_aws_vpc_id=$VPC_ID
PKR_VAR_aws_subnet_id=$SUBNET_ID
PKR_VAR_aws_security_group_id=$SG_ID

# IAM resources
PKR_VAR_aws_instance_profile_name=spel-packer-profile

# AWS credentials
AWS_GOVCLOUD_ACCESS_KEY_ID=<your-access-key>
AWS_GOVCLOUD_SECRET_ACCESS_KEY=<your-secret-key>

# Account ID
PKR_VAR_aws_nipr_account_id=<your-account-id>
```

## Migration from Old Pipeline

If you have an existing GitLab CI setup without the infrastructure and setup stages:

### What's New

1. **Infrastructure Stage**: Optional automated AWS resource creation
2. **Setup Stage**: 6 verification and initialization jobs (vs 1 simple setup job)
3. **Enhanced Validation**: Now depends on Packer plugin initialization
4. **Enhanced Build**: Uses all setup artifacts, activates Python venv

### Migration Steps

1. **Update `.gitlab-ci.yml`**: Replace with new version from repository
2. **First pipeline run**:
   - Extract archives as usual (`EXTRACT_ARCHIVES=true`)
   - Optionally create infrastructure (`CREATE_INFRASTRUCTURE=true`)
   - Setup jobs run automatically and verify environment
   - Validate jobs use offline Packer plugins
   - Build jobs work as before (manual trigger)

3. **No manual changes needed**:
   - Existing CI/CD variables still work
   - Manual infrastructure setup is still supported (just skip infra stage)
   - Archives are extracted the same way
   - Build commands are unchanged

### Compatibility

- **Backward compatible**: Old variables (`PKR_VAR_aws_vpc_id`, etc.) still work
- **Forward compatible**: New variables (`CREATE_INFRASTRUCTURE`) are optional
- **No breaking changes**: All existing functionality preserved
- **Enhanced validation**: New verification jobs catch errors earlier, preventing wasted build time

## Storage Requirements

### GitHub Actions Runner

- **Workspace**: 500 MB
- **Dependencies**: 1.5 GB (roles, collections, packages, Packer, Python)
- **Archives**: 1.1 GB
- **Total**: ~3 GB free space needed

### GitLab Runner (NIPR)

- **Extracted archives**: ~1 GB
  - SPEL packages: 56 KB
  - Offline packages: 86 MB
  - Ansible roles: 4 MB (git clones)
  - Ansible collections: 3.5 MB (tarballs)
  - Packer binaries: 97 MB (Linux 49 MB + Windows 48 MB)
  - Packer plugins: 241 MB
  - Python packages: 16 MB (wheels)
- **Python venv**: ~200 MB (created by `python:setup` job)
- **Packer plugin cache**: ~300 MB (after `packer:init`)
- **Build workspace per job**: 10-20 GB
- **Packer cache**: 5-10 GB
- **Total for single build**: ~17-32 GB free space needed
- **Total for concurrent builds**: Add 15-30 GB per additional concurrent build

### Artifact Storage (GitLab)

- **Extract artifacts**: ~1 GB (90-day retention)
- **Infrastructure artifacts**: ~10 KB (`infra.env`, `iam.env`, 90-day retention)
- **Total**: ~1 GB for artifacts

## References

- **Storage Optimization Guide**: `docs/Storage-Optimization.md`
- **NIPR Setup Guide**: `docs/NIPR-Setup.md`
- **Quick Reference**: `docs/QUICK-REFERENCE-Optimization.md`
- **GitHub Actions Workflow**: `.github/workflows/nipr-prepare.yml`
- **GitLab CI Configuration**: `.gitlab-ci.yml`
