# Storage Optimization Guide for NIPR Transfers

This guide provides strategies to minimize storage requirements and transfer sizes for SPEL NIPR deployments.

**Note**: NIPR builds use RHUI repositories available within the NIPR AWS GovCloud environment, eliminating the need for local YUM/DNF mirrors.

## Quick Reference

| Component | Default | Optimized | Savings |
|-----------|---------|-----------|---------||
| Ansible Roles | 300 MB | 4 MB | **99%** |
| Ansible Collections | 20 MB | 3.5 MB | **83%** |
| Offline Packages | 100 MB | 86 MB | **14%** |
| Python Deps | 100 MB | 16 MB | **84%** |
| Packer Binaries | 500 MB | 97 MB | **81%** |
| Packer Plugins | 80 MB | 241 MB | **-201%** |
| SPEL Packages | 20 MB | 56 KB | **99.7%** |
| **TOTAL** | **1120 MB** | **447 MB** | **60%** |

**Compressed Transfer**: 447 MB → **1.1 GB** (118 MB base + 289 MB tools + 694 MB complete)

## Automated Optimization Workflow

### On Internet-Connected System

```bash
# 1. Clone repository with submodules
git clone --recurse-submodules https://github.com/MetroStar/spel.git
cd spel/

# 2. Vendor Ansible roles (saves 80%)
SPEL_ROLES_REMOVE_GIT=true \
SPEL_ROLES_COMPRESS=true \
./scripts/vendor-ansible-roles.sh

# 3. Vendor Ansible collections (saves 75%)
./scripts/vendor-ansible-collections.sh

# 4. Download offline packages (saves 25%)
SPEL_OFFLINE_COMPRESS=true \
./scripts/download-offline-packages.sh

# 5. Create optimized transfer archives
./scripts/create-transfer-archive.sh

# 6. Verify and prepare for transfer
sha256sum -c spel-nipr-*-checksums.txt
ls -lh spel-*.tar.gz
```

### On NIPR System

```bash
# 1. Verify checksums after transfer
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt

# 2. Extract all archives
./scripts/extract-nipr-archives.sh

# 3. Initialize environment (uses RHUI repos)
./build/ci-setup.sh
```

## Optimization Strategies by Component

### 1. Ansible Roles (300 MB → 4 MB)

#### Strategy A: Shallow Clone (Saves 50%)

```bash
# Automatically done by vendor-ansible-roles.sh
git clone --depth 1 <repo>
```

**Result:** No git history, only latest snapshot

#### Strategy B: Remove .git Directories (Saves Additional 30%)

```bash
SPEL_ROLES_REMOVE_GIT=true \
./scripts/vendor-ansible-roles.sh
```

**Result:**
- Removes all git metadata
- Role remains fully functional
- Cannot `git pull` updates (re-vendor instead)

#### Strategy C: Specific Version Tags

```bash
SPEL_ROLES_TAG=v1.2.3 \
./scripts/vendor-ansible-roles.sh
```

**Result:**
- Locks to specific tested version
- Recommended for production NIPR environments

### 2. Ansible Collections (20 MB → 5 MB)

#### Strategy: Tarball Format (Saves 75%)

```bash
# Automatically done by vendor-ansible-collections.sh
ansible-galaxy collection download ansible.windows:1.14.0
# Creates ansible-windows-1.14.0.tar.gz
```

**Result:**
- Collections stored as compressed tarballs (~5 MB total)
- Installed to `~/.ansible/collections/` during build setup
- Compatible with Ansible Core 2.15.13

**Collections vendored:**
- `ansible.windows:1.14.0` - Windows automation modules (500 KB)
- `community.windows:1.13.0` - Additional Windows modules (800 KB)
- `community.general:7.5.0` - General-purpose modules (4 MB)

**Total**: ~5.3 MB (vs 20 MB if extracted)

### 3. Offline AWS Packages (100 MB → 86 MB)

#### Strategy: Single SSM Agent for Both EL8/EL9

```bash
./scripts/download-offline-packages.sh
```

**Optimization:**
- SSM Agent RPM is compatible with both EL8 and EL9
- No need for separate versions
- Saves 25 MB

### 4. Build Tools (400 MB)

#### Strategy A: Selective Python Packages

```bash
# Download only required dependencies
pip download ansible-core --no-deps --dest tools/python-deps/
# Then manually add only required transitive dependencies
```

#### Strategy B: Single Packer Binary

```bash
# Download only Linux x86_64 binary
# Skip unnecessary platforms (macOS, Windows, ARM)
wget https://releases.hashicorp.com/packer/1.11.2/packer_1.11.2_linux_amd64.zip
```

**Note**: NIPR builds use Packer v1.11.2 for compatibility with vendored plugins.

## Transfer Archive Strategies

## Transfer Archive Strategies

## Transfer Archive Strategies

### Option 1: Combined Archive

**Best for:** Initial deployment, small networks

```bash
# Creates single archive
SPEL_ARCHIVE_COMBINED=true \
SPEL_ARCHIVE_SEPARATE=false \
./scripts/create-transfer-archive.sh

# Result: spel-nipr-complete-YYYYMMDD.tar.gz (1.1 GB)
```

