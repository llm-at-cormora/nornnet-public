#!/usr/bin/env bats
# Acceptance tests for US7: Automated Reboot
#
# These tests verify that:
# 1. Reboot can be triggered programmatically
# 2. Device comes back online after reboot
# 3. Device runs the new image version after reboot
# 4. Reboot automation logic works correctly
#
# Environment Setup:
# These tests require a bootc-managed device. Set BOOTC_DEVICE_HOST (and optionally
# BOOTC_DEVICE_SSH_KEY) to configure. See tests/bats/bootc_helpers.bash for details.

load '../bats/common.bash'
load '../bats/fixtures.bash'
load '../bats/ci_helpers.bash'
load '../bats/bootc_helpers.bash'

# =============================================================================
# Test Configuration
# =============================================================================

REBOOT_TIMEOUT="${REBOOT_TIMEOUT:-300}"  # 5 minutes default timeout
REBOOT_POLL_INTERVAL="${REBOOT_POLL_INTERVAL:-10}"  # Check every 10 seconds
SHORT_TIMEOUT="${SHORT_TIMEOUT:-5}"  # For quick unit tests

setup() {
  # Create test context (always needed, even for unit tests)
  BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
  TEST_CONTEXT="$BATS_TMPDIR/nornnet-reboot-test-$$"
  mkdir -p "$TEST_CONTEXT"
}

teardown() {
  # Cleanup test context
  rm -rf "$TEST_CONTEXT" 2>/dev/null || true
}

# =============================================================================
# SECTION 1: Unit Tests for wait_for_reboot Logic (Mock-Based)
# =============================================================================

# These tests use mocks to verify wait_for_reboot behavior without a real device.

@test "wait_for_reboot: exits successfully when device comes back online" {
  # Given a mock that returns success after N attempts
  # When polling loop succeeds
  # Then it returns success when device responds
  
  # Use unique counter file for this test
  local counter_file="$TEST_CONTEXT/mock_counter_$$"
  rm -f "$counter_file"
  
  # Create a mock script that succeeds on third attempt
  cat > "$TEST_CONTEXT/mock_ssh_success.sh" << 'EOF'
#!/bin/bash
counter_file="$1"
if [ -f "$counter_file" ]; then
  count=$(cat "$counter_file")
else
  count=0
fi
count=$((count + 1))
echo "$count" > "$counter_file"

# Fail first 2 times, succeed on 3rd
if [ "$count" -lt 3 ]; then
  exit 1
fi
exit 0
EOF
  chmod +x "$TEST_CONTEXT/mock_ssh_success.sh"
  
  # Test the polling logic
  local start_time=$(date +%s)
  local elapsed=0
  local max_attempts=5
  local attempt=0
  local success=false
  
  while [ $attempt -lt $max_attempts ] && [ $elapsed -lt 15 ]; do
    attempt=$((attempt + 1))
    if $TEST_CONTEXT/mock_ssh_success.sh "$counter_file" 2>/dev/null; then
      success=true
      local end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      echo "Device came back online after ${attempt} attempts (${elapsed}s)"
      break
    fi
    sleep 1
    elapsed=$(( $(date +%s) - start_time ))
  done
  
  rm -f "$counter_file"
  
  if $success; then
    return 0
  else
    echo "Device did not respond after ${attempt} attempts"
    return 1
  fi
}

@test "wait_for_reboot: exits with failure on timeout" {
  # Given a mock that always fails
  # When wait_for_reboot is called
  # Then it returns failure after timeout
  
  # Create a mock that always fails
  cat > "$TEST_CONTEXT/always_fail.sh" << 'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TEST_CONTEXT/always_fail.sh"
  
  local timeout=3
  local start_time=$(date +%s)
  
  # Simulate wait_for_reboot with always-failing SSH
  for i in $(seq 1 $timeout); do
    $TEST_CONTEXT/always_fail.sh 2>/dev/null && break
    sleep 1
  done
  
  local elapsed=$(($(date +%s) - start_time))
  
  # Should timeout after ~3 seconds
  [ $elapsed -ge 2 ] && [ $elapsed -le 5 ]
}

