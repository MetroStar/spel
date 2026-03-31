#!/bin/bash
# =============================================================================
# Extract CLI tools from chimera-builder Docker image for air-gapped runners
# =============================================================================
# On air-gapped runners (GitLab CI, offline environments), CLI tools like
# OpenTofu, AWS CLI, jq, and zip may not be pre-installed. This script checks
# for each tool and, if missing, extracts it from the chimera-builder Docker image
# which has them baked in.
#
# Usage:
#   source extract-tools.sh [DOCKER_TAG]
#
# Arguments:
#   DOCKER_TAG  Docker image tag (default: $DOCKER_IMAGE_TAG or "latest")
#
# The script is idempotent — tools already on the PATH are skipped.
# Extracted binaries are placed in /usr/local/bin (or $EXTRACT_BIN_DIR).
# =============================================================================

set -euo pipefail

DOCKER_TAG="${1:-${DOCKER_IMAGE_TAG:-latest}}"
EXTRACT_BIN_DIR="${EXTRACT_BIN_DIR:-/usr/local/bin}"
IMAGE="chimera-builder:${DOCKER_TAG}"

echo "=== Extracting CLI Tools from ${IMAGE} ==="

# Track whether we created a container (so we clean it up once)
CID=""
cleanup() {
  if [[ -n "$CID" ]]; then
    docker rm "$CID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Lazily create a container — only when we actually need to extract something
ensure_container() {
  if [[ -z "$CID" ]]; then
    CID=$(docker create "$IMAGE" /bin/true)
    echo "  Created temporary container: ${CID:0:12}"
  fi
}

# -------------------------------------------------------------------------
# 1. OpenTofu (tofu)
# -------------------------------------------------------------------------
if command -v tofu &>/dev/null; then
  echo "  [OK] tofu already available: $(tofu version 2>/dev/null | head -1)"
else
  echo "  [EXTRACT] tofu not found — extracting from Docker image"
  ensure_container
  docker cp "${CID}:/usr/local/bin/tofu" "${EXTRACT_BIN_DIR}/tofu"
  chmod +x "${EXTRACT_BIN_DIR}/tofu"
  echo "  [OK] tofu extracted: $(${EXTRACT_BIN_DIR}/tofu version 2>/dev/null | head -1)"
fi

# -------------------------------------------------------------------------
# 2. AWS CLI v2 (aws)
#    AWS CLI is installed to /opt/aws-cli/ with a symlink at /usr/local/bin/aws.
#    We need the entire directory tree, not just a single binary.
# -------------------------------------------------------------------------
if command -v aws &>/dev/null; then
  echo "  [OK] aws already available: $(aws --version 2>/dev/null)"
else
  echo "  [EXTRACT] aws not found — extracting from Docker image"
  ensure_container
  mkdir -p /opt/aws-cli
  docker cp "${CID}:/opt/aws-cli/." /opt/aws-cli/
  ln -sf /opt/aws-cli/v2/current/bin/aws "${EXTRACT_BIN_DIR}/aws"
  ln -sf /opt/aws-cli/v2/current/bin/aws_completer "${EXTRACT_BIN_DIR}/aws_completer"
  echo "  [OK] aws extracted: $(${EXTRACT_BIN_DIR}/aws --version 2>/dev/null)"
fi

# -------------------------------------------------------------------------
# 3. jq
# -------------------------------------------------------------------------
if command -v jq &>/dev/null; then
  echo "  [OK] jq already available: $(jq --version 2>/dev/null)"
else
  echo "  [EXTRACT] jq not found — extracting from Docker image"
  ensure_container
  docker cp "${CID}:/usr/bin/jq" "${EXTRACT_BIN_DIR}/jq"
  chmod +x "${EXTRACT_BIN_DIR}/jq"
  # jq needs libjq and libonig shared libraries
  docker cp "${CID}:/usr/lib64/libjq.so.1" /usr/lib64/ 2>/dev/null || true
  docker cp "${CID}:/usr/lib64/libonig.so.5" /usr/lib64/ 2>/dev/null || true
  ldconfig 2>/dev/null || true
  echo "  [OK] jq extracted: $(${EXTRACT_BIN_DIR}/jq --version 2>/dev/null)"
fi

# -------------------------------------------------------------------------
# 4. zip
# -------------------------------------------------------------------------
if command -v zip &>/dev/null; then
  echo "  [OK] zip already available: $(zip --version 2>/dev/null | head -2 | tail -1)"
else
  echo "  [EXTRACT] zip not found — extracting from Docker image"
  ensure_container
  docker cp "${CID}:/usr/bin/zip" "${EXTRACT_BIN_DIR}/zip"
  chmod +x "${EXTRACT_BIN_DIR}/zip"
  echo "  [OK] zip extracted"
fi

echo ""
echo "=== Tool Extraction Complete ==="
