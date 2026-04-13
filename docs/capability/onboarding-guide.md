# Onboarding Guide

> **Chimera Platform** — From zero to your first hardened AMI.

This guide walks a new delivery team through environment setup, first build, and validation. Follow it sequentially; each section builds on the previous one.

## Prerequisites Checklist

Before starting, confirm you have:

- [ ] **AWS account** — Commercial or GovCloud, with admin-level access for initial setup
- [ ] **IAM OIDC provider + role** — An OIDC identity provider for GitHub Actions or GitLab, and an IAM role with permissions for EC2, IAM, KMS, S3, SSM, and VPC. `MaxSessionDuration` must be ≥ 21600. See [CI-CD-Setup — IAM Configuration](../CI-CD-Setup.md#aws-iam-configuration) for exact policies.
- [ ] **Docker** — Installed on your workstation or CI runner (`docker version` succeeds)
- [ ] **CI/CD runner** — GitHub Actions (hosted or self-hosted) or GitLab Runner with Docker and the `chimera-offline-runner` tag
- [ ] **Iron Bank credentials** — Username and CLI token from [registry1.dso.mil](https://registry1.dso.mil) (for Docker image build; tokens expire every 6 months)
- [ ] **Repository access** — Clone of this repo on your workstation
- [ ] **OpenTofu** *(optional)* — Only required if running infrastructure commands locally instead of through CI/CD (`tofu version` succeeds)

### Air-Gapped Additional Prerequisites

- [ ] **Docker image tarball** — Pre-built `chimera-builder-YYYYMMDD.tar.gz` transferred from a connected environment
- [ ] **Local YUM mirror** — URL to an internal mirror hosting RHEL/EL packages
- [ ] **GitLab Runner** — With Docker installed, tagged `chimera-offline-runner`, and access to the `/transfer/` directory

## Step 1 — Provision Infrastructure (30 minutes)

### 1a. Configure IAM Prerequisites (one-time)

Before infrastructure can be provisioned — whether by CI/CD or manually — you need an IAM role with sufficient permissions and an OIDC identity provider so the pipeline can authenticate.

1. **Create an IAM OIDC identity provider** for GitHub Actions or GitLab in each target AWS account.
2. **Create an IAM role** that trusts the OIDC provider with permissions for EC2, IAM, KMS, S3, SSM, VPC, and OpenTofu state management. Set `MaxSessionDuration` to at least **21600** (6 hours):
   ```bash
   aws iam update-role --role-name YourRole --max-session-duration 21600
   ```
3. **Store the role ARN** as a CI/CD secret (`AWS_ROLE_ARN` in GitHub, `CI_AWS_ROLE_ARN` in GitLab).

See [CI-CD-Setup — IAM Configuration](../CI-CD-Setup.md#aws-iam-configuration) for exact IAM policies (Packer execution + OpenTofu execution + instance profile).

### 1b. Provision via CI/CD (recommended)

The CI/CD pipelines automate backend bootstrap, tfvars generation, and `tofu apply`. No local OpenTofu installation required.

**GitHub Actions** — The `infra-setup.yml` workflow handles everything. `build.yml` calls it automatically before every build (`action=apply` is idempotent), but you can also run it manually:

1. Go to **Actions** → **Infrastructure Setup** → **Run workflow**
2. Set `action` to **apply**, choose your `aws_region`, and toggle `airgap_mode` if needed
3. Wait ~5 minutes — the workflow bootstraps the backend, generates tfvars, and runs `tofu apply`

The workflow exports `vpc_id`, `subnet_id`, `security_group_id`, `instance_profile`, and `kms_key_id` as outputs, which `build.yml` consumes automatically.

**GitLab CI (air-gapped)** — Run the `infra:create` job from `.gitlab/infra.gitlab-ci.yml`:

1. Go to **CI/CD** → **Pipelines** → **Run pipeline**
2. Set `CREATE_INFRASTRUCTURE=true`
3. Click ▶ on `infra:create`

The job bootstraps the backend, generates `ci.auto.tfvars` (with `AIRGAP_MODE` toggles), applies infrastructure, and exports outputs as a `dotenv` artifact for build jobs.

**Feature toggles** — Both pipelines auto-generate tfvars based on `airgap_mode`. Key toggles:

| Variable | Default | Air-Gapped |
|----------|---------|------------|
| `enable_internet_gateway` | `true` | `false` |
| `enable_packer_endpoints` | `false` | `true` |
| `enable_vpc_endpoints` | `true` | `true` |
| `vpc_cidr` | `10.0.0.0/16` | (your CIDR) |
| `subnet_cidr` | `10.0.1.0/24` | (your CIDR) |

### 1c. Alternative: Provision via Local CLI

If you prefer to run OpenTofu locally (e.g., for initial testing or environments without CI/CD):

```bash
cd infra/

# Copy the backend template and edit with your values
cp backend.tf.example backend.tf

# Bootstrap the S3 + DynamoDB state backend (first time only)
./bootstrap-backend.sh

# Initialize, review, and apply
tofu init
tofu plan
tofu apply
```

Air-gapped example:
```bash
tofu apply \
  -var="enable_internet_gateway=false" \
  -var="enable_packer_endpoints=true" \
  -var="aws_region=us-gov-west-1"
```

### 1d. Capture Outputs

CI/CD exports these automatically — build jobs receive them as workflow outputs (GitHub) or dotenv artifacts (GitLab). For local builds, run:

```bash
tofu output
```

| Output | Used For |
|--------|----------|
| `vpc_id` | Packer `aws_vpc_id` |
| `subnet_id` | Packer `aws_subnet_id` |
| `security_group_id` | Packer `aws_security_group_id` |
| `instance_profile_name` | Packer `aws_iam_instance_profile` |
| `kms_key_arn` | Packer `aws_kms_key_id` |

## Step 2 — Build the Docker Image

> **Skip this step** if you already have a `chimera-builder-YYYYMMDD.tar.gz` tarball.

### Via GitHub Actions

1. Go to **Actions** → **Prepare Offline Docker Image** → **Run workflow**
2. Optionally set `image_tag` (defaults to `YYYYMMDD`)
3. Wait 5–10 minutes
4. Download the artifact: `chimera-builder-YYYYMMDD`

The artifact contains:
- `chimera-builder-YYYYMMDD.tar.gz` — Docker image (~305 MB)
- `chimera-builder-YYYYMMDD.tar.gz.sha256` — Checksum
- Base64-encoded copy (for SharePoint transfer)

### Via Local Docker Build

```bash
# From repo root
docker build -t chimera-builder:$(date +%Y%m%d) .

# Export as tarball
docker save chimera-builder:$(date +%Y%m%d) | gzip > chimera-builder-$(date +%Y%m%d).tar.gz
```

## Step 3 — Build Your First AMI

### Option A: Connected Build (GitHub Actions)

1. Go to **Actions** → **Build STIGed AMI's** → **Run workflow**
2. Enter the Docker image artifact name (e.g., `chimera-builder-20260413`)
3. Select your target region
4. Enable one or more OS targets (e.g., `run_rhel9: true`)
5. Click **Run workflow** and wait 2–5 hours

The workflow automatically calls `infra-setup.yml` (idempotent) before building.

### Option B: Connected Build (Local Docker)

```bash
# Import the Docker image
gunzip -c chimera-builder-*.tar.gz | docker load

# Run a single-OS build
docker run --rm \
  -v "$(pwd):/workspace" \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e AWS_DEFAULT_REGION=us-gov-west-1 \
  -e CHIMERA_IDENTIFIER=chimera \
  -e CHIMERA_VERSION=2026.04.1 \
  -e CHIMERA_BUILDERS=amazon-ebssurrogate.minimal-rhel-9-hvm \
  -e WINDOWS_BUILDERS="" \
  chimera-builder:latest make build
```

`CHIMERA_IDENTIFIER` and `CHIMERA_VERSION` are **required** — the Makefile will refuse to run without them.

### Option C: Air-Gapped Build (GitLab CI)

**Transfer the Docker image:**

```bash
# From connected environment to air-gapped GitLab runner:
scp chimera-builder-*.tar.gz runner:/transfer/
```

**Run the pipeline:**

1. Go to **CI/CD** → **Pipelines** → **Run pipeline**
2. Click ▶ on `import:docker` — loads the Docker image from `/transfer/`
3. Click ▶ on `infra:create` — provisions AWS infrastructure
4. Click ▶ on the desired build job (e.g., `build:rhel9`)

**Required GitLab CI/CD variables:**

| Variable | Value |
|----------|-------|
| `PKR_VAR_aws_region` | `us-gov-west-1` |
| `AIRGAP_MODE` | `true` |
| `REPO_MIRROR_BASEURL` | `http://mirror.internal.mil` (your mirror URL) |
| AWS credentials | `CI_AWS_ROLE_ARN` (OIDC) or `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` |

**Additional air-gapped variables** (set as needed):

| Variable | Purpose |
|----------|---------|
| `AMIGEN9_REPO_NAMES` | JSON array of repo names (e.g., `["rhel-9-baseos","rhel-9-appstream"]`) |
| `AMIGEN9_REPO_SOURCES` | JSON array of repo-config RPM URLs |
| `AMIGEN9_EXTRA_RPMS` | JSON array of additional RPMs |
| `CHIMERA_GOSS_BINARY_URL` | URL to Goss binary for STIG auditing |

## Step 4 — Validate

After the build completes, verify the hardened AMI works correctly.

### 4a. Launch a Test Instance

Launch an EC2 instance from the new hardened AMI in the same VPC.

### 4b. Run SSM Validation

```bash
# From your workstation (requires AWS CLI configured):
INSTANCE_ID=i-0abc123def456  # your test instance

# Test 1: Verify SSM registration
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus'
# Expected: "Online"

# Test 2: Run a command via SSM
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo SSM is working"]' \
  --output text --query 'Command.CommandId'

# Test 3: Check FIPS mode (Linux)
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /proc/sys/crypto/fips_enabled"]'
# Expected: 1
```

The full validation script is at `tests/test-ssm-validation.sh`.

### 4c. Review Compliance Artifacts

- **OpenSCAP report**: Downloaded as a CI/CD build artifact (`oscap-report.html`)
- **Goss delta**: Downloaded as a CI/CD build artifact (JSON showing pre/post remediation)

## Step 5 — Distribute

### Copy AMI to Additional Regions

Set the `aws_ami_regions` Packer variable to a JSON array:

```bash
PKR_VAR_aws_ami_regions='["us-gov-east-1","us-gov-west-1"]'
```

### Update Downstream Consumers

After validating the new AMI:

1. Update launch templates or Auto Scaling groups to reference the new AMI ID
2. Update any CloudFormation / Terraform configurations that reference the AMI
3. Roll instances on next deployment cycle

## Common Gotchas

These are the top issues new teams encounter. Full details in the [Troubleshooting Guide](troubleshooting-guide.md).

| Issue | Quick Fix |
|-------|-----------|
| **Build fails after 1 hour** | IAM role `MaxSessionDuration` must be ≥ 21600 (6 hours). Run: `aws iam update-role --role-name YourRole --max-session-duration 21600` |
| **Packer can't find source AMI** | Verify the `source_ami_filter` owner ID matches your region (GovCloud AMI owners differ from Commercial) |
| **RPM signature verification fails** | In air-gapped environments with unsigned mirrors, set `AMIGEN_REPO_NOSIGNATURE=true` |
| **Instance not appearing in SSM** | Check: (1) instance profile attached, (2) VPC endpoints exist (ssm, ssmmessages, ec2messages), (3) DHMC is enabled |
| **Docker import fails on GitLab runner** | Verify tarball integrity with `sha256sum -c *.sha256`. If transferred via SharePoint (base64), ensure no line-break corruption during decode. |

## Next Steps

- Review the [Operating Model](operating-model.md) for Day 2+ operations
- Read the [Runbook](runbook.md) for steady-state procedures
- See the [Template Package](template-package.md) to customize for your program
