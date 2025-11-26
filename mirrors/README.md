# Local YUM/DNF Mirrors for NIPR Offline Builds

This directory contains local mirrors of YUM/DNF repositories required for building SPEL AMIs in air-gapped NIPR environments.

## Directory Structure

```
mirrors/
├── el8/
│   ├── baseos/       # RHEL/CentOS/Oracle Linux 8 Base OS packages
│   ├── appstream/    # RHEL/CentOS/Oracle Linux 8 AppStream packages
│   ├── extras/       # Extra packages
│   └── epel/         # Extra Packages for Enterprise Linux 8
├── el9/
│   ├── baseos/       # RHEL/CentOS/Oracle Linux 9 Base OS packages
│   ├── appstream/    # RHEL/CentOS/Oracle Linux 9 AppStream packages
│   ├── extras/       # Extra packages
│   └── epel/         # Extra Packages for Enterprise Linux 9
└── spel-packages/    # SPEL custom packages (minimal - latest versions only)
```

## Syncing Mirrors (Internet-Connected System)

Run these scripts on a system with internet access to download repository mirrors:

### 1. Sync YUM/DNF Repositories

```bash
# Default sync (includes all packages)
./scripts/sync-mirrors.sh

# Optimized sync (excludes debug/source, enables compression)
SPEL_MIRROR_EXCLUDE_DEBUG=true \
SPEL_MIRROR_EXCLUDE_SOURCE=true \
SPEL_MIRROR_COMPRESS=true \
./scripts/sync-mirrors.sh

# Minimal sync (excludes debug/source/devel packages)
SPEL_MIRROR_EXCLUDE_DEBUG=true \
SPEL_MIRROR_EXCLUDE_SOURCE=true \
SPEL_MIRROR_EXCLUDE_DEVEL=true \
SPEL_MIRROR_COMPRESS=true \
./scripts/sync-mirrors.sh
```

This will download the newest versions of packages from:
- BaseOS repositories
- AppStream repositories  
- Extras repositories
- EPEL repositories

**Storage Optimization Options:**
- `SPEL_MIRROR_EXCLUDE_DEBUG=true` - Excludes debuginfo packages (saves ~40%)
- `SPEL_MIRROR_EXCLUDE_SOURCE=true` - Excludes source RPMs (saves ~20%)
- `SPEL_MIRROR_EXCLUDE_DEVEL=true` - Excludes development packages (saves ~10%)
- `SPEL_MIRROR_COMPRESS=true` - Creates compressed .tar.gz archives
- `SPEL_MIRROR_HARDLINK=true` - Uses hardlinks to deduplicate files (default)

### 2. Sync SPEL Custom Packages

```bash
# Sync only latest spel-release packages and current versions
./scripts/sync-spel-packages.sh
```

This downloads minimal SPEL packages to reduce storage requirements.

## Transfer to NIPR

### Option 1: Direct Mirror Transfer
After syncing, transfer the entire `mirrors/` directory to your NIPR environment using approved data transfer methods.

### Option 2: Optimized Archive Transfer (Recommended)
Use the provided script to create optimized archives:

```bash
# Create separate archives for selective transfer
./scripts/create-transfer-archive.sh

# This creates:
# - spel-base-YYYYMMDD.tar.gz (code, scripts, configs)
# - spel-mirrors-compressed-YYYYMMDD.tar.gz (compressed repos)
# - spel-tools-YYYYMMDD.tar.gz (build tools)
# - spel-nipr-YYYYMMDD-checksums.txt (SHA256 verification)
```

Transfer only the archives you need, then extract in NIPR with:
```bash
./scripts/extract-nipr-archives.sh
```

## Setup in NIPR Environment

Once mirrors are in the NIPR environment, configure the system to use them:

```bash
# Run as root to configure local repositories
sudo ./scripts/setup-local-repos.sh
```

This script will:
1. Backup existing repository configuration
2. Disable all external repositories
3. Create `.repo` files pointing to local mirrors
4. Clean and rebuild repository cache

## Storage Requirements

### Default (Unoptimized)
- EL8 repositories: ~50-80 GB
- EL9 repositories: ~50-80 GB
- SPEL packages: ~100 MB
- **Total: 100-160 GB**

### Optimized (Recommended for NIPR)
With storage optimizations enabled:
- EL8 repositories (no debug/source): ~15-25 GB
- EL9 repositories (no debug/source): ~15-25 GB
- SPEL packages: ~100 MB
- **Total: 30-50 GB (70% reduction)**

### Compressed for Transfer
- Compressed mirrors: ~12-20 GB
- **Transfer size: 50-75% smaller**

## Automated Sync Schedule

For regular mirror updates (on internet-connected system), consider scheduling:

```bash
# Add to crontab for monthly sync (before monthly SPEL builds)
0 0 1 * * /path/to/spel/scripts/sync-mirrors.sh && /path/to/spel/scripts/sync-spel-packages.sh
```

## Using Mirrors in AMIgen Builds

Set the `AMIGEN_REPO_BASE` environment variable to use local mirrors during builds:

```bash
export AMIGEN_REPO_BASE="file:///path/to/mirrors"
```

The AMIgen scripts will automatically configure repository baseurls to use local mirrors when this variable is set.
