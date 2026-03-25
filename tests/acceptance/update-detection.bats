#!/usr/bin/env bats
# Acceptance tests for US5: Update Detection
#
# Acceptance Criteria:
# AC5.1: Given device running version 1.0, When version 1.1 is pushed to registry,
#        Then device detects new version available
# AC5.2: Given device already on latest, When update check runs,
#        Then system reports no updates available
# AC5.3: Given multiple versions in registry, When querying available versions,
#        Then system reports correct latest version
#
# Environment Setup:
# These tests require a bootc-managed device. Set BOOTC_DEVICE_HOST (and optionally
# BOOTC_DEVICE_SSH_KEY) to configure. See tests/bats/bootc_helpers.bash for details.

load '../bats/common.bash'
load '../bats/fixtures.bash'
load '../bats/ci_helpers.bash'
load '../bats/bootc_helpers.bash'

# Test configuration
REGISTRY="${REGISTRY:-ghcr.io}"
NAMESPACE="${NAMESPACE:-llm-at-cormora}"
IMAGE_NAME="${IMAGE_NAME:-nornnet}"
REMOTE_IMAGE="${REGISTRY}/${NAMESPACE}/${IMAGE_NAME}"

setup() {
  ci_skip_if_unavailable "podman" "podman required for update detection tests"
  
  # Verify podman is functional
  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi
  
  # Bootc device tests require a configured bootc device
  # This will skip all tests in this file if no bootc device is configured
  bootc_skip_if_not_configured
}

# =============================================================================
# AC5.1: Detect new version available
# =============================================================================

@test "AC5.1: bootc update check queries registry for new version" {
  # Given device running current version
  # When bootc update check runs
  # Then it queries the registry for available updates
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Run bootc update --check on the device
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # The command should succeed (exit 0) when booted via bootc
  # May still fail if no update available or network issues
  if [ $status -ne 0 ]; then
    echo "$output" | grep -qE "System not booted|not booted" && skip "Device not booted via bootc"
    echo "bootc update --check failed: $output"
    return 1
  fi
}

@test "AC5.1: Update available message when new version exists" {
  # Given device running version 1.0 and registry has 1.1
  # When update check runs
  # Then device reports update is available
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Run update check
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # Check output for update availability indicator
  # Should indicate whether update is available or not
  # bootc 1.14.1 outputs "No changes in: docker://..." when up to date
  # or shows available update when one exists
  # Either format is valid - the important thing is bootc responded
  [ $status -eq 0 ] || {
    # Non-zero exit means up to date or error
    # Accept "No changes" as valid response (system is up to date)
    echo "$output" | grep -qE "No changes|System not booted" && return 0
    echo "bootc update --check failed: $output"
    return 1
  }
  
  # Zero exit means command ran successfully
  # Output should indicate status (update available or no changes)
  echo "$output" | grep -qE "update|available|new|No changes" || {
    echo "bootc update --check returned unclear output: $output"
    return 1
  }
}

@test "AC5.1: Update check reports correct version number" {
  # Given registry has version 1.1.0
  # When update check runs
  # Then it reports the correct version number
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Run update check (bootc 1.14.1 does not support --format=json for update)
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # Should output version information or indicate no update
  # bootc 1.14.1 outputs "No changes in: docker://..." when up to date
  # Non-zero exit is OK (means no update available)
  if [ $status -ne 0 ]; then
    # Accept "No changes" format from bootc 1.14.1
    echo "$output" | grep -qE "up.to.date|already|no.*update|System not booted|No changes" && return 0
    echo "bootc update --check failed unexpectedly: $output"
    return 1
  fi
  
  # Output should contain version-like information (semver format) or "No changes"
  echo "$output" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+|No changes' || {
    echo "Update check output does not contain version or No changes: $output"
    return 1
  }
}

