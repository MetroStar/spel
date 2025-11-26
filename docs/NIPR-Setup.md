# NIPR Environment Setup Guide for SPEL

This guide provides step-by-step instructions for setting up and building SPEL AMIs in the NIPR (Non-classified Internet Protocol Router Network) air-gapped environment.

## Overview

The NIPR environment requires all dependencies, source code, and packages to be pre-staged locally due to lack of internet connectivity. This guide covers:

1. Preparing dependencies on an internet-connected system
2. Transferring artifacts to NIPR
3. Configuring the NIPR build environment
4. Running builds via GitLab CI

**Storage Optimization**: See [`docs/Storage-Optimization.md`](Storage-Optimization.md) for detailed strategies to reduce storage requirements from 100-160 GB to 30-50 GB (70% reduction).

## Prerequisites

### Internet-Connected System Requirements

- RHEL/Rocky Linux 8 or 9
- Git 2.x+
- Python 3.9+
- DNF/YUM with reposync capability
- ~50 GB free disk space for mirrors and tools

### NIPR System Requirements

- RHEL/Rocky Linux 8 or 9
- GitLab runner with tag `spel-nipr-runner`
- Access to NIPR marketplace AMIs
- VPC with EC2, S3, and SSM VPC endpoints configured
- ~50 GB free disk space

## Part 1: Preparing Dependencies (Internet-Connected System)

### 1.1 Clone SPEL Repository with Submodules

```bash
git clone --recurse-submodules https://github.com/MetroStar/spel.git
cd spel/

# Verify submodules are initialized
git submodule status
# Should show vendor/amigen8 and vendor/amigen9
```

### 1.2 Vendor Ansible Roles from GitHub

Use the automated vendoring script for storage-optimized roles:

```bash
# Download and optimize Ansible roles (saves 80% vs full git clones)
SPEL_ROLES_REMOVE_GIT=true \
SPEL_ROLES_COMPRESS=true \
./scripts/vendor-ansible-roles.sh
```

This script:
- Clones latest versions without git history (--depth 1)
- Removes .git directories to save space
- Creates compressed `ansible-roles.tar.gz` archive
- Supports specific version tags via `SPEL_ROLES_TAG`

**Manual vendoring** (if needed):

```bash
# Create roles directory
mkdir -p spel/ansible/roles/
cd spel/ansible/roles/

# RHEL 8 STIG
git clone https://github.com/ansible-lockdown/RHEL8-STIG.git

# RHEL 9 STIG
git clone https://github.com/ansible-lockdown/RHEL9-STIG.git

# Amazon Linux 2023 CIS
git clone https://github.com/ansible-lockdown/AMAZON2023-CIS.git

# Windows STIGs (if building Windows images)
git clone https://github.com/ansible-lockdown/Windows-2016-STIG.git
git clone https://github.com/ansible-lockdown/Windows-2019-STIG.git
git clone https://github.com/ansible-lockdown/Windows-2022-STIG.git

cd ../../..
```

**Note**: The roles are vendored as full git clones to preserve version history. Consider using specific tagged releases for production:

```bash
cd spel/ansible/roles/RHEL8-STIG/
git checkout <specific-tag>  # e.g., v1.2.3
cd ../../..
```

### 1.3 Create YUM/DNF Repository Mirrors

Use the optimized sync script to mirror EL8/EL9 repositories:

```bash
# Optimized sync (recommended - saves 70% storage)
SPEL_MIRROR_EXCLUDE_DEBUG=true \
SPEL_MIRROR_EXCLUDE_SOURCE=true \
SPEL_MIRROR_COMPRESS=true \
./scripts/sync-mirrors.sh

# This will:
# - Exclude debuginfo and source packages (saves ~60%)
# - Create compressed .tar.gz archives (saves ~50% transfer size)
# - Use hardlinks for deduplication (saves ~10%)
# - Take ~20-30 minutes and use ~30-50 GB (vs 100-160 GB unoptimized)
```

