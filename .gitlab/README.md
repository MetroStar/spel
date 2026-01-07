# GitLab CI Configuration

This directory contains GitLab CI pipeline configurations for the SPEL project.

## Pipeline Overview

The GitLab CI pipeline uses a **Docker-based approach** where all build dependencies are
baked into a container image. This image is built in a connected environment (GitHub Actions)
and transferred to the air-gapped GitLab environment.

## Pipeline File

### `.gitlab-ci.yml` (Root)

**Purpose**: Build STIGed AMIs in air-gapped AWS GovCloud environments using Docker.

**Key Features**:
- Imports pre-built Docker image from tarball
- Creates AWS infrastructure (VPC, security groups, IAM roles) if needed
- Builds SPEL images for Linux and Windows operating systems
- All dependencies are baked into the Docker image (no internet required)

**Stages**:
1. `import` - Import Docker image from tarball
2. `infra` - Create AWS infrastructure (optional, one-time setup)
3. `build` - Build AMIs using Docker container

## Workflow Overview

### Initial Setup (First Time)

1. **Build Docker Image** (in connected environment):
   ```bash
   # Run GitHub Actions: offline-prepare.yml
   # Or build locally:
   docker build -t spel-builder:$(date +%Y%m%d) .
   docker save spel-builder:$(date +%Y%m%d) | gzip > spel-builder-$(date +%Y%m%d).tar.gz
   ```

2. **Transfer to Air-Gapped Environment**:
   ```bash
   # Binary format (direct transfer - smaller, faster):
   scp spel-builder-*.tar.gz runner:/transfer/
   
   # Base64 format (SharePoint - avoids corruption):
   # Upload .tar.gz.b64 to SharePoint, download in air-gap, then:
   scp spel-builder-*.tar.gz.b64 runner:/transfer/
   
   # Optional: include checksum
   sha256sum spel-builder-*.tar.gz > spel-builder-*.tar.gz.sha256
   scp spel-builder-*.tar.gz.sha256 runner:/transfer/
   ```

3. **Run Pipeline**:
   - Trigger `import:docker` job to load the image
   - Trigger `infra:*` jobs if infrastructure doesn't exist
   - Trigger `build:*` jobs to create AMIs

### Updating Dependencies

1. Rebuild Docker image with new dependencies (connected environment)
2. Transfer new tarball to air-gapped environment
3. Run `import:docker` job to load updated image
4. Run build jobs as needed

## Configuration Variables

### Required CI/CD Variables

| Variable | Description |
|----------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key for Packer |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key for Packer |
| `AWS_SESSION_TOKEN` | Optional: STS session token |

> **Important**: The IAM user/role providing these credentials needs extensive EC2 permissions
> to create AMIs, launch instances, manage snapshots, etc. See [CI-CD-Setup.md](../docs/CI-CD-Setup.md#3-packer-execution-iam-permissions)
> for the full policy.

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOCKER_IMAGE_PATH` | `/transfer/spel-builder-*.tar.gz` | Path to Docker tarball |
| `PKR_VAR_aws_region` | `us-gov-east-1` | AWS region for builds |
| `PKR_VAR_aws_ami_regions` | `["${PKR_VAR_aws_region}"]` | Regions to copy AMI to (defaults to build region) |
| `SPEL_IDENTIFIER` | `spel` | AMI name prefix |
| `INFRA_PREFIX` | `spel-offline` | Infrastructure resource prefix |

## Docker Image Contents

The Docker image (~305 MB compressed) includes:

| Component | Version | Notes |
|-----------|---------|-------|
| Base Image | Rocky Linux 8 UBI Micro | Minimal footprint |
| Packer | 1.11.2 | With all required plugins |
| Ansible | 2.14+ | With collections and roles |
| Python | 3.9 | With pywinrm for Windows |
| AWS CLI v2 | Latest | For AWS operations |
| AMIgen Scripts | Latest | Baked in for offline EC2 |

## Air-Gapped Environment Considerations

### Windows Builds - WSUS Required

Windows builds use the `windows-update` Packer provisioner which by default contacts
Microsoft Update servers. In air-gapped environments, you **must** configure a local
WSUS server.

Edit `spel/hardened-linux.pkr.hcl` to enable WSUS:

```hcl
provisioner "windows-update" {
  pause_before = "30s"
  only = [
    "amazon-ebs.hardened-windows-2016-hvm",
    "amazon-ebs.hardened-windows-2019-hvm",
    "amazon-ebs.hardened-windows-2022-hvm"
  ]
  # Uncomment and configure for air-gapped:
  update_server = "http://wsus.your-domain.mil:8530"
  search_criteria = "IsInstalled=0"
}
```

### Linux Builds - Package Mirrors

Linux builds may attempt to install packages from internet repositories.
Ensure your VPC has access to:
- Local YUM/DNF mirrors for RHEL, Oracle Linux, Amazon Linux
- Or configure the EC2 instances to use internal mirrors

The Docker image includes offline packages for:
- AWS CLI v2
- CloudFormation Bootstrap (cfn-init)
- SSM Agent

### Network Requirements

The GitLab Runner needs:
- Docker installed and running
- Access to the transfer directory (default: `/transfer/`)
- Network access to AWS APIs (direct or via proxy)
- SSH access to EC2 instances (for Packer provisioners)

The EC2 build instances need:
- Outbound access to AWS APIs (S3, EC2, etc.)
- Access to package mirrors (internal or via NAT/proxy)
- For Windows: Access to WSUS server

## Runner Requirements

### Required Tags
- `spel-offline-runner`

### Runner Configuration
- Docker executor or shell executor with Docker installed
- Sufficient disk space (~5 GB for image import)
- AWS credentials configured via CI/CD variables

## Build Jobs

### Linux Builders
- `build:amzn2023` - Amazon Linux 2023
- `build:rhel9` - RHEL 9
- `build:ol9` - Oracle Linux 9
- `build:rhel8` - RHEL 8
- `build:ol8` - Oracle Linux 8

### Windows Builders
- `build:windows2016` - Windows Server 2016
- `build:windows2019` - Windows Server 2019
- `build:windows2022` - Windows Server 2022

### Full Build
- `build:all` - All Linux and Windows builders (triggered on tags)

## Troubleshooting

### Docker Import Fails

```
ERROR: No Docker image tarball found!
```

**Solution**: Transfer the Docker image tarball to the path specified by `DOCKER_IMAGE_PATH`:
```bash
scp spel-builder-*.tar.gz runner:/transfer/
```

### AWS Credential Issues

```
Error loading credentials
```

**Solution**: Verify CI/CD variables are set:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (if using STS)

### Windows Update Timeout

```
windows-update: timeout waiting for updates
```

**Solution**: Configure WSUS server in the Packer template (see above).

### Build Timeout (6 hours)

Long builds may timeout. Common causes:
- Slow network to AWS
- Large Windows updates
- AMI copy to multiple regions

**Solution**: Increase job timeout or split builders into separate jobs.

## References

- [CI-CD-Setup.md](../docs/CI-CD-Setup.md) - Complete CI/CD documentation
- [Storage-Optimization.md](../docs/Storage-Optimization.md) - Storage requirements
- [QUICK-REFERENCE-Optimization.md](../docs/QUICK-REFERENCE-Optimization.md) - Quick reference
