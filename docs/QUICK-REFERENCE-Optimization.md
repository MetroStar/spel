# NIPR Transfer & GitLab CI Quick Reference

## Pipeline Overview

### GitLab CI Stages

| Stage | Jobs | Duration | Trigger | Purpose |
|-------|------|----------|---------|---------|
| **Extract** | 1 | 2-3 min | Manual | Extract and verify archives |
| **Infra** | 3 | 2-3 min | Manual (one-time) | Create AWS resources |
| **Setup** | 6 | 4-5 min | Auto | Verify environment, init dependencies |
| **Validate** | 2 | 1 min | Auto | Validate Packer templates |
| **Build** | 1-9 | 2-5 hr each | Manual | Build AMI images |

**Total Time**:
- Initial setup: ~10 min (extract + infra + setup + validate)
- Monthly builds: ~6 min (setup + validate) + build time
- Quick rebuild: ~6 min setup + build time

## First-Time NIPR Setup

### Step 1: Prepare Archives on Internet System
```bash
# GitHub Actions runs automatically on 15th of month
# Or manually trigger workflow at:
# https://github.com/MetroStar/spel/actions/workflows/nipr-prepare.yml

# Workflow duration: 5-8 minutes (includes ClamAV virus scan)

# Download artifacts after workflow completes:
# - spel-nipr-YYYYMMDD-base.tar.gz (118 MB)
# - spel-nipr-YYYYMMDD-tools.tar.gz (289 MB)  
# - spel-nipr-YYYYMMDD-complete.tar.gz (694 MB)
# - spel-nipr-YYYYMMDD-checksums.txt
# - spel-nipr-YYYYMMDD-manifest.txt
# - spel-nipr-YYYYMMDD-clamav-scan.log (security audit trail)

# Verify security scan passed (check GitHub Actions summary)
# ClamAV scans ~1.6 GB across 7 directories (3-5 min)
# Scan log shows: Infected files: 0

# Verify checksums before transfer
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt
```

### Step 2: Transfer to NIPR
```bash
# Transfer via approved method (DVD, secure transfer, etc.)
# Total transfer size: ~1.1 GB (includes virus scan log)
# Verify checksums after transfer
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt

# Review security scan log for compliance
less spel-nipr-YYYYMMDD-clamav-scan.log
# Verify: "Infected files: 0" in scan summary
```

### Step 3: Upload to GitLab NIPR
```bash
# Clone your NIPR GitLab repository
git clone https://your-gitlab-nipr-instance.mil/your-group/spel.git
cd spel/

# Add archives and security artifacts
git lfs track "*.tar.gz"
git add .gitattributes spel-*.tar.gz \
  spel-nipr-*-checksums.txt \
  spel-nipr-*-manifest.txt \
  spel-nipr-*-clamav-scan.log
git commit -m "Add NIPR transfer archives for December 2025 (virus scan: clean)"
git push
```

### Step 4: Extract Archives
```bash
# In GitLab: CI/CD → Pipelines → Run pipeline
# Set variable: EXTRACT_ARCHIVES=true
# Click "Run pipeline"
# Manually click ▶ on "extract:archives" job
# Wait 2-3 minutes for extraction
```

### Step 5: Create Infrastructure (One-Time)
```bash
# In GitLab: CI/CD → Pipelines → Run pipeline  
# Set variable: CREATE_INFRASTRUCTURE=true
# Click "Run pipeline"
# Manually trigger jobs in order:
#   1. infra:network (creates VPC, IGW, subnet)
#   2. infra:security_group (creates security group)
#   3. infra:iam (creates IAM role, instance profile)
# Infrastructure IDs saved to artifacts (90-day retention)
```

### Step 6: Build AMIs
```bash
# In GitLab: CI/CD → Pipelines → Run pipeline
# Set variables for desired OS builds:
#   RUN_RHEL9=true
#   RUN_OL9=true
# Click "Run pipeline"
# Setup + validate run automatically (5-6 min)
# Manually click ▶ on build:rhel9 or build:ol9
# Wait 2-5 hours per build
```

