#!/bin/bash
# Build script for bootc ISO using bootc-image-builder
#
# This script builds a bootable ISO using bootc-image-builder
# Run from the project root directory
#
# Usage:
#   ./build.sh                    # Build with defaults
#   BASE_IMAGE=custom-image ./build.sh  # Use custom base image
#
# Requirements:
#   - podman with v5+ and CRIU support
#   - Access to /var/lib/containers/storage
#   - ~50GB free disk space

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
WORK_DIR="${SCRIPT_DIR}/work"

# Configuration
BASE_IMAGE="${BASE_IMAGE:-quay.io/centos-bootc/centos-bootc:stream9}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

# Create directories
mkdir -p "${OUTPUT_DIR}" "${WORK_DIR}"

echo "=== Bootc ISO Builder ==="
echo "Base image: ${BASE_IMAGE}"
echo "Output directory: ${OUTPUT_DIR}"
echo "Container engine: ${CONTAINER_ENGINE}"
echo ""

# Check if container engine is available
if ! command -v "${CONTAINER_ENGINE}" &> /dev/null; then
    echo "ERROR: ${CONTAINER_ENGINE} not found. Please install it first."
    exit 1
fi

# Check if we can run privileged containers
echo "=== Checking container permissions ==="
if ! ${CONTAINER_ENGINE} run --rm --privileged alpine echo "OK" &>/dev/null; then
    echo "WARNING: Cannot run privileged containers. The build may fail."
    echo "Consider running on Fedora/RHEL/CentOS or use the Hetzner server."
fi

# Pull bootc-image-builder
echo "=== Pulling bootc-image-builder container ==="
${CONTAINER_ENGINE} pull quay.io/centos-bootc/bootc-image-builder:latest || {
    echo "ERROR: Failed to pull bootc-image-builder"
    exit 1
}

# Pull base image (if not already cached)
echo "=== Pulling base image ==="
${CONTAINER_ENGINE} pull "${BASE_IMAGE}" || {
    echo "ERROR: Failed to pull base image: ${BASE_IMAGE}"
    exit 1
}

# Build ISO using bootc-image-builder
# Note: The correct syntax is 'build <image-name>' not environment variables
echo "=== Building ISO with bootc-image-builder ==="
echo "This may take 15-30 minutes depending on system resources..."

${CONTAINER_ENGINE} run --rm \
    --privileged \
    --net=host \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v "${OUTPUT_DIR}:/output" \
    quay.io/centos-bootc/bootc-image-builder:latest build \
    "${BASE_IMAGE}" \
    --type anaconda-iso \
    --output /output

echo ""
echo "=== Build complete ==="
echo ""
echo "Generated files:"
if [ -d "${OUTPUT_DIR}/bootiso" ]; then
    ls -lh "${OUTPUT_DIR}/bootiso/"
    echo ""
    echo "ISO location: ${OUTPUT_DIR}/bootiso/install.iso"
else
    echo "Warning: No bootiso directory found in output"
    ls -la "${OUTPUT_DIR}/"
fi

echo ""
echo "=== Next Steps ==="
echo "1. Write ISO to USB: sudo dd if=${OUTPUT_DIR}/bootiso/install.iso of=/dev/sdX bs=4M status=progress"
echo "2. Test in VM: qemu-system-x86_64 -m 4G -cdrom ${OUTPUT_DIR}/bootiso/install.iso -boot d"