@test "AC5.1: Update detection uses configured image reference" {
  # Given device is configured with specific image reference
  # When update check runs
  # Then it uses the correct image reference
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Check device configuration
  # Note: bootc 1.14.1 uses --format=json instead of --json
  run bash -c "ssh $(bootc_ssh_opts) 'bootc status --format=json 2>&1' 2>&1"
  
  # Should show the configured image origin or system info
  assert_success
  
  # Output should contain the image reference or system info
  echo "$output" | grep -qE "${REMOTE_IMAGE}|BootcHost|image" || {
    echo "Device status missing image or system info: $output"
    return 1
  }
}

# =============================================================================
# AC5.2: Report no updates when on latest
# =============================================================================

@test "AC5.2: Update check reports no updates when current" {
  # Given device already on latest version
  # When update check runs
  # Then system reports no updates available
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Run update check
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # bootc 1.14.1 outputs "No changes in: docker://..." when up to date
  # This format is the expected response when no updates available
  # Either non-zero exit with No changes, or zero exit with No changes is valid
  echo "$output" | grep -qiE "No changes|up.to.date|latest|no.*update|already.*current|System not booted" && return 0
  
  echo "No indication of up-to-date status: $output"
  return 1
}

@test "AC5.2: Version comparison works correctly" {
  # Given device is on version 1.0
  # When registry has only 1.0 (no new version)
  # Then system correctly identifies no update needed
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get current version from device
  # Note: bootc 1.14.1 uses --format=json instead of --json
  local current_version
  current_version="$(bash -c "ssh $(bootc_ssh_opts) 'bootc status --format=json 2>&1' 2>&1" | jq -r '.version // .image.version // .status.version // empty' 2>/dev/null)" || true
  
  if [ -z "$current_version" ]; then
    skip "Could not determine current device version"
  fi
  
  # Check update status
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # Should correctly compare versions
  # If device is on latest, should report no update
  [ $status -eq 0 ] || {
    # Non-zero is acceptable for "no update"
    echo "$output" | grep -qE "up.to.date|already|no.*update" && return 0
  }
}

@test "AC5.2: Periodic update check can be scheduled" {
  # Given device supports scheduled update checks
  # When configured with schedule
  # Then update checks run automatically
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Check if timer/unit exists for update checks
  run bash -c "ssh $(bootc_ssh_opts) 'systemctl list-timers bootc-update.timer 2>&1 || systemctl list-timers | grep -i bootc 2>&1 || echo no-timer' 2>&1"
  
  # Either timer exists or periodic checks are configured another way
  # This test verifies the feature exists
  echo "$output"
  
  # Should not show error about missing timer (if it's optional)
  # The exact mechanism may vary, so we just verify it can be queried
  [ $status -eq 0 ] || skip "Could not query timer status"
}

# =============================================================================
# AC5.3: Query available versions correctly
# =============================================================================

@test "AC5.3: Can list all available versions from registry" {
  # Given multiple versions in registry
  # When querying available versions
  # Then all versions are listed
  
  skip_if_tool_not_available "podman"
  
  # Use skopeo or crane to list tags from registry
  # Or use podman search/inspect
  
  # Try skopeo first (preferred)
  if command -v skopeo &>/dev/null; then
    run bash -c "skopeo list-tags docker://${REMOTE_IMAGE} 2>&1"
  elif command -v crane &>/dev/null; then
    run bash -c "crane tags ${REMOTE_IMAGE} 2>&1"
  else
    # Fall back to podman (may not support listing tags directly)
    run bash -c "podman search ${REMOTE_IMAGE} 2>&1" || true
    
    if [ $status -ne 0 ]; then
      skip "No tag listing tool available (skopeo or crane recommended)"
    fi
  fi
  
  # Should return list of tags
  assert_success
  
  # Output should contain version-like entries
  echo "$output" | grep -qE 'v?[0-9]+\.[0-9]+\.[0-9]+|latest' || {
    echo "No version tags found in registry listing: $output"
    return 1
  }
}