## Normal Monthly Builds

### Step 1: Update Archives (if new transfer)
```bash
# Transfer new archives to NIPR
# Update in GitLab repository
git add spel-*.tar.gz spel-nipr-*-checksums.txt
git commit -m "Update archives for $(date +%Y%m)"
git push

# Run pipeline with EXTRACT_ARCHIVES=true to re-extract
```

### Step 2: Run Builds
```bash
# In GitLab: CI/CD → Pipelines → Run pipeline
# Set desired OS variables (e.g., RUN_RHEL9=true)
# Click "Run pipeline"
# Setup + validate run automatically
# Click ▶ on desired build:* jobs
```

## Quick Rebuild (No Archive Updates)

```bash
# In GitLab: CI/CD → Pipelines → Run pipeline
# Set RUN_<OS>=true for specific OS
# Click "Run pipeline"
# Setup + validate run automatically (5-6 min)
# Click ▶ on build:<os> job
```

## Archive Contents Breakdown

### GitHub Actions Output (Total: 1.1 GB)

**Base Archive** (`spel-nipr-YYYYMMDD-base.tar.gz`): **118 MB**
- SPEL packages: 56 KB
- Ansible roles: 4 MB (git clones without history)
- Offline packages: 86 MB (AWS CLI, utilities)
- Scripts and configs: minimal

**Tools Archive** (`spel-nipr-YYYYMMDD-tools.tar.gz`): **289 MB**
- Packer binaries: 97 MB (Linux 49 MB + Windows 48 MB)
- Packer plugins: 241 MB (Amazon, Ansible, PowerShell)
- Python packages: 16 MB (wheels)
- Ansible collections: 3.5 MB (tarballs)

**Complete Archive** (`spel-nipr-YYYYMMDD-complete.tar.gz`): **694 MB**
- Everything from base + tools combined
- Optional (use for initial setup or when transferring everything)

### Component Sizes (Extracted)

| Component | Size | Notes |
|-----------|------|-------|
| SPEL packages | 56 KB | RPM packages for offline installs |
| Ansible roles | 4 MB | Git clones (vendor/ansible-roles/) |
| Ansible collections | 3.5 MB | Tarballs (ansible.windows, community.windows, community.general) |
| Offline packages | 86 MB | AWS CLI, boto3, utilities |
| Packer Linux | 49 MB | Packer v1.11.2 for Linux |
| Packer Windows | 48 MB | Packer v1.11.2 for Windows |
| Packer plugins | 241 MB | Amazon, Ansible, PowerShell plugins |
| Python packages | 16 MB | Wheels (boto3, ansible-core, pywinrm) |
| **Total Extracted** | **~447 MB** | Decompresses to working environment |

