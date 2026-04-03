# Chimera

Build STIG-hardened, LVM-partitioned Amazon Machine Images for Enterprise Linux.

Chimera produces AMIs where every DISA STIG filesystem-separation requirement is satisfied from first boot. No post-launch repartitioning needed.

## Supported Builds

| OS | EL Version | Builder Name |
|----|------------|--------------|
| RHEL 9 | EL9 | `amazon-ebssurrogate.minimal-rhel-9-hvm` |
| RHEL 8 | EL8 | `amazon-ebssurrogate.minimal-rhel-8-hvm` |
| Oracle Linux 9 | EL9 | `amazon-ebssurrogate.minimal-ol-9-hvm` |
| Oracle Linux 8 | EL8 | `amazon-ebssurrogate.minimal-ol-8-hvm` |
| Rocky Linux 9 | EL9 | `amazon-ebssurrogate.minimal-rl-9-hvm` |
| Alma Linux 9 | EL9 | `amazon-ebssurrogate.minimal-alma-9-hvm` |
| Amazon Linux 2023 | EL9-based | `amazon-ebssurrogate.minimal-amzn-2023-hvm` |
| Windows Server 2019 | — | `amazon-ebs.hardened-windows-2019` |
| Windows Server 2022 | — | `amazon-ebs.hardened-windows-2022` |

Each Linux build produces two AMIs: a **minimal** base image and a **hardened** image with STIG lockdowns applied via Ansible roles or the AWS STIG script.

## How It Works

```
Dockerfile           Build a portable chimera-builder container (~305 MB gz)
  ├─ Packer 1.11.2   Orchestrates EC2 surrogate builds
  ├─ Ansible          Applies STIG hardening roles (RHEL8-STIG, RHEL9-STIG, AL2023-STIG, Windows)
  ├─ AWS CLI v2       AMI registration and discovery
  ├─ vendor/amigen8   EL8 disk layout, chroot, and OS packaging scripts
  └─ vendor/amigen9   EL9 disk layout, chroot, and OS packaging scripts

build.sh             Runs packer init/validate/build for minimal, then hardened
Makefile             Sets env vars (logging, region, security group CIDR) and calls build.sh
```

**Two-phase pipeline:**

1. `chimera/minimal.pkr.hcl` — Launches a surrogate EC2, partitions disks with LVM per STIG layout, installs a minimal OS via amigen scripts, snapshots the volume as an AMI.
2. `chimera/hardened.pkr.hcl` — Launches instances from the minimal AMIs, applies Ansible STIG roles (Linux) or AWS STIG scripts (AL2023) or Ansible lockdown roles (Windows), produces final hardened AMIs.

## Quick Start

### With Docker (recommended)

```bash
# Build the container
docker build -t chimera-builder:$(date +%Y%m%d) .

# Run a build
docker run --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e AWS_REGION=us-east-1 \
  -e CHIMERA_IDENTIFIER=my-project \
  -e CHIMERA_VERSION=$(date +%Y.%m.1) \
  -e CHIMERA_BUILDERS=amazon-ebssurrogate.minimal-rhel-9-hvm \
  -v "$(pwd):/workspace" \
  chimera-builder:$(date +%Y%m%d)
```

### Without Docker

Requires: Packer 1.11.2+, AWS CLI v2, Ansible, configured AWS credentials.

```bash
export CHIMERA_IDENTIFIER=my-project
export CHIMERA_VERSION=$(date +%Y.%m.1)
export CHIMERA_BUILDERS=amazon-ebssurrogate.minimal-rhel-9-hvm
export AWS_REGION=us-east-1

make build
```

### GovCloud / Air-Gapped

The Docker image contains all dependencies — no internet access required at build time. Transfer the image tarball to the isolated environment and run:

```bash
docker load -i chimera-builder-YYYYMMDD.tar.gz
docker run --rm \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  -e AWS_REGION=us-gov-west-1 \
  -e CHIMERA_IDENTIFIER=my-project \
  -e CHIMERA_VERSION=$(date +%Y.%m.1) \
  -e CHIMERA_BUILDERS=amazon-ebssurrogate.minimal-rhel-9-hvm \
  -v "$(pwd):/workspace" \
  chimera-builder:YYYYMMDD
```

## Repository Layout

