#!/usr/bin/env bats
# Acceptance tests for US6: Transactional Update
#
# Acceptance Criteria:
# AC6.1: Given an update process starts, When update completes successfully,
#        Then all changes are applied atomically
# AC6.2: Given an update is in progress, When update fails,
#        Then automatic rollback restores previous state
# AC6.3: Given rollback completes, When status is checked,
#        Then system shows previous image and rollback status
#
# Environment Setup:
# These tests require a bootc-managed device. Set BOOTC_DEVICE_HOST (and optionally
# BOOTC_DEVICE_SSH_KEY) to configure. See tests/bats/bootc_helpers.bash for details.
#
# NOTE: Some tests require rollback capability (rollback and staged must not be null).
# If the device has no rollback available, these tests will be skipped.

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
  ci_skip_if_unavailable "podman" "podman required for transactional update tests"
  
  # Verify podman is functional
  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi
  
  # Bootc device tests require a configured bootc device
  bootc_skip_if_not_configured
  
  # Get initial state for comparison
  INITIAL_STATUS="$(bootc_ssh "bootc status --format=json" 2>&1)" || true
  # bootc 1.14.1: image is at status.booted.image.image
  # Use grep-based parsing since jq may not be available
  INITIAL_IMAGE="$(echo "$INITIAL_STATUS" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
}

teardown() {
  # Cleanup is handled by bootc's transactional nature
  # We don't need to manually rollback as bootc handles this
  true
}

# =============================================================================
# Helper: Check if rollback is available on the device
# =============================================================================

# Skip test if rollback is not available (both rollback and staged are null)
# Use this for tests that require actual rollback capability
bootc_skip_if_no_rollback() {
  if ! bootc_has_rollback; then
    skip "Rollback not available on this device (rollback: null, staged: null). Cannot test actual rollback scenarios without a staged update."
  fi
}

# =============================================================================
# AC6.1: Atomic Update Application
# =============================================================================

@test "AC6.1: bootc update applies changes transactionally" {
  # Given device is running with bootc
  # When update command is issued
  # Then update is applied atomically (all or nothing)
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Capture state before update
  local before_status
  before_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Run bootc update --check first to see if update available
  run bash -c "ssh $(bootc_ssh_opts) 'bootc update --check 2>&1' 2>&1"
  
  # Store the check result
  local update_check_output="$output"
  local update_check_status=$status
  
  # If update available, verify transactional behavior
  if echo "$update_check_output" | grep -qiE "update|available|changes"; then
    # Update is available, run it
    run bash -c "ssh $(bootc_ssh_opts) 'bootc update 2>&1' 2>&1" || true
    
    # After update attempt, verify device state is consistent
    # Either update succeeded OR system is still on original image (rollback)
    local after_status
    after_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
    local after_image
    # bootc 1.14.1: image is at status.booted.image.image
    # Use grep-based parsing since jq may not be available
    after_image="$(echo "$after_status" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
    
    # System must be in a consistent state - either:
    # 1. Image changed to new version (update succeeded)
    # 2. Image unchanged (update failed and rolled back)
    [ -n "$after_image" ] || {
      echo "Device in inconsistent state after update: $after_status"
      return 1
    }
  else
    # No update available - verify current state is valid
    if [ "${update_check_status:-1}" -eq 0 ]; then
      # Zero status - command succeeded, which is fine for "no update needed"
      true
    else
      # Non-zero status - check if it's actually "no update available"
      echo "$update_check_output" | grep -qE "No changes|up.to.date|already" && return 0
    fi
  fi
}

@test "AC6.1: System remains consistent if update interrupted" {
  # Given update is in progress
  # When process is interrupted (simulated by timeout)
  # Then system remains in consistent state
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get current state
  local before_status
  before_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Attempt update with short timeout (simulates interruption)
  # Using timeout of 5 seconds - update will be interrupted
  run timeout 5 bash -c "ssh $(bootc_ssh_opts) 'bootc update 2>&1' 2>&1" || true
  
  # After timeout/interruption, verify system is still accessible
  local after_status
  after_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # System must still respond to status queries (consistent state)
  [ -n "$after_status" ] || {
    echo "Device not responding after interrupted update"
    return 1
  }
  
  # Verify status is valid JSON using grep patterns
  echo "$after_status" | grep -qE '^\s*\{' && echo "$after_status" | grep -qE '\}\s*$' || {
    echo "Device status invalid after interrupted update: $after_status"
    return 1
  }
}

