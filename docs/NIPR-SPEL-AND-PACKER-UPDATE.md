# Update: SPEL Packages and Packer Added to NIPR Workflow

## Summary

The NIPR preparation workflow now includes:
- ✅ **SPEL custom packages** (spel-release RPMs)
- ✅ **Packer binary** (v1.11.2)

## What Changed

### New Workflow Inputs

1. **`sync_spel`** (boolean, default: true)
   - Syncs SPEL custom packages from spel-packages.cloudarmor.io

2. **`download_packer`** (boolean, default: true)
   - Downloads Packer binary from HashiCorp releases

### New Scripts

1. **`scripts/download-packer.sh`**
   - Downloads Packer binary for Linux AMD64
   - Verifies SHA256 checksums
   - Configurable version via `SPEL_PACKER_VERSION`
   - Default version: 1.11.2

### Updated Archives

Archives now include:
- `mirrors/spel-packages/` - SPEL custom package repository
- `tools/packer/packer` - Packer binary
- `tools/packer/VERSION.txt` - Version tracking

## New Transfer Sizes

| Component | Size |
|-----------|------|
| Ansible Roles | ~60 MB |
| Offline Packages | ~75 MB |
| **SPEL Packages** | **~20 MB** |
| **Packer Binary** | **~250 MB** |
| Build Scripts | ~100 MB |
| **Total Uncompressed** | **~1-2 GB** |
| **Compressed Transfer** | **~500 MB - 1 GB** |

**Previous size**: 200-500 MB compressed  
**New size**: 500 MB - 1 GB compressed  
**Increase**: Necessary for complete offline builds

## Complete Offline Capability

The workflow now prepares everything needed for offline NIPR builds:

| Component | Status | Notes |
|-----------|--------|-------|
| Ansible Lockdown Roles | ✅ | All STIG/CIS roles |
| AWS CLI | ✅ | Latest v2 |
| AWS CFN Bootstrap | ✅ | Latest |
| Amazon SSM Agent | ✅ | Single RPM for EL8/EL9 |
| **SPEL Packages** | ✅ | **spel-release RPMs** |
| **Packer** | ✅ | **v1.11.2 binary** |
| Ansible Core | ⚠️  | Install from NIPR repos |
| YUM/DNF Mirrors | ℹ️  | Use NIPR repos |

## Usage

### Run Workflow with All Components

```
GitHub Actions → Prepare NIPR Transfer Archives → Run workflow

Inputs:
  ✅ Sync SPEL Packages: true
  ✅ Download Packer: true
  ✅ Vendor Ansible roles: true
  ✅ Download offline packages: true
  ✅ Create transfer archives: true
  ✅ Upload archives as GitHub artifacts: true
```

### Run Workflow Without SPEL/Packer

If you want to skip SPEL packages or Packer:

```
Inputs:
  ❌ Sync SPEL Packages: false
  ❌ Download Packer: false
  ✅ Vendor Ansible roles: true
  ✅ Download offline packages: true
```

### Custom Packer Version

To use a different Packer version, update the workflow:

```yaml
# In .github/workflows/nipr-prepare.yml
echo "SPEL_PACKER_VERSION=1.10.0" >> $GITHUB_ENV
```

## NIPR Setup

After transferring archives to NIPR:

### 1. Extract Archives

```bash
./scripts/extract-nipr-archives.sh
```

This extracts:
- Ansible roles → `spel/ansible/roles/`
- Offline packages → `offline-packages/`
- SPEL packages → `mirrors/spel-packages/`
- Packer binary → `tools/packer/packer`

### 2. Install Packer

```bash
sudo install -m 755 tools/packer/packer /usr/local/bin/packer
packer version
```

### 3. Configure SPEL Repository

```bash
sudo ./scripts/setup-local-repos.sh
```

This creates `/etc/yum.repos.d/local-spel.repo` pointing to `mirrors/spel-packages/`

### 4. Verify Setup

```bash
# Check Packer
packer version

# Check SPEL repo
dnf repolist | grep spel

# Check available SPEL packages
dnf list available --disablerepo='*' --enablerepo='local-spel'
```

## Workflow Execution Time

| Task | Duration |
|------|----------|
| Sync SPEL packages | ~2 minutes |
| Download Packer | ~1 minute |
| Vendor Ansible roles | ~5 minutes |
| Download offline packages | ~2 minutes |
| Create archives | ~5 minutes |
| Upload artifacts | ~10 minutes |
| **Total** | **~25 minutes** |

(Previous: ~10 minutes without SPEL/Packer)

## Benefits

### Complete Offline Builds
No need to install Packer separately in NIPR - it's included in the transfer!

### SPEL Package Availability
SPEL custom packages (like spel-release) are available locally without external repo access.

### Version Consistency
Ensures consistent Packer and SPEL package versions across all builds.

### Simplified NIPR Setup
Fewer manual installation steps in the air-gapped environment.

## References

- **Workflow**: `.github/workflows/nipr-prepare.yml`
- **Download Script**: `scripts/download-packer.sh`
- **SPEL Sync Script**: `scripts/sync-spel-packages.sh`
- **Archive Script**: `scripts/create-transfer-archive.sh`
- **Previous Changes**: `docs/NIPR-NO-MIRRORS-NOTE.md`