```
.
├── Dockerfile                 Portable builder image (Rocky Linux 9 Iron Bank base)
├── Makefile                   Entry point: env setup + calls build.sh
├── build.sh                   Packer orchestration (minimal → hardened)
├── chimera/
│   ├── minimal.pkr.hcl        Packer template: STIG-partitioned base AMIs
│   ├── hardened.pkr.hcl        Packer template: STIG-hardened AMIs
│   ├── scripts/                Shell scripts run inside surrogate EC2s
│   ├── ansible/                Roles (RHEL8/9-STIG, AL2023-STIG, Windows), collections, CA certs
│   ├── kickstarts/             Kickstart configs
│   └── userdata/               Cloud-init and userdata templates
├── vendor/
│   ├── amigen8/                EL8 AMI generation scripts (DiskSetup, OSpackages, etc.)
│   └── amigen9/                EL9 AMI generation scripts
├── infra/                      OpenTofu modules for AWS infrastructure (IAM, VPC, SSM)
├── docs/                       Extended documentation
└── tests/                      Validation scripts
```

## CI/CD

| Environment | Pipeline | How It Works |
|-------------|----------|--------------|
| **GitHub Actions** | `offline-prepare.yml` → `build.yml` | Builds Docker image as artifact, then runs AMI builds with OIDC credentials |
| **GitLab CI** | `.gitlab-ci.yml` | Imports pre-built Docker tarball, runs AMI builds with static credentials |
| **Local** | `docker run` or `make build` | Developer builds with personal AWS credentials |

IAM role sessions must be at least **6 hours** (21600s) — builds can take 30 min to 5 hours depending on the OS.

## Infrastructure

The `infra/` directory contains OpenTofu modules to provision the AWS environment:

- **IAM** — Roles and instance profiles for Packer and SSM
- **Networking** — VPC with optional internet gateway (disable for air-gapped builds) and VPC endpoints
- **SSM** — Systems Manager documents, patch baselines, State Manager associations, compliance scanning

```bash
cd infra
tofu init
tofu apply -var="project_name=chimera"
```

See [infra/README.md](infra/README.md) for inputs/outputs and the air-gapped VPC endpoint configuration.

## Image Defaults

**Default user:** `maintuser`

Override at launch via cloud-init:

```yaml
#cloud-config
system_info:
  default_user:
    name: myuser
```

**SELinux:** Enforcing. The default user has SELinux role-transition rules that restrict access to `shadow_t` files (`/etc/shadow`, `/etc/gshadow`, `/etc/security/opasswd`). If your automation requires root access to these files after `sudo`, set `selinux_user: unconfined_u` in your cloud-config — but this will produce STIG scan findings.

**FIPS:** Enabled by default on all Linux builds.

**RHEL RHUI:** RHEL images use the CSP's Red Hat Update Infrastructure. The `billingProducts` attribute is baked into the AMI. If you use Satellite or RHN instead, build your own images from this repo's source to avoid RHUI billing.

## STIG Exceptions

Some STIG controls cannot be applied at AMI build time. See [docs/STIG_EXCEPTIONS.md](docs/STIG_EXCEPTIONS.md) for the full list. Key exceptions:

| Control | Why | Compensating Control |
|---------|-----|---------------------|
| Disk encryption | AWS EBS provides encryption at the infrastructure layer | Enable EBS default encryption in account settings |
| GRUB password | No console access in cloud; would block recovery | IMDSv2 + IAM policies |
| Smartcard/CAC auth | Requires PKI infrastructure | Configure SSSD post-deployment |

## Documentation

| Document | Description |
|----------|-------------|
| [CI-CD-Setup](docs/CI-CD-Setup.md) | Full GitHub Actions and GitLab CI configuration walkthrough |
| [QUICK-REFERENCE-Optimization](docs/QUICK-REFERENCE-Optimization.md) | Cheat sheet: variables, build times, troubleshooting |
| [Storage-Optimization](docs/Storage-Optimization.md) | Docker image size breakdown and storage planning |
| [Manual-SSM-Setup](docs/Manual-SSM-Setup.md) | Provision SSM infrastructure with AWS CLI (no OpenTofu) |
| [STIG_EXCEPTIONS](docs/STIG_EXCEPTIONS.md) | STIG exceptions and compensating controls |
| [Windows-STIG-Driver-Compatibility](docs/Windows-STIG-Driver-Compatibility.md) | Nitro driver compatibility with Windows STIG controls |
| [Infrastructure](infra/README.md) | OpenTofu module reference (IAM, networking, SSM) |

## Testing amigen Changes

The amigen scripts in `vendor/` are vendored copies. To test a fork or branch before merging:

```bash
packer build \
    -var 'amigen9_source_url=https://github.com/YOUR_FORK/amigen9.git' \
    -var 'amigen9_source_branch=your-branch' \
    chimera/minimal.pkr.hcl
```

Or via environment variables:

```bash
export PKR_VAR_amigen9_source_url=https://github.com/YOUR_FORK/amigen9.git
export PKR_VAR_amigen9_source_branch=your-branch
```
