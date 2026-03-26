# Shared test utilities for nornnet tests

# =============================================================================
# Helper functions for remote tool access
# =============================================================================

# Check if skopeo is available locally OR on bootc device
# Returns 0 if available, 1 if not
# Usage: skip_if_no_tag_lister || true
has_tag_lister() {
  # Check local first
  if command -v skopeo &>/dev/null; then
    return 0
  fi
  if command -v crane &>/dev/null; then
    return 0
  fi
  # Check if we can use skopeo on bootc device
  if bootc_device_configured; then
    if bootc_ssh "command -v skopeo" &>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# Get version from bootc status using grep-based parsing
# Works on build server without jq by running jq on bootc device
# Usage: version=$(bootc_get_version)
bootc_get_version() {
  # Try jq on bootc device first (bootc 1.14.1 format)
  # Run jq remotely to avoid needing jq locally
  local version
  version="$(bootc_ssh "bootc status --format=json | jq -r '.status.booted.image.version // .version // empty' 2>/dev/null")" || true
  
  # Fallback to grep-based parsing if jq returns empty
  if [ -z "$version" ]; then
    local status
    status="$(bootc_status)" || return 1
    version="$(echo "$status" | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/.*"version":[[:space:]]*"//;s/"$//')" || true
  fi
  
  echo "$version"
}

# Install skopeo on build server if not available
# Returns 0 if installed or already available, 1 on failure
install_skopeo_if_needed() {
  if command -v skopeo &>/dev/null; then
    return 0
  fi
  
  # Try dnf (Fedora/RHEL)
  if command -v dnf &>/dev/null; then
    dnf install -y skopeo &>/dev/null && return 0
  fi
  
  # Try apt (Debian/Ubuntu)
  if command -v apt-get &>/dev/null; then
    apt-get install -y skopeo &>/dev/null && return 0
  fi
  
  return 1
}

# List tags from registry using available tools
# Priority: local skopeo > remote skopeo on bootc > local crane
# Usage: list_tags "ghcr.io/namespace/image"
list_registry_tags() {
  local image="$1"
  
  # Try local skopeo first
  if command -v skopeo &>/dev/null; then
    skopeo list-tags "docker://${image}" 2>&1
    return $?
  fi
  
  # Try local crane
  if command -v crane &>/dev/null; then
    crane tags "${image}" 2>&1
    return $?
  fi
  
  # Try skopeo on bootc device
  if bootc_device_configured && bootc_ssh "command -v skopeo" &>/dev/null; then
    bootc_ssh "skopeo list-tags docker://${image}" 2>&1
    return $?
  fi
  
  echo '{"Tags":[]}' && return 1
}

# Get digest for a specific tag using available tools
# Usage: digest=$(get_tag_digest "ghcr.io/namespace/image:latest")
get_tag_digest() {
  local image_tag="$1"
  
  # Try local skopeo first
  if command -v skopeo &>/dev/null; then
    skopeo inspect "docker://${image_tag}" 2>/dev/null | jq -r '.Digest' || true
    return
  fi
  
  # Try skopeo on bootc device (it has both skopeo and jq)
  if bootc_device_configured && bootc_ssh "command -v skopeo" &>/dev/null; then
    bootc_ssh "skopeo inspect docker://${image_tag} 2>/dev/null | jq -r '.Digest'" || true
    return
  fi
  
  echo ""
}

# Create staged update on bootc device to enable rollback testing
# Usage: create_staged_update || skip "Could not create staged update"
ensure_staged_update() {
  if bootc_has_rollback; then
    # Already has rollback (staged update exists)
    return 0
  fi
  
  # Download and stage update without applying
  # This populates the staged field in bootc status
  bootc_ssh "bootc upgrade --download-only 2>&1" || {
    echo "Failed to stage update: $(bootc_ssh 'bootc upgrade --download-only 2>&1')"
    return 1
  }
  
  # Verify staged update was created
  sleep 2
  bootc_has_rollback
}

# Assert command succeeds
assert_success() {
  if [ $status -ne 0 ]; then
    echo "Expected success, got exit code $status"
    echo "Output: $output"
    return 1
  fi
}

# Assert command fails
assert_failure() {
  if [ $status -eq 0 ]; then
    echo "Expected failure, got success"
    echo "Output: $output"
    return 1
  fi
}

# Assert output contains string
assert_output_contains() {
  local expected="$1"
  # Use -- to prevent grep from interpreting options in the pattern
  if ! echo "$output" | grep -q -- "$expected"; then
    echo "Expected output to contain: $expected"
    echo "Actual output: $output"
    return 1
  fi
}

# Assert file exists
assert_file_exists() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Expected file to exist: $file"
    return 1
  fi
}

# Skip if tool not available
skip_if_tool_not_available() {
  local tool="$1"
  if ! command -v "$tool" &> /dev/null; then
    skip "$tool not installed"
  fi
}
