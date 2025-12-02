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
4. **Vendor roles** - Clone Ansible roles without git history (60 MB)
5. **Vendor collections** - Download Ansible collections as tarballs (30 MB)
6. **Download packages** - Get AWS utilities and Packer (500 MB)
7. **Create archives** - Build compressed transfer archives (~1 GB)
8. **Verify checksums** - Validate all archives with SHA256
9. **Generate manifest** - Create transfer documentation
10. **Upload artifacts** - Store in GitHub for download

### Expected Output

```
Archives created:
  spel-base-20251126.tar.gz                  ~200 MB
  spel-tools-20251126.tar.gz                 ~600 MB
  spel-nipr-complete-20251126.tar.gz         ~1 GB

Total archive size: ~1 GB

Files ready for transfer:
  - spel-nipr-20251126-checksums.txt
  - spel-nipr-20251126-manifest.txt
  - spel-*.tar.gz
```

## GitLab CI Setup (NIPR)

### Configuration File

Location: `.gitlab-ci.yml`

### Pipeline Stages

1. **extract** - Extract transferred archives
2. **setup** - Prepare build environment and configure repositories
3. **validate** - Validate Packer templates
4. **build** - Build AMI images

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

#### Required GitLab CI/CD Variables

Configure in GitLab project settings (**Settings** → **CI/CD** → **Variables**):

| Variable | Description | Example |
|----------|-------------|---------|
| `EXTRACT_ARCHIVES` | Enable archive extraction | `true` |
| `AWS_GOVCLOUD_ACCESS_KEY_ID` | NIPR GovCloud access key | `AKIA...` |
| `AWS_GOVCLOUD_SECRET_ACCESS_KEY` | NIPR GovCloud secret key | `secret` |
| `PKR_VAR_aws_nipr_account_id` | NIPR AWS account ID for source AMI filters | `123456789012` |
| `PKR_VAR_aws_vpc_id` | VPC ID in NIPR | `vpc-abc123` |
| `PKR_VAR_aws_subnet_id` | Subnet ID in NIPR | `subnet-xyz789` |
| `PKR_VAR_aws_nipr_ami_regions` | Target regions (optional) | `["us-gov-east-1"]` |
| `RUN_AMZN2023` | Build Amazon Linux 2023 | `true` (optional) |
| `RUN_RHEL9` | Build RHEL 9 | `true` (optional) |
| `RUN_RHEL8` | Build RHEL 8 | `true` (optional) |
| `RUN_OL9` | Build Oracle Linux 9 | `true` (optional) |
| `RUN_OL8` | Build Oracle Linux 8 | `true` (optional) |
| `RUN_WS2016` | Build Windows Server 2016 | `true` (optional) |
| `RUN_WS2019` | Build Windows Server 2019 | `true` (optional) |
| `RUN_WS2022` | Build Windows Server 2022 | `true` (optional) |

### Usage Workflow

#### Initial Setup (First Time)

1. **Transfer archives to NIPR GitLab**:
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

2. **Set GitLab variable**:
   - Go to **Settings** → **CI/CD** → **Variables**
   - Add variable: `EXTRACT_ARCHIVES` = `true`

3. **Run extraction pipeline**:
   - Go to **CI/CD** → **Pipelines**
   - Click **Run pipeline**
   - Set variable: `EXTRACT_ARCHIVES=true`
   - Click **Run pipeline**
   - Manually click **▶** on `extract:archives` job
   - Wait for extraction to complete

4. **Verify setup**:
   - Check job logs for successful extraction
   - `setup` job runs automatically and configures environment
   - All offline components (Packer, Python, Ansible collections) are configured automatically

#### Monthly AMI Builds

After initial setup, monthly builds are simpler:

1. **Update archives** (if needed):
   - Transfer new archives from GitHub Actions
   - Update files in GitLab repository
   - Commit and push

2. **Run build pipeline**:
   - Go to **CI/CD** → **Pipelines**
   - Click **Run pipeline**
   - Set build variables (e.g., `RUN_RHEL9=true`)
   - Click **Run pipeline**

3. **Monitor builds**:
   - `setup` job runs automatically
   - `validate:*` jobs run automatically
   - `build:*` jobs are manual - click **▶** to run