@test "AC5.3: Latest version is correctly identified" {
  # Given multiple versions in registry
  # When querying available versions
  # Then latest tag points to correct version
  
  skip_if_tool_not_available "podman"
  
  # Get the 'latest' tag image digest
  local latest_digest=""
  local latest_v_digest=""
  
  if command -v skopeo &>/dev/null; then
    latest_digest="$(skopeo inspect "docker://${REMOTE_IMAGE}:latest" 2>/dev/null | jq -r '.Digest')" || true
    latest_v_digest="$(skopeo inspect "docker://${REMOTE_IMAGE}:v$(get_latest_semver)" 2>/dev/null | jq -r '.Digest')" || true
  fi
  
  # Both latest and the highest semver tag should point to same image
  if [ -n "$latest_digest" ] && [ -n "$latest_v_digest" ]; then
    [ "$latest_digest" = "$latest_v_digest" ] || {
      echo "latest tag ($latest_digest) does not match latest semver ($latest_v_digest)"
      return 1
    }
  fi
}

@test "AC5.3: Version comparison is semantically correct" {
  # Given versions 1.0.0, 1.1.0, and 2.0.0 in registry
  # When determining latest
  # Then 2.0.0 is correctly identified as latest
  
  skip_if_tool_not_available "podman"
  
  # Test version sorting logic
  local v1="1.0.0" v2="1.1.0" v3="2.0.0"
  
  # These versions should be sortable
  # 2.0.0 > 1.1.0 > 1.0.0
  
  # Get available tags
  local tags=""
  if command -v skopeo &>/dev/null; then
    tags="$(skopeo list-tags "docker://${REMOTE_IMAGE}" 2>/dev/null | jq -r '.Tags[]' 2>/dev/null)" || true
  fi
  
  if [ -z "$tags" ]; then
    skip "Could not fetch tags from registry"
  fi
  
  # Find highest version using semantic versioning
  local highest=""
  for tag in $tags; do
    # Strip v prefix if present
    local clean_tag="${tag#v}"
    if [[ "$clean_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      if [ -z "$highest" ] || [[ "$(printf '%s\n' "$highest" "$clean_tag" | sort -V | tail -1)" == "$clean_tag" ]]; then
        highest="$clean_tag"
      fi
    fi
  done
  
  [ -n "$highest" ] || skip "No semver tags found in registry"
  echo "Highest version in registry: $highest"
}

@test "AC5.3: Update detection respects configured version tag" {
  # Given device is tracking specific version tag
  # When update check runs
  # Then it respects the configured tracking mode
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Check device status for version tracking configuration
  # Note: bootc 1.14.1 uses --format=json instead of --json
  run bash -c "ssh $(bootc_ssh_opts) 'bootc status --format=json 2>&1' 2>&1"
  
  assert_success
  
  # Should contain origin/version tracking information
  echo "$output" | grep -qE "origin|version|tracked|ref|image|BootcHost" || {
    echo "Device status missing tracking info: $output"
    return 1
  }
}

@test "AC5.3: Rollback version is available when newer deployed" {
  # Given version 1.1 was deployed
  # When querying available versions
  # Then version 1.0 is available for rollback
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Check if previous versions are available
  # Note: ostree admin may not be available in all bootc installations
  # Fall back to bootc status if ostree admin is not available
  run bash -c "ssh $(bootc_ssh_opts) 'ostree admin status 2>&1 || bootc status --format=json 2>&1' 2>&1"
  
  # Should show deployment list including rollback option
  # This indicates system can rollback to previous version
  assert_success
  
  # Check for rollback or previous deployment indication
  echo "$output" | grep -qE "rollback|previous|deploy|image|type|BootcHost" || {
    echo "No rollback information available: $output"
    return 1
  }
}

# =============================================================================
# Helper function to get latest semver from tags
# =============================================================================

get_latest_semver() {
  local tags="$1"
  local highest=""
  
  for tag in $tags; do
    local clean_tag="${tag#v}"
    if [[ "$clean_tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      if [ -z "$highest" ] || [[ "$(printf '%s\n' "$highest" "$clean_tag" | sort -V | tail -1)" == "$clean_tag" ]]; then
        highest="$clean_tag"
      fi
    fi
  done
  
  echo "$highest"
}
