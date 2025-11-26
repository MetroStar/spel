# Storage Optimization Quick Reference

## TL;DR - Optimized NIPR Transfer Workflow

### On Internet System (One-Time Setup)
```bash
# Clone repository
git clone --recurse-submodules https://github.com/MetroStar/spel.git && cd spel/

# Run all optimization scripts
SPEL_MIRROR_EXCLUDE_DEBUG=true SPEL_MIRROR_EXCLUDE_SOURCE=true SPEL_MIRROR_COMPRESS=true \
  ./scripts/sync-mirrors.sh                    # 30-50 GB (vs 100-160 GB)

./scripts/vendor-ansible-roles.sh              # 60 MB (vs 300 MB)
./scripts/download-offline-packages.sh          # 75 MB (vs 100 MB)
./scripts/sync-spel-packages.sh                 # 100 MB
./scripts/create-transfer-archive.sh            # Creates 12-20 GB archives

# Verify and transfer
sha256sum -c spel-nipr-*-checksums.txt
# Transfer spel-*.tar.gz files to NIPR
```

### On NIPR System (Deployment)
```bash
# Verify and extract
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt
./scripts/extract-nipr-archives.sh

# Configure and build
sudo ./scripts/setup-local-repos.sh
export SPEL_OFFLINE_MODE=true
./build/ci-setup.sh
```

## Storage Savings

| Component | Before | After | Savings |
|-----------|--------|-------|---------|
| Mirrors | 100-160 GB | 30-50 GB | 70% |
| Roles | 300 MB | 60 MB | 80% |
| Packages | 100 MB | 75 MB | 25% |
| **Total** | **101-161 GB** | **31-51 GB** | **70%** |
| **Compressed** | - | **12-20 GB** | **88%** |

## Key Scripts

| Script | Purpose | Output |
|--------|---------|--------|
| `sync-mirrors.sh` | YUM/DNF mirrors | 30-50 GB optimized repos |
| `vendor-ansible-roles.sh` | Ansible roles | 60 MB roles + archive |
| `download-offline-packages.sh` | AWS utilities | 75 MB packages + archive |
| `sync-spel-packages.sh` | SPEL packages | 100 MB minimal repo |
| `create-transfer-archive.sh` | Transfer archives | 12-20 GB compressed |
| `extract-nipr-archives.sh` | NIPR extraction | Deployed workspace |

## Environment Variables Cheat Sheet

### Maximum Storage Savings
```bash
export SPEL_MIRROR_EXCLUDE_DEBUG=true      # -40%
export SPEL_MIRROR_EXCLUDE_SOURCE=true     # -20%
export SPEL_MIRROR_EXCLUDE_DEVEL=true      # -10%
export SPEL_MIRROR_COMPRESS=true           # -50% transfer
export SPEL_MIRROR_HARDLINK=true           # -10% (default)
export SPEL_ROLES_REMOVE_GIT=true          # -50% (default)
export SPEL_ROLES_COMPRESS=true            # -30% (default)
export SPEL_OFFLINE_COMPRESS=true          # -7% (default)
```

### Separate vs Combined Archives
```bash
# Separate (recommended for updates)
export SPEL_ARCHIVE_SEPARATE=true          # Multiple archives
export SPEL_ARCHIVE_COMBINED=false         # Skip combined

# Combined (for initial deployment)
export SPEL_ARCHIVE_SEPARATE=false         # Skip separate
export SPEL_ARCHIVE_COMBINED=true          # Single archive
```

## Archive Contents

### Separate Archives (Default)
- `spel-base-YYYYMMDD.tar.gz` (~500 MB) - Code, scripts, configs
- `spel-mirrors-compressed-YYYYMMDD.tar.gz` (~10-18 GB) - YUM repos
- `spel-tools-YYYYMMDD.tar.gz` (~400 MB) - Packer, Python, packages
- `spel-nipr-YYYYMMDD-checksums.txt` - SHA256 verification

### Combined Archive
- `spel-nipr-complete-YYYYMMDD.tar.gz` (~12-20 GB) - Everything

## Common Tasks

### Update Mirrors Only
```bash
# Internet system
./scripts/sync-mirrors.sh
./scripts/create-transfer-archive.sh  # Only creates mirrors archive

# Transfer only spel-mirrors-*.tar.gz to NIPR

# NIPR system
tar xzf spel-mirrors-compressed-YYYYMMDD.tar.gz
./scripts/extract-nipr-archives.sh
```

### Update Ansible Roles Only
```bash
# Internet system
SPEL_ROLES_TAG=v2.0.0 ./scripts/vendor-ansible-roles.sh
tar czf ansible-roles-update.tar.gz spel/ansible/roles/

# Transfer to NIPR and extract
tar xzf ansible-roles-update.tar.gz
```

### Verify Everything
```bash
# Check archive sizes
ls -lh spel-*.tar.gz

# Verify checksums
sha256sum -c spel-nipr-*-checksums.txt

# Test extraction
mkdir test && cd test
../scripts/extract-nipr-archives.sh
```

## Troubleshooting

### Out of disk space during sync
```bash
# Use all exclusions
SPEL_MIRROR_EXCLUDE_DEBUG=true \
SPEL_MIRROR_EXCLUDE_SOURCE=true \
SPEL_MIRROR_EXCLUDE_DEVEL=true \
./scripts/sync-mirrors.sh
```

### Archive too large for media
```bash
# Split archive
split -b 4G spel-mirrors-*.tar.gz mirrors-part-

# Reassemble
cat mirrors-part-* > spel-mirrors.tar.gz
```

### Checksum verification failed
```bash
# Regenerate checksums
sha256sum spel-*.tar.gz > spel-nipr-YYYYMMDD-checksums.txt

# Re-verify
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt
```

## Documentation

- **Full Optimization Guide**: `docs/Storage-Optimization.md`
- **NIPR Setup Guide**: `docs/NIPR-Setup.md`
- **Implementation Summary**: `docs/Storage-Optimization-Summary.md`
- **Mirror Details**: `mirrors/README.md`
- **Offline Packages**: `offline-packages/README.md`
- **Build Tools**: `tools/README.md`

## Success Criteria

✅ Mirror sync completes in 30-50 GB (not 100-160 GB)  
✅ Ansible roles total ~60 MB (not 300 MB)  
✅ Transfer archives total 12-20 GB (not 30+ GB)  
✅ All checksums verify successfully  
✅ Extract script completes without errors  
✅ Local repos configure successfully  
✅ Packer validates templates  
✅ Test build succeeds in NIPR