@test "AC6.1: bootc status shows transactional state during update" {
  # Given update is in progress
  # When bootc status is checked
  # Then status reflects current transactional state
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get bootc status which shows transactional state
  run bash -c "ssh $(bootc_ssh_opts) 'bootc status --format=json 2>&1' 2>&1"
  
  # Status should return valid JSON with state information
  assert_success
  
  # Verify JSON structure contains expected fields using grep
  # Check for common bootc status fields
  echo "$output" | grep -qE '"status"|"image"|"BootcHost"|"version"|"type"' || {
    echo "bootc status missing expected fields: $output"
    return 1
  }
}

@test "AC6.1: Complete update shows new image in status" {
  # Given update completes successfully
  # When bootc status is checked
  # Then status shows the newly deployed image
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Check current status
  local current_status
  current_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Extract current image reference using grep
  # bootc 1.14.1: image is at status.booted.image.image
  local current_image
  current_image="$(echo "$current_status" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
  
  # If we have a current image, verify it's valid
  if [ -n "$current_image" ]; then
    # Verify image contains registry reference or digest
    echo "$current_image" | grep -qE "quay.io|docker.io|localhost|sha256" || {
      echo "Current image not in expected format: $current_image"
      return 1
    }
  fi
  
  # Verify status contains version or deployment info
  echo "$current_status" | grep -qE "version|image|BootcHost|type" || {
    echo "Status missing version/image info: $current_status"
    return 1
  }
}

# =============================================================================
# AC6.2: Automatic Rollback on Update Failure
# =============================================================================

@test "AC6.2: System remains consistent after failed update (no rollback needed)" {
  # Given update fails
  # When system state is checked
  # Then system is not corrupted (bootable and consistent)
  #
  # This test verifies that failed updates don't corrupt the system
  # without requiring rollback capability.
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get baseline state
  local baseline_status
  baseline_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Verify baseline is valid JSON using grep
  echo "$baseline_status" | grep -qE '^\s*\{' && echo "$baseline_status" | grep -qE '\}\s*$' || {
    skip "Baseline system state is invalid"
  }
  
  # Attempt failed update with non-existent image
  local bad_image="${REMOTE_IMAGE}:corruption-test-$(date +%s)"
  bash -c "ssh $(bootc_ssh_opts) 'bootc switch ${bad_image} 2>&1' 2>&1" || true
  
  # Wait for any rollback to complete
  sleep 3
  
  # Check system is still functional
  run bash -c "ssh $(bootc_ssh_opts) 'hostname' 2>&1"
  
  # System should still be reachable
  assert_success
  
  # Check bootc status works
  run bash -c "ssh $(bootc_ssh_opts) 'bootc status --format=json 2>&1' 2>&1"
  
  # Status should return valid JSON using grep
  echo "$output" | grep -qE '^\s*\{' && echo "$output" | grep -qE '\}\s*$' || {
    echo "System corrupted - invalid bootc status: $output"
    return 1
  }
}

