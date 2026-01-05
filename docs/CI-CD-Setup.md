# CI/CD Setup Guide

This guide covers the CI/CD pipeline configuration for SPEL (STIG-Partitioned Enterprise Linux) AMI builds using Docker containers with baked-in dependencies.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [GitHub Actions Setup](#github-actions-setup)
  - [Workflow 1: Prepare Offline Docker Image](#workflow-1-prepare-offline-docker-image)
  - [Workflow 2: Build STIGed AMIs](#workflow-2-build-stiged-amis)
- [GitLab CI Setup (Air-Gapped)](#gitlab-ci-setup-air-gapped)
  - [Pipeline Stages](#pipeline-stages)
  - [Configuration](#configuration)
  - [Usage Workflows](#usage-workflows)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Performance Metrics](#performance-metrics)
- [References](#references)

## Overview

The SPEL CI/CD pipeline uses a **Docker-based build system** where all dependencies are baked into a portable container image. This approach offers several advantages:

1. **Portability**: The Docker image can be exported and transferred to air-gapped environments
2. **Reproducibility**: All builds use identical dependency versions
3. **Simplicity**: No runtime dependency downloads or network access required during builds
4. **Speed**: Dependencies are pre-installed, reducing build time

### Workflow Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GitHub Actions (Online)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ offline-prepare.yml                                                  │   │
│  │                                                                      │   │
│  │  1. Checkout with submodules                                         │   │
│  │  2. Build Docker image with all dependencies                         │   │
│  │  3. Export as gzipped tarball                                        │   │
│  │  4. Upload artifact (30-day retention)                               │   │
│  │                                                                      │   │
│  │  Output: spel-builder-YYYYMMDD.tar.gz (~305 MB)                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                               │                                              │
│                               ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ build.yml (Optional - Test in GitHub Actions)                        │   │
│  │                                                                      │   │
│  │  1. Download Docker image artifact                                   │   │
│  │  2. Import Docker image                                              │   │
│  │  3. Configure AWS credentials (OIDC)                                 │   │
│  │  4. Run builds inside container                                      │   │
│  │                                                                      │   │
│  │  Output: STIGed AMIs in AWS Commercial                               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                               │
                   (Transfer tarball to air-gapped)
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GitLab CI (Air-Gapped)                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ .gitlab-ci.yml                                                        │   │
│  │                                                                      │   │
│  │  Stage 1: import - Import Docker image from tarball                  │   │
│  │  Stage 2: infra  - Create AWS infrastructure (optional)              │   │
│  │  Stage 3: build  - Build AMIs using Docker container                 │   │
│  │                                                                      │   │
│  │  Output: STIGed AMIs in AWS GovCloud                                 │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Architecture

### Docker Image Contents

The `spel-builder` Docker image (based on Rocky Linux 8) includes:

| Component | Version | Purpose |
|-----------|---------|---------|
| Packer | 1.12.0 | AMI building automation |
| Ansible Core | 2.15.x | Configuration management |
| AWS CLI v2 | Latest | AWS API interactions |
| Python 3 | 3.11 | Runtime for Ansible and AWS CLI |
| Packer Plugins | Latest | Amazon, Ansible, PowerShell, Windows-update |
| Ansible Roles | Latest | AMIgen8, AMIgen9, ash-linux |
| Ansible Collections | Latest | amazon.aws, community.general, ansible.windows |
| AMIgen Scripts | Latest | vendor/amigen8, vendor/amigen9 |

### Image Size

- **Uncompressed**: ~834 MB
- **Gzipped Tarball**: ~305 MB

## Prerequisites

### AWS IAM Configuration

#### 1. IAM Role Session Duration

The IAM role used for OIDC authentication **must** have `MaxSessionDuration` set to at least 21600 seconds (6 hours) to accommodate long-running builds:

```bash
# Update the IAM role's maximum session duration
aws iam update-role --role-name Packer_Amazon --max-session-duration 21600

# Verify the change
aws iam get-role --role-name Packer_Amazon --query 'Role.MaxSessionDuration'
# Expected output: 21600
```

> **Note**: AMI builds (especially with STIG hardening) can take 3-5 hours. The default 1-hour session duration will cause credential expiration during long builds.

#### 2. Public AMI Quota Increase

If building multiple AMIs concurrently or making AMIs public (`aws_ami_groups=["all"]`), increase the public AMI quota:

```bash
# Check current quota (default is 5)
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0E3CBAB9 \
  --region us-east-1 \
  --query 'Quota.Value'

# Request quota increase to 20 (adjust as needed)
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-0E3CBAB9 \
  --desired-value 20 \
  --region us-east-1

# Check request status
aws service-quotas list-requested-service-quota-change-history \
  --service-code ec2 \
  --region us-east-1 \
  --query 'RequestedQuotas[?QuotaCode==`L-0E3CBAB9`]'
```

For GovCloud regions, use `us-gov-east-1` or `us-gov-west-1`.

> **Note**: Quota increases typically take 1-3 business days for approval.

### GitHub Actions Prerequisites

1. **OIDC Provider**: Configure AWS to trust GitHub Actions OIDC tokens
2. **IAM Role**: Create a role that GitHub Actions can assume via OIDC
3. **Submodules**: Ensure `vendor/amigen8` and `vendor/amigen9` submodules are present

### GitLab CI Prerequisites

1. **Docker**: GitLab Runner must have Docker installed and running
2. **AWS Credentials**: Store in CI/CD variables:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN` (optional, for STS credentials)
3. **Transferred Tarball**: Docker image tarball must be accessible to the runner

## GitHub Actions Setup

### Workflow 1: Prepare Offline Docker Image

**File**: `.github/workflows/offline-prepare.yml`

**Purpose**: Build the SPEL Docker image with all dependencies baked in and export it as a portable tarball artifact.

#### Trigger

```yaml
on:
  workflow_dispatch:
    inputs:
      image_tag:
        description: "Docker image tag (default: YYYYMMDD)"
        required: false
        default: ""
        type: string
```

#### Workflow Steps

1. **Checkout repository with submodules**
   - Clones repo with `submodules: recursive`
   - Ensures vendor/amigen8 and vendor/amigen9 are present

2. **Verify submodules**
   - Validates that AMIgen submodules are not empty
   - Fails early if submodules are missing

3. **Build Docker image**
   - Uses `docker buildx` for efficient caching
   - Tags image as `spel-builder:YYYYMMDD` and `spel-builder:latest`
   - Multi-stage build keeps final image size minimal

4. **Verify Docker image**
   - Runs quick verification commands (packer version, ansible --version, aws --version)
   - Ensures all tools are properly installed

5. **Export Docker image as tarball**
   - Exports with `docker save | gzip`
   - Generates SHA256 checksum file
   - Creates manifest with build details

6. **Upload artifact**
   - Uploads tarball, checksum, and manifest
   - 30-day retention period
   - Artifact name: `spel-builder-YYYYMMDD`

#### Usage

1. Go to **Actions** → **Prepare Offline Docker Image**
2. Click **Run workflow**
3. Optionally specify a custom image tag
4. Wait for workflow to complete (~5-10 minutes)
5. Download artifact from workflow run

#### Output Artifact Contents

```
spel-builder-YYYYMMDD/
├── spel-builder-YYYYMMDD.tar.gz       # Docker image tarball (~305 MB)
├── spel-builder-YYYYMMDD.tar.gz.sha256 # SHA256 checksum
└── spel-builder-YYYYMMDD-manifest.txt  # Build manifest with tool versions
```

### Workflow 2: Build STIGed AMIs

**File**: `.github/workflows/build.yml`

**Purpose**: Build STIGed AMIs using the pre-built Docker container.

#### Prerequisites

Before running this workflow:

1. Run the `offline-prepare.yml` workflow first
2. Note the artifact name (e.g., `spel-builder-20251230`)
3. Ensure IAM role has `MaxSessionDuration >= 21600`
4. Ensure public AMI quota is sufficient (if making AMIs public)

#### Trigger

```yaml
on:
  workflow_dispatch:
    inputs:
      docker_image_artifact:
        description: "Docker image artifact name (e.g., spel-builder-20251231)"
        required: true
        type: string
      run_amzn2023:
        description: "Run Amazon Linux 2023 builder"
        type: boolean
      run_ol9:
        description: "Run Oracle Linux 9 builder"
        type: boolean
      run_rhel9:
        description: "Run RHEL 9 builder"
        type: boolean
      run_ol8:
        description: "Run Oracle Linux 8 builder"
        type: boolean
      run_rhel8:
        description: "Run RHEL 8 builder"
        type: boolean
      run_ws2016:
        description: "Run Windows Server 2016 builder"
        type: boolean
      run_ws2019:
        description: "Run Windows Server 2019 builder"
        type: boolean
      run_ws2022:
        description: "Run Windows Server 2022 builder"
        type: boolean
```

#### Workflow Steps

1. **Download Docker image artifact**
   - Uses `dawidd6/action-download-artifact@v6`
   - Downloads from previous `offline-prepare.yml` run

2. **Import Docker image**
   - Verifies checksum of tarball
   - Imports with `gunzip -c | docker load`
   - Verifies image is correctly loaded

3. **Verify Docker image**
   - Runs verification commands inside container
   - Confirms Packer, Ansible, and AWS CLI are working

4. **Configure AWS credentials**
   - Uses OIDC authentication via `aws-actions/configure-aws-credentials@v4`
   - 6-hour session duration (`role-duration-seconds: 21600`)

5. **Set up environment**
   - Builds list of selected builders
   - Configures Packer variables

6. **Build STIGed AMIs**
   - Runs Docker container with:
     - Repository mounted at `/workspace`
     - AWS credentials passed via environment variables
     - Build configuration via environment variables
   - Executes `make -f Makefile.spel build`

#### Usage

1. Go to **Actions** → **Build STIGed AMI's**
2. Click **Run workflow**
3. Enter the Docker image artifact name
4. Select which OS builders to run
5. Click **Run workflow**
6. Monitor build progress (2-5 hours depending on OS)

#### AWS Credentials

The workflow uses OIDC to obtain AWS credentials without storing secrets:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-region: us-east-1
    role-to-assume: arn:aws:iam::199150299627:role/Packer_Amazon
    role-duration-seconds: 21600  # 6 hours
```

The credentials are passed to the Docker container via environment variables:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

## GitLab CI Setup (Air-Gapped)

### Configuration File

**File**: `.gitlab-ci.yml`

### Pipeline Stages

The GitLab CI pipeline has 3 stages:

| Stage | Purpose | Trigger | Duration |
|-------|---------|---------|----------|
| **import** | Import Docker image from tarball | Manual | 2-3 min |
| **infra** | Create AWS infrastructure (optional) | Manual | 2-3 min |
| **build** | Build AMIs using Docker container | Manual | 2-5 hr/OS |

### CI/CD Variables

Configure in GitLab project settings (**Settings** → **CI/CD** → **Variables**):

#### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `secret` |
| `DOCKER_IMAGE_PATH` | Path to Docker tarball | `/transfer/spel-builder-*.tar.gz` |

#### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_SESSION_TOKEN` | STS session token | (none) |
| `PKR_VAR_aws_region` | AWS region | `us-gov-east-1` |
| `PKR_VAR_aws_vpc_id` | VPC ID for builds | (auto-create) |
| `PKR_VAR_aws_subnet_id` | Subnet ID for builds | (auto-create) |
| `INFRA_PREFIX` | Prefix for created resources | `spel-offline` |
| `RUN_RHEL9` | Build RHEL 9 | `false` |
| `RUN_RHEL8` | Build RHEL 8 | `false` |
| `RUN_OL9` | Build Oracle Linux 9 | `false` |
| `RUN_OL8` | Build Oracle Linux 8 | `false` |
| `RUN_AMZN2023` | Build Amazon Linux 2023 | `false` |

### Usage Workflows

#### Scenario 1: Initial Setup (First Time)

**Step 1: Transfer Docker image tarball**

```bash
# On transfer workstation
# Download artifact from GitHub Actions (spel-builder-YYYYMMDD.tar.gz)
# Transfer to air-gapped environment

# Place tarball in accessible location
cp spel-builder-*.tar.gz /transfer/
```

**Step 2: Run import job**

1. Go to **CI/CD** → **Pipelines** → **Run pipeline**
2. Set variable: `IMPORT_DOCKER=true`
3. Click **Run pipeline**
4. Manually click **▶** on `import:docker` job
5. Wait for import to complete (2-3 minutes)

**Step 3: Create AWS infrastructure (one-time)**

1. In the same pipeline, click **▶** on `infra:network`
2. Wait for completion, then run `infra:security_group`
3. Finally run `infra:iam` to create IAM role and instance profile

**Step 4: Build AMIs**

1. Set build variables (e.g., `RUN_RHEL9=true`)
2. Run pipeline
3. Click **▶** on `build:rhel9` job
4. Monitor build progress (2-5 hours)

#### Scenario 2: Subsequent Builds

After initial setup, only the import and build stages are needed:

1. Transfer new Docker image tarball (if updated)
2. Run `import:docker` job
3. Run desired `build:*` jobs

### Job Details

#### import:docker

Imports the Docker image from the transferred tarball:

```yaml
import:docker:
  stage: import
  script:
    # Find and verify tarball
    - TARBALL=$(ls -t ${DOCKER_IMAGE_PATH} | head -1)
    - sha256sum -c "${TARBALL}.sha256"  # Verify checksum
    
    # Import Docker image
    - gunzip -c "${TARBALL}" | docker load
    
    # Verify image
    - docker run --rm "spel-builder:${TAG}" packer version
    - docker run --rm "spel-builder:${TAG}" ansible --version
```

#### infra:network, infra:security_group, infra:iam

Create AWS infrastructure resources:

- **VPC** with DNS enabled
- **Internet Gateway** (required for RHUI access)
- **Public Subnet**
- **Route Table** with IGW route
- **Security Group** (SSH/WinRM access)
- **IAM Role** with EC2 permissions
- **Instance Profile** for Packer builders

#### build:* Jobs

Run AMI builds using the Docker container:

```yaml
build:rhel9:
  stage: build
  script:
    - |
      docker run --rm \
        -v "$(pwd):/workspace" \
        -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
        -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
        -e AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}" \
        -e AWS_DEFAULT_REGION="${PKR_VAR_aws_region}" \
        -e SPEL_BUILDERS="amazon-ebssurrogate.minimal-rhel-9-hvm" \
        "spel-builder:${DOCKER_IMAGE_TAG}" \
        make -f Makefile.spel build
```

## Troubleshooting

### Common Issues

#### Docker Import Fails - No Tarball Found

**Problem**: Import job can't find the Docker image tarball.

**Solution**:
```bash
# Verify tarball location
ls -lh /transfer/spel-builder-*.tar.gz

# Ensure DOCKER_IMAGE_PATH variable matches actual path
echo $DOCKER_IMAGE_PATH

# If using different path, update CI/CD variable
```

#### Checksum Verification Fails

**Problem**: SHA256 checksum doesn't match.

**Solution**:
```bash
# File may have been corrupted during transfer
# Re-transfer the tarball from GitHub Actions artifact

# Verify checksum manually
sha256sum spel-builder-*.tar.gz
cat spel-builder-*.tar.gz.sha256
```

#### AWS Credentials Expire During Build

**Problem**: Build fails after several hours with credential expiration error.

**Solution**:
```bash
# For GitHub Actions:
# Ensure role-duration-seconds is set to 21600 (6 hours)

# For IAM role:
aws iam update-role --role-name Packer_Amazon --max-session-duration 21600

# For GitLab CI with STS:
# Obtain new credentials with longer session duration
```

#### Public AMI Quota Exceeded

**Problem**: Build fails with "public AMI quota exceeded" error.

**Solution**:
```bash
# Check current quota
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-0E3CBAB9 \
  --region us-east-1

# Request increase (takes 1-3 business days)
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-0E3CBAB9 \
  --desired-value 20 \
  --region us-east-1
```

> **Note**: The build will continue even if public AMI quota is exceeded, but the AMIs will remain private.

#### Docker Container Can't Access AWS

**Problem**: Packer fails with AWS authentication errors inside container.

**Solution**:
```bash
# Verify credentials are being passed
docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  spel-builder:latest aws sts get-caller-identity

# Ensure all three variables are exported before running
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

#### Build Fails - Cannot Access Repositories

**Problem**: Packer instance can't reach RHUI repositories.

**Solution**:
```bash
# Verify VPC has Internet Gateway
aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=vpc-xxxxx"

# Verify route table has route to IGW
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxx"

# Security group must allow outbound HTTPS (443)
aws ec2 describe-security-groups --group-ids sg-xxxxx
```

### Debugging

#### View Container Logs

```bash
# Run container interactively
docker run -it --rm \
  -v "$(pwd):/workspace" \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  spel-builder:latest /bin/bash

# Inside container:
packer version
ansible --version
aws sts get-caller-identity
```

#### Check Packer Debug Output

```bash
# Enable Packer debug logging
export PACKER_LOG=1
export PACKER_LOG_PATH=/workspace/packer.log

docker run --rm \
  -v "$(pwd):/workspace" \
  -e PACKER_LOG=1 \
  -e PACKER_LOG_PATH=/workspace/packer.log \
  spel-builder:latest make -f Makefile.spel build

# Review log file
cat packer.log
```

## Best Practices

### Docker Image Management

1. **Build monthly**: Create new Docker images monthly to get updated dependencies
2. **Tag consistently**: Use date-based tags (YYYYMMDD) for traceability
3. **Verify checksums**: Always verify tarball integrity after transfer
4. **Clean old images**: Remove outdated images to save storage

### Build Optimization

1. **Sequential builds**: Run one OS build at a time to avoid resource contention
2. **Monitor quotas**: Check AMI quotas before starting builds
3. **Off-hours builds**: Schedule long builds during off-peak hours
4. **Use specific builders**: Don't run all builders unless necessary

### Security

1. **Rotate credentials**: Update AWS credentials regularly
2. **Minimal permissions**: Use IAM policies with least privilege
3. **Protect variables**: Mark CI/CD variables as "Protected" and "Masked"
4. **Audit access**: Review security group rules periodically

### Air-Gapped Environment

1. **Verify before transfer**: Run `build.yml` in GitHub Actions first to validate
2. **Document versions**: Keep manifest files for audit trail
3. **Test imports**: Verify Docker image imports correctly before builds
4. **Backup tarballs**: Keep copies of working Docker image tarballs

## Performance Metrics

### Build Times

| Workflow | Duration |
|----------|----------|
| Prepare Docker Image | 5-10 minutes |
| Import Docker Image | 2-3 minutes |
| Create Infrastructure | 2-3 minutes |

| OS Build | Minimal | Hardened |
|----------|---------|----------|
| Amazon Linux 2023 | 30-45 min | 2-3 hr |
| RHEL 9 | 45-60 min | 3-4 hr |
| RHEL 8 | 45-60 min | 3-4 hr |
| Oracle Linux 9 | 45-60 min | 3-4 hr |
| Oracle Linux 8 | 45-60 min | 3-4 hr |
| Windows Server 2016 | 60-90 min | 4-5 hr |
| Windows Server 2019 | 60-90 min | 4-5 hr |
| Windows Server 2022 | 60-90 min | 4-5 hr |

### Storage Requirements

| Component | Size |
|-----------|------|
| Docker image (gzipped) | ~305 MB |
| Docker image (uncompressed) | ~834 MB |
| Build workspace per job | 10-20 GB |
| Packer cache | 5-10 GB |

## References

- **Dockerfile**: `Dockerfile` (repository root)
- **GitHub Actions Workflows**:
  - `.github/workflows/offline-prepare.yml`
  - `.github/workflows/build.yml`
- **GitLab CI Configuration**: `.gitlab-ci.yml`
- **Build Script**: `build/build.sh`
- **Makefile**: `Makefile.spel`
- **Quick Reference**: `docs/QUICK-REFERENCE-Optimization.md`
- **Storage Optimization**: `docs/Storage-Optimization.md`
