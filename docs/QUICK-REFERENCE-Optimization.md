# Docker-Based CI/CD Quick Reference

Quick reference guide for Chimera Docker-based builds.

## Overview

The Chimera build system uses Docker containers with all dependencies baked in:

| Component | Size | Purpose |
|-----------|------|---------|
| Docker image (gzipped) | ~305 MB | Portable tarball for transfer |
| Docker image (uncompressed) | ~834 MB | Ready-to-run container |
| Contains | Packer, Ansible, AWS CLI, all plugins and roles | No runtime downloads |

## GitHub Actions Quick Start

### Step 1: Build Docker Image

```bash
# Go to: Actions → Prepare Offline Docker Image → Run workflow
# Wait 5-10 minutes
# Download artifact: chimera-builder-YYYYMMDD
```

### Step 2: Build AMIs

```bash
# Go to: Actions → Build STIGed AMI's → Run workflow
# Enter artifact name: chimera-builder-20251230
# Select builders (run_rhel9, run_ol9, etc.)
# Wait 2-5 hours per OS
```

## GitLab CI Quick Start (Air-Gapped)

### Initial Setup (One-Time)

```bash
# 1. Transfer Docker tarball to air-gapped environment
cp chimera-builder-*.tar.gz /transfer/

# 2. Import Docker image
# GitLab: CI/CD → Pipelines → Run pipeline
# Set: IMPORT_DOCKER=true
# Click ▶ on import:docker job

# 3. Create infrastructure
# Click ▶ on infra:create (single OpenTofu job provisions all infrastructure)
```

### Monthly Builds

```bash
# GitLab: CI/CD → Pipelines → Run pipeline
# Set desired builders: RUN_RHEL9=true, RUN_OL9=true, etc.
# Click ▶ on build:* jobs
# Wait 2-5 hours per OS
```

## CI/CD Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_ACCESS_KEY_ID` | AWS access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `secret...` |
| `DOCKER_IMAGE_PATH` | Path to tarball | `/transfer/chimera-builder-*.tar.gz` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AWS_SESSION_TOKEN` | STS session token | (none) |
| `PKR_VAR_aws_region` | AWS region | `us-gov-east-1` |
| `RUN_RHEL9` | Build RHEL 9 | `false` |
| `RUN_RHEL8` | Build RHEL 8 | `false` |
| `RUN_OL9` | Build Oracle Linux 9 | `false` |
| `RUN_OL8` | Build Oracle Linux 8 | `false` |
| `RUN_AMZN2023` | Build Amazon Linux 2023 | `false` |
| `CHIMERA_GOSS_BINARY_URL` | Goss binary URL for air-gapped STIG audit | (none) |

## Prerequisites

### 1. IAM Role Session Duration (Required)

```bash
# Must be >= 21600 seconds (6 hours) for long builds
aws iam update-role --role-name Packer_Amazon --max-session-duration 21600

# Verify
aws iam get-role --role-name Packer_Amazon --query 'Role.MaxSessionDuration'
```

## Build Times

| Operating System | Minimal | Hardened |
|-----------------|---------|----------|
| Amazon Linux 2023 | 30-45 min | 2-3 hr |
| RHEL 9 | 45-60 min | 3-4 hr |
| RHEL 8 | 45-60 min | 3-4 hr |
| Oracle Linux 9 | 45-60 min | 3-4 hr |
| Oracle Linux 8 | 45-60 min | 3-4 hr |
| Windows Server | 60-90 min | 4-5 hr |

## Pipeline Stages (GitLab CI)

| Stage | Duration | Trigger | Purpose |
|-------|----------|---------|---------|
| import | 2-3 min | Manual | Import Docker image from tarball |
| infra | 2-3 min | Manual | Create AWS infrastructure (one-time) |
| build | 2-5 hr/OS | Manual | Build AMI images |

## Troubleshooting

### Docker Import Fails

```bash
# Verify tarball exists
ls -lh /transfer/chimera-builder-*.tar.gz

# Verify checksum
sha256sum -c chimera-builder-*.tar.gz.sha256
```

### AWS Credentials Expire

```bash
# Ensure IAM role has 6-hour max session duration
aws iam get-role --role-name Packer_Amazon --query 'Role.MaxSessionDuration'
# If < 21600, update it:
aws iam update-role --role-name Packer_Amazon --max-session-duration 21600
```

### Build Can't Access Repositories

```bash
# IGW-enabled (default): verify Internet Gateway
aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=vpc-xxxxx"

# Air-gapped (no IGW): verify VPC endpoints for Packer and SSM
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'VpcEndpoints[].ServiceName'
# Expected: ec2, sts, ssm, ssmmessages, ec2messages, logs, kms, s3
# Also ensure REPO_MIRROR_BASEURL is set to your local mirror
```

## Quick Commands

### Run Docker Container Locally

```bash
# Import image
gunzip -c chimera-builder-*.tar.gz | docker load

# Run interactively
docker run -it --rm \
  -v "$(pwd):/workspace" \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  chimera-builder:latest /bin/bash

# Build AMIs
docker run --rm \
  -v "$(pwd):/workspace" \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e CHIMERA_BUILDERS="amazon-ebssurrogate.minimal-rhel-9-hvm" \
  chimera-builder:latest make build
```

### Verify Docker Image

```bash
docker run --rm chimera-builder:latest packer version
docker run --rm chimera-builder:latest ansible --version
docker run --rm chimera-builder:latest aws --version
```

## Storage Requirements

| Component | Size |
|-----------|------|
| Docker tarball (gzipped) | ~305 MB |
| Docker image (imported) | ~834 MB |
| Build workspace per job | 10-20 GB |
| Packer cache | 5-10 GB |

## See Also

- [CI-CD-Setup.md](CI-CD-Setup.md) - Full setup documentation
- [Dockerfile](../Dockerfile) - Docker image definition
- [.github/workflows/offline-prepare.yml](../.github/workflows/offline-prepare.yml) - Build Docker image
- [.github/workflows/build.yml](../.github/workflows/build.yml) - Build AMIs
- [.gitlab-ci.yml](../.gitlab-ci.yml) - Air-gapped builds
