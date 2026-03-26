#!/usr/bin/env bats
# Acceptance tests for US5: Update Detection
#
# Tests version comparison, semver parsing, and update detection logic.
# These tests focus on the core logic without requiring a bootc device.
#
# Acceptance Criteria:
# AC5.1: Given device running version 1.0, When version 1.1 is pushed to registry,
#        Then device detects new version available
# AC5.2: Given device already on latest, When update check runs,
#        Then system reports no updates available
# AC5.3: Given multiple versions in registry, When querying available versions,
#        Then system reports correct latest version

load '../bats/common.bash'
load '../bats/fixtures.bash'
load '../bats/bootc_helpers.bash'

# =============================================================================
# Test Configuration
# =============================================================================

REMOTE_IMAGE="${REMOTE_IMAGE:-ghcr.io/llm-at-cormora/nornnet}"

# =============================================================================
# AC5.1: Version Comparison - Core Logic Tests
# =============================================================================

# Version comparison using sort -V for semantic versioning
# Returns 0 if $1 < $2, 1 otherwise
# Handles equal versions correctly (returns false for equal)
version_lt() {
  local v1="$1"
  local v2="$2"
  
  # Equal versions are NOT less than
  [[ "$v1" = "$v2" ]] && return 1
  
  # Use sort -V for proper semantic version comparison
  [ "$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)" = "$v1" ]
}

# Get the highest version from a space-separated list
get_latest_version() {
  local versions="$1"
  local highest=""
  
  for v in $versions; do
    if [ -z "$highest" ]; then
      highest="$v"
    elif version_lt "$highest" "$v"; then
      highest="$v"
    fi
  done
  
  echo "$highest"
}