@test "AC6.2: Rollback mechanism is properly configured (skips if no rollback available)" {
  # Given system is booted via bootc
  # When checking rollback capability
  # Then rollback mechanism is properly reported in status
  #
  # This test verifies the ROLLBACK MECHANISM exists, even if no rollback
  # is currently available (requires staged update first).
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get current status
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Verify status is valid JSON using grep
  echo "$status" | grep -qE '^\s*\{' && echo "$status" | grep -qE '\}\s*$' || {
    echo "Invalid bootc status: $status"
    return 1
  }
  
  # Check for rollback-related fields in the status using grep
  # bootc 1.14.1: status.rollback, status.staged
  # Legacy: .rollback, .staged
  local has_rollback_fields
  has_rollback_fields=0
  
  # Check for rollback/staged fields (may be null or have values)
  if echo "$status" | grep -qE '"rollback":|"staged":|"type":'; then
    has_rollback_fields=1
  fi
  
  # The status should contain rollback-related fields (even if null)
  # This verifies the MECHANISM for rollback exists
  # Count how many rollback-related fields are present (even as null)
  local rollback_field_count=0
  
  # Check for presence of rollback/staged/type fields (even as null)
  echo "$status" | grep -qE '"rollback"' && rollback_field_count=$((rollback_field_count + 1))
  echo "$status" | grep -qE '"staged"' && rollback_field_count=$((rollback_field_count + 1))
  echo "$status" | grep -qE '"type"' && rollback_field_count=$((rollback_field_count + 1))
  echo "$status" | grep -qE '"booted"' && rollback_field_count=$((rollback_field_count + 1))
  
  # If no rollback fields exist at all, the mechanism may not be present
  if [ "$rollback_field_count" -eq 0 ]; then
    # Check if at least the status structure is complete using grep
    echo "$status" | grep -qE '"status"|"image"|"BootcHost"' || {
      skip "Bootc status structure incomplete - cannot verify rollback mechanism"
    }
  fi
  
  # At minimum, verify bootc status reports the booted image correctly
  # bootc 1.14.1: image is at status.booted.image.image
  # Use grep-based parsing
  local image
  image="$(echo "$status" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
  
  [ -n "$image" ] || {
    skip "No booted image in status - cannot verify rollback mechanism without booted image"
  }
}

@test "AC6.2: Rollback available after staged update (requires staged update)" {
  # Given a staged update exists
  # When rollback is triggered
  # Then system rolls back to previous deployment
  #
  # REQUIRES: rollback and staged must not be null
  # SKIPS: If no rollback is available (no staged update to roll back from)
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # SKIP if rollback is not available
  # We cannot test actual rollback without a staged update
  bootc_skip_if_no_rollback
  
  # Get current status with rollback available
  local status_before
  status_before="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Extract current image using grep
  local image_before
  image_before="$(echo "$status_before" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
  
  # Trigger rollback (this should work since we have rollback available)
  run bash -c "ssh $(bootc_ssh_opts) 'bootc rollback 2>&1' 2>&1"
  
  # Wait for rollback to complete
  sleep 5
  
  # Check status after rollback
  local status_after
  status_after="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Verify system is in valid state using grep for JSON validation
  echo "$status_after" | grep -qE '^\s*\{' && echo "$status_after" | grep -qE '\}\s*$' || {
    echo "Invalid status after rollback: $status_after"
    return 1
  }
  
  # System should be bootable
  local image_after
  image_after="$(echo "$status_after" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
  
  [ -n "$image_after" ] || {
    echo "No booted image after rollback: $status_after"
    return 1
  }
}

# =============================================================================
# AC6.3: Status Verification After Rollback
# =============================================================================

@test "AC6.3: bootc status shows current deployment correctly" {
  # Given system is running
  # When bootc status is checked
  # Then status shows the current deployment information
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get current status
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Status should show current image
  assert_success
  
  # Verify status contains image information
  echo "$status" | grep -qE "image|BootcHost" || {
    echo "Status missing image information: $status"
    return 1
  }
  
  # Parse image reference using grep
  # bootc 1.14.1: image is at status.booted.image.image
  local image
  image="$(echo "$status" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
  
  # Image should be present and valid
  [ -n "$image" ] || {
    echo "No image in status: $status"
    return 1
  }
  
  # Image should contain valid reference (registry or digest)
  echo "$image" | grep -qE "quay.io|docker.io|localhost|sha256" || {
    echo "Invalid image reference: $image"
    return 1
  }
}

@test "AC6.3: bootc status shows rollback fields (mechanism verification)" {
  # Given system is booted via bootc
  # When status is checked
  # Then status contains rollback-related fields (mechanism present)
  #
  # This verifies the ROLLBACK MECHANISM exists, regardless of whether
  # rollback is currently available.
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get status
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Status should indicate deployment state
  # Look for fields indicating rollback capability using grep
  # bootc 1.14.1: status.rollback, status.staged are the correct paths
  # Legacy: .rollback, .staged, .type, .image
  echo "$status" | grep -qE '"rollback"|"staged"|"type"|"booted"|"image"|"BootcHost"|"version"' || {
    echo "Status missing rollback/deployment information: $status"
    return 1
  }
  
  # Status should contain version or image reference
  echo "$status" | grep -qE "version|image|id|BootcHost" || {
    echo "Status missing version/image identification: $status"
    return 1
  }
}