**Full sync** (if you need all packages including debug/source):

```bash
# Review and customize the sync script if needed
cat scripts/sync-mirrors.sh

# Run repository synchronization (takes ~30 minutes, uses ~100-160 GB)
sudo ./scripts/sync-mirrors.sh

# Verify mirrors were created
ls -lh mirrors/el8/ mirrors/el9/
```

### 1.4 Mirror SPEL Custom Packages

Sync the minimal SPEL package repository:

```bash
# Run SPEL packages sync
./scripts/sync-spel-packages.sh

# Verify SPEL packages
ls -lh mirrors/spel-packages/
# Should contain spel-release RPMs
```

### 1.5 Download Offline Build Tools

#### Packer Binary

```bash
# Set desired version
PACKER_VERSION="1.9.4"

# Download for Linux x86_64
wget https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip \
  -O /tmp/packer.zip

# Extract to tools directory
unzip /tmp/packer.zip -d tools/packer/
chmod +x tools/packer/packer
```

#### Packer Plugins

```bash
# Initialize Packer to download required plugins
./tools/packer/packer init spel/minimal-linux.pkr.hcl
./tools/packer/packer init spel/hardened-linux.pkr.hcl

# Copy plugin cache
mkdir -p tools/packer/plugins/
cp -r ~/.config/packer/plugins/ tools/packer/
```

#### Python Dependencies

```bash
# Create requirements file
cat > /tmp/spel-requirements.txt <<'EOF'
ansible-core>=2.16.0,<2.19.0
pywinrm>=0.4.3
requests>=2.31.0
passlib>=1.7.4
lxml>=4.9.0
xmltodict>=0.13.0
jmespath>=1.0.1
EOF

# Download all wheels
pip download -r /tmp/spel-requirements.txt \
  --dest tools/python-deps/ \
  --platform manylinux2014_x86_64 \
  --python-version 3.9
```

### 1.6 Download AWS Utilities for Offline Installation

Use the automated download script:

```bash
# Download and optimize all AWS utilities
SPEL_OFFLINE_COMPRESS=true \
./scripts/download-offline-packages.sh

# This creates:
# - awscli-exe-linux-x86_64.zip
# - aws-cfn-bootstrap-py3-latest.tar.gz
# - amazon-ssm-agent.rpm (single file for both EL8/EL9)
# - VERSIONS.txt (version tracking with SHA256 checksums)
# - offline-packages.tar.gz (compressed archive)
```

**Manual download** (if needed):

```bash
# AWS CLI v2
wget https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
  -O offline-packages/awscli-exe-linux-x86_64.zip

# CloudFormation Bootstrap
wget https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz \
  -O offline-packages/aws-cfn-bootstrap-py3-latest.tar.gz

# SSM Agent (single version compatible with both EL8 and EL9)
wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm \
  -O offline-packages/amazon-ssm-agent.rpm
```

### 1.7 Create Transfer Archive

Use the optimized archive creation script:

```bash
# Create separate component archives (recommended)
./scripts/create-transfer-archive.sh

# This creates:
# - spel-base-YYYYMMDD.tar.gz           (~500 MB - code, scripts, configs)
# - spel-mirrors-compressed-YYYYMMDD.tar.gz  (~10-18 GB - optimized repos)
# - spel-tools-YYYYMMDD.tar.gz          (~400 MB - Packer, Python, packages)
# - spel-nipr-YYYYMMDD-checksums.txt    (SHA256 verification)
```

**Alternative - single combined archive**:

```bash
# Create complete archive for transfer
SPEL_ARCHIVE_SEPARATE=false \
./scripts/create-transfer-archive.sh

# Single archive: spel-nipr-complete-YYYYMMDD.tar.gz (~12-20 GB)
```

**Legacy manual method**:

```bash
# Create complete archive for NIPR transfer
tar czf spel-nipr-offline-$(date +%Y%m%d).tar.gz \
  --exclude='.git' \
  --exclude='*.pyc' \
  --exclude='__pycache__' \
  .

# Verify archive size
ls -lh spel-nipr-offline-*.tar.gz
# Should be ~15-20 GB compressed
```

