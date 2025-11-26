# NIPR Refactoring Summary

**Date**: 2024
**Objective**: Refactor SPEL repository for air-gapped NIPR environment builds

## Changes Overview

This refactoring enables SPEL AMI builds to work in the NIPR (air-gapped) environment while maintaining compatibility with commercial AWS builds via GitHub Actions.

## Key Modifications

### 1. Dependency Vendoring

**AMIgen Submodules**:
- `vendor/amigen8/` - Git submodule for EL8 builds
- `vendor/amigen9/` - Git submodule for EL9 builds
- Modified `spel/scripts/amigen8-build.sh` and `amigen9-build.sh` to use `file://` protocol
- Uses `cp` instead of `git clone` when local paths detected

**Ansible Roles**:
- Created `spel/ansible/roles/` directory for vendored roles from GitHub
- Updated `requirements.yml` to use local paths
- Modified `spel/hardened-linux.pkr.hcl` provisioners to use local roles instead of git clone
- Roles to vendor: RHEL8-STIG, RHEL9-STIG, AMAZON2023-CIS, Windows-*-STIG

**Build Tools**:
- `tools/packer/` - For Packer binary and plugins
- `tools/python-deps/` - For Python wheel files
- `build/ci-setup.sh` - Unified setup script with offline detection

### 2. Package Mirroring

**Repository Mirrors**:
- `mirrors/el8/` - RHEL 8 baseos, appstream, extras, epel
- `mirrors/el9/` - RHEL 9 baseos, appstream, extras, epel
- `mirrors/spel-packages/` - SPEL custom packages repository
- `scripts/sync-mirrors.sh` - Automated sync script
- `scripts/sync-spel-packages.sh` - SPEL packages sync
- `scripts/setup-local-repos.sh` - Configure local repos in NIPR

**Offline AWS Utilities**:
- `offline-packages/` directory created
- Pre-staged: AWS CLI v2, CloudFormation Bootstrap, SSM Agent
- New Packer variables: `spel_cfnbootstrap_source`, `spel_awscli_source`, `spel_ssm_agent_source`
- Support for `file://` URLs in both minimal and hardened templates

### 3. NIPR AWS Integration

**VPC Endpoint Support**:
- New variables in both `minimal-linux.pkr.hcl` and `hardened-linux.pkr.hcl`:
  - `aws_vpc_id` - VPC ID for Packer builds
  - `aws_vpc_endpoint_ec2` - EC2 VPC endpoint DNS
  - `aws_vpc_endpoint_s3` - S3 VPC endpoint DNS  
  - `aws_vpc_endpoint_ssm` - SSM VPC endpoint DNS
- Updated builder blocks to use `vpc_id` parameter
- Created `spel/userdata/nipr-vpc-config.sh` for DNS configuration

**NIPR Account Support**:
- New variable: `aws_nipr_account_id` - Override marketplace AMI account IDs
- New variable: `aws_nipr_ami_regions` - Override commercial regions
- Added `local.effective_*_owners` logic with ternary operators
- Updated all `source_ami_filter` blocks to use effective owners

### 4. CI/CD Updates

**GitLab CI**:
- `.gitlab-ci.yml` configured with:
  - `SPEL_OFFLINE_MODE=true` environment variable
  - Manual job triggers for builds
  - `spel-nipr-runner` tag requirement
  - Conditional variables for different build targets

**Tardigrade-CI Removal**:
- Created static `.tardigrade-ci` stubs in amigen8/amigen9
- Eliminates GitHub dependency during builds
- Maintains file structure compatibility

**Unified CI Setup**:
- `build/ci-setup.sh` with offline mode detection
- Auto-detects vendored tools or `SPEL_OFFLINE_MODE` env var
- Installs from local binaries/wheels when available
- Falls back to downloads in commercial environment

### 5. Documentation

**NIPR Setup Guide**:
- `docs/NIPR-Setup.md` - Comprehensive 7-part guide covering:
  1. Preparing dependencies on internet-connected system
  2. Transferring artifacts to NIPR
  3. NIPR environment setup
  4. Running builds via GitLab CI
  5. Maintenance and updates
  6. Troubleshooting
  7. Security considerations

