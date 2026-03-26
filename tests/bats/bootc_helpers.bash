# Bootc Device Testing Helpers
#
# This module provides utilities for testing bootc-managed devices.
#
# Environment Variables Required for Bootc Device Testing:
# -------------------------------------------------
#
# BOOTC_DEVICE_HOST (required for dedicated bootc testing)
#   - IP address or hostname of a device booted via bootc
#   - This is separate from HETZNER_SERVER_IP to allow testing
#     against a dedicated bootc device
#
# BOOTC_DEVICE_SSH_KEY (optional, defaults to DEVICE_SSH_KEY)
#   - SSH private key for authenticating to bootc device
#   - If not set, will use DEVICE_SSH_KEY
#
# BOOTC_SKIP_MESSAGE (optional)
#   - Custom skip message explaining how to configure bootc device
#   - If not set, a default message is used
#
# Legacy/Alternative Variables (for Hetzner server as bootc device):
# -------------------------------------------------
#
# DEVICE_HOST (alternative to BOOTC_DEVICE_HOST)
#   - Can be used if HETZNER_SERVER_IP is not set
#
# HETZNER_SERVER_IP (alternative to BOOTC_DEVICE_HOST)
#   - The existing Hetzner server IP
#   - Only works if that server is booted via bootc
#
# DEVICE_SSH_KEY (fallback for BOOTC_DEVICE_SSH_KEY)
#   - SSH private key for device authentication
#
# Example Usage:
# -------------------------------------------------
#
# In your CI environment or local shell:
#
#   export BOOTC_DEVICE_HOST=192.168.1.100
#   export BOOTC_DEVICE_SSH_KEY=~/.ssh/bootc_ed25519
#   bats tests/acceptance/device-deployment.bats
#
# Or with Hetzner server (if booted via bootc):
#
#   export HETZNER_SERVER_IP=192.168.1.50
#   export DEVICE_SSH_KEY=~/.ssh/hetzner_ed25519
#   bats tests/acceptance/device-deployment.bats
#
# =============================================================================

# Get the bootc device host IP
# Priority: BOOTC_DEVICE_HOST > DEVICE_HOST > HETZNER_SERVER_IP
bootc_device_host() {
  echo "${BOOTC_DEVICE_HOST:-${DEVICE_HOST:-${HETZNER_SERVER_IP:-}}}"
}

# Get the bootc device SSH key
# Priority: BOOTC_DEVICE_SSH_KEY > DEVICE_SSH_KEY
bootc_device_ssh_key() {
  echo "${BOOTC_DEVICE_SSH_KEY:-${DEVICE_SSH_KEY:-}}"
}

# Get the full SSH connection string (user@host with key)
bootc_ssh_opts() {
  local host
  local key
  local opts="-o BatchMode=yes -o StrictHostKeyChecking=no"
  
  host="$(bootc_device_host)"
  key="$(bootc_device_ssh_key)"
  
  if [ -n "$key" ]; then
    opts="$opts -i $key"
  fi
  
  echo "$opts root@$host"
}

# SSH to bootc device (convenience wrapper)
bootc_ssh() {
  local cmd="${1:-echo test}"
  ssh $(bootc_ssh_opts) "$cmd" 2>&1
}

# Check if a bootc device is configured
# Returns 0 (success) if configured, 1 if not configured
bootc_device_configured() {
  [ -n "$(bootc_device_host)" ]
}

# Check if bootc is available on the device
# Returns 0 if bootc is available, 1 if not
bootc_available_on_device() {
  local output
  output="$(bootc_ssh "bootc --version" 2>&1)" || return 1
  echo "$output" | grep -q "bootc"
}

# Check if device is booted via bootc (not just has bootc installed)
# Returns 0 if booted via bootc, 1 if not
bootc_is_bootc_system() {
  local output
  output="$(bootc_ssh "bootc status --format=json" 2>&1)" || return 1
  # If "System not booted via bootc" appears, it's not a bootc system
  echo "$output" | grep -q "System not booted via bootc" && return 1
  return 0
}

# Get bootc status JSON from device
# Outputs the status JSON or empty string on error
bootc_status() {
  bootc_ssh "bootc status --format=json" 2>&1
}

# Default skip message for when bootc device is not configured
BOOTC_SKIP_NOT_CONFIGURED="${BOOTC_SKIP_MESSAGE:-Bootc device not configured. Set BOOTC_DEVICE_HOST (and optionally BOOTC_DEVICE_SSH_KEY) to run these tests. See tests/bats/bootc_helpers.bash for documentation.}"

