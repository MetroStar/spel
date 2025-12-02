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
