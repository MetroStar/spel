# Storage Optimization Guide for NIPR Transfers

This guide provides strategies to minimize storage requirements and transfer sizes for SPEL NIPR deployments.

## Quick Reference

| Component | Default | Optimized | Savings |
|-----------|---------|-----------|---------|
| YUM/DNF Mirrors | 100-160 GB | 30-50 GB | **70%** |
| Ansible Roles | 300 MB | 60 MB | **80%** |
| Offline Packages | 100 MB | 75 MB | **25%** |
| Build Tools | 350 MB | 250 MB | **29%** |
| **TOTAL** | **101-161 GB** | **31-51 GB** | **70%** |

**Compressed Transfer**: 31-51 GB → **12-20 GB** (60% additional compression)

## Automated Optimization Workflow

### On Internet-Connected System

```bash
# 1. Clone repository with submodules
git clone --recurse-submodules https://github.com/MetroStar/spel.git
cd spel/

# 2. Sync optimized mirrors (saves 70%)
SPEL_MIRROR_EXCLUDE_DEBUG=true \
SPEL_MIRROR_EXCLUDE_SOURCE=true \
SPEL_MIRROR_COMPRESS=true \
./scripts/sync-mirrors.sh

# 3. Vendor Ansible roles (saves 80%)
SPEL_ROLES_REMOVE_GIT=true \
SPEL_ROLES_COMPRESS=true \
./scripts/vendor-ansible-roles.sh

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

# 3. Configure local repositories
sudo ./scripts/setup-local-repos.sh

# 4. Initialize environment
./build/ci-setup.sh
```

## Optimization Strategies by Component

### 1. YUM/DNF Repository Mirrors (100-160 GB → 30-50 GB)

#### Strategy A: Exclude Debug/Source Packages (Saves 60%)

```bash
SPEL_MIRROR_EXCLUDE_DEBUG=true \
SPEL_MIRROR_EXCLUDE_SOURCE=true \
./scripts/sync-mirrors.sh
```

**What's excluded:**
- `*-debuginfo-*` packages (debugging symbols)
- `*-debugsource-*` packages (debug source code)
- `*.src.rpm` packages (source RPMs)

**Impact:** No impact on SPEL builds (debug packages not needed)

#### Strategy B: Exclude Development Packages (Saves Additional 10%)

```bash
SPEL_MIRROR_EXCLUDE_DEVEL=true \
./scripts/sync-mirrors.sh
```

**What's excluded:**
- `*-devel-*` packages (development headers and libraries)

**Impact:** Only affects builds that compile from source (SPEL uses pre-built packages)

#### Strategy C: Compress Repositories (Saves 50% Transfer Size)

```bash
SPEL_MIRROR_COMPRESS=true \
./scripts/sync-mirrors.sh
```

**Result:**
- Creates `.tar.gz` archives for each repository
- Reduces transfer size by ~50%
- Auto-extracted by `extract-nipr-archives.sh`

#### Strategy D: Hardlink Deduplication (Saves 5-15%)

```bash
# Enabled by default, or explicitly:
SPEL_MIRROR_HARDLINK=true \
./scripts/sync-mirrors.sh
```

**Requires:** `hardlink` package (`dnf install hardlink`)
**Result:** Identical files across repos are hardlinked

### 2. Ansible Roles (300 MB → 60 MB)

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

### 3. Offline AWS Packages (100 MB → 75 MB)

#### Strategy: Single SSM Agent for Both EL8/EL9

```bash
./scripts/download-offline-packages.sh
```

**Optimization:**
- SSM Agent RPM is compatible with both EL8 and EL9
- No need for separate versions
- Saves 25 MB

### 4. Build Tools (350 MB → 250 MB)

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
wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
```

## Transfer Archive Strategies

### Option 1: Combined Archive

**Best for:** Initial deployment, small networks

```bash
# Creates single archive
SPEL_ARCHIVE_COMBINED=true \
SPEL_ARCHIVE_SEPARATE=false \
./scripts/create-transfer-archive.sh

# Result: spel-nipr-complete-YYYYMMDD.tar.gz (~12-20 GB)
```

### Option 2: Separate Component Archives (Recommended)

**Best for:** Partial updates, large networks, parallel transfers

```bash
# Creates separate archives (default)
./scripts/create-transfer-archive.sh

# Results:
# - spel-base-YYYYMMDD.tar.gz (~500 MB)
# - spel-mirrors-compressed-YYYYMMDD.tar.gz (~10-18 GB)
# - spel-tools-YYYYMMDD.tar.gz (~400 MB)
```

**Benefits:**
- Transfer only what changed
- Parallel transfers possible
- Faster verification
- Smaller individual files

### Option 3: EL Version Specific

**Best for:** EL8-only or EL9-only environments

```bash
# Manual - extract only needed repos before archiving
./scripts/sync-mirrors.sh
rm -rf mirrors/el8  # If only building EL9