**Component Documentation**:
- `mirrors/README.md` - Mirror usage and sync instructions
- `offline-packages/README.md` - AWS utilities download guide
- `tools/README.md` - Build tools preparation instructions

## File Modifications Summary

### Modified Files

1. `spel/scripts/amigen8-build.sh` - Added file:// protocol support
2. `spel/scripts/amigen9-build.sh` - Added file:// protocol support  
3. `spel/minimal-linux.pkr.hcl` - Added VPC, NIPR, offline package variables
4. `spel/hardened-linux.pkr.hcl` - Added VPC, NIPR, offline package variables
5. `requirements.yml` - Changed to local paths for Ansible roles

### Created Files

1. `spel/ansible/roles/.gitkeep` - Placeholder for vendored roles
2. `spel/ansible/collections/.gitkeep` - Placeholder for collections
3. `mirrors/README.md` - Mirror documentation
4. `mirrors/el8/.gitkeep`, `mirrors/el9/.gitkeep`, `mirrors/spel-packages/.gitkeep`
5. `scripts/sync-mirrors.sh` - Automated repository sync
6. `scripts/sync-spel-packages.sh` - SPEL packages sync
7. `scripts/setup-local-repos.sh` - Local repo configuration
8. `amigen8/.tardigrade-ci` - Static stub
9. `amigen9/.tardigrade-ci` - Static stub
10. `build/ci-setup.sh` - Unified CI setup script
11. `spel/userdata/nipr-vpc-config.sh` - VPC endpoint DNS config
12. `offline-packages/README.md` - AWS utilities guide
13. `offline-packages/.gitkeep` - Directory placeholder
14. `tools/README.md` - Build tools guide
15. `tools/packer/.gitkeep`, `tools/python-deps/.gitkeep`
16. `tools/.gitignore` - Exclude downloaded binaries
17. `docs/NIPR-Setup.md` - Comprehensive setup guide
18. `docs/NIPR-Refactoring-Summary.md` - This file

### Unchanged (Requires Manual Steps)

- `.gitmodules` - Submodules already configured
- `.gitlab-ci.yml` - Already existed with NIPR configuration
- AMIgen repos in `vendor/` - Require `git submodule update`

## Variable Reference

### New Packer Variables

**NIPR AWS Configuration**:
- `aws_nipr_account_id` (string) - NIPR marketplace account ID
- `aws_nipr_ami_regions` (list) - NIPR regions for AMI distribution
- `aws_vpc_id` (string) - VPC ID for builds
- `aws_vpc_endpoint_ec2` (string) - EC2 VPC endpoint DNS
- `aws_vpc_endpoint_s3` (string) - S3 VPC endpoint DNS
- `aws_vpc_endpoint_ssm` (string) - SSM VPC endpoint DNS

**Offline Package Sources**:
- `spel_cfnbootstrap_source` (string) - CloudFormation bootstrap URL or file:// path
- `spel_awscli_source` (string) - AWS CLI v2 URL or file:// path
- `spel_ssm_agent_source` (string) - SSM Agent URL or file:// path

**Conditional Behavior**:
- `amigen_aws_cfnbootstrap` - Now defaults to "" (uses spel_cfnbootstrap_source fallback)
- `amigen_aws_cliv1_source` - Now defaults to "" (uses spel_awscli_source fallback)
- `amigen_aws_cliv2_source` - Now defaults to "" (uses spel_awscli_source fallback)

### Environment Variables

- `SPEL_OFFLINE_MODE` - Set to "true" to enable offline mode
- `PACKER_PLUGIN_PATH` - Auto-set to local plugins by ci-setup.sh
- `PKR_VAR_*` - GitLab CI variables pass-through to Packer

## Migration Path

### For Existing Commercial Builds

**No changes required** - all modifications are backward compatible:
- Default variable values maintain current behavior
- VPC variables default to null (not used in commercial)
- Offline packages fall back to internet URLs
- GitHub Actions continue to work as before

### For New NIPR Builds