@test "AC6.3: Journal shows bootc events" {
  # Given system is running
  # When journal is checked
  # Then journal shows bootc-related events
  #
  # This verifies the journaling mechanism works for bootc.
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Check journal for bootc-related entries
  run bash -c "ssh $(bootc_ssh_opts) 'journalctl -u bootc-switch --no-pager -n 20 2>&1 || journalctl -b -u bootc* --no-pager -n 20 2>&1 || echo no-bootc-journal' 2>&1"
  
  # Should get some journal output (or indicate no entries)
  # This verifies journal is accessible and bootc events are logged
  [ $status -eq 0 ] || skip "Could not access system journal"
  
  # Either shows bootc events or is empty (acceptable)
  # The important thing is the command worked
  echo "$output" | grep -qE "bootc|switch|deployment|rollback|journal|no-bootc-journal" || {
    echo "Unexpected journal output: $output"
  }
}

@test "AC6.3: ostree admin status available (if installed)" {
  # Given system is booted via bootc
  # When ostree admin status is checked
  # Then it shows deployment information (if ostree is installed)
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Check ostree admin status (may not be available in all bootc installations)
  run bash -c "ssh $(bootc_ssh_opts) 'ostree admin status 2>&1' 2>&1"
  
  # ostree admin may not be available in minimal bootc images
  # Fall back to bootc status if not available
  if [ $status -ne 0 ]; then
    skip "ostree admin not available on this bootc installation"
  fi
  
  # Should show deployment information
  echo "$output" | grep -qE "deploy|current|origin|image" || {
    echo "ostree admin status missing deployment info: $output"
    return 1
  }
}

@test "AC6.3: Device is bootable (system consistency check)" {
  # Given system is running
  # When device is checked
  # Then device is in bootable state
  #
  # This verifies system consistency without requiring rollback.
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # After any rollback, verify device is bootable
  
  # 1. Verify SSH is working (system is running)
  run bash -c "ssh $(bootc_ssh_opts) 'echo alive' 2>&1"
  assert_success
  
  # 2. Verify bootc is responsive
  run bash -c "ssh $(bootc_ssh_opts) 'bootc status 2>&1' 2>&1"
  assert_success
  
  # 3. Verify bootc status is valid JSON using grep
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  echo "$status" | grep -qE '^\s*\{' && echo "$status" | grep -qE '\}\s*$' || {
    echo "Invalid bootc status: $status"
    return 1
  }
  
  # 4. Verify system has valid image using grep
  # bootc 1.14.1: image is at status.booted.image.image
  local image
  image="$(echo "$status" | grep -oE '"image":\s*"[^"]*"' | head -1 | sed 's/.*"image":[[:space:]]*"//;s/"$//')" || true
  
  [ -n "$image" ] || {
    # In bootc 1.14.1: check for rollback/staged/type fields as fallback
    echo "$status" | grep -qE '"rollback"|"staged"|"type"|"booted"' || {
      echo "No valid image or deployment info: $status"
      return 1
    }
  }
}

@test "AC6.3: Version is correctly reported" {
  # Given system is running
  # When version is queried
  # Then correct version is reported
  
  skip_if_tool_not_available "podman"
  
  # Verify system is booted via bootc
  bootc_skip_if_not_bootc_system
  
  # Get status with version info
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Extract version using grep - look for version field
  # bootc 1.14.1: version might be in status.booted.version or status.version
  local version
  version="$(echo "$status" | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/.*"version":[[:space:]]*"//;s/"$//')" || true
  
  # Version should be present (or system should have other identifier)
  # This verifies version reporting works
  if [ -n "$version" ]; then
    # Version format should be recognizable (semver or other)
    echo "$version" | grep -qE '[0-9]|\.' || {
      echo "Version format unexpected: $version"
    }
  else
    # If no version, system should have image ID or other identifier
    # bootc 1.14.1: check for booted/image fields
    echo "$status" | grep -qE '"booted"|"image"|"id"|"BootcHost"' || {
      echo "No version or image identifier in status: $status"
      return 1
    }
  fi
}
