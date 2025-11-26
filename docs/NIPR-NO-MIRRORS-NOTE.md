# Important: NIPR Mirror Sync Changes

## Summary

YUM/DNF repository mirrors are **NO LONGER SYNCED** for NIPR transfers.

## Rationale

The NIPR environment has its own RPM repositories available, making local mirror syncing unnecessary.

## What Changed

### Removed:
- ❌ `scripts/sync-mirrors.sh` (deleted)
- ❌ Mirror syncing from `nipr-prepare.yml` workflow
- ❌ Mirror archiving from `create-transfer-archive.sh`
- ❌ Mirror extraction from `extract-nipr-archives.sh`
- ❌ All `SPEL_MIRROR_*` environment variables

### What's Still Transferred:
- ✅ Ansible roles (vendored)
- ✅ Offline packages (AWS CLI, SSM Agent, CFN Bootstrap)  
- ✅ Build scripts and configurations

## New Transfer Sizes

| Component | Size |
|-----------|------|
| Ansible Roles | ~60 MB |
| Offline Packages | ~75 MB |
| Build Tools & Scripts | ~250 MB |
| **Total Uncompressed** | **~500 MB - 1 GB** |
| **Compressed Transfer** | **~200 MB - 500 MB** |

**Previous size**: 12-20 GB compressed  
**New size**: 200 MB - 500 MB compressed  
**Reduction**: ~97% smaller!

## Updated Workflows

### Internet-Connected System (GitHub Actions)

1. Run `nipr-prepare` workflow (manual or scheduled)
2. Downloads:
   - Vendors Ansible roles
   - Downloads offline AWS packages
   - Creates compressed archives
3. Upload artifacts to GitHub (~200-500 MB)

### NIPR System (GitLab CI)

1. Download artifacts from GitHub
2. Transfer to NIPR via approved method
3. Extract archives
4. **Configure DNF/YUM to use NIPR RPM repositories** (not local mirrors)
5. Run builds

## Documentation Updates Needed

The following documentation files contain outdated mirror references and should be reviewed:

- `docs/Storage-Optimization.md` - Remove mirror optimization sections
- `docs/Storage-Optimization-Summary.md` - Update sizes and remove mirror references
- `docs/QUICK-REFERENCE-Optimization.md` - Remove mirror sync commands
- `docs/CI-CD-Setup.md` - Update workflow descriptions
- `docs/Offline-Mode-Testing.md` - Remove mirror verification steps
- `docs/NIPR-Setup.md` - Remove mirror sync instructions

## Action Required

**Configure NIPR RPM Repositories**: Instead of syncing mirrors, configure your NIPR system to use the available NIPR RPM repositories:

```bash
# Configure DNF/YUM to use NIPR repos
# (Specific configuration depends on NIPR environment setup)

# Example: Update repo files to point to NIPR mirrors
sudo vi /etc/yum.repos.d/rocky.repo
# Update baseurl to NIPR repository URLs
```

## Questions?

See `docs/CI-CD-Setup.md` for the updated workflow or reach out to the team.
