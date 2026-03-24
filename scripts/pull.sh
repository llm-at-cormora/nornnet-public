#!/usr/bin/env bash
# Pull image from container registry
# Implements US2 (Anonymous Read) and US3 (Image Verification)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/logging.sh
source "${SCRIPT_DIR}/scripts/lib/logging.sh"
# shellcheck source=scripts/lib/config.sh
source "${SCRIPT_DIR}/scripts/lib/config.sh"
# shellcheck source=scripts/lib/registry.sh
source "${SCRIPT_DIR}/scripts/lib/registry.sh"

LOG_COMPONENT="pull"

# =============================================================================
# Usage
# =============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Pull image from container registry.

OPTIONS:
  -i, --image NAME      Image name (default: nornnet)
  -t, --tag VERSION     Version tag (e.g., 1.0.0) or 'latest'
  -r, --registry URL    Registry URL (default: ghcr.io)
  -n, --namespace NS    Namespace/org (default: llm-at-cormora)
  -o, --output TAG      Local tag to save as (default: same as remote)
  --arch ARCH          Architecture filter (e.g., amd64, arm64)
  -h, --help            Show this help

EXAMPLES:
  $(basename "$0") --tag 1.0.0
  $(basename "$0") --image myapp --tag latest
EOF
}

# =============================================================================
# Parse Arguments
# =============================================================================

IMAGE_NAME="nornnet"
VERSION="latest"
REGISTRY="ghcr.io"
NAMESPACE="llm-at-cormora"
OUTPUT_TAG=""
ARCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--image) IMAGE_NAME="$2"; shift 2 ;;
    -t|--tag) VERSION="$2"; shift 2 ;;
    -r|--registry) REGISTRY="$2"; shift 2 ;;
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -o|--output) OUTPUT_TAG="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# =============================================================================
# Main Pull Logic
# =============================================================================

main() {
  log_info "Starting image pull from registry"
  
  # Build full image reference
  local remote_image
  remote_image=$(registry_full_image_name "$REGISTRY" "$NAMESPACE" "$IMAGE_NAME" "$VERSION")
  
  log_info "Source image: $remote_image"
  
  # Determine local tag
  if [[ -z "$OUTPUT_TAG" ]]; then
    OUTPUT_TAG="$remote_image"
  fi
  
  # Check anonymous read access
  log_info "Verifying registry access..."
  if ! registry_check_anonymous_read "$REGISTRY" "$remote_image"; then
    log_warn "Anonymous read may not work, attempting pull anyway..."
  fi
  
  # Pull image
  log_info "Pulling image..."
  if ! podman pull "$remote_image"; then
    log_error "Pull failed"
    exit 1
  fi
  
  # Tag with local name if different
  if [[ "$OUTPUT_TAG" != "$remote_image" ]]; then
    log_info "Tagging as $OUTPUT_TAG"
    podman tag "$remote_image" "$OUTPUT_TAG"
  fi
  
  log_info "Successfully pulled $remote_image"
  
  # Verify image
  log_info "Verifying image..."
  local image_id
  image_id=$(podman inspect --format '{{.Id}}' "$remote_image")
  log_info "Image ID: ${image_id:0:12}"
  
  # Show labels
  local version_label
  version_label=$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$remote_image" 2>/dev/null || echo "none")
  local revision_label
  revision_label=$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$remote_image" 2>/dev/null || echo "none")
  
  log_info "Version: $version_label"
  log_info "Revision: $revision_label"
}

main "$@"
