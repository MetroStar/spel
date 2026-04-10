# Chimera

Build STIG-hardened, LVM-partitioned Amazon Machine Images for Enterprise Linux.

Chimera produces AMIs where every DISA STIG filesystem-separation requirement is satisfied from first boot. No post-launch repartitioning needed. Builds run entirely through CI/CD — GitHub Actions or GitLab CI — using a self-contained Docker image with all dependencies baked in.

## Supported Builds

| OS | Builder Name |
| ---- | -------------- |
| RHEL 9 | `amazon-ebssurrogate.minimal-rhel-9-hvm` |
| RHEL 8 | `amazon-ebssurrogate.minimal-rhel-8-hvm` |
| Oracle Linux 9 | `amazon-ebssurrogate.minimal-ol-9-hvm` |
| Oracle Linux 8 | `amazon-ebssurrogate.minimal-ol-8-hvm` |
| Rocky Linux 9 | `amazon-ebssurrogate.minimal-rl-9-hvm` |
| Alma Linux 9 | `amazon-ebssurrogate.minimal-alma-9-hvm` |
| Amazon Linux 2023 | `amazon-ebssurrogate.minimal-amzn-2023-hvm` |
| Windows Server 2019 | `amazon-ebs.hardened-windows-2019` |
| Windows Server 2022 | `amazon-ebs.hardened-windows-2022` |

Each Linux build produces two AMIs: a **minimal** base image and a **hardened** image with STIG lockdowns applied via Ansible roles or the AWS STIG script.

## Building AMIs with GitHub Actions

The GitHub Actions pipeline has four workflows. The three build workflows are triggered manually via `workflow_dispatch`; a fourth runs automatically to monitor credential health.

### Prerequisites

1. **Iron Bank credentials** — Store `IRONBANK_USERNAME` and `IRONBANK_PASSWORD` as repository secrets. These are required to pull the Rocky Linux 9 base image used in the Docker build. **Iron Bank CLI tokens expire every 6 months.** The `ironbank-token-check.yml` workflow runs monthly to verify they are still valid and alerts on failure. To renew: log in to <https://registry1.dso.mil> → User Profile → CLI Token → Regenerate, then update the `IRONBANK_PASSWORD` secret.
2. **AWS OIDC provider** — Configure an [IAM OIDC identity provider](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) for GitHub Actions in your AWS account.
3. **IAM role** — Create a role that trusts the GitHub OIDC provider with permissions for EC2, IAM, KMS, S3, SSM, and VPC. Set `MaxSessionDuration` to at least **21600** (6 hours):

   ```bash
   aws iam update-role --role-name YourRole --max-session-duration 21600
   ```

4. Store the role ARN as the `AWS_ROLE_ARN` repository secret (or however your workflow references it).

### Step 1 — Build the Docker Image (`offline-prepare.yml`)

Run the **Prepare Offline Docker Image** workflow. It builds the `chimera-builder` container with Packer, Ansible, AWS CLI, and all vendored scripts baked in, then exports it as a tarball artifact.

| Input | Description |
| ------- | ------------- |
| `image_tag` | Docker image tag (defaults to `YYYYMMDD`) |

The artifact (`chimera-builder-YYYYMMDD`) is retained for 30 days and includes both a binary tarball and a base64-encoded copy for SharePoint transfer to air-gapped environments.

### Step 2 — Provision Infrastructure (`infra-setup.yml`)

This workflow manages all AWS infrastructure via OpenTofu. `build.yml` calls it automatically before every build (`action=apply` is idempotent), but you can also run it manually to plan, apply, or destroy.

| Input | Description |
| ------- | ------------- |
| `action` | `plan`, `apply`, `destroy`, or `status` |
| `aws_region` | Target region |
| `vpc_cidr` | VPC CIDR (default `10.0.0.0/16`) |
| `subnet_cidr` | Subnet CIDR (default `10.0.1.0/24`) |
| `airgap_mode` | Disables internet gateway, enables EC2 + STS VPC endpoints |
| `destroy_confirmation` | Type `destroy` to confirm teardown |

Resources created: VPC, subnet, security group, internet gateway (unless air-gapped), VPC endpoints, IAM role/instance profile, KMS CMK, S3 bucket, CloudWatch log group, SSM documents.

### Step 3 — Build AMIs (`build.yml`)

Run the **Build STIGed AMI's** workflow. It downloads the Docker image artifact from Step 1, ensures infrastructure via Step 2, and runs Packer inside the container.