# Default skip message for when device exists but is not booted via bootc
BOOTC_SKIP_NOT_BOOTC="${BOOTC_SKIP_MESSAGE:-Device is not booted via bootc. These tests require a system booted via bootc (bootc-installed system).}"

# Skip test if no bootc device is configured
# Use this at the start of setup() for tests requiring a bootc device
bootc_skip_if_not_configured() {
  if ! bootc_device_configured; then
    skip "$BOOTC_SKIP_NOT_CONFIGURED"
  fi
}

# Skip test if device is not booted via bootc
# Use this in individual tests after verifying device connectivity
bootc_skip_if_not_bootc_system() {
  if ! bootc_is_bootc_system; then
    skip "$BOOTC_SKIP_NOT_BOOTC"
  fi
}

# Combined check: skip if no device OR not booted via bootc
# Use this for tests that need a fully configured bootc device
bootc_skip_if_unavailable() {
  bootc_skip_if_not_configured
  bootc_skip_if_not_bootc_system
}

# Run a bootc command on the device and capture output
# Usage: run bootc_cmd "bootc switch ${image}"
bootc_cmd() {
  local cmd="${1:-}"
  if [ -z "$cmd" ]; then
    echo "bootc_cmd: no command specified" >&2
    return 1
  fi
  bootc_ssh "$cmd"
}

# Get the current booted image from bootc status
# Outputs the image reference or empty string
bootc_current_image() {
  local status
  status="$(bootc_status)" || return 1
  echo "$status" | jq -r '.image.id // .image // empty' 2>/dev/null
}

# Get the version from bootc status
# Outputs the version string or empty string
bootc_current_version() {
  local status
  status="$(bootc_status)" || return 1
  echo "$status" | jq -r '.version // .image.version // empty' 2>/dev/null
}

# Check if a rollback/staged image is available
# Returns 0 if rollback is available, 1 if not
# Handles both older bootc format (.rollback, .staged) and bootc 1.14.1 format (.status.rollback, .status.staged)
# Uses grep-based parsing for JSON since jq may not be available on build server
bootc_has_rollback() {
  local status
  status="$(bootc_status)" || return 1
  
  # Check for non-null rollback or staged fields using grep
  # Look for patterns like "rollback":{ or "staged":{ (object, not null)
  # In bootc 1.14.1, the format is "rollback":null or "rollback":{"image":...
  # We need to detect when rollback/staged is NOT null (has an object value)
  
  # For legacy format: look for "rollback":{ at start of value
  if echo "$status" | grep -qE '"rollback":\s*\{'; then
    return 0
  fi
  # For legacy format: look for "staged":{ at start of value
  if echo "$status" | grep -qE '"staged":\s*\{'; then
    return 0
  fi
  # For bootc 1.14.1 format: look for "rollback":{ and "staged":{ in status object
  if echo "$status" | grep -qE '"status":\s*\{[^}]*"rollback":\s*\{"'; then
    return 0
  fi
  if echo "$status" | grep -qE '"status":\s*\{[^}]*"staged":\s*\{"'; then
    return 0
  fi
  return 1
}

# Skip test if no rollback is available on the device
# Use this for tests that require rollback capability
bootc_skip_if_no_rollback() {
  if ! bootc_has_rollback; then
    skip "No rollback available on device (rollback and staged are null). Rollback requires having a previous deployment to roll back to."
  fi
}

# Get the version from bootc status using grep-based parsing
# Outputs the version string or empty string
bootc_get_version() {
  local status
  status="$(bootc_status)" || return 1
  # bootc 1.14.1: version is in status.booted.image.version
  echo "$status" | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/.*"version":[[:space:]]*"//;s/"$//' || true
}

# Check if a tag lister tool is available (skopeo, crane, or podman)
# Returns 0 if available, 1 if not
has_tag_lister() {
  command -v skopeo &>/dev/null && return 0
  command -v crane &>/dev/null && return 0
  # Check on bootc device
  bootc_ssh "command -v skopeo" &>/dev/null && return 0
  return 1
}

# Install skopeo on the build server if needed
# Returns 0 if skopeo is now available, 1 if installation failed
install_skopeo_if_needed() {
  if command -v skopeo &>/dev/null; then
    return 0
  fi
  
  # Try to install skopeo
  if command -v dnf &>/dev/null; then
    dnf install -y skopeo &>/dev/null && return 0
  elif command -v apt-get &>/dev/null; then
    apt-get install -y skopeo &>/dev/null && return 0
  fi
  
  # Check if it became available
  command -v skopeo &>/dev/null && return 0
  return 1
}

