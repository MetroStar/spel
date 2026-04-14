# Template Package

> **Crucible Platform** — How to fork, adapt, and deploy for a new program.

This guide covers configuration, infrastructure customization, pipeline adaptation, STIG customization, and storage planning for adopting the Crucible Platform on a new contract or program.

## Configuration Reference

All build behavior is controlled through environment variables. Set these in your CI/CD system or export them before running Docker locally.

### Identity & Naming

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CRUCIBLE_IDENTIFIER` | **Yes** | — | Prefix for AMI names (e.g., `crucible`) |
| `CRUCIBLE_VERSION` | **Yes** | — | Version string in AMI names (e.g., `2026.04.1`) |
| `CRUCIBLE_BUILDERS` | **Yes** | — | Comma-delimited list of Linux builders to run |
| `WINDOWS_BUILDERS` | No | `""` | Comma-delimited list of Windows builders to run |

### AWS & Networking

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PKR_VAR_aws_region` | **Yes** | — | Target AWS region |
| `PKR_VAR_aws_vpc_id` | Auto | From infra output | VPC ID |
| `PKR_VAR_aws_subnet_id` | Auto | From infra output | Subnet ID |
| `PKR_VAR_aws_security_group_id` | Auto | From infra output | Security Group ID |
| `PKR_VAR_aws_iam_instance_profile` | Auto | From infra output | Instance profile name |
| `PKR_VAR_aws_kms_key_id` | No | — | KMS key ARN for EBS encryption |
| `PKR_VAR_aws_ami_regions` | No | Build region only | JSON array of regions to copy AMIs to |

### Air-Gapped Mode

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `AIRGAP_MODE` | No | `false` | Master toggle — sets the four flags below |
| `AMIGEN_CROSS_DISTRO` | No | `false` | Skip RHUI auto-detection |
| `AMIGEN_USE_DEFAULT_REPOS` | No | `true` | Use default RHUI repos |
| `AMIGEN_REPO_NOSIGNATURE` | No | `false` | Accept unsigned RPMs |
| `AMIGEN_SSLVERIFY_DISABLE` | No | `false` | Skip SSL verification for internal mirrors |
| `REPO_MIRROR_BASEURL` | No | — | Local YUM mirror URL (e.g., `http://mirror.internal.mil`) |
| `DOCKER_IMAGE_PATH` | No | `/transfer/crucible-builder-*.tar.gz` | Path to Docker image tarball |

### Package Sources (Offline Overrides)

| Variable | Default | Description |
|----------|---------|-------------|
| `AMIGEN9_REPO_NAMES` | `""` | JSON array of repo names |
| `AMIGEN9_REPO_SOURCES` | `""` | JSON array of repo-config RPM URLs |
| `AMIGEN9_EXTRA_RPMS` | `""` | JSON array of additional RPMs |
| `AMIGEN8_REPO_NAMES` | `""` | JSON array of EL8 repo names |
| `AMIGEN8_REPO_SOURCES` | `""` | JSON array of EL8 repo-config RPM URLs |
| `AMIGEN8_EXTRA_RPMS` | `""` | JSON array of additional EL8 RPMs |
| `CRUCIBLE_GOSS_BINARY_URL` | `""` | URL to Goss binary for STIG auditing |

### Storage Layout (Advanced)

| Variable | Default | Description |
|----------|---------|-------------|
| `PKR_VAR_amigen9_storage_layout` | LVM defaults | JSON array of LVM volume tuples: `["/:rootVol:6","swap:swapVol:2","/var:varVol:2"]` |

## Infrastructure Customization

The `infra/` directory contains OpenTofu modules. Customize by setting variables in `terraform.tfvars` or via `-var` flags.

### Feature Toggles

