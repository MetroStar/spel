# Offline Mode Testing with GitHub Actions

This guide explains how to test SPEL builds in offline mode using NIPR artifacts within GitHub Actions.

## Overview

The enhanced `build.yml` workflow now supports offline mode testing, allowing you to validate that SPEL builds work correctly in air-gapped environments without requiring actual NIPR infrastructure.

## Prerequisites

1. **NIPR Artifacts**: Run the `nipr-prepare` workflow first to create transfer archives
2. **Artifact Name**: Note the artifact name (e.g., `spel-nipr-transfer-20251126`)

## Quick Start

### Step 1: Prepare NIPR Artifacts

Run the NIPR preparation workflow:

```
GitHub Actions → Prepare NIPR Transfer Archives → Run workflow
```

This creates artifacts with the naming pattern: `spel-nipr-transfer-YYYYMMDD`

### Step 2: Run Offline Build Test

1. Go to **Actions** → **Build STIGed AMI's**
2. Click **Run workflow**
3. Configure inputs:
   - ✅ **Use offline mode with NIPR artifacts**: `true`
   - 📝 **NIPR artifact name**: `spel-nipr-transfer-20251126` (use actual date)
   - Select builders to test (e.g., **Run RHEL 9 builder**: `true`)
4. Click **Run workflow**

## New Workflow Inputs

### offline_mode (boolean)
- **Description**: Use offline mode with NIPR artifacts
- **Default**: `false`
- **When to use**: Testing offline builds before NIPR deployment

### nipr_artifact_name (string)
- **Description**: Name of NIPR artifact from `nipr-prepare` workflow
- **Format**: `spel-nipr-transfer-YYYYMMDD`
- **How to find**: 
  - Go to successful `nipr-prepare` workflow run
  - Check **Artifacts** section for artifact name
  - Copy the exact name

## How It Works

### 1. Artifact Download
```yaml
- name: Download NIPR artifacts for offline mode
  uses: actions/download-artifact@v4
  with:
    name: spel-nipr-transfer-20251126
    path: ./nipr-artifacts/
```

Downloads the NIPR transfer archives from a previous workflow run.

### 2. Archive Extraction
```yaml
- name: Setup offline environment
  run: |
    # Verify checksums
    sha256sum -c spel-nipr-*-checksums.txt
    
    # Extract archives
    ./scripts/extract-nipr-archives.sh
    
    # Verify offline files
    ls mirrors/el9/repodata/repomd.xml
    ls offline-packages/
```

Extracts and verifies the NIPR archives.

### 3. Offline Mode Detection
```yaml
- name: Set up environment
  run: |
    if [ -f "mirrors/el9/repodata/repomd.xml" ]; then
      echo "SPEL_OFFLINE_MODE=true"
      echo "✓ Detected offline mode - using vendored packages"
    fi
```

Automatically detects offline mode when mirrors are present.

### 4. Normal Build Process
The rest of the build proceeds normally, but uses vendored packages instead of downloading from the internet.

## Usage Scenarios

### Scenario 1: Test Before NIPR Transfer

Validate that your NIPR archives work before transferring to NIPR:

```bash
1. Run: nipr-prepare workflow
2. Wait for completion
3. Note artifact name: spel-nipr-transfer-20251126
4. Run: build workflow with offline_mode=true
5. Verify: Build completes successfully
6. Transfer: Confident archives work in NIPR
```

### Scenario 2: Monthly Validation

Test monthly NIPR builds before actual deployment:

```bash
# Automatic workflow
15th: nipr-prepare runs automatically
16th: Download artifacts
16th: Run build with offline_mode to validate
17th: Transfer validated archives to NIPR
```

### Scenario 3: Troubleshooting

Debug offline build issues:

```bash
1. Run offline build test
2. Check logs for missing packages
3. Update nipr-prepare workflow if needed
4. Re-run nipr-prepare
5. Test again with new artifacts
```

## Alternative: Testing Branch Method

For repeated testing, you can commit archives to a testing branch:

### Setup Testing Branch

```bash
# Download NIPR artifacts locally
cd ~/downloads
unzip spel-nipr-transfer-20251126.zip

# Clone repository
git clone https://github.com/MetroStar/spel.git
cd spel/
git checkout -b test-offline-20251126

# Extract archives
cp ~/downloads/spel-*.tar.gz .
./scripts/extract-nipr-archives.sh

# Commit extracted files
git add mirrors/ offline-packages/ spel/ansible/roles/
git commit -m "Add NIPR offline artifacts for testing (Nov 2025)"
git push -u origin test-offline-20251126
```

### Run Tests

```bash
# Switch to testing branch in GitHub Actions UI
# Or update workflow to use specific branch
git checkout test-offline-20251126
```