# List tags from a container registry
# Uses skopeo on bootc device (which has it) with GHCR auth
# Arguments: registry/image (e.g., ghcr.io/llm-at-cormora/nornnet)
# Outputs JSON array of tags or empty on failure
list_registry_tags() {
  local image="${1:-}"
  if [ -z "$image" ]; then
    echo "list_registry_tags: no image specified" >&2
    return 1
  fi
  
  # Try skopeo on bootc device with auth file
  if bootc_device_configured; then
    # Use podman auth file on bootc device for skopeo
    local authfile="/var/lib/containers/auth.json"
    bootc_ssh "test -f $authfile" &>/dev/null || authfile="$HOME/.config/containers/auth.json"
    
    local output
    output="$(bootc_ssh "skopeo list-tags --authfile $authfile docker://${image}" 2>&1)" || return 1
    echo "$output"
    return 0
  fi
  
  # Try local skopeo with auth file
  local authfile="${XDG_RUNTIME_DIR:-/tmp}/containers/auth.json"
  if [ -f "$authfile" ]; then
    skopeo list-tags --authfile "$authfile" "docker://${image}" 2>&1 && return 0
  fi
  
  # Try skopeo without auth (public repos)
  skopeo list-tags "docker://${image}" 2>&1 && return 0
  
  return 1
}

# Get digest of a specific tag from registry
# Arguments: registry/image:tag
# Outputs digest string or empty on failure
get_tag_digest() {
  local ref="${1:-}"
  if [ -z "$ref" ]; then
    echo "get_tag_digest: no image reference specified" >&2
    return 1
  fi
  
  # Try on bootc device first
  if bootc_device_configured; then
    local authfile="/var/lib/containers/auth.json"
    bootc_ssh "test -f $authfile" &>/dev/null || authfile="$HOME/.config/containers/auth.json"
    
    local output
    output="$(bootc_ssh "skopeo inspect --authfile $authfile docker://${ref}" 2>&1 | grep -oE 'sha256:[a-f0-9]+' | head -1)" || return 1
    echo "$output"
    return 0
  fi
  
  # Try local skopeo
  local authfile="${XDG_RUNTIME_DIR:-/tmp}/containers/auth.json"
  if [ -f "$authfile" ]; then
    skopeo inspect --authfile "$authfile" "docker://${ref}" 2>&1 | grep -oE 'sha256:[a-f0-9]+' | head -1 && return 0
  fi
  
  skopeo inspect "docker://${ref}" 2>&1 | grep -oE 'sha256:[a-f0-9]+' | head -1 && return 0
  return 1
}

# Ensure a staged update exists on the device for rollback testing
# This creates a staged update by switching to a different image
# Returns 0 if staged update is now available, 1 otherwise
ensure_staged_update() {
  local target_image="${1:-}"
  
  if bootc_has_rollback; then
    return 0
  fi
  
  # If no target image specified, use a different test image
  if [ -z "$target_image" ]; then
    target_image="ghcr.io/llm-at-cormora/nornnet-test:latest"
  fi
  
  # Check if bootc device is configured
  bootc_device_configured || return 1
  
  # Check if image is already available in containers-storage
  if bootc_ssh "podman images -q ${target_image}" &>/dev/null; then
    # Image is available locally, switch to it with containers-storage transport
    bootc_ssh "bootc switch --transport containers-storage ${target_image}" &>/dev/null && return 0
  fi
  
  # Try pulling the image first
  bootc_ssh "podman pull ${target_image}" &>/dev/null || return 1
  
  # Now switch
  bootc_ssh "bootc switch --transport containers-storage ${target_image}" &>/dev/null && return 0
  
  return 1
}

# Export functions for use in bats tests
export -f bootc_device_host
export -f bootc_device_ssh_key
export -f bootc_ssh_opts
export -f bootc_ssh
export -f bootc_device_configured
export -f bootc_available_on_device
export -f bootc_is_bootc_system
export -f bootc_status
export -f bootc_skip_if_not_configured
export -f bootc_skip_if_not_bootc_system
export -f bootc_skip_if_unavailable
export -f bootc_cmd
export -f bootc_current_image
export -f bootc_current_version
export -f bootc_has_rollback
export -f bootc_skip_if_no_rollback
export -f bootc_get_version
export -f has_tag_lister
export -f install_skopeo_if_needed
export -f list_registry_tags
export -f get_tag_digest
export -f ensure_staged_update
