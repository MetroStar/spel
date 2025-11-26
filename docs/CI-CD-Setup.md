# CI/CD Setup for NIPR Transfers

This guide explains how to set up and use the automated CI/CD pipelines for NIPR SPEL deployments.

## Overview

The NIPR transfer workflow is split across two CI/CD systems:

1. **GitHub Actions** (Internet-connected) - Prepares optimized transfer archives
2. **GitLab CI** (NIPR air-gapped) - Extracts archives and builds AMIs

```
Internet System (GitHub)          NIPR System (GitLab)
┌─────────────────────┐          ┌──────────────────────┐
│ 1. Sync Mirrors     │          │ 7. Extract Archives  │
│ 2. Vendor Roles     │          │ 8. Configure Repos   │
│ 3. Download Pkgs    │   -->    │ 9. Setup Environment │
│ 4. Create Archives  │ Transfer │ 10. Validate         │
│ 5. Verify Checksums │          │ 11. Build AMIs       │
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
   - **Sync mirrors**: Download YUM/DNF repositories (default: true)
   - **Vendor roles**: Clone Ansible roles (default: true)
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
SPEL_MIRROR_EXCLUDE_DEBUG=true    # Exclude debug packages (saves 40%)
SPEL_MIRROR_EXCLUDE_SOURCE=true   # Exclude source RPMs (saves 20%)
SPEL_MIRROR_COMPRESS=true         # Compress repos (saves 60% transfer)
SPEL_MIRROR_HARDLINK=true         # Deduplicate files (saves 10%)
SPEL_ROLES_REMOVE_GIT=true        # Remove .git dirs (saves 50%)
SPEL_ROLES_COMPRESS=true          # Compress roles archive
SPEL_OFFLINE_COMPRESS=true        # Compress offline packages
SPEL_ARCHIVE_SEPARATE=true        # Create separate archives
SPEL_ARCHIVE_COMBINED=true        # Also create combined archive
```

### Workflow Steps

1. **Checkout** - Clone repository with submodules
2. **Install dependencies** - dnf, createrepo-c, hardlink, wget
3. **Set environment** - Configure optimization variables
4. **Sync mirrors** - Download YUM/DNF repositories (30-50 GB)
5. **Vendor roles** - Clone Ansible roles without git history (60 MB)
6. **Download packages** - Get AWS utilities (75 MB)
7. **Create archives** - Build compressed transfer archives (12-20 GB)
8. **Verify checksums** - Validate all archives with SHA256
9. **Generate manifest** - Create transfer documentation
10. **Upload artifacts** - Store in GitHub for download

### Expected Output

```
Archives created:
  spel-base-20251126.tar.gz                  500 MB
  spel-mirrors-compressed-20251126.tar.gz    15 GB
  spel-tools-20251126.tar.gz                 400 MB
  spel-nipr-complete-20251126.tar.gz         18 GB

Total archive size: 18 GB

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
2. **configure** - Set up local repositories
3. **setup** - Prepare build environment
4. **validate** - Validate Packer templates
5. **build** - Build AMI images

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

# Grant sudo privileges
sudo visudo
# Add: gitlab-runner ALL=(ALL) NOPASSWD: /path/to/spel/scripts/setup-local-repos.sh
```

#### Required GitLab CI/CD Variables

Configure in GitLab project settings (**Settings** → **CI/CD** → **Variables**):

| Variable | Description | Example |
|----------|-------------|---------|
| `EXTRACT_ARCHIVES` | Enable archive extraction | `true` |
| `AWS_COMMERCIAL_ACCESS_KEY_ID` | NIPR AWS access key | `AKIA...` |
| `AWS_COMMERCIAL_SECRET_ACCESS_KEY` | NIPR AWS secret key | `secret` |
| `PKR_VAR_aws_nipr_account_id` | NIPR AWS account ID | `123456789012` |
| `PKR_VAR_aws_vpc_id` | VPC ID in NIPR | `vpc-abc123` |
| `PKR_VAR_aws_subnet_id` | Subnet ID in NIPR | `subnet-xyz789` |
| `PKR_VAR_aws_nipr_ami_regions` | Target regions | `["us-east-1"]` |
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
   - Pipeline will run `extract:archives` (manual job)
   - Click **▶** button on `extract:archives` job
   - Wait for extraction to complete
   - `configure:repos` job runs automatically after extraction

4. **Verify setup**:
   - Check job logs for successful extraction
   - Verify repositories configured: `sudo dnf repolist`

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

#### configure:repos (Automatic)

Configures local YUM/DNF repositories.

```yaml
needs: ["extract:archives"]
when: on_success
```

**Run when**: After successful extraction

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

## Complete Workflow Example

### Month 1: Initial Setup

**Internet System (GitHub Actions)**:
```bash
# Automatic on 15th of month, or manually trigger
# Downloads: mirrors, roles, packages
# Creates: spel-*.tar.gz archives
# Uploads to GitHub artifacts
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
# Only changed components need transfer (usually just mirrors)
```

**Transfer**:
```bash
# Transfer only updated archives (e.g., mirrors only)
# Much smaller transfer size for incremental updates
```

**NIPR System (GitLab CI)**:
```bash
# Update only changed archives in repository
# Re-run extract:archives if needed
# Build AMIs with existing setup
```

## Troubleshooting

### GitHub Actions Issues

**Problem**: Mirror sync fails
```bash
Solution: Check network connectivity, retry workflow
```

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

**Problem**: Configure repos fails - permission denied
```bash
Solution: Add gitlab-runner to sudoers for setup-local-repos.sh
sudo visudo
```

**Problem**: Build fails - cannot access repositories
```bash
Solution: Verify local repos configured
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

- **Mirrors**: 30-50 GB
- **Roles**: 100 MB
- **Packages**: 100 MB
- **Archives**: 12-20 GB
- **Total**: ~50-70 GB free space needed

### GitLab Runner (NIPR)

- **Extracted archives**: 31-51 GB
- **Build artifacts**: 10-20 GB
- **Packer cache**: 5-10 GB
- **Total**: ~60-80 GB free space needed

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