| Variable | Default | Purpose |
|----------|---------|---------|
| `enable_internet_gateway` | `true` | Set `false` for air-gapped |
| `enable_packer_endpoints` | `false` | EC2 + STS endpoints for air-gapped Packer |
| `enable_vpc_endpoints` | `true` | SSM, S3, KMS, CloudWatch endpoints |
| `enable_patch_manager` | `true` | Patch baselines + maintenance windows |
| `enable_session_manager` | `true` | Session Manager logging |
| `enable_auto_tagging` | `true` | EventBridge + Lambda for AMI→instance tags |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `subnet_cidr` | `10.0.1.0/24` | Subnet CIDR block |
| `aws_region` | — | Target AWS region |

### Retention & Scheduling

| Variable | Default | Description |
|----------|---------|-------------|
| `cloudwatch_retention_days` | `90` | Log retention period |
| `stig_enforcement_schedule` | `rate(7 days)` | STIG enforcement frequency |
| `patch_maintenance_schedule` | `cron(0 4 ? * SUN *)` | Patch window (Sunday 4AM UTC) |
| `patch_maintenance_duration` | `3` | Maintenance window duration (hours) |
| `patch_auto_approval_days` | `7` | Days before auto-approving patches |

### Profiles for Deployment Models

**CI-only (minimal infrastructure)**:
```hcl
enable_patch_manager    = false
enable_session_manager  = false
enable_auto_tagging     = false
enable_vpc_endpoints    = false
```

**Production (full features)**:
```hcl
enable_patch_manager    = true
enable_session_manager  = true
enable_auto_tagging     = true
enable_vpc_endpoints    = true
```

**Air-gapped production**:
```hcl
enable_internet_gateway = false
enable_packer_endpoints = true
enable_patch_manager    = true
enable_session_manager  = true
enable_auto_tagging     = true
enable_vpc_endpoints    = true
```

## Pipeline Adaptation

### GitHub Actions

The workflows in `.github/workflows/` are designed to be fork-friendly. Common adaptations:

**Different runner type**:
```yaml
# In build.yml, change:
runs-on: ubuntu-latest
# To:
runs-on: self-hosted  # or your custom runner label
```

**Additional approval gates**:
```yaml
# Add an environment with required reviewers:
jobs:
  build:
    environment: production  # requires approval in GitHub settings
```

**Different artifact storage** (e.g., Artifactory):
```yaml
# Replace the upload-artifact step with your artifact manager
- name: Upload to Artifactory
  run: curl -T crucible-builder-*.tar.gz https://artifactory.example.com/crucible/
```

### GitLab CI (Air-Gapped)

**Runner configuration**:
- Tag: `crucible-offline-runner`
- Docker must be installed
- `/transfer/` directory must be accessible (mount or volume)

**Pipeline variables** — Set in **Settings → CI/CD → Variables**. See the air-gapped variables table in the Configuration Reference above.

**Pre-stage Docker images**:
```bash
# On the runner host:
mkdir -p /transfer
cp crucible-builder-*.tar.gz /transfer/
```

**Integration with ITSM / ServiceNow**:
- Add a pipeline stage that creates a change request before the build stage
- Add a post-build stage that updates the change request with AMI IDs and compliance report links
- Use GitLab CI/CD variables for ServiceNow API credentials

## STIG Customization

### Organization-Specific Overrides

Override STIG role defaults without forking the role. Create a variable file and pass it to Ansible:

```yaml
# crucible/ansible/my-org-overrides.yml
# Example: Adjust password complexity to match org policy
rhel9stig_pass_min_length: 15
rhel9stig_pass_min_days: 1
rhel9stig_pass_max_days: 60

# Skip specific controls (with documented justification)
rhel9stig_rule_12345_enabled: false
```

Reference the override file in the Packer provisioner or pass it via `--extra-vars`.

### Documenting Compensating Controls

For controls that cannot be remediated at AMI build time, document them in `docs/STIG_EXCEPTIONS.md` following the existing pattern:

```markdown
### VULN-ID: V-12345 — Control Title

**Status**: Exception — Compensating Control

**Justification**: [Why this control cannot be applied at build time]

**Compensating Control**: [What alternative measure is in place]
```

### Adding a Custom STIG Role