1. Follow `docs/NIPR-Setup.md` preparation steps
2. Set GitLab CI variables for NIPR account/VPC
3. Transfer complete archive to NIPR
4. Extract and run `git submodule update`
5. Configure local repos with `setup-local-repos.sh`
6. Run GitLab CI pipeline

## Testing Recommendations

### Commercial Environment (GitHub Actions)

```bash
# Verify backward compatibility
packer validate spel/minimal-linux.pkr.hcl
packer validate spel/hardened-linux.pkr.hcl

# Test minimal build
packer build -only 'amazon-ebssurrogate.minimal-rhel-9-hvm' spel/minimal-linux.pkr.hcl
```

### NIPR Environment (GitLab CI)

```bash
# Set offline mode
export SPEL_OFFLINE_MODE=true

# Run CI setup
./build/ci-setup.sh

# Validate templates
./tools/packer/packer validate \
  -var aws_nipr_account_id="<ACCOUNT>" \
  -var aws_vpc_id="vpc-xxx" \
  spel/minimal-linux.pkr.hcl

# Test build
./tools/packer/packer build \
  -var aws_nipr_account_id="<ACCOUNT>" \
  -var aws_vpc_id="vpc-xxx" \
  -var aws_vpc_endpoint_ec2="vpce-xxx.ec2..." \
  -var aws_vpc_endpoint_s3="vpce-xxx.s3..." \
  -var aws_vpc_endpoint_ssm="vpce-xxx.ssm..." \
  -only 'amazon-ebssurrogate.minimal-rhel-9-hvm' \
  spel/minimal-linux.pkr.hcl
```

## Storage Requirements

### Internet-Connected System

- Repository mirrors: ~30 GB
- SPEL packages: ~100 MB
- Build tools: ~300 MB
- Offline packages: ~100 MB
- **Total**: ~31 GB

### Transfer Archive

- Compressed size: ~15-20 GB
- Uncompressed size: ~30-35 GB

### NIPR System

- Full repository: ~35 GB
- Plus build workspace: ~10-15 GB per concurrent build
- **Recommended**: 50 GB free disk space

## Maintenance Schedule

- **Monthly**: Update package mirrors for security patches
- **Quarterly**: Update Ansible roles for STIG updates
- **Semi-annually**: Update Packer and Python tools
- **As needed**: Update AMIgen submodules

## Security Notes

1. All transfers must use approved NIPR transfer methods
2. Scan archives before and after transfer per org policy
3. Verify SHA256 checksums on both sides
4. Use IAM roles (not long-lived credentials) for AWS access
5. Restrict GitLab runner access to dedicated service accounts
6. Encrypt archives during transfer with approved encryption

## Known Limitations

1. **Manual sync required**: Repository mirrors must be manually synced and transferred
2. **No automatic updates**: Ansible roles must be manually updated
3. **Version pinning**: Consider pinning specific versions in production
4. **Storage overhead**: Full mirrors require significant disk space
5. **Transfer time**: Initial archive transfer may take hours depending on method

## Future Enhancements

Potential improvements for consideration:

1. **Incremental mirrors**: Delta sync to reduce transfer size
2. **Version management**: Automated tracking of component versions
3. **Validation scripts**: Pre-transfer verification of all dependencies
4. **Build caching**: Reuse intermediate artifacts across builds
5. **Automated testing**: Integration tests for NIPR-specific configuration

## Support

For questions or issues:

1. Review `docs/NIPR-Setup.md` troubleshooting section
2. Check GitLab CI job logs for detailed errors
3. Contact your organization's SPEL administrator
4. For general SPEL issues, create GitHub issue (from commercial network)

## References

- **Main SPEL Repo**: https://github.com/MetroStar/spel
- **AMIgen8**: https://github.com/MetroStar/amigen8
- **AMIgen9**: https://github.com/MetroStar/amigen9
- **Ansible Lockdown**: https://github.com/ansible-lockdown
- **Packer Docs**: https://www.packer.io/docs
- **AWS VPC Endpoints**: https://docs.aws.amazon.com/vpc/latest/privatelink/