## CI/CD Variables Reference

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AWS_GOVCLOUD_ACCESS_KEY_ID` | GovCloud access key | `AKIA...` |
| `AWS_GOVCLOUD_SECRET_ACCESS_KEY` | GovCloud secret key | `wJa...` |
| `PKR_VAR_aws_nipr_account_id` | AWS account ID | `123456789012` |
| `PKR_VAR_aws_vpc_id` | VPC ID (if not using infra stage) | `vpc-abc123` |
| `PKR_VAR_aws_subnet_id` | Subnet ID (if not using infra stage) | `subnet-xyz789` |

### Optional Variables - Build Control

| Variable | Description | Default |
|----------|-------------|---------|
| `EXTRACT_ARCHIVES` | Enable archive extraction | `false` |
| `RUN_AMZN2023` | Build Amazon Linux 2023 | `false` |
| `RUN_RHEL9` | Build RHEL 9 | `false` |
| `RUN_RHEL8` | Build RHEL 8 | `false` |
| `RUN_OL9` | Build Oracle Linux 9 | `false` |
| `RUN_OL8` | Build Oracle Linux 8 | `false` |
| `RUN_WS2016` | Build Windows Server 2016 | `false` |
| `RUN_WS2019` | Build Windows Server 2019 | `false` |
| `RUN_WS2022` | Build Windows Server 2022 | `false` |

### Optional Variables - Infrastructure Control

| Variable | Description | Default |
|----------|-------------|---------|
| `CREATE_INFRASTRUCTURE` | Enable infrastructure jobs | `false` |
| `INFRA_PREFIX` | Prefix for resource names | `spel-packer` |
| `INFRA_TAGS` | JSON tags for resources | `{"Project":"SPEL"}` |
| `PKR_VAR_aws_nipr_ami_regions` | Regions for AMI copy | `["us-gov-east-1"]` |

## Build Times by OS

| Operating System | Minimal Build | Hardened Build |
|-----------------|---------------|----------------|
| Amazon Linux 2023 | 30-45 min | 2-3 hr |
| RHEL 9 | 45-60 min | 3-4 hr |
| RHEL 8 | 45-60 min | 3-4 hr |
| Oracle Linux 9 | 45-60 min | 3-4 hr |
| Oracle Linux 8 | 45-60 min | 3-4 hr |
| Windows Server 2016 | 60-90 min | 4-5 hr |
| Windows Server 2019 | 60-90 min | 4-5 hr |
| Windows Server 2022 | 60-90 min | 4-5 hr |

*Times vary based on instance type, network, and hardening level*

## Storage Requirements

### Internet System (GitHub Actions Runner)
- Workspace: 500 MB
- Dependencies download: 1.5 GB
- ClamAV virus definitions: ~300 MB
- Archives created: 1.1 GB
- **Total needed**: ~3.4 GB free space

### Transfer Media
- **Total transfer**: 1.1 GB
  - Base archive: 118 MB
  - Tools archive: 289 MB
  - Complete archive: 694 MB (optional)
  - Checksums: minimal
  - Manifest: minimal
  - ClamAV scan log: ~50 KB (security audit trail)

### NIPR System (GitLab Runner)
- Extracted archives: ~1 GB
- Python venv: ~200 MB (created by `python:setup`)
- Packer plugin cache: ~300 MB (after `packer:init`)
- Build workspace per job: 10-20 GB
- Packer cache: 5-10 GB
- **Total for single build**: 17-32 GB free space
- **Total for concurrent builds**: Add 15-30 GB per additional build

## Troubleshooting Quick Reference

### Extract Stage
```bash
# Archives not found
ls -lh spel-*.tar.gz

# Checksum failed
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt

# Extraction incomplete
ls -lh tools/packer-linux/
ls -lh vendor/ansible-roles/
```

### Infrastructure Stage
```bash
# VPC creation failed - check quota
aws ec2 describe-account-attributes --attribute-names vpc-quota

# IAM creation failed - check permissions
aws iam get-user

# Artifacts missing - check retention
cat infra.env  # Should show VPC_ID, SUBNET_ID, etc.
```

### Setup Stage
```bash
# Disk space check failed
df -h  # Need 50+ GB free

# Memory check failed
free -h  # Need 2+ GB available

# AWS verify failed - no IGW
aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$PKR_VAR_aws_vpc_id"

# Python setup failed - missing wheels
ls -lh tools/python-deps/

# Packer init failed - missing plugins
ls -lh tools/packer-plugins/

# Submodules empty
git submodule update --init --recursive
ls -lh vendor/amigen8/ vendor/amigen9/
```

### Security Scanning
```bash
# Verify scan passed (on Internet system, GitHub Actions summary)
# Look for: "Security Scan: ✅ PASSED (0 infected files)"

# Review scan log details
less spel-nipr-YYYYMMDD-clamav-scan.log

# Check scan summary
grep "SCAN SUMMARY" -A 10 spel-nipr-YYYYMMDD-clamav-scan.log
# Verify: "Infected files: 0"
# Typical: 5000+ files scanned, 3-5 min duration

