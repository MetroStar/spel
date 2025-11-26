# Offline Build Tools for NIPR Environment

This directory contains pre-downloaded tools and dependencies required for SPEL AMI builds in air-gapped environments.

## Directory Structure

```
tools/
├── packer/          # Packer binary and plugins
│   ├── packer       # Packer executable
│   └── plugins/     # Packer plugins
└── python-deps/     # Python packages as wheels
    └── *.whl        # Python wheel files
```

## Required Downloads

### Packer Binary

Download from a system with internet access:

```bash
# For Linux x86_64
PACKER_VERSION="1.9.4"  # Check for latest version
wget https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip \
  -O /tmp/packer.zip

unzip /tmp/packer.zip -d tools/packer/
chmod +x tools/packer/packer
```

### Packer Plugins

The required plugins will be installed automatically by Packer on first run. To cache them for offline use:

```bash
# On a system with internet, run Packer once to download plugins
cd spel/
./tools/packer/packer init spel/minimal-linux.pkr.hcl
./tools/packer/packer init spel/hardened-linux.pkr.hcl

# Copy the plugin cache directory
cp -r ~/.config/packer/plugins/ tools/packer/
```

Required plugins (defined in `*.pkr.hcl` files):
- `hashicorp/amazon` >= 1.0.0, < 2.0.0
- `hashicorp/azure` >= 1.0.0, < 2.0.0

### Python Dependencies

Download all required Python packages as wheels:

```bash
# Create a requirements file for downloads
cat > /tmp/spel-requirements.txt <<'EOF'
ansible-core>=2.16.0,<2.19.0
pywinrm>=0.4.3
requests>=2.31.0
passlib>=1.7.4
lxml>=4.9.0
xmltodict>=0.13.0
jmespath>=1.0.1
EOF

# Download wheels to tools/python-deps/
pip download -r /tmp/spel-requirements.txt \
  --dest tools/python-deps/ \
  --platform manylinux2014_x86_64 \
  --python-version 3.9 \
  --only-binary=:all:

# Or include source distributions for compatibility
pip download -r /tmp/spel-requirements.txt \
  --dest tools/python-deps/
```

## File Sizes (Approximate)

- **Packer Binary**: ~100 MB (compressed: ~30 MB)
- **Packer Plugins**: ~200 MB
- **Python Dependencies**: ~50 MB

**Total: ~350 MB (compressed: ~280 MB)**

## Usage

The `build/ci-setup.sh` script automatically detects and uses these offline tools:

```bash
# Offline mode is auto-detected when tools/ directory exists
export SPEL_OFFLINE_MODE=true
./build/ci-setup.sh
```

### Manual Installation

If you need to manually set up the environment:

```bash
# Install Packer
export PATH="${PWD}/tools/packer:${PATH}"

# Set Packer plugin cache
export PACKER_PLUGIN_PATH="${PWD}/tools/packer/plugins"

# Install Python dependencies
pip install --no-index --find-links tools/python-deps/ \
  ansible-core pywinrm requests passlib lxml xmltodict jmespath
```

## Verification

Check that all required files are present:

```bash
# Check Packer
tools/packer/packer version

# Check Packer plugins
ls -lh tools/packer/plugins/

# Check Python wheels
ls -lh tools/python-deps/*.whl
```

## Transfer to NIPR

When transferring to NIPR environment:

1. **Create archive** on internet-connected system:
   ```bash
   tar czf spel-offline-tools.tar.gz tools/
   ```

2. **Transfer** via approved secure transfer method

3. **Extract** in NIPR SPEL repository:
   ```bash
   cd /path/to/spel/
   tar xzf spel-offline-tools.tar.gz
   ```

4. **Verify** tools are recognized:
   ```bash
   ./build/ci-setup.sh
   # Should show: "Offline mode detected"
   ```

## Updates

To update tools in NIPR:

1. Download updated versions on internet-connected system
2. Replace files in `tools/` directory
3. Re-create and transfer archive
4. Extract in NIPR environment

## Notes

- The `ci-setup.sh` script prioritizes local tools over downloads
- Packer plugins must match the plugin versions specified in `*.pkr.hcl` files
- Python wheels should be compatible with the target RHEL/Rocky Linux version (Python 3.9+)
- Consider periodic updates to address security vulnerabilities