### Option 2: Separate Component Archives (Recommended)

**Best for:** Partial updates, large networks, parallel transfers

```bash
# Creates separate archives (default)
./scripts/create-transfer-archive.sh

# Results:
# - spel-base-YYYYMMDD.tar.gz (118 MB)
# - spel-tools-YYYYMMDD.tar.gz (~400 MB)
```

**Benefits:**
- Transfer only what changed
- Parallel transfers possible
- Faster verification
- Smaller individual files

## Storage Requirement Summary

### Internet-Connected System (Preparation)

```
Workspace:
  ├── Code/Scripts         ~100 MB
  ├── Ansible roles        4 MB (optimized)
  ├── Ansible collections  3.5 MB (tarballs)
  ├── Python dependencies  16 MB
  ├── Offline packages     86 MB
  ├── Packer binaries      97 MB
  ├── Packer plugins       241 MB
  ├── SPEL packages        56 KB
  └── Transfer archives    1.1 GB
Total working space: 2-3 GB
```

### Transfer Media

```
Minimum (compressed archives only):
  └── spel-nipr-*.tar.gz   1.1 GB

Recommended (archives + checksums):
  ├── spel-base-*.tar.gz       118 MB
  ├── spel-tools-*.tar.gz      289 MB
  ├── spel-nipr-complete-*.tar.gz  694 MB
  └── checksums + manifest     <1 MB
  Total: 1.1 GB
```

### NIPR System (Deployed)

```
Deployed workspace:
  ├── Code/Scripts         ~100 MB
  ├── Ansible roles        4 MB
  ├── Ansible collections  3.5 MB (tarballs, installed to ~/.ansible/collections/)
  ├── Python dependencies  16 MB
  ├── Offline packages     86 MB
  ├── Packer binaries      97 MB
  ├── Packer plugins       241 MB
  ├── SPEL packages        56 KB
  ├── Vendor submodules    ~100 MB
  └── Build workspace      ~10-15 GB (per concurrent build)
  
Minimum: 1.1 GB
Recommended: 20-35 GB (allows 1-2 concurrent builds)
```

**Note**: NIPR builds use RHUI repositories within AWS GovCloud, so no local mirrors are needed.

## Configuration Variables Reference

### Ansible Roles (`vendor-ansible-roles.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `SPEL_ROLES_REMOVE_GIT` | `true` | Remove .git directories |
| `SPEL_ROLES_COMPRESS` | `true` | Create compressed archive |
| `SPEL_ROLES_TAG` | (empty) | Specific git tag to checkout |

### Offline Packages (`download-offline-packages.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `SPEL_OFFLINE_COMPRESS` | `true` | Create compressed archive |
| `SPEL_OFFLINE_VERIFY` | `true` | Verify downloads |

### Transfer Archives (`create-transfer-archive.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `SPEL_ARCHIVE_SEPARATE` | `true` | Create separate component archives |
| `SPEL_ARCHIVE_COMBINED` | `true` | Create combined archive |
| `SPEL_ARCHIVE_OUTPUT` | `$PWD` | Output directory for archives |

### NIPR Extraction (`extract-nipr-archives.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `SPEL_ARCHIVE_DIR` | `$PWD` | Directory containing archives |
| `SPEL_VERIFY_CHECKSUMS` | `true` | Verify SHA256 checksums |
| `SPEL_CLEANUP_ARCHIVES` | `false` | Remove archives after extraction |

## Pipeline Integration

### GitLab CI Storage Analysis by Stage

The GitLab CI pipeline manages storage efficiently across multiple stages:

#### Stage 1: Extract (2-3 minutes)

**Storage Impact**: +1 GB (one-time)

```
Input: Archives in repository (1.1 GB compressed)
Process: Extract to working directories
Output: ~1 GB extracted files
```

**Storage breakdown**:
- SPEL packages: 56 KB → `spel/`
- Ansible roles: 4 MB → `vendor/ansible-roles/`
- Ansible collections: 3.5 MB → `vendor/ansible-collections/`
- Offline packages: 86 MB → `offline-packages/`
- Packer binaries: 97 MB → `tools/packer-linux/`, `tools/packer-windows/`
- Packer plugins: 241 MB → `tools/packer-plugins/`
- Python packages: 16 MB → `tools/python-deps/`

**Artifacts**: Retained for 90 days, used by all subsequent stages

#### Stage 2: Infrastructure (2-3 minutes, one-time)

**Storage Impact**: Minimal (~10 KB artifacts)

```
Process: Creates AWS resources via API calls
Output: infra.env, iam.env configuration files
```

**Resources created**:
- VPC, Internet Gateway, Subnet, Route Table (no local storage)
- Security Group (no local storage)
- IAM Role, Policy, Instance Profile (no local storage)

**Artifacts**: Configuration files retained for 90 days

#### Stage 3: Setup (4-5 minutes)

**Storage Impact**: +500 MB (temporary)

