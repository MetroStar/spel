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
│  │  Stage 2: infra  - Provision persistent AWS infrastructure via        │   │
│  │                    Terraform (one-time, from .gitlab/infra.gitlab-ci)  │   │
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

#### 2. Packer Execution IAM Permissions

The IAM role or user that **runs Packer** (the credentials passed to the Docker container) needs extensive EC2 and AMI permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PackerEC2",
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
        "ec2:DescribeVpcs",
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
    },
    {
      "Sid": "PackerIAM",
      "Effect": "Allow",
      "Action": [
        "iam:GetInstanceProfile",
        "iam:PassRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PackerServiceQuotas",
      "Effect": "Allow",
      "Action": [
        "servicequotas:GetServiceQuota"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Note**: This policy is for the credentials that **execute Packer**, not the EC2 instance profile. The instance profile permissions are created by the `infra:create` job in GitLab CI (or by the `infra` job in GitHub Actions, which calls `infra-setup.yml`).

#### 3. Terraform Execution IAM Permissions

The IAM role also needs permissions to manage infrastructure via Terraform. The `infra-setup.yml` workflow (and GitLab's `infra:create` job) runs `terraform apply` to create VPCs, subnets, security groups, IAM roles, KMS keys, and SSM resources. Add these permissions to the same role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformNetworking",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:ModifyVpcAttribute",
        "ec2:DescribeVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateVpcEndpoint",
        "ec2:DeleteVpcEndpoints",
        "ec2:ModifyVpcEndpoint",
        "ec2:DescribeVpcEndpoints",
        "ec2:DescribeVpcEndpointServices",
        "ec2:DescribePrefixLists",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeSecurityGroupRules",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DeleteTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformIAM",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:ListInstanceProfilesForRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:PassRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformKMS",
      "Effect": "Allow",
      "Action": [
        "kms:CreateKey",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:DescribeKey",
        "kms:GetKeyPolicy",
        "kms:GetKeyRotationStatus",
        "kms:ListAliases",
        "kms:ListResourceTags",
        "kms:PutKeyPolicy",
        "kms:EnableKeyRotation",
        "kms:ScheduleKeyDeletion",
        "kms:TagResource",
        "kms:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformSSM",
      "Effect": "Allow",
      "Action": [
        "ssm:CreateDocument",
        "ssm:DeleteDocument",
        "ssm:DescribeDocument",
        "ssm:GetDocument",
        "ssm:UpdateDocument",
        "ssm:UpdateDocumentDefaultVersion",
        "ssm:AddTagsToResource",
        "ssm:RemoveTagsFromResource",
        "ssm:ListTagsForResource",
        "ssm:CreateAssociation",
        "ssm:DeleteAssociation",
        "ssm:DescribeAssociation",
        "ssm:UpdateAssociation",
        "ssm:CreatePatchBaseline",
        "ssm:DeletePatchBaseline",
        "ssm:GetPatchBaseline",
        "ssm:UpdatePatchBaseline",
        "ssm:RegisterPatchBaselineForPatchGroup",
        "ssm:DeregisterPatchBaselineForPatchGroup",
        "ssm:CreateMaintenanceWindow",
        "ssm:DeleteMaintenanceWindow",
        "ssm:GetMaintenanceWindow",
        "ssm:UpdateMaintenanceWindow",
        "ssm:DescribeMaintenanceWindows",
        "ssm:RegisterTargetWithMaintenanceWindow",
        "ssm:DeregisterTargetFromMaintenanceWindow",
        "ssm:DescribeMaintenanceWindowTargets",
        "ssm:RegisterTaskWithMaintenanceWindow",
        "ssm:DeregisterTaskFromMaintenanceWindow",
        "ssm:GetMaintenanceWindowTask",
        "ssm:DescribeMaintenanceWindowTasks",
        "ssm:GetServiceSetting",
        "ssm:UpdateServiceSetting",
        "ssm:ResetServiceSetting"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformS3",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetLifecycleConfiguration",
        "s3:PutLifecycleConfiguration",
        "s3:GetBucketLogging",
        "s3:PutBucketLogging",
        "s3:GetBucketAcl",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:*:s3:::spel-*",
        "arn:*:s3:::spel-*/*"
      ]
    },
    {
      "Sid": "TerraformDynamoDB",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:TagResource"
      ],
      "Resource": "arn:*:dynamodb:*:*:table/spel-*"
    },
    {
      "Sid": "TerraformCloudWatch",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:ListTagsLogGroup",
        "logs:PutMetricFilter",
        "logs:DeleteMetricFilter",
        "logs:DescribeMetricFilters",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformSNS",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:SetTopicAttributes",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:GetSubscriptionAttributes",
        "sns:TagResource",
        "sns:UntagResource",
        "sns:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformSTS",
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

> **Note**: This policy covers Terraform state backend (S3 + DynamoDB), networking, IAM, KMS, SSM (documents, associations, patch baselines, maintenance windows, DHMC), CloudWatch (logs, metric filters, alarms), SNS, and STS resources created by the `infra/` root module. For GovCloud, the ARN partition resolves automatically.

#### 4. EC2 Instance Profile Permissions (Created by Pipeline)

The Terraform root module at `infra/` creates an instance profile with minimal permissions for the Packer-launched EC2 instances:

- **SSM Access**: For Session Manager connectivity (if using SSH via SSM)
- **S3 Access**: To SSM buckets for agent operation
- **CloudWatch Logs**: For optional logging

These are created automatically when you run the `infra:create` job (GitLab) or when `build.yml` calls `infra-setup.yml` (GitHub Actions).

### GitHub Actions Prerequisites

#### 1. GitHub OIDC Identity Provider

GitHub Actions uses [OpenID Connect (OIDC)](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) to obtain short-lived AWS credentials without storing secrets. Create the OIDC provider in each AWS account (Commercial and/or GovCloud):

```bash
# Create the GitHub OIDC provider (one-time per AWS account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Verify
aws iam list-open-id-connect-providers
```

> **Note**: The thumbprint may change over time. See [GitHub's documentation](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) for the current value. AWS also validates the certificate chain automatically.

#### 2. IAM Role for GitHub Actions (OIDC)

Create an IAM role that GitHub Actions can assume via OIDC. The trust policy restricts access to your specific repository and branch:

```bash
# Create the trust policy
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:*"
        }
      }
    }
  ]
}
EOF

# Replace placeholders
sed -i 's/ACCOUNT_ID/123456789012/' trust-policy.json
sed -i 's|OWNER/REPO|MetroStar/spel|' trust-policy.json

# Create the role
aws iam create-role \
  --role-name Packer_Amazon \
  --assume-role-policy-document file://trust-policy.json \
  --max-session-duration 21600

# Attach the Packer and Terraform permissions (from sections 2 and 3 above)
aws iam put-role-policy \
  --role-name Packer_Amazon \
  --policy-name PackerBuildPolicy \
  --policy-document file://packer-policy.json

aws iam put-role-policy \
  --role-name Packer_Amazon \
  --policy-name TerraformInfraPolicy \
  --policy-document file://terraform-policy.json
```

> **Security**: The `sub` condition restricts which repository (and optionally branch) can assume the role. Use `repo:OWNER/REPO:ref:refs/heads/BRANCH` to restrict to a specific branch, or `repo:OWNER/REPO:*` to allow any branch.

> **GovCloud**: For GovCloud accounts, replace the ARN partition with `aws-us-gov` (e.g., `arn:aws-us-gov:iam::ACCOUNT_ID:oidc-provider/...`).

#### 3. Store Role ARN

The `infra-setup.yml` workflow reads the role ARN from `vars.AWS_ROLE_ARN` or `secrets.AWS_ROLE_ARN`. Store it in your GitHub repository:

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Add a **Repository variable** named `AWS_ROLE_ARN` with value `arn:aws:iam::ACCOUNT_ID:role/Packer_Amazon`

Alternatively, store it as a **Repository secret** if you prefer to keep the account ID hidden.

#### 4. Submodules

Ensure `vendor/amigen8` and `vendor/amigen9` submodules are initialized:

```bash
git submodule update --init --recursive
```

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
| **infra** | Provision persistent AWS infrastructure via Terraform (one-time) | Manual | 2-3 min |
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
| `PKR_VAR_aws_vpc_id` | VPC ID for builds | (from Terraform) |
| `PKR_VAR_aws_subnet_id` | Subnet ID for builds | (from Terraform) |
| `PKR_VAR_aws_kms_key_id` | KMS key ARN for CMK-encrypted AMIs | (none) |
| `INFRA_PREFIX` | Prefix for created resources | `spel` |
| `RUN_RHEL9` | Build RHEL 9 | `false` |
| `RUN_RHEL8` | Build RHEL 8 | `false` |
| `RUN_OL9` | Build Oracle Linux 9 | `false` |
| `RUN_OL8` | Build Oracle Linux 8 | `false` |
| `RUN_AMZN2023` | Build Amazon Linux 2023 | `false` |

#### Air-Gapped Linux Build Variables

These variables configure Linux builds to use local repository mirrors instead of RHUI:

| Variable | Description | Default |
|----------|-------------|---------|
| `REPO_MIRROR_BASEURL` | Local yum mirror base URL | (none) |
| `AMIGEN_CROSS_DISTRO` | Skip RHUI package auto-detection | `false` |
| `AMIGEN_USE_DEFAULT_REPOS` | Use default RHUI repositories | `true` |
| `AMIGEN_REPO_NOSIGNATURE` | Skip RPM signature check for repo RPMs | `false` |
| `AMIGEN8_REPO_NAMES` | JSON array of EL8 repo names | (none) |
| `AMIGEN9_REPO_NAMES` | JSON array of EL9 repo names | (none) |
| `AMIGEN8_EXTRA_RPMS` | JSON array of extra RPMs for EL8 | (none) |
| `AMIGEN9_EXTRA_RPMS` | JSON array of extra RPMs for EL9 | (none) |
| `PKR_VAR_amigen8_repo_sources` | JSON array of EL8 repo source RPM URLs | (none) |
| `PKR_VAR_amigen9_repo_sources` | JSON array of EL9 repo source RPM URLs | (none) |

> **Important**: For air-gapped Linux builds, you must create a repo configuration RPM
> that installs your mirror settings into the chroot. See [Air-Gapped Linux Builds](#air-gapped-linux-builds).

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

1. In the same pipeline, click **▶** on `infra:create`
2. Wait for completion — this single Terraform job provisions all infrastructure (VPC, subnets, security groups, IAM roles, KMS, SSM)
3. Infrastructure outputs are exported as `infra.env` dotenv artifact for build jobs

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

#### infra:create

Provisions all AWS infrastructure via the Terraform root module at `infra/`:

- **VPC** with DNS enabled
- **Internet Gateway** (required for RHUI access)
- **Public Subnet**
- **Route Table** with IGW route
- **Security Group** (SSH/WinRM access)
- **IAM Role** with EC2 permissions
- **Instance Profile** for Packer builders
- **KMS Key** for encrypted AMIs
- **SSM infrastructure** (VPC endpoints, documents, etc.)

Defined in `.gitlab/infra.gitlab-ci.yml` and included by `.gitlab-ci.yml`.

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
        -e PKR_VAR_aws_region="${PKR_VAR_aws_region}" \
        -e SPEL_BUILDERS="amazon-ebssurrogate.minimal-rhel-9-hvm" \
        "spel-builder:${DOCKER_IMAGE_TAG}" \
        make -f Makefile.spel build
```

> **Note**: The workflow automatically sets `PKR_VAR_aws_ami_regions` to include the build region.
> Set it explicitly to copy AMIs to multiple regions (e.g., `["us-gov-east-1","us-gov-west-1"]`).

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
2. **Off-hours builds**: Schedule long builds during off-peak hours
3. **Use specific builders**: Don't run all builders unless necessary

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

## Air-Gapped Linux Builds

In air-gapped environments, Linux AMI builds cannot access RHUI (Red Hat Update Infrastructure)
or public package repositories. You must configure local repository mirrors and create a repo
configuration RPM.

### Understanding the Build Process

The SPEL build creates a chroot environment at `/mnt/ec2-root` where the AMI filesystem is built.
This chroot is completely separate from the builder host and does **not** inherit repository
configurations. The `OSpackages.sh` script:

1. Auto-detects packages from the builder host's `/etc/yum.repos.d/` (including RHUI clients)
2. Installs repo configuration RPMs into the chroot (via `-r` flag)
3. Uses those repos to install the base system

In air-gapped environments, step 1 fails because it tries to install `rh-amazon-rhui-client` which
requires RHUI access. The solution is to skip auto-detection and provide your own repo configuration.

### Step 1: Create a Repository Configuration RPM

Create an unsigned RPM that installs your mirror configuration:

```bash
# Create RPM build structure
mkdir -p ~/rpmbuild/{SPECS,SOURCES,BUILD,RPMS,SRPMS}

# Create spec file for RHEL 8
cat > ~/rpmbuild/SPECS/myorg-release-el8.spec << 'EOF'
Name:           myorg-release
Version:        1.0
Release:        1.el8
Summary:        Organization Repository Configuration
License:        MIT
BuildArch:      noarch

%description
Repository configuration for internal RHEL 8 mirrors.

%install
mkdir -p %{buildroot}/etc/yum.repos.d

cat > %{buildroot}/etc/yum.repos.d/myorg-rhel.repo << 'REPO'
[myorg-rhel8-baseos]
name=MyOrg RHEL 8 BaseOS Mirror
baseurl=http://mirror.internal.mil/rhel8/baseos
enabled=1
gpgcheck=0

[myorg-rhel8-appstream]
name=MyOrg RHEL 8 AppStream Mirror
baseurl=http://mirror.internal.mil/rhel8/appstream
enabled=1
gpgcheck=0

[myorg-rhel8-epel]
name=MyOrg EPEL 8 Mirror
baseurl=http://mirror.internal.mil/epel8
enabled=1
gpgcheck=0
REPO

%files
/etc/yum.repos.d/myorg-rhel.repo
EOF

# Build unsigned RPM (no GPG signing required)
rpmbuild -bb ~/rpmbuild/SPECS/myorg-release-el8.spec

# Result: ~/rpmbuild/RPMS/noarch/myorg-release-1.0-1.el8.noarch.rpm
```

Create a similar spec file for RHEL 9 with `Release: 1.el9` and appropriate repo URLs.

### Step 2: Host the RPM on Your Mirror

Upload the repo configuration RPM to your internal mirror:

```bash
cp ~/rpmbuild/RPMS/noarch/myorg-release-1.0-1.el8.noarch.rpm /path/to/mirror/repos/
cp ~/rpmbuild/RPMS/noarch/myorg-release-1.0-1.el9.noarch.rpm /path/to/mirror/repos/
```

### Step 3: Configure GitLab CI/CD Variables

Set these variables in **Settings** → **CI/CD** → **Variables**:

| Variable | Value | Notes |
|----------|-------|-------|
| `AMIGEN_CROSS_DISTRO` | `true` | Skips RHUI package auto-detection |
| `AMIGEN_USE_DEFAULT_REPOS` | `false` | Disables default RHUI repositories |
| `AMIGEN_REPO_NOSIGNATURE` | `true` | Allows unsigned repo RPMs |
| `AMIGEN8_REPO_NAMES` | `["myorg-rhel8-baseos","myorg-rhel8-appstream"]` | Your EL8 repo names |
| `AMIGEN9_REPO_NAMES` | `["myorg-rhel9-baseos","myorg-rhel9-appstream"]` | Your EL9 repo names |
| `PKR_VAR_amigen8_repo_sources` | `["http://mirror.internal.mil/repos/myorg-release-1.0-1.el8.noarch.rpm"]` | EL8 repo RPM URL |
| `PKR_VAR_amigen9_repo_sources` | `["http://mirror.internal.mil/repos/myorg-release-1.0-1.el9.noarch.rpm"]` | EL9 repo RPM URL |

### Troubleshooting Air-Gapped Linux Builds

**Error: "No package artifactory-rhel8 available"**

This means cross-distro mode is not enabled. The build is trying to install packages auto-detected
from the builder host. Verify `AMIGEN_CROSS_DISTRO=true` is set.

**Error: "Failed installing staged RPMs" with signature error**

The repo RPM is unsigned. Set `AMIGEN_REPO_NOSIGNATURE=true` to skip signature verification.

**Debug output shows `AMIGENCROSSDISTRO=false`**

The environment variable is not reaching the build script. Check that:
1. `AMIGEN_CROSS_DISTRO` is set in GitLab CI/CD Variables
2. The variable is not marked as "Protected" if running on unprotected branches

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