# If virus detected (workflow fails)
grep "FOUND" spel-nipr-YYYYMMDD-clamav-scan.log
# Investigate detected files, verify false positives

# ClamAV version check (on Internet system)
freshclam --version
clamscan --version
# Database should have 8M+ signatures
```

### Build Stage
```bash
# Cannot access repositories
# SSH into builder instance
ssh -i <key> ec2-user@<ip>
sudo dnf repolist

# Ansible connection timeout
# Check security group allows SSH (22) or WinRM (5985, 5986)
aws ec2 describe-security-groups --group-ids $PKR_VAR_aws_security_group_id

# AMI quota exceeded
aws ec2 describe-images --owners self | grep ami-
# Deregister old AMIs
```

## Quick Commands

### Check Pipeline Status
```bash
# View all pipelines
gitlab-ci-multi-runner list

# View specific pipeline
curl -H "PRIVATE-TOKEN: <token>" \
  "https://gitlab.mil/api/v4/projects/<id>/pipelines"

# View job logs
curl -H "PRIVATE-TOKEN: <token>" \
  "https://gitlab.mil/api/v4/projects/<id>/jobs/<job-id>/trace"
```

### Verify Environment
```bash
# Check disk space (need 50+ GB)
df -h /

# Check memory (need 2+ GB)
free -h

# Check AWS connectivity
aws sts get-caller-identity

# Check VPC has IGW
aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$PKR_VAR_aws_vpc_id"

# Check Packer offline mode
ls -lh tools/packer-linux/packer
./tools/packer-linux/packer version

# Check Python environment
ls -lh .venv/
source .venv/bin/activate && python --version
```

### Clean Up Resources
```bash
# Clean Packer cache
rm -rf ~/.packer.d/tmp/*

# Clean build artifacts
rm -rf spel-artifacts-*

# Clean old venv
rm -rf .venv/

# Re-extract archives
./scripts/extract-nipr-archives.sh
```

## Monthly Workflow Calendar

### Days 1-14: Preparation
- Monitor for security updates
- Plan OS builds for the month
- Verify GitLab runner health

### Day 15: GitHub Actions Run
- Automatic workflow execution (or manual trigger)
- Download archives from GitHub artifacts
- Verify checksums before transfer

### Days 16-20: Transfer to NIPR
- Transfer archives via approved method
- Verify checksums after transfer
- Upload to GitLab NIPR repository

### Days 21-25: AMI Builds
- Extract archives (if updated)
- Run GitLab CI pipeline
- Build selected OS AMIs
- Verify AMI IDs and test instances

### Days 26-31: Validation & Cleanup
- Test AMIs in NIPR environment
- Document any issues
- Clean up old AMIs and artifacts
- Update runbooks if needed

## Documentation References

- **Full CI/CD Setup Guide**: `docs/CI-CD-Setup.md` - Complete pipeline documentation
- **Storage Optimization**: `docs/Storage-Optimization.md` - Detailed optimization strategies
- **NIPR Setup**: `docs/NIPR-Setup.md` - NIPR environment configuration
- **GitHub Actions Workflow**: `.github/workflows/nipr-prepare.yml` - Automated preparation
- **GitLab CI Pipeline**: `.gitlab-ci.yml` - NIPR build automation
- **Offline Packages**: `offline-packages/README.md` - Package details
- **Build Tools**: `tools/README.md` - Packer and Python tools

## Success Criteria

✅ Archives total ~1.1 GB compressed  
✅ All checksums verify successfully  
✅ Extract completes without errors  
✅ Infrastructure created (one-time) or variables configured  
✅ Setup stage passes all verification jobs (6/6)  
✅ Validate stage passes (2/2 templates valid)  
✅ Build succeeds using RHUI repositories in AWS GovCloud  
✅ AMI IDs output in build job logs  
✅ Test instances launch successfully from built AMIs
