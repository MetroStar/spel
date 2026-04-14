# Crucible

Build STIG-hardened, LVM-partitioned Amazon Machine Images for Enterprise Linux.

Crucible produces AMIs where every DISA STIG filesystem-separation requirement is satisfied from first boot. No post-launch repartitioning needed. Builds run entirely through CI/CD — GitHub Actions or GitLab CI — using a self-contained Docker image with all dependencies baked in.

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

## Building AMIs

Crucible supports three build paths — **GitHub Actions** (connected), **GitLab CI** (air-gapped), and **local Docker** — all using the same self-contained `crucible-builder` container image.

The full step-by-step walkthrough for each path, including prerequisites, input variables, and air-gapped configuration, is in the **[Onboarding Guide](docs/capability/onboarding-guide.md)**.

Quick summary:

1. **Build the Docker image** — `offline-prepare.yml` (GitHub) or `docker build` (local)
2. **Provision infrastructure** — `infra-setup.yml` runs OpenTofu automatically (or run manually)
3. **Build AMIs** — `build.yml` runs Packer inside the container

For variable reference tables and deployment profiles, see the **[Template Package](docs/capability/template-package.md)**.

## How It Works

Each build is a two-phase Packer pipeline running inside the Docker container:

1. **Minimal** (`crucible/minimal.pkr.hcl`) — Launches a surrogate EC2, partitions disks with LVM per STIG layout, installs a minimal OS via amigen scripts, snapshots the volume as an AMI.
2. **Hardened** (`crucible/hardened.pkr.hcl`) — Launches instances from the minimal AMIs, applies STIG hardening, and produces final hardened AMIs.

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

- **Goss** (via Ansible Lockdown roles) — Runs before and after Ansible remediation to produce JSON delta reports showing pre- and post-hardening posture. For air-gapped builds, set `crucible_goss_binary_url` to an internal mirror.
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
├── crucible/
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

## Troubleshooting

See the **[Troubleshooting Guide](docs/capability/troubleshooting-guide.md)** for diagnostic commands and resolution steps covering build failures, infrastructure issues, SSM/runtime problems, and air-gapped-specific errors.

## Documentation

The **[Crucible Capability Package](docs/capability/README.md)** is the main documentation hub. It includes an onboarding guide, runbook, troubleshooting guide, reference architecture, operating model, and proposal-ready value brief.

Additional deep-reference docs:

| Document | Description |
| ---------- | ------------- |
| [CI-CD-Setup](docs/CI-CD-Setup.md) | IAM policies, OIDC configuration, pipeline internals |
| [Manual-SSM-Setup](docs/Manual-SSM-Setup.md) | Provision SSM infrastructure with AWS CLI (no OpenTofu) |
| [STIG_EXCEPTIONS](docs/STIG_EXCEPTIONS.md) | STIG exceptions and compensating controls |
| [Windows-STIG-Driver-Compatibility](docs/Windows-STIG-Driver-Compatibility.md) | Nitro driver compatibility with Windows STIG controls |
| [Infrastructure](infra/README.md) | OpenTofu module reference (IAM, networking, SSM) |