1. Create a new role under `crucible/ansible/roles/YOUR-STIG/`
2. Reference it in the hardened Packer template (`crucible/hardened.pkr.hcl`)
3. Add an SSM association for post-deployment enforcement if needed
4. Update the platform support matrix in `docs/capability/reference-architecture.md`

## Storage Planning

### Docker Image Size

| Format | Size |
|--------|------|
| Gzipped tarball | ~305 MB |
| Uncompressed image | ~834 MB |

### Storage by Environment

**GitHub Actions Runner** (ephemeral):
| Component | Size |
|-----------|------|
| Repository checkout | ~100 MB |
| Docker build cache | ~1–2 GB |
| Final Docker image | ~834 MB |
| Gzipped tarball | ~305 MB |
| **Peak usage** | **~3 GB** |

**GitLab Runner** (air-gapped):
| Component | Size |
|-----------|------|
| Docker image tarball | ~305 MB |
| Imported Docker image | ~834 MB |
| Repository checkout | ~100 MB |
| Build workspace per job | 10–20 GB |
| Packer cache | 5–10 GB |
| **Single build total** | **~15–25 GB** |
| **Per additional concurrent build** | **+10–20 GB** |

**Recommendation**: Maintain at least **50 GB free space** for builds. Run builds sequentially when storage is limited.

### Transfer Artifacts

Each Docker image build produces:

```
crucible-builder-YYYYMMDD/
├── crucible-builder-YYYYMMDD.tar.gz         # ~305 MB
├── crucible-builder-YYYYMMDD.tar.gz.sha256  # <1 KB
└── crucible-builder-YYYYMMDD-manifest.txt   # <2 KB
```

| Transfer Medium | Considerations |
|----------------|---------------|
| SCP / SFTP | ~305 MB transfer |
| USB drive | Minimum 512 MB |
| Secure file share | ~305 MB upload; zip `.b64` file first for SharePoint |

### Artifact Retention

| Platform | Retention | Configurable In |
|----------|-----------|----------------|
| GitHub Actions | 30 days | Workflow file |
| GitLab CI (jobs) | 7 days | `.gitlab-ci.yml` |
| GitLab CI (infra.env) | 90 days | `.gitlab-ci.yml` |

### Cleanup

```bash
# Remove old Docker images
docker images crucible-builder --format '{{.Tag}}' | sort | head -n -2 | \
  xargs -I{} docker rmi crucible-builder:{}

# Remove Packer cache
rm -rf ~/.cache/packer/* ~/.packer.d/tmp/*
```

## Pre-Flight Checklist for New Program Adoption

Use this checklist when deploying Crucible on a new program:

### AWS Account Readiness
- [ ] AWS account provisioned (Commercial or GovCloud)
- [ ] IAM permissions available (see [CI-CD-Setup — IAM Configuration](../CI-CD-Setup.md#aws-iam-configuration))
- [ ] OIDC identity provider created (GitHub and/or GitLab)
- [ ] Service quotas sufficient (EC2 instances, EBS volumes, AMIs)
- [ ] EBS default encryption enabled (recommended)

### Network Prerequisites
- [ ] VPC CIDR allocated (non-overlapping with existing VPCs)
- [ ] Subnet CIDR allocated
- [ ] For air-gapped: local YUM mirror URL known
- [ ] For air-gapped: VPC endpoint service names verified for the target region

### Tooling
- [ ] Docker installed on CI/CD runner
- [ ] OpenTofu installed (for manual infra operations)
- [ ] AWS CLI configured with credentials
- [ ] Iron Bank credentials obtained (for Docker image build)

### Repository
- [ ] Repository cloned / forked
- [ ] `backend.tf` configured for target account/region
- [ ] CI/CD variables set (AWS credentials, region, builder selection)
- [ ] STIG exception documentation reviewed for program-specific needs

### Validation
- [ ] `bootstrap-backend.sh` ran successfully
- [ ] `tofu apply` completed without errors
- [ ] First Docker image built or imported
- [ ] First AMI built and validated
- [ ] SSM connectivity confirmed on test instance