| Input | Description |
| ------- | ------------- |
| `docker_image_artifact` | Artifact name from Step 1 (e.g., `chimera-builder-20250101`) |
| `aws_region` | Target region (`us-east-1`, `us-gov-west-1`, etc.) |
| `run_amzn2023` | Build Amazon Linux 2023 |
| `run_ol9` / `run_rhel9` | Build Oracle Linux 9 / RHEL 9 |
| `run_ol8` / `run_rhel8` | Build Oracle Linux 8 / RHEL 8 |
| `run_ws2019` / `run_ws2022` | Build Windows Server 2019 / 2022 |

**Air-gapped inputs** (set these when building in isolated networks):

| Input | Description |
| ------- | ------------- |
| `airgap_mode` | Master toggle — sets `cross_distro=true`, `use_default_repos=false`, `repo_nosignature=true`, `sslverify_disable=true` |
| `repo_mirror_baseurl` | Local YUM mirror URL (e.g., `http://mirror.internal.mil`) |
| `amigen8_repo_names` | JSON array of EL8 repo names (e.g., `["rhel-8-baseos","rhel-8-appstream"]`) |
| `amigen9_repo_names` | JSON array of EL9 repo names |
| `amigen8_repo_sources` / `amigen9_repo_sources` | JSON arrays of repo-config RPM URLs |
| `amigen8_extra_rpms` / `amigen9_extra_rpms` | JSON arrays of extra RPMs (exclude RHUI packages) |
| `goss_binary_url` | URL to Goss binary for STIG auditing |

## Building AMIs with GitLab CI

The GitLab CI pipeline is designed for air-gapped environments where the Docker image is pre-built and transferred offline.

### GitLab Prerequisites

1. **Docker image tarball** — Build using the GitHub Actions `offline-prepare.yml` workflow (or `docker build` + `docker save` locally).
2. **Transfer** — Copy the tarball to the GitLab runner at the path specified by `DOCKER_IMAGE_PATH` (default: `/transfer/chimera-builder-*.tar.gz`). Both binary tarballs and base64-encoded files (for SharePoint transfer) are supported.
3. **GitLab Runner** — Must have Docker installed. Tag it with `chimera-offline-runner`.
4. **AWS credentials** — Choose one:
   - **OIDC federation** (recommended): Set `CI_AWS_ROLE_ARN` as a CI/CD variable. Requires GitLab 15.7+ with an IAM OIDC provider configured for your GitLab instance.
   - **Static keys**: Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as CI/CD variables.

### Pipeline Stages

| Stage | Job | Description |
| ------- | ----- | ------------- |
| import | `import:docker` | Loads Docker image from tarball (verifies checksums) |
| infra | `infra:create` / `infra:destroy` | OpenTofu infrastructure (from `.gitlab/infra.gitlab-ci.yml`) |
| build | `build:amzn2023`, `build:rhel9`, etc. | Individual OS builds (manual trigger) |
| build | `build:all` | All builders at once (auto on tagged releases) |
| test | SSM validation | Optional SSM connectivity tests |

### Key Variables

Set these in **Settings → CI/CD → Variables** or override per-pipeline:

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `PKR_VAR_aws_region` | `us-gov-west-1` | Target AWS region |
| `DOCKER_IMAGE_PATH` | `/transfer/chimera-builder-*.tar.gz` | Path to Docker image tarball |
| `AIRGAP_MODE` | `true` | Disables IGW, enables VPC endpoints, scopes SG to VPC CIDR |
| `REPO_MIRROR_BASEURL` | (empty) | Local YUM mirror URL |
| `AMIGEN_CROSS_DISTRO` | `false` | Skip RHUI auto-detection |
| `AMIGEN_USE_DEFAULT_REPOS` | `true` | Use default RHUI repos |
| `AMIGEN8_REPO_NAMES` / `AMIGEN9_REPO_NAMES` | (empty) | Custom repo names (JSON array) |
| `AMIGEN8_REPO_SOURCES` / `AMIGEN9_REPO_SOURCES` | (empty) | Repo-config RPM URLs (JSON array) |
| `AMIGEN8_EXTRA_RPMS` / `AMIGEN9_EXTRA_RPMS` | (empty) | Extra RPMs (JSON array) |
| `AMIGEN_REPO_NOSIGNATURE` | `false` | Skip RPM signature checks |
| `AMIGEN_SSLVERIFY_DISABLE` | `false` | Disable SSL verification for internal mirrors |
| `PKR_VAR_aws_kms_key_id` | (empty) | KMS key ARN for EBS encryption |
| `CHIMERA_GOSS_BINARY_URL` | (empty) | Goss binary URL for STIG auditing |

### Workflow

```text
# On an internet-connected system:
offline-prepare.yml  →  chimera-builder-YYYYMMDD.tar.gz

# Transfer to air-gapped GitLab runner:
scp chimera-builder-*.tar.gz runner:/transfer/

# In GitLab:
import:docker  →  infra:create  →  build:rhel9 (or whichever OS)
```