**Generate checksums for verification**:

```bash
# Already done by create-transfer-archive.sh, or manually:
sha256sum spel-nipr-*.tar.gz > checksums.txt
```

## Part 2: Transferring to NIPR

Transfer the archive to NIPR using your organization's approved secure transfer method:

- Sneakernet (physical media)
- Approved secure file transfer system
- Cross-domain solution (CDS)

**Security Note**: Ensure the archive is scanned for malware before and after transfer per your organization's security policies.

## Part 3: NIPR Environment Setup

### 3.1 Extract Archive in NIPR

Use the automated extraction script:

```bash
# On NIPR system, verify checksums first
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt

# Extract all archives automatically
cd /opt/builds/spel/  # Or your preferred location
./scripts/extract-nipr-archives.sh

# This script:
# - Verifies checksums
# - Extracts all component archives
# - Decompresses repository mirrors
# - Initializes git submodules
# - Validates extraction
```

**Manual extraction** (if needed):

```bash
# On NIPR system, extract the archive
cd /opt/builds/  # Or your preferred location
tar xzf spel-nipr-offline-YYYYMMDD.tar.gz
cd spel/
```

### 3.2 Initialize Git Submodules

```bash
# Initialize the vendored AMIgen submodules
git submodule init
git submodule update
```

### 3.3 Configure Local Package Repositories

```bash
# Run the repository setup script
sudo ./scripts/setup-local-repos.sh

# Verify repos are configured
sudo dnf repolist
# Should show local-baseos, local-appstream, local-spel, etc.
```

### 3.4 Configure GitLab CI Variables

In your GitLab project, configure the following CI/CD variables:

#### Required Variables

| Variable | Value | Description |
|----------|-------|-------------|
| `SPEL_OFFLINE_MODE` | `true` | Enables offline build mode |
| `PKR_VAR_aws_nipr_account_id` | `<NIPR-ACCOUNT-ID>` | NIPR AWS account ID for marketplace AMIs |
| `PKR_VAR_aws_vpc_id` | `vpc-xxxxxxxxx` | VPC ID for Packer builds |
| `PKR_VAR_aws_vpc_endpoint_ec2` | `vpce-xxxxxxxxx.ec2.us-gov-west-1.vpce.amazonaws.com` | EC2 VPC endpoint DNS |
| `PKR_VAR_aws_vpc_endpoint_s3` | `vpce-xxxxxxxxx.s3.us-gov-west-1.vpce.amazonaws.com` | S3 VPC endpoint DNS |
| `PKR_VAR_aws_vpc_endpoint_ssm` | `vpce-xxxxxxxxx.ssm.us-gov-west-1.vpce.amazonaws.com` | SSM VPC endpoint DNS |

#### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PKR_VAR_aws_nipr_ami_regions` | (none) | JSON list of regions to copy AMIs to |
| `PKR_VAR_spel_cfnbootstrap_source` | `file://...` | Override CloudFormation bootstrap source |
| `PKR_VAR_spel_awscli_source` | `file://...` | Override AWS CLI source |
| `PKR_VAR_spel_ssm_agent_source` | `file://...` | Override SSM Agent source |

#### Setting Variables in GitLab

1. Navigate to **Settings → CI/CD → Variables**
2. Click **Add variable**
3. Enter the variable key and value
4. Set appropriate **Protect** and **Mask** options
5. Save

### 3.5 Configure VPC Endpoints

Ensure your NIPR VPC has the following VPC endpoints configured:

```hcl
# EC2 endpoint (interface type)
resource "aws_vpc_endpoint" "ec2" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.us-gov-west-1.ec2"
  vpc_endpoint_type = "Interface"
  
  subnet_ids = var.private_subnet_ids
  
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
}

# S3 endpoint (gateway type)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.us-gov-west-1.s3"
  vpc_endpoint_type = "Gateway"
  
  route_table_ids = var.route_table_ids
}

# SSM endpoint (interface type)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.us-gov-west-1.ssm"
  vpc_endpoint_type = "Interface"
  
  subnet_ids = var.private_subnet_ids
  
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
}
```