### Pipeline Jobs

#### extract:archives (Manual)

Extracts transferred archives and verifies checksums.

```yaml
when: manual
only:
  variables:
    - $EXTRACT_ARCHIVES == "true"
```

**Run when**: Initial setup or archive updates

#### setup (Automatic)

Initializes git submodules and sets up build environment.

#### validate:minimal, validate:hardened (Automatic)

Validates Packer templates before building.

#### build:* (Manual)

Builds specific AMI types. Run manually to control which AMIs to build.

**Available jobs**:
- `build:amzn2023` - Amazon Linux 2023
- `build:rhel9` - RHEL 9
- `build:rhel8` - RHEL 8
- `build:ol9` - Oracle Linux 9
- `build:ol8` - Oracle Linux 8
- `build:windows2016` - Windows Server 2016
- `build:windows2019` - Windows Server 2019
- `build:windows2022` - Windows Server 2022
- `build:all` - All builders (on tagged releases)

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

### GitHub Actions Issues

**Problem**: Archive too large for GitHub artifacts
```bash
Solution: Separate archives are uploaded individually
Maximum artifact size: 2 GB per file (archives are typically under this)
```

**Problem**: Workflow timeout
```bash
Solution: Increase timeout-minutes in workflow file
Default: 480 minutes (8 hours)
```

### GitLab CI Issues

**Problem**: Extract job fails - no archives found
```bash
Solution: Ensure archives are in repository root
ls -lh spel-*.tar.gz
```

**Problem**: Checksum verification fails
```bash
Solution: Re-transfer archives, verify file integrity
sha256sum spel-*.tar.gz > manual-checksums.txt
```

**Problem**: Build fails - cannot access repositories
```bash
Solution: Verify AWS GovCloud RHUI repositories are accessible
sudo dnf repolist
sudo dnf makecache
```

**Problem**: GitLab Runner offline
```bash
Solution: Check runner status and restart if needed
sudo gitlab-runner status
sudo gitlab-runner restart
```

## Storage Requirements

### GitHub Actions Runner

- **Roles**: 100 MB
- **Collections**: 50 MB
- **Packages**: 200 MB
- **Packer/Python**: 600 MB
- **Archives**: 1 GB
- **Total**: ~2-3 GB free space needed

### GitLab Runner (NIPR)

- **Extracted archives**: ~1 GB
  - Offline packages: 75 MB
  - Ansible roles: 60 MB
  - Ansible collections (tarballs): 30 MB
  - Packer binaries: 500 MB
  - Python packages: 100 MB
  - SPEL packages: 20 MB
  - Build scripts: 100 MB
- **Build artifacts**: 10-20 GB
- **Packer cache**: 5-10 GB
- **Total**: ~20-35 GB free space needed

## Security Considerations

### GitHub Actions

- Uses GitHub-hosted runners (ephemeral)
- No credentials stored in workflow
- Artifacts encrypted at rest
- 90-day retention, auto-deleted

### GitLab CI

- Self-hosted runner required
- AWS credentials stored as protected variables
- Runner isolated in NIPR network
- Archives verified with checksums before extraction

## Maintenance

### Monthly Tasks

1. **Monitor GitHub Actions runs** (15th of each month)
2. **Download and transfer archives** to NIPR
3. **Update GitLab repository** with new archives
4. **Run GitLab pipeline** for AMI builds

### Quarterly Tasks

1. **Review storage usage** on both systems
2. **Clean old artifacts** from GitHub (automatic after 90 days)
3. **Update GitLab Runner** to latest version
4. **Review and update CI/CD variables**

### Annual Tasks

1. **Audit CI/CD configurations** for security
2. **Review and optimize** archive sizes
3. **Update documentation** with lessons learned
4. **Test disaster recovery** procedures

## References

- **Storage Optimization Guide**: `docs/Storage-Optimization.md`
- **NIPR Setup Guide**: `docs/NIPR-Setup.md`
- **Quick Reference**: `docs/QUICK-REFERENCE-Optimization.md`
- **GitHub Actions Workflow**: `.github/workflows/nipr-prepare.yml`
- **GitLab CI Configuration**: `.gitlab-ci.yml`