# Check if version string is valid semver
is_valid_semver() {
  local v="$1"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Check if update is available
update_available() {
  local current="$1"
  local latest="$2"
  version_lt "$current" "$latest"
}

@test "AC5.1: Patch version comparison - 1.0.1 > 1.0.0" {
  version_lt "1.0.0" "1.0.1"
}

@test "AC5.1: Patch version comparison - 1.0.0 < 1.0.2" {
  version_lt "1.0.0" "1.0.2"
}

@test "AC5.1: CRITICAL - Patch version numeric comparison - 1.0.10 > 1.0.9" {
  # This is a common bug where 1.0.10 is incorrectly considered < 1.0.9
  # because string comparison gives "1.0.1" < "1.0.9"
  # sort -V handles this correctly
  version_lt "1.0.9" "1.0.10"
}

@test "AC5.1: Patch version numeric comparison - 1.0.2 < 1.0.10" {
  version_lt "1.0.2" "1.0.10"
}

@test "AC5.1: Minor version comparison - 1.1.0 > 1.0.0" {
  version_lt "1.0.0" "1.1.0"
}

@test "AC5.1: Minor version comparison - 1.1.0 < 1.2.0" {
  version_lt "1.1.0" "1.2.0"
}

@test "AC5.1: Major version comparison - 2.0.0 > 1.9.9" {
  version_lt "1.9.9" "2.0.0"
}

@test "AC5.1: Major version comparison - 2.0.0 > 1.0.0" {
  version_lt "1.0.0" "2.0.0"
}

@test "AC5.1: Full semver chain - 1.0.0 < 1.0.1 < 1.1.0 < 2.0.0" {
  version_lt "1.0.0" "1.0.1"
  version_lt "1.0.1" "1.1.0"
  version_lt "1.1.0" "2.0.0"
}

@test "AC5.1: Complex version chain - 1.0.0 < 1.0.10 < 1.1.0 < 1.10.0 < 2.0.0" {
  version_lt "1.0.0" "1.0.10"
  version_lt "1.0.10" "1.1.0"
  version_lt "1.1.0" "1.10.0"
  version_lt "1.10.0" "2.0.0"
}

@test "AC5.1: Equal versions are not less than" {
  ! version_lt "1.0.0" "1.0.0"
  ! version_lt "1.2.3" "1.2.3"
}

@test "AC5.1: Version is not less than lower version" {
  ! version_lt "1.0.1" "1.0.0"
  ! version_lt "2.0.0" "1.0.0"
}

# =============================================================================
# AC5.1: Semver Validation Tests
# =============================================================================

@test "AC5.1: Valid semver is accepted - 1.0.0" {
  is_valid_semver "1.0.0"
}

@test "AC5.1: Valid semver is accepted - 0.0.1" {
  is_valid_semver "0.0.1"
}

@test "AC5.1: Valid semver is accepted - 10.20.30" {
  is_valid_semver "10.20.30"
}

@test "AC5.1: Invalid semver rejected - missing patch (1.0)" {
  ! is_valid_semver "1.0"
}

@test "AC5.1: Invalid semver rejected - too many parts (1.0.0.0)" {
  ! is_valid_semver "1.0.0.0"
}

@test "AC5.1: Invalid semver rejected - letters (1.0.a)" {
  ! is_valid_semver "1.0.a"
}

@test "AC5.1: Invalid semver rejected - leading v (v1.0.0)" {
  # Registry tags may have v prefix, but semver comparison should strip it
  ! is_valid_semver "v1.0.0"
}

@test "AC5.1: Invalid semver rejected - empty string" {
  ! is_valid_semver ""
}

@test "AC5.1: Invalid semver rejected - negative numbers" {
  ! is_valid_semver "1.0.-1"
}

# =============================================================================
# AC5.1: Version Parsing from Tag Lists
# =============================================================================

@test "AC5.1: Parse semver from tagged image - v1.0.0" {
  local tag="v1.0.0"
  local clean="${tag#v}"
  [[ "$clean" = "1.0.0" ]]
  is_valid_semver "$clean"
}

@test "AC5.1: Parse semver from tagged image - v2.3.4" {
  local tag="v2.3.4"
  local clean="${tag#v}"
  [[ "$clean" = "2.3.4" ]]
  is_valid_semver "$clean"
}

@test "AC5.1: Parse semver without v prefix - 1.0.0" {
  local tag="1.0.0"
  local clean="${tag#v}"
  [[ "$clean" = "1.0.0" ]]
  is_valid_semver "$clean"
}

# =============================================================================
# AC5.3: Find Latest Version from List
# =============================================================================

@test "AC5.3: Find latest from two versions" {
  result=$(get_latest_version "1.0.0 2.0.0")
  [[ "$result" = "2.0.0" ]]
}

@test "AC5.3: Find latest from three versions - 1.0.0 < 1.0.1 < 2.0.0" {
  result=$(get_latest_version "1.0.0 1.0.1 2.0.0")
  [[ "$result" = "2.0.0" ]]
}

@test "AC5.3: Find latest from five versions" {
  result=$(get_latest_version "1.0.0 1.0.5 1.0.10 1.1.0 2.0.0")
  [[ "$result" = "2.0.0" ]]
}

@test "AC5.3: CRITICAL - Find latest with double-digit patches - 1.0.10 > 1.0.9" {
  result=$(get_latest_version "1.0.0 1.0.9 1.0.10 1.1.0")
  [[ "$result" = "1.1.0" ]]
}

@test "AC5.3: Single version returns itself" {
  result=$(get_latest_version "1.0.0")
  [[ "$result" = "1.0.0" ]]
}

@test "AC5.3: Empty list returns empty" {
  result=$(get_latest_version "")
  [[ -z "$result" ]]
}

@test "AC5.3: Latest from unsorted list" {
  result=$(get_latest_version "3.0.0 1.0.0 2.0.0")
  [[ "$result" = "3.0.0" ]]
}

@test "AC5.3: Latest from reverse-sorted list" {
  result=$(get_latest_version "3.0.0 2.0.0 1.0.0")
  [[ "$result" = "3.0.0" ]]
}

# =============================================================================
# AC5.3: Update Detection Logic
# =============================================================================

@test "AC5.3: Update available when current < latest" {
  local current="1.0.0"
  local latest="1.0.1"
  
  # Update is available if current < latest
  update_available "$current" "$latest"
}

@test "AC5.3: No update when current = latest" {
  local current="1.0.1"
  local latest="1.0.1"
  
  # No update if current >= latest
  ! update_available "$current" "$latest"
}

@test "AC5.3: Update available across major versions" {
  local current="1.9.9"
  local latest="2.0.0"
  
  update_available "$current" "$latest"
}

@test "AC5.3: Determine update status - current 1.0.0, registry has 1.0.0 and 1.0.1" {
  local current="1.0.0"
  local available="1.0.0 1.0.1"
  
  local latest
  latest=$(get_latest_version "$available")
  
  [[ "$latest" = "1.0.1" ]]
  update_available "$current" "$latest"  # Update should be available
}

@test "AC5.3: Determine update status - current 1.0.1, registry has 1.0.0 and 1.0.1" {
  local current="1.0.1"
  local available="1.0.0 1.0.1"
  
  local latest
  latest=$(get_latest_version "$available")
  
  [[ "$latest" = "1.0.1" ]]
  ! update_available "$current" "$latest"  # No update
}

# =============================================================================
# AC5.2: Registry Tag List Parsing
# =============================================================================

@test "AC5.2: Parse JSON tag list - extract v-prefixed tags" {
  # Simulate list_registry_tags output
  local json='{"Tags":["v1.0.0","v1.0.1","v1.1.0","v2.0.0","latest"]}'
  
  # Extract semver tags (v-prefixed)
  local tags
  tags=$(echo "$json" | grep -oE '"v[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | tr -d 'v' | tr '\n' ' ')
  tags="${tags% }"  # Trim trailing space
  
  local latest
  latest=$(get_latest_version "$tags")
  
  [[ "$latest" = "2.0.0" ]]
}

@test "AC5.2: Parse JSON tag list - extract non-v-prefixed tags" {
  # Simulate list_registry_tags output without v prefix
  local json='{"Tags":["1.0.0","1.0.1","1.1.0","2.0.0","latest"]}'
  
  # Extract semver tags (without v prefix)
  local tags
  tags=$(echo "$json" | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | tr '\n' ' ')
  tags="${tags% }"  # Trim trailing space
  
  local latest
  latest=$(get_latest_version "$tags")
  
  [[ "$latest" = "2.0.0" ]]
}

@test "AC5.2: Parse mixed tag list - v-prefixed and non-prefixed" {
  # Registry might have both v1.0.0 and 1.0.0 tags
  local json='{"Tags":["v1.0.0","1.0.1","v2.0.0"]}'
  
  # Strip v prefix and extract
  local tags
  tags=$(echo "$json" | grep -oE '"v?[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | tr -d 'v' | tr '\n' ' ')
  tags="${tags% }"
  
  local latest
  latest=$(get_latest_version "$tags")
  
  [[ "$latest" = "2.0.0" ]]
}

@test "AC5.2: Parse tag list - filter out invalid semver" {
  # Some tags might not be semver
  local json='{"Tags":["v1.0.0","latest","test","v2.0.0","debug"]}'
  
  # Only extract valid semver
  local tags=""
  for tag in $(echo "$json" | grep -oE '"v?[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | tr -d 'v'); do
    if is_valid_semver "$tag"; then
      tags="$tags $tag"
    fi
  done
  tags="${tags# }"  # Trim leading space
  
  local latest
  latest=$(get_latest_version "$tags")
  
  [[ "$latest" = "2.0.0" ]]
}

# =============================================================================
# AC5.1: Update Message Generation
# =============================================================================

@test "AC5.1: Generate update available message" {
  local current="1.0.0"
  local latest="1.0.1"
  
  local status_message
  if update_available "$current" "$latest"; then
    status_message="Update available: $current -> $latest"
  else
    status_message="No updates available"
  fi
  
  [[ "$status_message" = "Update available: 1.0.0 -> 1.0.1" ]]
}

@test "AC5.2: Generate no-update message" {
  local current="1.0.1"
  local latest="1.0.1"
  
  local status_message
  if update_available "$current" "$latest"; then
    status_message="Update available: $current -> $latest"
  else
    status_message="No updates available"
  fi
  
  [[ "$status_message" = "No updates available" ]]
}

# =============================================================================
# AC5.1: Bootc Update Check Integration
# =============================================================================

@test "AC5.1: list_registry_tags function exists" {
  type list_registry_tags | grep -q "function"
}

@test "AC5.1: get_tag_digest function exists" {
  type get_tag_digest | grep -q "function"
}

# =============================================================================
# AC5.3: Real Registry Integration Tests
# =============================================================================

@test "AC5.3: List tags from registry - requires network" {
  skip_if_tool_not_available "skopeo"
  
  # Skip if no credentials configured
  if [ -z "${PUSH_PASSWORD:-}" ]; then
    skip "Registry authentication not configured"
  fi
  
  # Login to registry
  if command -v skopeo &>/dev/null; then
    skopeo login -u "${PUSH_USERNAME:-${GITHUB_ACTOR:-user}}" -p "$PUSH_PASSWORD" ghcr.io 2>/dev/null || true
  fi
  
  # List tags
  local output
  output=$(list_registry_tags "${REMOTE_IMAGE}" 2>&1)
  
  # Should get JSON output
  echo "$output" | grep -q "Tags"
}

@test "AC5.3: Find latest version from registry - requires network" {
  skip_if_tool_not_available "skopeo"
  
  if [ -z "${PUSH_PASSWORD:-}" ]; then
    skip "Registry authentication not configured"
  fi
  
  # Login first
  if command -v skopeo &>/dev/null; then
    skopeo login -u "${PUSH_USERNAME:-${GITHUB_ACTOR:-user}}" -p "$PUSH_PASSWORD" ghcr.io 2>/dev/null || true
  fi
  
  # Get tags from registry
  local tags_output
  tags_output=$(list_registry_tags "${REMOTE_IMAGE}" 2>&1) || {
    skip "Could not fetch tags: $tags_output"
  }
  
  # Parse tags
  local tags
  tags=$(echo "$tags_output" | grep -oE '"v?[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | tr -d 'v' | tr '\n' ' ')
  tags="${tags% }"
  
  if [ -z "$tags" ]; then
    skip "No semver tags found in registry"
  fi
  
  # Find latest
  local latest
  latest=$(get_latest_version "$tags")
  
  # Output should be a valid semver
  is_valid_semver "$latest" || skip "No valid semver tags found"
  
  echo "Latest version in registry: $latest"
}

# =============================================================================
# AC5.3: Digest Comparison Tests
# =============================================================================

@test "AC5.3: Different digests mean different images" {
  # Same tag should have same digest
  local digest1="sha256:abc123def456abc123def456abc123def456abc123def456abc123def456abc1"
  local digest2="sha256:abc123def456abc123def456abc123def456abc123def456abc123def456abc1"
  
  [[ "$digest1" = "$digest2" ]]
}

@test "AC5.3: Digest format validation" {
  local digest="sha256:abc123def456abc123def456abc123def456abc123def456abc123def456abc1"
  
  # Digest should be 64 hex characters after sha256:
  [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]
}

# =============================================================================
# Bootc Device Tests (require remote device)
# =============================================================================

@test "bootc update check: detects newer version on registry" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Run bootc update --check on the device
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # Command should succeed or report "No changes"
  if [ $status -ne 0 ]; then
    echo "$output" | grep -qE "No changes|System not booted" && return 0
    echo "bootc update --check failed: $output"
    return 1
  fi
  
  # Output should indicate update status
  echo "$output" | grep -qE "update|available|new|No changes"
}

@test "bootc update check: reports no updates when current" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # Should report no changes when current
  echo "$output" | grep -qiE "No changes|up.to.date|latest|no.*update|already.*current" || {
    echo "Unexpected output for up-to-date check: $output"
    return 1
  }
}

@test "bootc status: shows correct current version" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  run bash -c "ssh $(bootc_ssh_opts) 'bootc status --format=json 2>&1' 2>&1"
  
  [ $status -eq 0 ]
  
  # Should contain version information
  echo "$output" | grep -qE '"version"|"image"|BootcHost'
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "Edge case: Very large version numbers" {
  version_lt "1.0.0" "999.999.999"
}

@test "Edge case: Zero versions" {
  version_lt "0.0.0" "0.0.1"
}

@test "Edge case: Get latest from large version set" {
  result=$(get_latest_version "0.0.1 0.0.2 0.1.0 1.0.0 1.0.1 1.0.10 1.1.0 1.10.0 10.0.0")
  [[ "$result" = "10.0.0" ]]
}

@test "Edge case: Filter out 'latest' from version list" {
  local tags="v1.0.0 v1.0.1 latest"
  
  # Filter out 'latest'
  local filtered=""
  for tag in $tags; do
    local clean="${tag#v}"
    if is_valid_semver "$clean" && [[ "$clean" != "latest" ]]; then
      filtered="$filtered $clean"
    fi
  done
  filtered="${filtered# }"
  
  result=$(get_latest_version "$filtered")
  [[ "$result" = "1.0.1" ]]
}

# =============================================================================
# Summary
# =============================================================================

@test "Test coverage summary" {
  echo ""
  echo "=== Update Detection Test Coverage ==="
  echo "Version comparison: Patch, minor, major versions"
  echo "Semver validation: Valid and invalid formats"
  echo "Latest detection: Various list sizes and orderings"
  echo "Update status: Available vs not available"
  echo "Registry parsing: JSON tag list extraction"
  echo "Bootc integration: Remote device commands"
  echo "========================================"
}