./scripts/create-transfer-archive.sh
# Result: 50% smaller mirrors archive
```

## Advanced Optimization Techniques

### 1. Incremental Mirror Updates

For subsequent updates after initial transfer:

```bash
# On internet system - sync changes only
./scripts/sync-mirrors.sh  # Updates existing mirrors

# Create delta archive (only changed files)
tar czf mirrors-update-$(date +%Y%m%d).tar.gz \
  --newer-mtime="2024-11-01" \
  mirrors/

# Transfer only the delta archive (~500 MB - 2 GB typically)
```

### 2. Repository Subset Mirroring

For minimal builds, mirror only essential repos:

```bash
# Edit sync-mirrors.sh to comment out EPEL sync
# EPEL often not required for minimal SPEL builds
# Saves: ~5-10 GB per EL version
```

### 3. Compressed Root Filesystem

If NIPR system supports it:

```bash
# Use squashfs for read-only mirrors
mksquashfs mirrors/ mirrors.sqfs -comp zstd
mount -t squashfs mirrors.sqfs /mnt/mirrors

# Saves: ~60% disk space (but read-only)
```

## Storage Requirement Summary

### Internet-Connected System (Preparation)

```
Workspace:
  ├── Code/Scripts         ~500 MB
  ├── Mirrors (raw)        ~30-50 GB (optimized) or 100-160 GB (full)
  ├── Compressed mirrors   ~12-20 GB (archives)
  ├── Ansible roles        ~60 MB (optimized)
  ├── Offline packages     ~75 MB
  ├── Build tools          ~250 MB
  └── Transfer archives    ~12-20 GB
Total working space: ~45-70 GB
```

### Transfer Media

```
Minimum (compressed archives only):
  └── spel-nipr-*.tar.gz   ~12-20 GB

Recommended (archives + checksums):
  └── All archives         ~13-21 GB
```

### NIPR System (Deployed)

```
Deployed workspace:
  ├── Code/Scripts         ~500 MB
  ├── Mirrors              ~30-50 GB (extracted)
  ├── Ansible roles        ~60 MB
  ├── Offline packages     ~75 MB
  ├── Build tools          ~250 MB
  ├── Vendor submodules    ~100 MB
  └── Build workspace      ~10-15 GB (per concurrent build)
  
Minimum: ~32 GB
Recommended: ~50 GB (allows 1-2 concurrent builds)
```

## Configuration Variables Reference

### Mirror Sync (`sync-mirrors.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `SPEL_MIRROR_EXCLUDE_DEBUG` | `true` | Exclude debuginfo packages |
| `SPEL_MIRROR_EXCLUDE_SOURCE` | `true` | Exclude source RPMs |
| `SPEL_MIRROR_EXCLUDE_DEVEL` | `false` | Exclude devel packages |
| `SPEL_MIRROR_COMPRESS` | `false` | Create compressed archives |
| `SPEL_MIRROR_HARDLINK` | `true` | Use hardlinks for deduplication |

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
| `SPEL_ARCHIVE_MIRRORS` | `true` | Include mirrors in archives |
| `SPEL_ARCHIVE_OUTPUT` | `$PWD` | Output directory for archives |

### NIPR Extraction (`extract-nipr-archives.sh`)

| Variable | Default | Description |
|----------|---------|-------------|
| `SPEL_ARCHIVE_DIR` | `$PWD` | Directory containing archives |
| `SPEL_VERIFY_CHECKSUMS` | `true` | Verify SHA256 checksums |
| `SPEL_CLEANUP_ARCHIVES` | `false` | Remove archives after extraction |

## Troubleshooting

### Issue: Mirror sync runs out of disk space

**Solution:**
```bash
# Enable all exclusions
SPEL_MIRROR_EXCLUDE_DEBUG=true \
SPEL_MIRROR_EXCLUDE_SOURCE=true \
SPEL_MIRROR_EXCLUDE_DEVEL=true \
./scripts/sync-mirrors.sh
```

### Issue: Transfer archive too large for media

**Solution:**
```bash
# Use separate archives, transfer individually
SPEL_ARCHIVE_COMBINED=false \
./scripts/create-transfer-archive.sh

# Or split large archive
split -b 4G spel-mirrors-*.tar.gz mirrors-part-
# Reassemble: cat mirrors-part-* > spel-mirrors.tar.gz
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
5. **Update quarterly** for security patches
6. **Use separate archives** for updates (don't re-transfer everything)
7. **Compress before transfer** (default in scripts)
8. **Hardlink on NIPR system** to save disk space post-extraction

## See Also

- `docs/NIPR-Setup.md` - Complete NIPR setup guide
- `mirrors/README.md` - Mirror-specific documentation
- `offline-packages/README.md` - AWS utilities documentation
- `tools/README.md` - Build tools documentation
