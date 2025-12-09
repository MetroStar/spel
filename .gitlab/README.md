# GitLab CI Configuration

This directory contains GitLab CI pipeline configurations for the SPEL project.

## Pipeline Files

### `.gitlab-ci.yml` (Root)
**Purpose**: Main Offline build pipeline for air-gapped AWS GovCloud environments.

**When to use**: Automatically triggered when building SPEL images in the Offline environment.

**Key features**:
- Extracts and validates offline transfer archives
- Verifies ClamAV and TruffleHog security scans
- Creates AWS infrastructure (VPC, security groups, IAM roles)
- Builds SPEL images for multiple operating systems (RHEL, Oracle Linux, Amazon Linux, Windows)
- Runs in air-gapped environment with limited internet access

**Stages**:
1. `extract` - Extract archives and verify security scans
2. `infra` - Create AWS infrastructure components
3. `setup` - Install dependencies from offline archives
4. `validate` - Validate Packer configurations
5. `build` - Build AMIs for each OS variant

### `ci/offline-prepare.gitlab-ci.yml`
**Purpose**: Prepare offline transfer archives containing Packer, Ansible, and other dependencies.

**When to use**: Manually triggered when you need to update the offline transfer archives.

**Trigger**: Set the variable `PREPARE_OFFLINE_TRANSFER=true`

**Key features**:
- Runs in Offline environment with HTTP/HTTPS proxy support
- Downloads Packer binaries and plugins
- Downloads Ansible Core, collections, and roles
- Downloads Python packages
- Runs ClamAV virus scanning
- Runs TruffleHog secrets detection
- Creates two archive variants:
  - `offline-transfer-base.tar.gz` (~100 MB) - Core dependencies only
  - `offline-transfer-complete.tar.gz` (~500 MB) - All dependencies including Ansible collections/roles

**Environment requirements**:
- HTTP_PROXY and HTTPS_PROXY variables configured
- Access to package repositories via proxy
- spel-offline-runner tag

## Workflow Overview

### Initial Setup (First Time)
1. Run `offline-prepare.gitlab-ci.yml` to create offline transfer archives
   - Set `PREPARE_OFFLINE_TRANSFER=true`
   - Downloads all dependencies with security scanning
2. Transfer archives to air-gapped Offline environment
3. Run `.gitlab-ci.yml` to build SPEL images
   - Extracts archives
   - Verifies security scans passed
   - Builds AMIs

### Subsequent Updates
1. Run `offline-prepare.gitlab-ci.yml` to refresh dependencies
   - Set `PREPARE_OFFLINE_TRANSFER=true`
   - Downloads latest versions of Packer, Ansible, etc.
2. Transfer updated archives to Offline environment
3. Run `.gitlab-ci.yml` to build with updated dependencies

## Configuration Variables

### Offline Prepare Pipeline

#### Packer Configuration
- `PACKER_VERSION`: Packer version to download (default: 1.11.2)
- `PACKER_PLUGIN_VERSION_AMAZON`: Amazon plugin version (default: 1.3.3)
- `PACKER_PLUGIN_VERSION_ANSIBLE`: Ansible plugin version (default: 1.1.2)
- `DOWNLOAD_PACKER`: Download Packer binaries (default: true)
- `DOWNLOAD_PACKER_PLUGINS`: Download Packer plugins (default: true)

#### Ansible Configuration
- `ANSIBLE_CORE_MIN`: Minimum Ansible Core version (default: 2.14)
- `ANSIBLE_CORE_MAX`: Maximum Ansible Core version (default: 2.16)
- `DOWNLOAD_ANSIBLE_CORE`: Download Ansible Core (default: true)
- `DOWNLOAD_ANSIBLE_COLLECTIONS`: Download collections from requirements.yml (default: true)
- `DOWNLOAD_ANSIBLE_ROLES`: Download roles from requirements.yml (default: true)
- `INCLUDE_COLLECTION_DEPENDENCIES`: Include collection dependencies (default: true)