## How It Works

Each build is a two-phase Packer pipeline running inside the Docker container:

1. **Minimal** (`chimera/minimal.pkr.hcl`) — Launches a surrogate EC2, partitions disks with LVM per STIG layout, installs a minimal OS via amigen scripts, snapshots the volume as an AMI.
2. **Hardened** (`chimera/hardened.pkr.hcl`) — Launches instances from the minimal AMIs, applies STIG hardening, and produces final hardened AMIs.

After a successful hardened build, `build.sh` automatically **deregisters the intermediate minimal AMIs** and deletes their backing snapshots. Only the final hardened AMIs are retained.

### Linux vs. Windows Build Architecture

| | Linux | Windows |
| --- | --- | --- |
| Builder type | `amazon-ebssurrogate` — builds the OS from scratch on a surrogate EC2 instance with custom LVM disk partitioning | `amazon-ebs` — launches an existing AWS-provided Windows AMI |
| Hardening method | Ansible STIG roles (RHEL8-STIG, RHEL9-STIG) or AWS STIG script (AL2023) | SSM `AWSEC2-ConfigureSTIG` document wrapped by a custom SSM document that restores the built-in admin rename (`maintuser`) |
| Produces | Two AMIs per OS (minimal + hardened) | One hardened AMI per OS |

The Docker container (`Dockerfile`) packages Packer 1.11.2, Ansible, AWS CLI v2, and all vendored amigen scripts so that no internet access is required at build time.

### Compliance Scanning

Compliance is verified at build time using two tools:

- **Goss** (via Ansible Lockdown roles) — Runs before and after Ansible remediation to produce JSON delta reports showing pre- and post-hardening posture. For air-gapped builds, set `chimera_goss_binary_url` to an internal mirror.
- **OpenSCAP** — Runs after hardening using the DISA STIG profile from `scap-security-guide`. Produces `/tmp/oscap-report.html` and `/tmp/oscap-results.xml`, downloaded as build artifacts.

See [docs/STIG_EXCEPTIONS.md](docs/STIG_EXCEPTIONS.md) for controls that are intentionally skipped and why.

### Build Times

| Operating System | Minimal Phase | Hardened Phase |
| ----------------- | --------------- | ---------------- |
| Amazon Linux 2023 | 30–45 min | 2–3 hr |
| RHEL 9 / Oracle Linux 9 | 45–60 min | 3–4 hr |
| RHEL 8 / Oracle Linux 8 | 45–60 min | 3–4 hr |
| Windows Server 2019/2022 | N/A (uses existing AMI) | 4–5 hr |

Builds that exceed 6 hours will fail due to AWS STS session expiry — ensure the IAM role's `MaxSessionDuration` is set to at least 21600.

## Infrastructure

The `infra/` directory contains OpenTofu modules provisioned automatically by CI/CD:

- **Networking** — VPC, subnet, security group, optional internet gateway, VPC endpoints (EC2 + STS for air-gapped)
- **IAM** — Roles and instance profiles for Packer-launched instances
- **SSM** — A full Systems Manager deployment: KMS CMK, S3 bucket, CloudWatch log group, VPC endpoints (ssm, ssmmessages, ec2messages, logs, kms, s3), Default Host Management Configuration (DHMC), Session Manager with encrypted logging, State Manager associations (STIG enforcement schedules, inventory collection, SSM Agent auto-update), Patch Manager baselines and maintenance windows, OpenSCAP and Windows STIG SSM documents, auto-tagging via EventBridge + Lambda, and SNS alerting

See [infra/README.md](infra/README.md) for full input/output reference.

## Image Defaults

| Setting | Default | Notes |
| --------- | --------- | ------- |
| Default user | `maintuser` | Override via cloud-init `system_info.default_user.name` |
| SELinux | Enforcing | Default user has restricted `shadow_t` access; set `selinux_user: unconfined_u` if needed (produces STIG findings) |
| FIPS | Enabled | All Linux builds |
| RHEL RHUI | CSP billing | `billingProducts` baked into AMI; build from source if using Satellite/RHN instead |

## STIG Exceptions

Some STIG controls cannot be applied at AMI build time. See [docs/STIG_EXCEPTIONS.md](docs/STIG_EXCEPTIONS.md) for the full list.

| Control | Why | Compensating Control |
| --------- | ----- | --------------------- |
| Disk encryption | EBS provides infrastructure-layer encryption | Enable EBS default encryption in account settings |
| GRUB password | No console access in cloud | IMDSv2 + IAM policies |
| Smartcard/CAC auth | Requires PKI infrastructure | Configure SSSD post-deployment |

## Repository Layout