**Note**: This approach uses significant repository space (~30-50 GB), so use sparingly.

## Verification Steps

After offline build completes, verify:

### ✅ Offline Mode Detected
```
✓ Detected offline mode - using vendored packages
=== Offline Mode Active ===
Mirrors: 35G
Roles: 60M
Packages: 75M
===========================
```

### ✅ Mirrors Used
```
Setting up local repositories...
Configuring baseurl=file:///path/to/mirrors/el9/baseos
```

### ✅ Roles Installed
```
Installing Ansible roles from local vendor...
RHEL9-STIG -> ./spel/ansible/roles/RHEL9-STIG
```

### ✅ Offline Packages Used
```
Installing AWS CLI from offline-packages/awscli-exe-linux-x86_64.zip
Installing SSM Agent from offline-packages/amazon-ssm-agent.rpm
```

### ✅ Build Succeeds
```
Build 'amazon-ebssurrogate.minimal-rhel-9-hvm' finished after X minutes.
AMI: ami-xxxxxxxxxxxxxxxxx
```

## Troubleshooting

### Issue: Artifact not found

**Error**: 
```
Unable to find artifact with name: spel-nipr-transfer-20251126
```

**Solution**:
1. Verify artifact name matches exactly (including date)
2. Check that nipr-prepare workflow completed successfully
3. Ensure artifact hasn't expired (90-day retention)
4. Try downloading from workflow run page manually

### Issue: Checksum verification failed

**Error**:
```
✗ Checksum verification failed!
```

**Solution**:
1. Re-download artifacts (may be corrupted)
2. Re-run nipr-prepare workflow
3. Check for network issues during download

### Issue: Offline mode not detected

**Error**:
```
Online mode - will download packages from internet
```

**Solution**:
1. Verify archives extracted: `ls -la mirrors/el9/repodata/repomd.xml`
2. Check extract-nipr-archives.sh ran successfully
3. Review extraction logs for errors

### Issue: Missing packages during build

**Error**:
```
No package 'xyz' found in offline repositories
```

**Solution**:
1. Package may be missing from mirrors
2. Update sync-mirrors.sh to include missing packages
3. Re-run nipr-prepare workflow
4. Test again with new artifacts

## Storage Considerations

### GitHub Actions Runner
- **Downloaded artifacts**: 12-20 GB compressed
- **Extracted files**: 31-51 GB
- **Build artifacts**: 5-10 GB
- **Total**: ~60-80 GB needed

**Recommendation**: Use self-hosted runner with sufficient storage for offline testing.

### Artifact Retention
- **GitHub artifacts**: 90 days
- **After expiration**: Re-run nipr-prepare workflow
- **Monthly builds**: Each month creates new artifacts

## Best Practices

1. **Test before transfer**: Always run offline build test before NIPR transfer
2. **Validate checksums**: Don't skip checksum verification
3. **Test all builders**: Test at least one Linux and one Windows builder
4. **Document results**: Keep logs from successful offline builds
5. **Regular updates**: Re-test when nipr-prepare workflow changes
6. **Clean up**: Remove old testing branches after validation

## Example Workflow Run

Complete example of offline testing:

```bash
# 1. Prepare artifacts (15th of month, automatic)
Workflow: Prepare NIPR Transfer Archives
Status: ✓ Success
Artifacts: spel-nipr-transfer-20251115
Duration: 6 hours
Size: 18 GB

# 2. Test offline build (16th of month, manual)
Workflow: Build STIGed AMI's
Inputs:
  - offline_mode: true
  - nipr_artifact_name: spel-nipr-transfer-20251115
  - run_rhel9: true
Status: ✓ Success
Duration: 45 minutes
Result: ami-0123456789abcdef0

# 3. Transfer to NIPR (17th of month)
Download artifacts from GitHub
Transfer via approved method
Extract in NIPR GitLab
Run NIPR builds
```

## References

- **NIPR Preparation Workflow**: `.github/workflows/nipr-prepare.yml`
- **Build Workflow**: `.github/workflows/build.yml`
- **Extraction Script**: `scripts/extract-nipr-archives.sh`
- **Storage Optimization**: `docs/Storage-Optimization.md`
- **CI/CD Setup**: `docs/CI-CD-Setup.md`

## Summary

The enhanced build workflow provides:

✅ **Automated Testing**: Test offline builds in GitHub Actions  
✅ **Pre-Transfer Validation**: Verify archives before NIPR transfer  
✅ **Troubleshooting**: Debug offline issues before deployment  
✅ **Confidence**: Deploy to NIPR with verified artifacts  
✅ **Documentation**: Clear process for offline testing

Use this capability to ensure smooth NIPR deployments every month!