**Security Group Requirements**:
- Allow HTTPS (443) inbound from VPC CIDR
- Allow all outbound traffic

### 3.6 Verify NIPR Marketplace AMI Access

Ensure your NIPR account has access to the required marketplace AMIs:

```bash
# Test AMI discovery (replace with your region)
aws ec2 describe-images \
  --region us-gov-west-1 \
  --owners <NIPR-ACCOUNT-ID> \
  --filters "Name=name,Values=RHEL-9*" \
  --query 'Images[*].[ImageId,Name,CreationDate]' \
  --output table
```

Expected marketplace AMI sources:
- **RHEL 8**: Red Hat Enterprise Linux 8
- **RHEL 9**: Red Hat Enterprise Linux 9
- **OL 8/9**: Oracle Linux 8/9 (if applicable)
- **CentOS Stream 9**: CentOS Stream 9 (if applicable)

## Part 4: Running Builds in NIPR

### 4.1 Manual Build Verification

Before using GitLab CI, verify the environment manually:

```bash
# Set offline mode
export SPEL_OFFLINE_MODE=true

# Run CI setup script
./build/ci-setup.sh
# Should show: "Offline mode detected"

# Validate Packer templates
./tools/packer/packer validate spel/minimal-linux.pkr.hcl

# Run a test build (minimal RHEL 9)
./tools/packer/packer build \
  -var aws_nipr_account_id="<ACCOUNT-ID>" \
  -var aws_vpc_id="vpc-xxxxxxxxx" \
  -var aws_vpc_endpoint_ec2="vpce-xxx.ec2.region.vpce.amazonaws.com" \
  -var aws_vpc_endpoint_s3="vpce-xxx.s3.region.vpce.amazonaws.com" \
  -var aws_vpc_endpoint_ssm="vpce-xxx.ssm.region.vpce.amazonaws.com" \
  -var spel_identifier_rhel="true" \
  -var spel_version="$(git describe --tags --always)" \
  -only 'amazon-ebssurrogate.minimal-rhel-9-hvm' \
  spel/minimal-linux.pkr.hcl
```

### 4.2 GitLab CI Pipeline

The `.gitlab-ci.yml` pipeline includes:

#### Stages

1. **setup**: Prepare build environment
2. **validate**: Validate Packer templates
3. **build**: Build AMIs (manual trigger)

#### Running Builds

Builds are configured with manual triggers to prevent accidental launches:

1. Navigate to **CI/CD → Pipelines**
2. Click on the latest pipeline
3. In the **build** stage, click the **▶ Play** button next to desired build job:
   - `build-minimal-rhel-8`
   - `build-minimal-rhel-9`
   - `build-minimal-ol-8`
   - `build-minimal-ol-9`
   - `build-hardened-rhel-8`
   - `build-hardened-rhel-9`

#### Triggering via API

```bash
# Trigger pipeline with specific variables
curl --request POST \
  --form token=<PIPELINE-TOKEN> \
  --form ref=main \
  --form "variables[SPEL_BUILD_TARGET]=minimal-rhel-9" \
  "https://gitlab.nipr.mil/api/v4/projects/<PROJECT-ID>/trigger/pipeline"
```

### 4.3 Monitoring Builds

Monitor build progress:

1. **GitLab UI**: Navigate to **CI/CD → Pipelines → [Pipeline]** → Job logs
2. **Build Artifacts**: AMI IDs are output in job logs
3. **AWS Console**: Check EC2 → AMIs for newly created images

## Part 5: Maintenance and Updates

### 5.1 Updating Repository Mirrors

Periodically update package mirrors on the internet-connected system:

