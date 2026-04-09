# Build Documentation

This document explains the GitHub Actions workflow defined in `build.yml`, detailing the two-job architecture, infrastructure provisioning, and Docker-based AMI builds.

## GitHub Actions Workflow: `build.yml`

The `build.yml` workflow automates building STIGed AMIs (Amazon Machine Images) for the Chimera project. It uses a **two-job architecture**: an `infra` job ensures persistent AWS infrastructure exists via OpenTofu, followed by a `build` job that runs Packer inside a pre-built Docker container.

### Workflow Triggers

- **Manual Trigger** (`workflow_dispatch`): Manually triggered with inputs for Docker image artifact name, OS builder selection, air-gapped build configuration, and infrastructure prefix.

### Permissions

- **id-token**: Write permission for generating OIDC tokens.
- **contents**: Write permission for repository contents.

### Job 1: Ensure Infrastructure (`infra`)

Calls `infra-setup.yml` via `workflow_call` with `action: apply` and the specified `infra_prefix` (default: `chimera`). OpenTofu apply is idempotent — it creates infrastructure if missing, or is a no-op if it already exists.

**Outputs** (auto-discovered via `workflow_call`):

- `vpc_id` — VPC for Packer builds
- `subnet_id` — Subnet for EC2 instances
- `security_group_id` — Security group for build instances
- `instance_profile` — IAM instance profile for EC2
- `kms_key_id` — KMS key for encrypted AMIs

### Job 2: Build Chimera AMIs (`build`)

Depends on `infra` job. Uses infrastructure outputs from Job 1. Runs on `ubuntu-latest` with a 6-hour timeout.

#### Steps

1. **Checkout Repository**
   - Uses `actions/checkout@v6`

2. **Download Docker Image Artifact**
   - Uses `dawidd6/action-download-artifact@v19` to download the pre-built `chimera-builder` image from a previous `offline-prepare.yml` run

3. **Import Docker Image**
   - Decodes base64 if needed, verifies SHA256 checksum, imports with `docker load`

4. **Configure AWS Credentials**
   - Uses OIDC authentication via `aws-actions/configure-aws-credentials@v6`
   - 6-hour session duration (`role-duration-seconds: 21600`)

5. **Build STIGed AMIs**
   - Runs Docker container with repository mounted at `/workspace`
   - AWS credentials and infrastructure outputs passed via environment variables (`PKR_VAR_aws_vpc_id`, `PKR_VAR_aws_subnet_id`, etc.)
   - Executes `make build` inside the container

### Key Inputs

| Input | Description | Default |
| ------- | ----------- | --------- |
| `docker_image_artifact` | Artifact name from `offline-prepare.yml` | (required) |
| `run_rhel9`, `run_ol9`, etc. | OS builder toggles | `false` |
| `infra_prefix` | Infrastructure name prefix for OpenTofu | `chimera` |
| `airgap_mode` | Enable air-gapped build settings | `false` |
| `repo_mirror_baseurl` | Local YUM mirror URL for air-gapped builds | (empty) |

## AWS Credentials Configuration

AWS credentials are configured via OIDC to allow the workflow to interact with AWS services without storing secrets. The credentials are necessary for:

- Running OpenTofu to ensure infrastructure exists (infra job)
- Authenticating with AWS for Packer operations (build job)
- Assuming the required IAM role for accessing resources

## `build.sh` Script

The `build.sh` script orchestrates the two-phase Packer build:

- Validates required environment variables (`CHIMERA_IDENTIFIER`, `CHIMERA_VERSION`, `CHIMERA_BUILDERS`)
- Runs `packer init`, `packer validate`, and `packer build` for `chimera/minimal.pkr.hcl` (base AMIs)
- Discovers the AMI IDs produced by the minimal build
- Maps minimal builder names to hardened builder names and combines with any `WINDOWS_BUILDERS`
- Runs `packer init`, `packer validate`, and `packer build` for `chimera/hardened.pkr.hcl` (STIG-hardened AMIs)
- Exits non-zero if either phase fails
