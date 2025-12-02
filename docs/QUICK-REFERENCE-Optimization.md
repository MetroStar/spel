# Storage Optimization Quick Reference

## TL;DR - Optimized NIPR Transfer Workflow

### On Internet System (One-Time Setup)
```bash
# Clone repository
git clone --recurse-submodules https://github.com/MetroStar/spel.git && cd spel/

# Run all optimization scripts
./scripts/vendor-ansible-roles.sh              # 60 MB (vs 300 MB)
./scripts/vendor-ansible-collections.sh         # 5 MB (vs 20 MB)
./scripts/download-offline-packages.sh          # 75 MB (vs 100 MB)
./scripts/create-transfer-archive.sh            # Creates ~1 GB archives

# Verify and transfer
sha256sum -c spel-nipr-*-checksums.txt
# Transfer spel-*.tar.gz files to NIPR
```

### On NIPR System (Deployment)
```bash
# Verify and extract
sha256sum -c spel-nipr-YYYYMMDD-checksums.txt
./scripts/extract-nipr-archives.sh

# Build (uses RHUI repositories in AWS GovCloud)
export SPEL_OFFLINE_MODE=true
./build/ci-setup.sh
```

## Storage Savings

| Component | Before | After | Savings |
|-----------|--------|-------|---------|  
| Roles | 300 MB | 60 MB | 80% |
| Collections | 20 MB | 5 MB | 75% |
| Packages | 100 MB | 75 MB | 25% |
| Tools | 400 MB | 400 MB | - |
| **Total** | **820 MB** | **600 MB** | **27%** |
| **Compressed** | - | **~1 GB** | **~0%** |

Note: NIPR builds now use RHUI repositories available in AWS GovCloud, eliminating the need for 30-50 GB of YUM/DNF mirrors.

## Key Scripts

| Script | Purpose | Output |
|--------|---------|--------|
| `vendor-ansible-roles.sh` | Ansible roles | 60 MB roles + archive |
| `vendor-ansible-collections.sh` | Ansible collections | 5 MB tarballs |
| `download-offline-packages.sh` | AWS utilities | 75 MB packages + archive |
| `create-transfer-archive.sh` | Transfer archives | ~1 GB compressed |
| `extract-nipr-archives.sh` | NIPR extraction | Deployed workspace |

## Environment Variables Cheat Sheet

### Optimizations
```bash
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
- `spel-base-YYYYMMDD.tar.gz` (~100 MB) - Code, scripts, configs, roles
- `spel-tools-YYYYMMDD.tar.gz` (~400 MB) - Packer, Python, AWS packages
- `spel-nipr-YYYYMMDD-checksums.txt` - SHA256 verification

### Combined Archive
- `spel-nipr-complete-YYYYMMDD.tar.gz` (~1 GB) - Everything

## Common Tasks

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

### Archive too large for media
```bash
# Use separate archives instead of combined
export SPEL_ARCHIVE_SEPARATE=true
export SPEL_ARCHIVE_COMBINED=false
./scripts/create-transfer-archive.sh
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
- **Offline Packages**: `offline-packages/README.md`
- **Build Tools**: `tools/README.md`

## Success Criteria

✅ Ansible roles total ~60 MB (not 300 MB)  
✅ Transfer archives total ~1 GB  
✅ All checksums verify successfully  
✅ Extract script completes without errors  
✅ Packer validates templates  
✅ Test build succeeds in NIPR using RHUI repositories