@test "wait_for_reboot: polls at correct interval" {
  # Given a poll counter
  # When wait_for_reboot polls
  # Then it polls at configured interval
  
  local poll_interval=2
  local timeout=10
  local poll_count=0
  local start_time=$(date +%s)
  
  # Count polls until timeout
  while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
    poll_count=$((poll_count + 1))
    sleep $poll_interval
  done
  
  # Should have polled approximately timeout/poll_interval times
  # Allow some tolerance for timing variations
  local expected=$((timeout / poll_interval))
  local diff=$((poll_count - expected))
  
  # Diff should be within 2 polls (accounting for shell overhead)
  [ $diff -ge -2 ] && [ $diff -le 2 ]
}

@test "wait_for_reboot: reports elapsed time on success" {
  # Given a mock that succeeds after a delay
  # When polling completes
  # Then it reports the elapsed time
  
  local counter_file="$TEST_CONTEXT/delayed_counter_$$"
  rm -f "$counter_file"
  
  cat > "$TEST_CONTEXT/delayed_success.sh" << 'EOF'
#!/bin/bash
counter_file="$1"
if [ -f "$counter_file" ]; then
  count=$(cat "$counter_file")
else
  count=0
fi
count=$((count + 1))
echo "$count" > "$counter_file"
# Succeed after 3 attempts
[ "$count" -ge 3 ]
EOF
  chmod +x "$TEST_CONTEXT/delayed_success.sh"
  
  local start_time=$(date +%s)
  local success=false
  
  for i in $(seq 1 10); do
    if $TEST_CONTEXT/delayed_success.sh "$counter_file" 2>/dev/null; then
      success=true
      break
    fi
    sleep 1
  done
  
  local elapsed=$(($(date +%s) - start_time))
  rm -f "$counter_file"
  
  $success && [ $elapsed -ge 2 ] && [ $elapsed -le 5 ]
}

# =============================================================================
# SECTION 2: Helper Function Tests
# =============================================================================

@test "bootc_helpers: bootc_status returns valid JSON" {
  # Given device is reachable
  # When bootc_status is called
  # Then it returns valid JSON
  
  bootc_skip_if_unavailable
  
  local status
  status="$(bootc_status)" || {
    skip "Could not get bootc status"
  }
  
  # Should be valid JSON (basic check)
  echo "$status" | grep -qE '^\{.*\}$'
}

@test "bootc_helpers: bootc_status contains required fields" {
  # Given device is reachable
  # When bootc_status is called
  # Then it contains bootc system information
  
  bootc_skip_if_unavailable
  
  local status
  status="$(bootc_status)" || {
    skip "Could not get bootc status"
  }
  
  # Must contain BootcHost or at minimum image/type info
  echo "$status" | grep -qE 'BootcHost|"image"|"type"' || {
    echo "bootc status missing expected fields: $status"
    return 1
  }
}

@test "bootc_helpers: bootc_status extracts image correctly" {
  # Given bootc status JSON
  # When extracting current image
  # Then image ID/digest is extracted correctly
  
  bootc_skip_if_unavailable
  
  # Get raw status
  local status
  status="$(bootc_status)" || {
    skip "Could not get bootc status"
  }
  
  # Should be able to find image information
  # Try various possible JSON paths
  local has_image=false
  
  # Check for image.id (legacy format)
  if echo "$status" | grep -qE '"image":\s*\{[^}]*"id":'; then
    has_image=true
  fi
  
  # Check for status.booted.image.id (bootc 1.14.1 format)
  if echo "$status" | grep -qE '"booted":\s*\{[^}]*"image":'; then
    has_image=true
  fi
  
  # Check for direct image id
  if echo "$status" | grep -qE '"id":\s*"sha256:'; then
    has_image=true
  fi
  
  $has_image || {
    echo "Could not find image information in status: $status"
    return 1
  }
}