```text
.
├── Dockerfile                 Self-contained builder image (Iron Bank Rocky Linux 9)
├── Makefile                   Entry point called by CI: env setup → build.sh
├── build.sh                   Packer orchestration (minimal → hardened)
├── chimera/
│   ├── minimal.pkr.hcl        Packer template: STIG-partitioned base AMIs
│   ├── hardened.pkr.hcl        Packer template: STIG-hardened AMIs
│   ├── scripts/                Shell scripts run inside surrogate EC2s
│   ├── ansible/                Roles (RHEL8/9-STIG, AL2023-STIG, Windows), collections, CA certs
│   └── userdata/               Cloud-init and userdata templates
├── vendor/
│   ├── amigen8/                EL8 AMI generation scripts (DiskSetup, OSpackages, etc.)
│   └── amigen9/                EL9 AMI generation scripts + install manifests
├── infra/                      OpenTofu modules (IAM, VPC, SSM)
├── .github/workflows/
│   ├── offline-prepare.yml     Step 1: Build Docker image artifact
│   ├── infra-setup.yml         Step 2: Provision AWS infra (called by build.yml)
│   ├── build.yml               Step 3: Build AMIs
│   └── ironbank-token-check.yml  Monthly Iron Bank credential health check
├── .gitlab-ci.yml              Air-gapped GitLab pipeline
├── docs/                       Extended documentation
└── tests/                      Validation scripts
```

## Building Locally (Without CI/CD)

You can build AMIs directly from a workstation using the Docker image. Two environment variables are **required** — the `Makefile` will refuse to run without them:

| Variable | Description | Example |
| ---------- | ------------- | -------- |
| `CHIMERA_IDENTIFIER` | Prefix for AMI names | `chimera` |
| `CHIMERA_VERSION` | Version string embedded in AMI names | `2025.04.1` |

```bash
# Import the Docker image
gunzip -c chimera-builder-*.tar.gz | docker load

# Run a build
docker run --rm \
  -v "$(pwd):/workspace" \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e AWS_DEFAULT_REGION=us-east-1 \
  -e CHIMERA_IDENTIFIER=chimera \
  -e CHIMERA_VERSION=2025.04.1 \
  -e CHIMERA_BUILDERS=amazon-ebssurrogate.minimal-rhel-9-hvm \
  -e WINDOWS_BUILDERS="" \
  chimera-builder:latest make build
```

The same `CHIMERA_IDENTIFIER` and `CHIMERA_VERSION` variables are used by CI/CD pipelines — they are set automatically by the workflow files.

## Troubleshooting

Common issues and where to find solutions:

| Problem | Where to Look |
| --------- | --------------- |
| Docker import fails / checksum mismatch | [QUICK-REFERENCE](docs/QUICK-REFERENCE-Optimization.md) — "Docker Import Fails" |
| AWS credentials expire mid-build | [QUICK-REFERENCE](docs/QUICK-REFERENCE-Optimization.md) — "AWS Credentials Expire" (ensure IAM role `MaxSessionDuration >= 21600`) |
| Build can't reach package repos | [QUICK-REFERENCE](docs/QUICK-REFERENCE-Optimization.md) — "Build Can't Access Repositories" |
| Full IAM policy examples (Packer + OpenTofu) | [CI-CD-Setup](docs/CI-CD-Setup.md) — "IAM Configuration" |
| SSM infrastructure provisioning without OpenTofu | [Manual-SSM-Setup](docs/Manual-SSM-Setup.md) — step-by-step AWS CLI commands |
| Windows driver/boot issues after STIG | [Windows-STIG-Driver-Compatibility](docs/Windows-STIG-Driver-Compatibility.md) |
| Storage planning for runners | [Storage-Optimization](docs/Storage-Optimization.md) (~50 GB recommended free space) |

## Documentation

| Document | Description |
| ---------- | ------------- |
| [CI-CD-Setup](docs/CI-CD-Setup.md) | Full GitHub Actions and GitLab CI configuration walkthrough |
| [QUICK-REFERENCE-Optimization](docs/QUICK-REFERENCE-Optimization.md) | Cheat sheet: variables, build times, troubleshooting |
| [Storage-Optimization](docs/Storage-Optimization.md) | Docker image size breakdown and storage planning |
| [Manual-SSM-Setup](docs/Manual-SSM-Setup.md) | Provision SSM infrastructure with AWS CLI (no OpenTofu) |
| [STIG_EXCEPTIONS](docs/STIG_EXCEPTIONS.md) | STIG exceptions and compensating controls |
| [Windows-STIG-Driver-Compatibility](docs/Windows-STIG-Driver-Compatibility.md) | Nitro driver compatibility with Windows STIG controls |
| [Infrastructure](infra/README.md) | OpenTofu module reference (IAM, networking, SSM) |
