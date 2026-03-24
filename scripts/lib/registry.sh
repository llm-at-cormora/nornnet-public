#!/usr/bin/env bash
# Shared registry functions for nornnet
# Handles authentication and registry operations

set -euo pipefail

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=logging.sh
source "${SCRIPT_DIR}/logging.sh"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# =============================================================================
# Registry Configuration
# =============================================================================

REGISTRY_DEFAULT="${REGISTRY:-ghcr.io}"
NAMESPACE_DEFAULT="${NAMESPACE:-llm-at-cormora}"
IMAGE_NAME_DEFAULT="${IMAGE_NAME:-nornnet}"

# =============================================================================
# Authentication Functions
# =============================================================================

# Check if push credentials are configured
registry_has_push_credentials() {
  local registry="${1:-$REGISTRY_DEFAULT}"
  
  # Check for GitHub token in environment
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    return 0
  fi
  
  # Check for podman login credentials
  if podman login --get-login "$registry" &>/dev/null; then
    return 0
  fi
  
  return 1
}

# Login to registry with token
registry_login() {
  local registry="${1:-$REGISTRY_DEFAULT}"
  local username="${2:-${PUSH_USERNAME:-}}"
  local token="${3:-${GITHUB_TOKEN:-${PUSH_PASSWORD:-}}}"
  
  if [[ -z "$username" ]] || [[ -z "$token" ]]; then
    log_error "Registry login requires username and token"
    return 1
  fi
  
  log_info "Authenticating with registry: $registry"
  
  if ! echo "$token" | podman login \
    --username "$username" \
    --password-stdin \
    "$registry" 2>&1; then
    log_error "Failed to authenticate with registry"
    return 1
  fi
  
  log_info "Successfully authenticated with registry"
  return 0
}

# Check anonymous read access
registry_check_anonymous_read() {
  local registry="${1:-$REGISTRY_DEFAULT}"
  local image="${2:-}"
  
  # Test with a known public image
  if podman pull --quiet docker.io/library/alpine:latest &>/dev/null; then
    log_info "Anonymous read access verified"
    return 0
  fi
  
  log_warn "Anonymous read may be restricted"
  return 1
}

# =============================================================================
# Image Tagging Functions
# =============================================================================

# Build full image reference
registry_full_image_name() {
  local registry="${1:-$REGISTRY_DEFAULT}"
  local namespace="${2:-$NAMESPACE_DEFAULT}"
  local image="${3:-$IMAGE_NAME_DEFAULT}"
  local version="${4:-}"
  
  local name="${registry}/${namespace}/${image}"
  
  if [[ -n "$version" ]]; then
    echo "${name}:v${version}"
  else
    echo "${name}:latest"
  fi
}

# =============================================================================
# Version and Metadata Functions
# =============================================================================

# Get Git commit hash for image label
get_image_revision() {
  git rev-parse HEAD 2>/dev/null || echo "unknown"
}

# Get version from Cargo.toml, package.json, or default
get_image_version() {
  local version="0.0.1"
  
  if [[ -f "Cargo.toml" ]]; then
    version=$(grep '^version' Cargo.toml | head -1 | sed 's/version = "\(.*\)"/\1/')
  elif [[ -f "package.json" ]]; then
    version=$(grep '"version"' package.json | sed 's/.*"\([0-9.]*\)".*/\1/')
  fi
  
  echo "$version"
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate registry format
validate_registry() {
  local registry="$1"
  
  if [[ ! "$registry" =~ ^[a-z0-9.-]+\.[a-z]{2,}(:[0-9]+)?$ ]]; then
    log_error "Invalid registry format: $registry"
    return 1
  fi
  
  return 0
}

# Validate image name format
validate_image_name() {
  local image="$1"
  
  if [[ ! "$image" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    log_error "Invalid image name format: $image"
    return 1
  fi
  
  return 0
}

# Validate version format (semantic versioning)
validate_version() {
  local version="$1"
  
  if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version format (expected semver): $version"
    return 1
  fi
  
  return 0
}