```bash
# On internet-connected system
cd /path/to/spel/
sudo ./scripts/sync-mirrors.sh

# Create incremental archive
tar czf mirrors-update-$(date +%Y%m%d).tar.gz mirrors/

# Transfer to NIPR and extract
```

### 5.2 Updating Ansible Roles

Update vendored roles to latest versions:

```bash
# On internet-connected system
cd spel/ansible/roles/RHEL9-STIG/
git fetch --all
git checkout <latest-tag>
cd ../../..

# Re-create transfer archive with updated roles
```

### 5.3 Updating Build Tools

Update Packer, Python packages, or AWS utilities:

```bash
# On internet-connected system
# Example: Update Packer
PACKER_VERSION="1.10.0"
wget https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip \
  -O /tmp/packer.zip
unzip /tmp/packer.zip -d tools/packer/

# Update Python dependencies
pip download -r /tmp/spel-requirements.txt \
  --dest tools/python-deps/ \
  --platform manylinux2014_x86_64 \
  --python-version 3.9

# Re-create transfer archive
```

### 5.4 Updating AMIgen Submodules

Update AMIgen to latest versions:

```bash
# On internet-connected system
git submodule update --remote vendor/amigen8
git submodule update --remote vendor/amigen9
git commit -am "Update AMIgen submodules"

# Re-create transfer archive
```

## Part 6: Troubleshooting

### Build Failures

#### VPC Endpoint Connection Issues

**Symptom**: Packer fails with timeout connecting to EC2/S3 services

**Solution**:
1. Verify VPC endpoint DNS names in GitLab variables
2. Check security group rules allow HTTPS (443) from VPC CIDR
3. Ensure `private_dns_enabled = true` on interface endpoints
4. Test connectivity from build runner:
   ```bash
   curl -I https://ec2.us-gov-west-1.amazonaws.com
   # Should resolve to VPC endpoint private IP
   ```

#### Source AMI Not Found

**Symptom**: Packer fails with "No AMI found matching filters"

**Solution**:
1. Verify `PKR_VAR_aws_nipr_account_id` is set correctly
2. Check marketplace AMI access in NIPR account:
   ```bash
   aws ec2 describe-images \
     --owners <NIPR-ACCOUNT-ID> \
     --filters "Name=name,Values=RHEL-9*"
   ```
3. Update source AMI filter patterns in `*.pkr.hcl` if needed

#### Repository Metadata Errors

**Symptom**: YUM/DNF fails with "Failed to synchronize cache"

**Solution**:
1. Regenerate repository metadata:
   ```bash
   cd mirrors/el9/baseos/
   sudo createrepo_c .
   ```
2. Clear DNF cache:
   ```bash
   sudo dnf clean all
   sudo dnf makecache
   ```

#### Ansible Role Not Found

**Symptom**: Packer provisioner fails with "Role not found"

**Solution**:
1. Verify roles are in `spel/ansible/roles/`:
   ```bash
   ls -la spel/ansible/roles/
   ```
2. Check role names in `requirements.yml` match directory names
3. Ensure `.gitkeep` was removed after vendoring roles

### Performance Optimization

#### Parallel Builds

Run multiple builds simultaneously if resources allow:

```bash
# Set max parallel builds
export PACKER_MAX_PROCS=2

# Run multiple builds
./tools/packer/packer build -parallel-builds=2 ...
```

#### Mirror Optimization

Reduce mirror size by syncing only required packages:

```bash
# Edit sync-mirrors.sh to add --downloadcomps and --download-metadata
dnf reposync \
  --repoid=baseos \
  --download-path=mirrors/el9/ \
  --newest-only \
  --downloadcomps \
  --download-metadata
```

## Part 7: Security Considerations

### Artifact Verification

Always verify transferred artifacts:

```bash
# Generate checksums on internet-connected system
sha256sum spel-nipr-offline-*.tar.gz > checksums.txt

# Verify in NIPR
sha256sum -c checksums.txt
```

### Regular Updates