#### Python Configuration
- `PYTHON_VERSION`: Python version to use (default: 3.9)
- `DOWNLOAD_PYTHON_PACKAGES`: Download Python packages (default: true)

#### Archive Configuration
- `CREATE_BASE_ARCHIVE`: Create base archive (default: true)
- `CREATE_COMPLETE_ARCHIVE`: Create complete archive (default: true)

#### Security Configuration
- `RUN_TRUFFLEHOG`: Run TruffleHog secrets scan (default: true)

#### Proxy Configuration
- `HTTP_PROXY`: HTTP proxy URL (required in Offline environment)
- `HTTPS_PROXY`: HTTPS proxy URL (required in Offline environment)
- `NO_PROXY`: Comma-separated list of hosts to bypass proxy

## Archive Contents

### Base Archive (~100 MB)
- Packer binaries (Linux and Windows)
- Packer plugins (Amazon, Ansible)
- Python virtual environment with Ansible Core
- Installation scripts
- Security scan results (ClamAV, TruffleHog)

### Complete Archive (~500 MB)
- Everything in base archive, plus:
- Ansible collections from requirements.yml
- Ansible roles from requirements.yml
- Additional Python packages
- Collection dependencies

## Security Requirements

Both archives include security scan results that must pass before the main build pipeline will proceed:

1. **ClamAV**: Scans all downloaded files for viruses and malware
   - Results: `security-scans/clamav-scan.log`
   - Summary: `security-scans/clamav-summary.txt`

2. **TruffleHog**: Scans for exposed secrets, credentials, and API keys
   - Results: `security-scans/trufflehog-results.json`
   - Summary: `security-scans/trufflehog-summary.txt`

The main `.gitlab-ci.yml` pipeline verifies these scans passed in the `extract:archives` job before proceeding with the build.

## Installation Scripts

Archives include automated installation scripts:

### `scripts/install-packer.sh`
Installs Packer binary and plugins.
```bash
cd offline-transfer
bash scripts/install-packer.sh [install_dir]
```

### `scripts/install-ansible.sh`
Creates Python virtual environment and installs Ansible with collections/roles.
```bash
cd offline-transfer
bash scripts/install-ansible.sh [python_version]
source ansible-venv/bin/activate
```

## Runner Requirements

### spel-offline-runner
Required tags for GitLab runners in Offline environment:
- `spel-offline-runner`

Runner must have:
- Docker or Podman for container execution
- HTTP/HTTPS proxy configuration
- Access to Fedora container images
- Sufficient disk space (~10 GB for complete builds)

## Troubleshooting

### Proxy Issues
If downloads fail with connection errors:
1. Verify `HTTP_PROXY` and `HTTPS_PROXY` are set correctly
2. Check `NO_PROXY` excludes internal hosts
3. Test proxy with: `curl -I https://releases.hashicorp.com`

### ClamAV Update Failures
If freshclam fails to update:
- Check proxy configuration in `/etc/freshclam.conf`
- Verify `HTTPProxyServer` and `HTTPProxyPort` are correct
- Pipeline will continue with existing definitions (warning only)

### Security Scan Failures
If ClamAV or TruffleHog detects issues:
1. Review scan logs in `offline-transfer/security-scans/`
2. Identify flagged files
3. Investigate false positives or legitimate threats
4. Update exclusions or remediate issues before proceeding

### Archive Size Issues
If archives are larger than expected:
- Disable collection dependencies: `INCLUDE_COLLECTION_DEPENDENCIES=false`
- Use base archive only: `CREATE_COMPLETE_ARCHIVE=false`
- Review downloaded collections in requirements.yml

## References

- [Packer Documentation](https://www.packer.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [ClamAV Documentation](https://docs.clamav.net/)
- [TruffleHog Documentation](https://github.com/trufflesecurity/trufflehog)
