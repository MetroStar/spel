# Storage Requirements Guide

This guide covers storage requirements for the Docker-based Chimera build system.

## Docker Image Size

The Chimera builder Docker image contains all dependencies baked in:

| Format              | Size    |
| ------------------- | ------- |
| Gzipped tarball     | ~305 MB |
| Uncompressed image  | ~834 MB |

### What's Included

The Docker image contains:

| Component | Approximate Size |
| --- | --- |
| Rocky Linux 9 base (Iron Bank) | ~200 MB |
| Packer 1.11.2 | ~95 MB |
| AWS CLI v2 | ~150 MB |
| Ansible Core | ~50 MB |
| Packer plugins (Amazon, Ansible, etc.) | ~250 MB |
| Ansible roles and collections | ~20 MB |
| Python packages and dependencies | ~50 MB |
| AMIgen scripts (vendor/amigen8, vendor/amigen9) | ~5 MB |
| Other tools and utilities | ~14 MB |
| **Total** | **~834 MB** |

## Storage by Environment

### GitHub Actions Runner

The GitHub Actions workflows automatically manage storage:

| Workflow Step | Storage Used |
| --- | --- |
| Repository checkout | ~100 MB |
| Docker build cache | ~1-2 GB |
| Final Docker image | ~834 MB |
| Gzipped tarball | ~305 MB |
| Artifact upload | 0 (uses GitHub storage) |
| **Peak Usage** | **~3 GB** |

The runner is ephemeral, so storage is released after workflow completion.

### GitLab Runner (Air-Gapped)

For GitLab CI builds, plan for the following storage:

| Component | Size |
| --- | --- |
| Docker image tarball | ~305 MB |
| Imported Docker image | ~834 MB |
| Repository checkout | ~100 MB |
| Build workspace per job | 10-20 GB |
| Packer cache | 5-10 GB |
| **Single Build Total** | **~15-25 GB** |
| **Per Additional Concurrent Build** | **+10-20 GB** |

**Recommendation**: Maintain at least 50 GB free space for builds.

### Local Development

For local Docker-based builds:

| Component | Size |
| --- | --- |
| Docker image | ~834 MB |
| Repository clone | ~100 MB |
| Build workspace | 10-20 GB |
| Packer cache | 5-10 GB |
| **Total** | **~15-25 GB** |

## Transfer Considerations

When transferring the Docker image tarball to air-gapped environments:

| Transfer Medium | Considerations |
| --- | --- |
| USB drive | Minimum 512 MB capacity |
| CD/DVD | Single CD is sufficient |
| Network transfer | ~305 MB transfer |
| Secure file share | ~305 MB upload |

### Transfer Artifacts

Each Docker image build produces:

```bash
chimera-builder-YYYYMMDD/
├── chimera-builder-YYYYMMDD.tar.gz       # ~305 MB - Docker image
├── chimera-builder-YYYYMMDD.tar.gz.sha256 # <1 KB - Checksum
└── chimera-builder-YYYYMMDD-manifest.txt  # <2 KB - Build details
```

**Total transfer size**: ~305 MB

## Optimization Tips

### Clean Up Old Images

```bash
# List chimera-builder images
docker images chimera-builder

# Remove old images
docker rmi chimera-builder:old_tag

# Remove unused Docker resources
docker system prune
```

### Clean Up Packer Cache

```bash
# Remove Packer temporary files
rm -rf ~/.cache/packer/*
rm -rf ~/.packer.d/tmp/*
```

### Minimize Concurrent Builds

Each concurrent build requires additional storage. Run builds sequentially when storage is limited.

## Artifact Retention

| Platform       | Retention                           | Notes                              |
|----------------|-------------------------------------|----------------------------------- |
| GitHub Actions | 30 days                             | Configurable in workflow           |
| GitLab CI      | 7 days (jobs), 90 days (infra.env)  | Configurable in .gitlab-ci.yml     |

Adjust retention periods based on your needs and storage constraints.

## Comparison: Docker vs. Old Archive Approach

The Docker-based approach simplifies storage management:

| Aspect | Docker Approach | Old Archive Approach |
| -------- | ------------------- | ----------------------- |
| Transfer size | ~305 MB | ~1.1 GB |
| Number of files | 3 | 7+ |
| Extraction needed | `docker load` | Multiple extractions |
| Verification | Single checksum | Multiple checksums |
| Dependencies | Self-contained | Scattered directories |

The Docker approach reduces transfer size by ~70% and simplifies the workflow significantly.

## See Also

- [CI-CD-Setup.md](CI-CD-Setup.md) - Full CI/CD documentation
- [QUICK-REFERENCE-Optimization.md](QUICK-REFERENCE-Optimization.md) - Quick reference guide