- Update mirrors monthly for security patches
- Update Ansible roles quarterly for STIG updates
- Update tools semi-annually or as needed

### Access Control

- Restrict GitLab runner to dedicated service accounts
- Use IAM roles for AWS API access (no long-lived credentials)
- Encrypt archives during transfer with approved encryption

## Appendix A: Complete Transfer Checklist

Use this checklist when transferring SPEL to NIPR:

- [ ] Clone SPEL repository with submodules
- [ ] Vendor all Ansible roles from GitHub
- [ ] Sync EL8/EL9 YUM repositories (~30 GB)
- [ ] Sync SPEL custom packages (~100 MB)
- [ ] Download Packer binary and plugins (~300 MB)
- [ ] Download Python dependencies (~50 MB)
- [ ] Download AWS utilities (CLI, CFN, SSM) (~100 MB)
- [ ] Create transfer archive
- [ ] Generate SHA256 checksums
- [ ] Transfer via approved method
- [ ] Verify checksums in NIPR
- [ ] Extract archive
- [ ] Initialize submodules
- [ ] Configure local repositories
- [ ] Set GitLab CI variables
- [ ] Verify VPC endpoints
- [ ] Test manual build
- [ ] Configure GitLab runner
- [ ] Run pipeline validation
- [ ] Document NIPR-specific configuration

## Appendix B: Directory Structure Reference

```
spel/
├── .gitlab-ci.yml              # GitLab CI pipeline for NIPR
├── build/
│   └── ci-setup.sh            # Unified CI setup with offline detection
├── docs/
│   └── NIPR-Setup.md          # This file
├── mirrors/                    # Local package mirrors
│   ├── el8/                   # RHEL 8 repositories
│   ├── el9/                   # RHEL 9 repositories
│   ├── spel-packages/         # SPEL custom packages
│   └── README.md
├── offline-packages/           # AWS utilities for offline install
│   ├── awscli-exe-linux-x86_64.zip
│   ├── aws-cfn-bootstrap-py3-latest.tar.gz
│   ├── amazon-ssm-agent.rpm
│   └── README.md
├── scripts/
│   ├── sync-mirrors.sh        # Automated repository sync
│   ├── sync-spel-packages.sh  # SPEL packages sync
│   └── setup-local-repos.sh   # Configure local repos
├── spel/
│   ├── ansible/
│   │   ├── collections/       # Ansible collections (if needed)
│   │   └── roles/             # Vendored Ansible roles
│   │       ├── RHEL8-STIG/
│   │       ├── RHEL9-STIG/
│   │       └── AMAZON2023-CIS/
│   ├── hardened-linux.pkr.hcl # Hardened builds template
│   ├── minimal-linux.pkr.hcl  # Minimal builds template
│   └── userdata/
│       └── nipr-vpc-config.sh # VPC endpoint DNS config
├── tools/                      # Offline build tools
│   ├── packer/                # Packer binary and plugins
│   │   ├── packer
│   │   └── plugins/
│   ├── python-deps/           # Python wheel files
│   └── README.md
└── vendor/                     # Git submodules
    ├── amigen8/               # AMIgen for EL8
    └── amigen9/               # AMIgen for EL9
```

## Appendix C: Support and Resources

### Internal Documentation

- **AMIgen**: See `vendor/amigen8/docs/` and `vendor/amigen9/docs/`
- **Build Scripts**: See `build/README.md`
- **Packer Templates**: Inline comments in `*.pkr.hcl` files

### External Resources (Available in Commercial)

- **SPEL GitHub**: https://github.com/MetroStar/spel
- **Packer Documentation**: https://www.packer.io/docs
- **Ansible Lockdown**: https://github.com/ansible-lockdown

### Getting Help

For issues specific to NIPR deployments:

1. Check GitLab CI job logs for detailed error messages
2. Review this documentation's troubleshooting section
3. Contact your organization's SPEL administrator
4. For general SPEL issues, create issue on GitHub (from commercial network)