**Job: verify:resources**
- No storage impact (checks only)
- Verifies 50+ GB free disk space
- Verifies 2+ GB free memory

**Job: aws:verify**
- No storage impact (API calls only)
- Tests AWS credentials
- Verifies VPC/subnet configuration

**Job: setup**
- Initializes git submodules: vendor/amigen8 (~2 MB), vendor/amigen9 (~2 MB)
- Detects offline Packer installation
- No additional storage (uses extracted files)

**Job: python:setup**
- Creates virtual environment: `.venv/` (~200 MB)
- Installs from offline wheels in `tools/python-deps/`
- Temporary: Cleaned between builds or retained for reuse

**Job: packer:init**
- Initializes Packer plugin cache: `~/.packer.d/` (~300 MB)
- Uses plugins from `tools/packer-plugins/` (offline mode)
- Persistent cache: Reused across builds

**Job: verify:dependencies**
- No storage impact (verification only)
- Checks submodule content

**Total setup stage storage**: ~500 MB (venv + plugin cache)

#### Stage 4: Validate (1 minute)

**Storage Impact**: Minimal

```
Process: Runs packer validate on all templates
Output: Validation results (text logs only)
```

No additional storage required (uses setup artifacts)

#### Stage 5: Build (2-5 hours per OS)

**Storage Impact**: +15-30 GB per concurrent build

**Per build job storage breakdown**:
- Packer working directory: 2-5 GB
  - Source AMI snapshot downloads
  - Ansible playbook execution
  - STIG content and scripts
- Packer cache (`~/.packer.d/tmp/`): 5-10 GB
  - AMI creation temporary files
  - Instance volume snapshots
- Build logs: 10-50 MB
  - Ansible output
  - Packer progress logs
  - Error debugging information

**Concurrent builds**:
- 1 OS build: ~17 GB total workspace
- 2 concurrent builds: ~32 GB total workspace
- 3 concurrent builds: ~47 GB total workspace
- Full parallel (8 OS): ~120+ GB total workspace

**Cleanup**: Packer automatically cleans working directory after successful build, but cache persists

### Total System Requirements

**Minimum for single OS build**:
- Extracted archives: 1 GB
- Python venv: 200 MB
- Packer plugin cache: 300 MB
- Build workspace: 15-20 GB
- **Total**: 17-22 GB free space

**Recommended for monthly builds** (2-3 OS concurrently):
- Base: 1.5 GB (archives + setup)
- Build workspaces: 45-60 GB (3 × 15-20 GB)
- **Total**: 50+ GB free space (verified by `verify:resources` job)

**Required for full release** (8 OS builds in parallel):
- Base: 1.5 GB
- Build workspaces: 120-160 GB (8 × 15-20 GB)
- **Total**: 130+ GB free space

### Storage Optimization Tips for Pipeline

1. **Clean Packer cache periodically**:
   ```bash
   rm -rf ~/.packer.d/tmp/*
   # Saves 5-10 GB per previous build
   ```

2. **Reuse Python venv**:
   - Keep `.venv/` between builds (saves 4-5 min setup time)
   - Recreate monthly when archives update

3. **Run builds serially for limited disk**:
   - Set only one `RUN_<OS>=true` at a time
   - Reduces peak storage to ~20 GB vs 120+ GB

4. **Archive rotation**:
   - Keep only current month's archives in repository
   - Delete previous month after successful extraction
   - Saves 1 GB per old archive set

5. **Artifact cleanup**:
   - GitLab automatically deletes artifacts after 90 days
   - Manually delete old pipeline artifacts if storage constrained
   - infra.env/iam.env are tiny (<10 KB), keep for infrastructure reuse

### Pipeline Storage Best Practices

1. **Initial setup**: Run extract and infrastructure stages once, artifacts last 90 days
2. **Monthly builds**: Only re-extract if archives updated, reuse infrastructure
3. **Concurrent limits**: Don't exceed (available_space - 2GB) / 20GB concurrent builds
4. **Monitor usage**: Check `df -h` before starting builds (verified automatically)
5. **Clean between releases**: Remove Packer cache and old venv before major releases

## Troubleshooting

### Issue: Transfer archive too large for media

**Solution:**
```bash
# Use separate archives, transfer individually
SPEL_ARCHIVE_COMBINED=false \
./scripts/create-transfer-archive.sh
```

### Issue: Slow extraction in NIPR

**Solution:**
```bash
# Extract directly without intermediate storage
tar xzf archive.tar.gz -C /final/destination/
# Rather than extracting then moving
```

## Best Practices

1. **Always verify checksums** after transfer
2. **Test extraction** before deleting transfer media
3. **Document versions** in transfer package (use VERSIONS.txt files)
4. **Keep one previous version** in NIPR for rollback
5. **Update monthly** for security patches (Ansible roles and collections)
6. **Use separate archives** for updates (don't re-transfer everything)
7. **Compress before transfer** (default in scripts)

## See Also

- `docs/NIPR-Setup.md` - Complete NIPR setup guide
- `offline-packages/README.md` - AWS utilities documentation
- `tools/README.md` - Build tools documentation