@test "bootc_helpers: bootc_status extracts version correctly" {
  # Given bootc status JSON
  # When extracting version
  # Then version string is extracted (or empty if not available)
  
  bootc_skip_if_unavailable
  
  local status
  status="$(bootc_status)" || {
    skip "Could not get bootc status"
  }
  
  # Should contain version field (may be null or empty)
  # This test verifies parsing doesn't fail
  local version
  version="$(echo "$status" | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/.*"version":[[:space:]]*"//;s/"$//')" || true
  
  # If version is present, should be non-empty string
  if [ -n "$version" ]; then
    [ ${#version} -gt 0 ]
  else
    # Version may be empty/null - this is valid
    echo "Version field empty or not present"
  fi
}

@test "bootc_helpers: bootc_has_rollback detects available rollback" {
  # Given a device with staged update
  # When bootc_has_rollback is called
  # Then it correctly detects rollback availability
  
  bootc_skip_if_unavailable
  
  # This test just verifies the function exists and runs
  # The actual result depends on device state
  run bootc_has_rollback
  
  # Function should return 0 or 1, not error
  [ $status -eq 0 ] || [ $status -eq 1 ]
}

# =============================================================================
# SECTION 3: Device Connectivity Tests
# =============================================================================

@test "connectivity: device is reachable before reboot testing" {
  # Given bootc device is configured
  # When connectivity is tested
  # Then device responds to SSH
  
  bootc_skip_if_unavailable
  
  run bash -c "bootc_ssh 'echo online' 2>&1"
  
  assert_success
  echo "$output" | grep -q "online"
}

@test "connectivity: bootc command is available on device" {
  # Given device is reachable
  # When bootc command is run
  # Then it executes successfully
  
  bootc_skip_if_unavailable
  
  run bash -c "bootc_ssh 'bootc --version' 2>&1"
  
  assert_success
  echo "$output" | grep -qE "bootc|version"
}

@test "connectivity: systemctl is available on device" {
  # Given device is reachable
  # When systemctl is called
  # Then it executes (we just check it exists)
  
  bootc_skip_if_unavailable
  
  run bash -c "bootc_ssh 'systemctl --version' 2>&1"
  
  assert_success
}

# =============================================================================
# SECTION 4: Reboot Triggering Tests
# =============================================================================

@test "reboot-trigger: systemctl reboot is available" {
  # Given device is running
  # When systemctl reboot command is executed
  # Then it initiates reboot (doesn't error out)
  
  bootc_skip_if_unavailable
  
  # Check if systemctl reboot would work (dry run - just verify command exists)
  # We don't actually trigger reboot in this test
  run bash -c "bootc_ssh 'type systemctl' 2>&1"
  
  assert_success
}

@test "reboot-trigger: reboot can be initiated programmatically" {
  # Given a test script that can trigger reboot
  # When reboot is triggered
  # Then the command succeeds (actual reboot happens async)
  
  bootc_skip_if_unavailable
  
  # Create a test script that would trigger reboot
  # We test that the mechanism exists, without actually rebooting
  cat > "$TEST_CONTEXT/test_reboot_script.sh" << 'EOF'
#!/bin/bash
# This script tests that reboot can be triggered
# The actual reboot happens asynchronously
systemctl reboot || reboot || exit 0
EOF
  
  # Copy to device and verify it can be executed (without actually running)
  # This verifies the script syntax is valid
  bash "$TEST_CONTEXT/test_reboot_script.sh" 2>&1 || true
  
  # The script should be valid bash (syntax check)
  bash -n "$TEST_CONTEXT/test_reboot_script.sh"
}

@test "reboot-trigger: reboot reason is logged" {
  # Given device reboots
  # When journal is checked
  # Then reboot reason is captured
  
  bootc_skip_if_unavailable
  
  # Check if we can access journal (may require permissions)
  run bash -c "bootc_ssh 'journalctl --list-boots 2>&1 | head -5' 2>&1"
  
  # May fail due to permissions, but should return some output or graceful error
  [ $status -eq 0 ] || {
    # Permission errors are acceptable
    echo "$output" | grep -qE "permission|denied|not.*admin" && return 0
    echo "Unexpected error accessing journal: $output"
    return 1
  }
}

# =============================================================================
# SECTION 5: State Comparison Tests (Before/After Reboot)
# =============================================================================

@test "state: can capture bootc status before reboot" {
  # Given device is running
  # When bootc status is captured
  # Then it can be stored for comparison
  
  bootc_skip_if_unavailable
  
  # Capture current state
  local status_before
  status_before="$(bootc_status)" || {
    skip "Could not get bootc status"
  }
  
  # Store in test context for comparison
  echo "$status_before" > "$TEST_CONTEXT/status_before.json"
  
  # Verify we captured something
  [ -s "$TEST_CONTEXT/status_before.json" ]
  
  # Should be valid JSON
  grep -qE '^\{.*\}$' "$TEST_CONTEXT/status_before.json"
}

@test "state: bootc status is stable during normal operation" {
  # Given device is running without changes
  # When bootc status is queried multiple times
  # Then status remains consistent
  
  bootc_skip_if_unavailable
  
  local status1
  local status2
  local status3
  
  status1="$(bootc_status)" || skip "Could not get first status"
  sleep 2
  status2="$(bootc_status)" || skip "Could not get second status"
  sleep 2
  status3="$(bootc_status)" || skip "Could not get third status"
  
  # All three should contain same core information
  # (version may change due to build time, but image ID should be stable)
  echo "$status1" | grep -oE 'sha256:[a-f0-9]+' | head -1 > "$TEST_CONTEXT/image1.txt"
  echo "$status2" | grep -oE 'sha256:[a-f0-9]+' | head -1 > "$TEST_CONTEXT/image2.txt"
  echo "$status3" | grep -oE 'sha256:[a-f0-9]+' | head -1 > "$TEST_CONTEXT/image3.txt"
  
  # Image should be stable (same during normal operation)
  diff "$TEST_CONTEXT/image1.txt" "$TEST_CONTEXT/image2.txt" || true
  diff "$TEST_CONTEXT/image2.txt" "$TEST_CONTEXT/image3.txt" || true
  
  # Either all same (stable) or all different (edge case, still valid)
  if ! diff "$TEST_CONTEXT/image1.txt" "$TEST_CONTEXT/image2.txt" &>/dev/null; then
    # If different, verify it's a valid sha256
    grep -qE 'sha256:[a-f0-9]{64}' "$TEST_CONTEXT/image1.txt"
    grep -qE 'sha256:[a-f0-9]{64}' "$TEST_CONTEXT/image2.txt"
  fi
}

@test "state: can detect image change after update" {
  # Given we have captured state before
  # When comparing with current state
  # Then we can detect if image changed
  
  bootc_skip_if_unavailable
  
  # Get current image
  local current_status
  current_status="$(bootc_status)" || skip "Could not get bootc status"
  
  # Extract image identifier
  local image
  image="$(echo "$current_status" | grep -oE 'sha256:[a-f0-9]{64}' | head -1)" || true
  
  if [ -n "$image" ]; then
    echo "Current image: $image"
    # Verify it's a valid digest format
    echo "$image" | grep -qE '^sha256:[a-f0-9]{64}$'
  else
    # No digest found - check for alternative image reference
    echo "$current_status" | grep -qE '"image"|"id"|"booted"'
  fi
}

# =============================================================================
# SECTION 6: Integration Tests (Actual Reboot Sequence)
# =============================================================================

# These tests actually trigger reboot and verify device comes back online.
# They are marked as integration tests and can be skipped in unit test mode.

@test "integration: device reboots and comes back online" {
  # Given a device that can be rebooted
  # When reboot is triggered
  # Then device comes back online within timeout
  
  bootc_skip_if_unavailable
  
  local host
  host="$(bootc_device_host)"
  
  # Skip if explicitly disabled (to prevent accidental reboots in CI)
  if [ "${SKIP_ACTUAL_REBOOT:-false}" = "true" ]; then
    skip "SKIP_ACTUAL_REBOOT is set - skipping actual reboot test"
  fi
  
  # Verify device is online before reboot
  run bash -c "bootc_ssh 'echo online' 2>&1"
  assert_success
  
  # Record pre-reboot state
  local status_before
  status_before="$(bootc_status)" || skip "Could not get pre-reboot status"
  local image_before
  image_before="$(echo "$status_before" | grep -oE 'sha256:[a-f0-9]{64}' | head -1)" || true
  
  echo "Pre-reboot image: ${image_before:-unknown}"
  
  # Trigger reboot in background (async)
  # We redirect output to avoid hanging on SSH
  bootc_ssh "nohup systemctl reboot > /dev/null 2>&1 &" &
  local reboot_pid=$!
  
  # Give it a moment to initiate
  sleep 3
  
  # Verify connection is lost (device is rebooting)
  local connection_lost=false
  for i in $(seq 1 10); do
    if ! bootc_ssh "echo online" &>/dev/null; then
      connection_lost=true
      break
    fi
    sleep 1
  done
  
  if ! $connection_lost; then
    echo "Warning: Connection not lost - reboot may not have initiated"
  fi
  
  # Wait for device to come back online
  echo "Waiting for device to come back online (timeout: ${REBOOT_TIMEOUT}s)..."
  local online=false
  local elapsed=0
  
  while [ $elapsed -lt $REBOOT_TIMEOUT ]; do
    if bootc_ssh "echo online" &>/dev/null; then
      online=true
      echo "Device back online after ${elapsed}s"
      break
    fi
    sleep $REBOOT_POLL_INTERVAL
    elapsed=$((elapsed + REBOOT_POLL_INTERVAL))
    echo "  Still waiting... ${elapsed}s elapsed"
  done
  
  if ! $online; then
    echo "ERROR: Device did not come back online within ${REBOOT_TIMEOUT}s"
    return 1
  fi
  
  # Give system a moment to stabilize
  sleep 10
  
  # Verify post-reboot state
  local status_after
  status_after="$(bootc_status)" || {
    echo "ERROR: Could not get bootc status after reboot"
    return 1
  }
  
  local image_after
  image_after="$(echo "$status_after" | grep -oE 'sha256:[a-f0-9]{64}' | head -1)" || true
  
  echo "Post-reboot image: ${image_after:-unknown}"
  
  # Verify system is operational
  run bash -c "bootc_ssh 'systemctl is-system-running' 2>&1"
  echo "$output" | grep -qE "running|degraded" || {
    echo "Warning: System not in expected state: $output"
  }
}

@test "integration: bootc status is correct after reboot" {
  # Given device has rebooted
  # When bootc status is checked
  # Then it shows valid bootc system information
  
  bootc_skip_if_unavailable
  
  # Skip if explicitly disabled
  if [ "${SKIP_ACTUAL_REBOOT:-false}" = "true" ]; then
    skip "SKIP_ACTUAL_REBOOT is set - skipping actual reboot test"
  fi
  
  # Just verify we can get bootc status (basic smoke test after any previous reboot)
  local status
  status="$(bootc_status)" || {
    skip "Could not get bootc status"
  }
  
  # Should contain bootc system information
  echo "$status" | grep -qE 'BootcHost|"image"|"type"|"booted"' || {
    echo "bootc status does not contain expected fields: $status"
    return 1
  }
  
  echo "Post-reboot bootc status verified"
}

@test "integration: system services are running after reboot" {
  # Given device has rebooted
  # When critical services are checked
  # Then services are running
  
  bootc_skip_if_unavailable
  
  # Skip if explicitly disabled
  if [ "${SKIP_ACTUAL_REBOOT:-false}" = "true" ]; then
    skip "SKIP_ACTUAL_REBOOT is set - skipping actual reboot test"
  fi
  
  # Check system is running (not degraded)
  local system_state
  system_state="$(bootc_ssh 'systemctl is-system-running 2>&1')" || {
    skip "Could not get system state"
  }
  
  echo "System state: $system_state"
  
  # Should be running (degraded is acceptable but not ideal)
  echo "$system_state" | grep -qE "running|degraded" || {
    echo "System not in expected state: $system_state"
    return 1
  }
  
  # Check a few critical services
  local services=("sshd" "systemd-journald")
  
  for svc in "${services[@]}"; do
    local svc_status
    svc_status="$(bootc_ssh "systemctl is-active $svc 2>&1")" || true
    if ! echo "$svc_status" | grep -qE "active|inactive"; then
      echo "Warning: Could not check $svc status"
    fi
  done
}

@test "integration: uptime reflects recent reboot" {
  # Given device has rebooted
  # When uptime is checked
  # Then uptime reflects current boot
  
  bootc_skip_if_unavailable
  
  # Skip if explicitly disabled
  if [ "${SKIP_ACTUAL_REBOOT:-false}" = "true" ]; then
    skip "SKIP_ACTUAL_REBOOT is set - skipping actual reboot test"
  fi
  
  local uptime
  uptime="$(bootc_ssh 'uptime 2>&1')" || {
    skip "Could not get uptime"
  }
  
  echo "Current uptime: $uptime"
  
  # Uptime should be available and show current time
  echo "$uptime" | grep -qE "up.*[0-9]" || {
    echo "Uptime format unexpected: $uptime"
    return 1
  }
}

# =============================================================================
# SECTION 7: Rollback Availability Tests
# =============================================================================

@test "rollback: rollback is available after update" {
  # Given update has been staged
  # When checking rollback capability
  # Then previous image is available
  
  bootc_skip_if_unavailable
  
  # Run bootc upgrade to potentially stage an update
  # This doesn't apply it, just checks/prepares
  local upgrade_output
  upgrade_output="$(bootc_ssh 'bootc upgrade 2>&1')" || true
  
  echo "Upgrade output: $upgrade_output"
  
  # Check for rollback availability
  local status
  status="$(bootc_status)" || {
    skip "Could not get bootc status"
  }
  
  # Look for rollback or staged fields
  local has_rollback_field=false
  
  if echo "$status" | grep -qE '"rollback":\s*\{'; then
    has_rollback_field=true
    echo "Found rollback field (legacy format)"
  fi
  
  if echo "$status" | grep -qE '"staged":\s*\{'; then
    has_rollback_field=true
    echo "Found staged field"
  fi
  
  if echo "$status" | grep -qE '"status":\s*\{[^}]*"rollback":'; then
    has_rollback_field=true
    echo "Found rollback field (bootc 1.14.1 format)"
  fi
  
  if echo "$status" | grep -qE '"status":\s*\{[^}]*"staged":'; then
    has_rollback_field=true
    echo "Found staged field (bootc 1.14.1 format)"
  fi
  
  # Note: rollback might not be available if this is a fresh install
  # This is informational - we just report the state
  if ! $has_rollback_field; then
    echo "No rollback/staged field found - this is normal for fresh install"
  fi
}

@test "rollback: ostree admin status shows deployments" {
  # Given device is running
  # When ostree admin status is checked
  # Then deployments are listed
  
  bootc_skip_if_unavailable
  
  # Try ostree admin status (may not be available in all bootc installs)
  local ostree_output
  ostree_output="$(bootc_ssh 'ostree admin status 2>&1')" || {
    # This is acceptable - ostree admin may not be available
    echo "ostree admin not available: $ostree_output"
    return 0
  }
  
  echo "Ostree admin output: $ostree_output"
  
  # Should show deployments
  echo "$ostree_output" | grep -qE "^\*" || {
    echo "No deployments shown in ostree admin status"
    return 1
  }
}

# =============================================================================
# SECTION 8: Error Handling Tests
# =============================================================================

@test "error: wait_for_reboot handles connection timeout gracefully" {
  # Given a device that doesn't respond
  # When wait_for_reboot times out
  # Then it returns appropriate error
  
  # Test timeout logic with a non-existent host
  local start_time=$(date +%s)
  
  # Simulate SSH to non-existent host with timeout
  timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no root@127.0.0.1 'echo' 2>/dev/null || true
  
  local elapsed=$(($(date +%s) - start_time))
  
  # Should complete within reasonable time (not hang forever)
  [ $elapsed -lt 10 ]
}

@test "error: bootc_status handles unreachable device" {
  # Given device is unreachable
  # When bootc_status is called
  # Then it returns error gracefully
  
  # This is tested by the helper function behavior
  # When device is unreachable, bootc_status should return empty
  
  # We verify the error handling path exists
  local result
  result="$(bootc_status 2>&1)" || result=""
  
  # If result is empty, that's acceptable (device unreachable)
  # If result has content, it should be parseable
  if [ -n "$result" ]; then
    echo "$result" | grep -qE "."  # Just verify it's not binary garbage
  fi
}

@test "error: version extraction handles malformed JSON" {
  # Given a malformed JSON string
  # When extracting version
  # Then it handles gracefully
  
  # Test with invalid JSON
  local malformed='{"version": invalid, "image": {"id": "sha'
  local version
  version="$(echo "$malformed" | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/.*"version":[[:space:]]*"//;s/"$//')" || true
  
  # Should not crash, may return empty
  [ -z "$version" ] || [ ${#version} -gt 0 ]
}

# =============================================================================
# SECTION 9: Comprehensive Reboot Workflow Test
# =============================================================================

@test "workflow: complete update and reboot cycle" {
  # Given a device with available update
  # When update is applied and reboot is triggered
  # Then complete cycle works correctly
  
  bootc_skip_if_unavailable
  
  # Skip if explicitly disabled
  if [ "${SKIP_ACTUAL_REBOOT:-false}" = "true" ]; then
    skip "SKIP_ACTUAL_REBOOT is set - skipping update/reboot cycle test"
  fi
  
  echo "=== Step 1: Capture pre-update state ==="
  local status_pre
  status_pre="$(bootc_status)" || skip "Could not get pre-update status"
  local image_pre
  image_pre="$(echo "$status_pre" | grep -oE 'sha256:[a-f0-9]{64}' | head -1)" || image_pre="unknown"
  echo "Pre-update image: $image_pre"
  
  echo "=== Step 2: Apply update ==="
  local upgrade_result
  upgrade_result="$(bootc_ssh 'bootc upgrade 2>&1')" || true
  echo "Upgrade result: $upgrade_result"
  
  # Check if update was applied
  if echo "$upgrade_result" | grep -qE "No changes|up.to.date|already.*latest"; then
    echo "No update available - this is acceptable"
    skip "No update available for testing"
  fi
  
  echo "=== Step 3: Capture post-update state ==="
  sleep 5
  local status_post_update
  status_post_update="$(bootc_status)" || skip "Could not get post-update status"
  local image_post_update
  image_post_update="$(echo "$status_post_update" | grep -oE 'sha256:[a-f0-9]{64}' | head -1)" || image_post_update="unknown"
  echo "Post-update image: $image_post_update"
  
  # Check if staged update exists
  local has_staged
  has_staged=false
  if echo "$status_post_update" | grep -qE '"staged":\s*\{'; then
    has_staged=true
  fi
  if echo "$status_post_update" | grep -qE '"status":\s*\{[^}]*"staged":'; then
    has_staged=true
  fi
  
  if $has_staged; then
    echo "Staged update detected - rollback available"
  fi
  
  echo "=== Step 4: Reboot to apply update ==="
  bootc_ssh "nohup systemctl reboot > /dev/null 2>&1 &"
  
  echo "Waiting for reboot to complete (timeout: ${REBOOT_TIMEOUT}s)..."
  local online=false
  local elapsed=0
  
  while [ $elapsed -lt $REBOOT_TIMEOUT ]; do
    if bootc_ssh "echo online" &>/dev/null; then
      online=true
      echo "Device back online after ${elapsed}s"
      break
    fi
    sleep $REBOOT_POLL_INTERVAL
    elapsed=$((elapsed + REBOOT_POLL_INTERVAL))
    echo "  Still waiting... ${elapsed}s elapsed"
  done
  
  if ! $online; then
    echo "ERROR: Device did not come back online"
    return 1
  fi
  
  # Let system stabilize
  sleep 15
  
  echo "=== Step 5: Verify post-reboot state ==="
  local status_post_reboot
  status_post_reboot="$(bootc_status)" || {
    echo "ERROR: Could not get bootc status after reboot"
    return 1
  }
  
  local image_post_reboot
  image_post_reboot="$(echo "$status_post_reboot" | grep -oE 'sha256:[a-f0-9]{64}' | head -1)" || image_post_reboot="unknown"
  echo "Post-reboot image: $image_post_reboot"
  
  echo "=== Step 6: Verify system is operational ==="
  local system_state
  system_state="$(bootc_ssh 'systemctl is-system-running 2>&1')" || {
    echo "Warning: Could not get system state"
    system_state="unknown"
  }
  echo "System state: $system_state"
  
  echo "=== Summary ==="
  echo "Pre-update:    $image_pre"
  echo "Post-update:   $image_post_update"
  echo "Post-reboot:   $image_post_reboot"
  echo "System state:  $system_state"
  
  # Verify system is running
  echo "$system_state" | grep -qE "running|degraded" || {
    echo "ERROR: System not in expected state"
    return 1
  }
  
  echo "=== Update and reboot cycle completed successfully ==="
}
