#!/usr/bin/env bash
# Push image to container registry
# Implements US2 (Registry Authentication) and US3 (Image Registry Operations)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/registry.sh
source "${SCRIPT_DIR}/lib/registry.sh"

LOG_COMPONENT="push"

# =============================================================================
# Usage
# =============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Push image to container registry.

OPTIONS:
  -i, --image NAME      Image name (default: nornnet)
  -t, --tag VERSION     Version tag (e.g., 1.0.0)
  -r, --registry URL    Registry URL (default: ghcr.io)
  -n, --namespace NS    Namespace/org (default: llm-at-cormora)
  -l, --local-tag TAG   Local image tag to push
  --no-build            Skip build, push existing image
  -h, --help            Show this help

EXAMPLES:
  $(basename "$0") --tag 1.0.0
  $(basename "$0") --image myapp --tag 2.0.0 --registry docker.io
EOF
}

# =============================================================================
# Parse Arguments
# =============================================================================

IMAGE_NAME="nornnet"
VERSION=""
REGISTRY="ghcr.io"
NAMESPACE="llm-at-cormora"
LOCAL_TAG=""
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--image) IMAGE_NAME="$2"; shift 2 ;;
    -t|--tag) VERSION="$2"; shift 2 ;;
    -r|--registry) REGISTRY="$2"; shift 2 ;;
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -l|--local-tag) LOCAL_TAG="$2"; shift 2 ;;
    --no-build) SKIP_BUILD=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# =============================================================================
# Main Push Logic
# =============================================================================

main() {
  log_info "Starting image push to registry"
  
  # Check authentication
  if ! registry_has_push_credentials "$REGISTRY"; then
    log_error "No push credentials configured. Set GITHUB_TOKEN or login with podman."
    log_error "Cannot push without authentication."
    exit 1
  fi
  
  # Determine version
  if [[ -z "$VERSION" ]]; then
    VERSION=$(get_image_version)
    log_info "Using version from project: $VERSION"
  fi
  
  # Build full image reference
  local remote_image
  remote_image=$(registry_full_image_name "$REGISTRY" "$NAMESPACE" "$IMAGE_NAME" "$VERSION")
  
  log_info "Target image: $remote_image"
  
  # Build image if not skipping
  if [[ "$SKIP_BUILD" == false ]]; then
    log_info "Building image..."
    
    local commit_hash
    commit_hash=$(get_image_revision)
    
    # Build with labels
    if ! podman build \
      --file "${SCRIPT_DIR}/../Containerfile.app" \
      --tag "nornnet-build:local" \
      --label "org.opencontainers.image.version=${VERSION}" \
      --label "org.opencontainers.image.revision=${commit_hash}" \
      --label "org.opencontainers.image.source=https://github.com/${NAMESPACE}/${IMAGE_NAME}" \
      "${SCRIPT_DIR}/.."; then
      log_error "Build failed"
      exit 1
    fi
    
    LOCAL_TAG="nornnet-build:local"
  fi
  
  # Verify local image exists
  if [[ -z "$LOCAL_TAG" ]]; then
    log_error "No local image specified"
    exit 1
  fi
  
  if ! podman image exists "$LOCAL_TAG"; then
    log_error "Local image not found: $LOCAL_TAG"
    exit 1
  fi
  
  # Tag for remote registry
  log_info "Tagging image for registry..."
  podman tag "$LOCAL_TAG" "$remote_image"
  
  # Push to registry
  log_info "Pushing to registry..."
  if ! podman push "$remote_image"; then
    log_error "Push failed"
    exit 1
  fi
  
  log_info "Successfully pushed $remote_image"
  
  # Verify push
  log_info "Verifying push..."
  if podman manifest inspect "$remote_image" &>/dev/null; then
    log_info "Image verified in registry"
  else
    log_warn "Could not verify image in registry"
  fi
}

main "$@"
