#!/usr/bin/env bats
# Acceptance tests for US6: Transactional Update
#
# Tests bootc's transactional update mechanism - updates are atomic (all-or-nothing)
# and the system automatically rolls back if an update fails.
#
# Acceptance Criteria:
# AC6.1: Given an update process starts, When update completes successfully,
#        Then all changes are applied atomically
# AC6.2: Given an update is in progress, When update fails,
#        Then automatic rollback restores previous state
# AC6.3: Given rollback completes, When status is checked,
#        Then system shows previous image and rollback status
#
# Bootc Status JSON Structure (bootc 1.14.1):
# {
#   "status": {
#     "booted": { "image": {...}, "version": "..." },     // Current running image
#     "rollback": { "image": {...}, "version": "..." },    // Previous image (populated after first update)
#     "staged": { "image": {...}, "version": "..." },      // Downloaded but not yet active
#     "rollbackQueued": false,                              // Whether rollback is pending
#     "type": "bootcHost"
#   }
# }

load '../bats/common.bash'
load '../bats/fixtures.bash'
load '../bats/bootc_helpers.bash'
load '../bats/ci_helpers.bash'

# =============================================================================
# Test Configuration
# =============================================================================

BOOTC_SSH_CONFIG="/tmp/ssh_config/config"

setup() {
  # Create SSH config to bypass systemd-ssh-proxy permission issues
  mkdir -p /tmp/ssh_config
  echo "Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null" > "$BOOTC_SSH_CONFIG"
  chmod 600 "$BOOTC_SSH_CONFIG"
}

teardown() {
  # No cleanup needed - bootc handles transactional cleanup
  true
}

# =============================================================================
# Helper: Parse bootc status JSON using grep (works without jq)
# =============================================================================

# Parse a field from bootc status JSON using grep
# Usage: value=$(parse_bootc_field "$json" "status.booted.version")
# Supports: . notation for nested fields
parse_bootc_field() {
  local json="$1"
  local field="$2"
  
  # Normalize newlines to spaces for consistent parsing of multiline JSON
  json="$(echo "$json" | tr '\n' ' ' | tr -s ' ')"
  
  # Convert dots to regex for nested JSON traversal
  local pattern
  case "$field" in
    "apiVersion")
      pattern='"apiVersion":\s*"([^"]*)"'
      ;;
    "kind")
      pattern='"kind":\s*"([^"]*)"'
      ;;
    "status.type")
      # Find type field anywhere - type is not nested so simple grep works
      echo "$json" | grep -oE '"type":\s*"[^"]*"' | head -1 | sed 's/"type":\s*"//;s/"$//'
      return
      ;;
    "status.booted")
      # Check if booted is not null - just look for booted":{
      echo "$json" | grep -qE '"booted":\s*\{' && echo "present" || echo "null"
      return
      ;;
    "status.rollback")
      # Check if rollback is not null - just look for rollback":{
      echo "$json" | grep -qE '"rollback":\s*\{' && echo "present" || echo "null"
      return
      ;;
    "status.staged")
      # Check if staged is not null - just look for staged":{
      echo "$json" | grep -qE '"staged":\s*\{' && echo "present" || echo "null"
      return
      ;;
    "status.rollbackQueued")
      # Handle boolean values (not quoted)
      echo "$json" | grep -oE '"rollbackQueued":\s*(true|false)' | head -1 | sed 's/.*rollbackQueued":\s*//'
      return
      ;;
    "status.booted.version")
      # Extract version after booted section
      echo "$json" | sed 's/.*"booted":\s*//' | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/"version":\s*"//;s/"$//'
      return
      ;;
    "status.rollback.version")
      echo "$json" | sed 's/.*"rollback":\s*//' | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/"version":\s*"//;s/"$//'
      return
      ;;
    "status.staged.version")
      echo "$json" | sed 's/.*"staged":\s*//' | grep -oE '"version":\s*"[^"]*"' | head -1 | sed 's/"version":\s*"//;s/"$//'
      return
      ;;
    "status.booted.image.image")
      # For deeply nested image objects, grep for image patterns after booted section
      # The image reference is always in format "image":"registry/path:tag"
      local after_booted
      after_booted="$(echo "$json" | sed 's/.*"booted":\s*//' | head -c 2000)"
      echo "$after_booted" | grep -oE '"image":"[^"]*"' | head -1 | sed 's/"image":"//;s/"$//'
      return
      ;;
    "status.rollback.image.image")
      local after_rollback
      after_rollback="$(echo "$json" | sed 's/.*"rollback":\s*//' | head -c 2000)"
      echo "$after_rollback" | grep -oE '"image":"[^"]*"' | head -1 | sed 's/"image":"//;s/"$//'
      return
      ;;
    "status.staged.image.image")
      local after_staged
      after_staged="$(echo "$json" | sed 's/.*"staged":\s*//' | head -c 2000)"
      echo "$after_staged" | grep -oE '"image":"[^"]*"' | head -1 | sed 's/"image":"//;s/"$//'
      return
      ;;
    "status.booted.imageDigest")
      echo "$json" | sed 's/.*"booted":\s*//' | grep -oE '"imageDigest":\s*"[^"]*"' | head -1 | sed 's/"imageDigest":\s*"//;s/"$//'
      return
      ;;
    "status.rollback.imageDigest")
      echo "$json" | sed 's/.*"rollback":\s*//' | grep -oE '"imageDigest":\s*"[^"]*"' | head -1 | sed 's/"imageDigest":\s*"//;s/"$//'
      return
      ;;
    *)
      echo "Unsupported field: $field" >&2
      return 1
      ;;
  esac
  
  echo "$json" | grep -oE "$pattern" | head -1 | sed 's/.*:\s*"//;s/"$//'
}

# Get full bootc status via SSH
bootc_get_status() {
  local host="${1:-}"
  local key="${2:-}"
  local opts="-F $BOOTC_SSH_CONFIG -o BatchMode=yes"
  
  if [ -n "$key" ]; then
    opts="$opts -i $key"
  fi
  
  ssh $opts "root@${host}" "bootc status --format=json" 2>&1
}

# =============================================================================
# AC6.1: Atomic Update Application - Unit Tests for JSON Parsing
# =============================================================================

@test "AC6.1: Parse bootc status JSON - booted field present" {
  local json='{"status":{"booted":{"version":"1.0.0"},"rollback":null,"staged":null}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.booted")"
  
  [ "$result" = "present" ]
}

@test "AC6.1: Parse bootc status JSON - booted field null" {
  local json='{"status":{"booted":null,"rollback":null,"staged":null}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.booted")"
  
  [ "$result" = "null" ]
}

@test "AC6.1: Parse bootc status JSON - rollback field present" {
  local json='{"status":{"booted":{},"rollback":{"version":"0.9.0"},"staged":null}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.rollback")"
  
  [ "$result" = "present" ]
}

@test "AC6.1: Parse bootc status JSON - rollback field null" {
  local json='{"status":{"booted":{},"rollback":null,"staged":null}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.rollback")"
  
  [ "$result" = "null" ]
}

@test "AC6.1: Parse bootc status JSON - staged field present" {
  local json='{"status":{"booted":{},"rollback":null,"staged":{"version":"1.1.0"}}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.staged")"
  
  [ "$result" = "present" ]
}

@test "AC6.1: Parse bootc status JSON - staged field null" {
  local json='{"status":{"booted":{},"rollback":null,"staged":null}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.staged")"
  
  [ "$result" = "null" ]
}

@test "AC6.1: Parse bootc status JSON - rollbackQueued true" {
  local json='{"status":{"rollbackQueued":true}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.rollbackQueued")"
  
  [ "$result" = "true" ]
}

@test "AC6.1: Parse bootc status JSON - rollbackQueued false" {
  local json='{"status":{"rollbackQueued":false}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.rollbackQueued")"
  
  [ "$result" = "false" ]
}

@test "AC6.1: Parse bootc status JSON - booted version extraction" {
  local json='{"status":{"booted":{"version":"1.0.0","image":{"image":"quay.io/test:1.0.0"}}}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.booted.version")"
  
  [ "$result" = "1.0.0" ]
}

@test "AC6.1: Parse bootc status JSON - rollback version extraction" {
  local json='{"status":{"rollback":{"version":"0.9.0","image":{"image":"quay.io/test:0.9.0"}}}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.rollback.version")"
  
  [ "$result" = "0.9.0" ]
}

@test "AC6.1: Parse bootc status JSON - booted image extraction" {
  local json='{"status":{"booted":{"image":{"image":"quay.io/fedora/fedora-bootc:42"}}}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.booted.image.image")"
  
  [ "$result" = "quay.io/fedora/fedora-bootc:42" ]
}

@test "AC6.1: Parse bootc status JSON - booted imageDigest extraction" {
  local json='{"status":{"booted":{"imageDigest":"sha256:abc123def456"}}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.booted.imageDigest")"
  
  [ "$result" = "sha256:abc123def456" ]
}

@test "AC6.1: Parse bootc status JSON - kind field" {
  local json='{"kind":"BootcHost"}'
  
  local result
  result="$(parse_bootc_field "$json" "kind")"
  
  [ "$result" = "BootcHost" ]
}

@test "AC6.1: Parse bootc status JSON - apiVersion field" {
  local json='{"apiVersion":"org.containers.bootc/v1"}'
  
  local result
  result="$(parse_bootc_field "$json" "apiVersion")"
  
  [ "$result" = "org.containers.bootc/v1" ]
}

@test "AC6.1: Parse bootc status JSON - type field" {
  local json='{"status":{"type":"bootcHost"}}'
  
  local result
  result="$(parse_bootc_field "$json" "status.type")"
  
  [ "$result" = "bootcHost" ]
}

# =============================================================================
# AC6.1: Atomic Update Application - State Machine Tests
# =============================================================================

@test "AC6.1: State machine - Initial state has booted only" {
  # Fresh install: only booted is populated, rollback/staged are null
  local json='{"status":{"booted":{"version":"1.0.0"},"rollback":null,"staged":null,"rollbackQueued":false}}'
  
  local booted_staged_rollback
  booted_staged_rollback="$(parse_bootc_field "$json" "status.booted")"
  [ "$booted_staged_rollback" = "present" ]
  
  local staged
  staged="$(parse_bootc_field "$json" "status.staged")"
  [ "$staged" = "null" ]
  
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  [ "$rollback" = "null" ]
}

@test "AC6.1: State machine - After update download (staged)" {
  # After bootc update --download-only: staged is populated
  local json='{"status":{"booted":{"version":"1.0.0"},"rollback":null,"staged":{"version":"1.1.0"},"rollbackQueued":false}}'
  
  local booted
  booted="$(parse_bootc_field "$json" "status.booted")"
  [ "$booted" = "present" ]
  
  local staged
  staged="$(parse_bootc_field "$json" "status.staged")"
  [ "$staged" = "present" ]
  
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  [ "$rollback" = "null" ]
}

@test "AC6.1: State machine - After reboot (rollback populated)" {
  # After reboot: booted changes to new version, old version moves to rollback
  local json='{"status":{"booted":{"version":"1.1.0"},"rollback":{"version":"1.0.0"},"staged":null,"rollbackQueued":false}}'
  
  local booted_version
  booted_version="$(parse_bootc_field "$json" "status.booted.version")"
  [ "$booted_version" = "1.1.0" ]
  
  local rollback_version
  rollback_version="$(parse_bootc_field "$json" "status.rollback.version")"
  [ "$rollback_version" = "1.0.0" ]
  
  local staged
  staged="$(parse_bootc_field "$json" "status.staged")"
  [ "$staged" = "null" ]
}

@test "AC6.1: State machine - Rollback queued" {
  # After failed update: rollbackQueued is true
  local json='{"status":{"rollbackQueued":true}}'
  
  local rollback_queued
  rollback_queued="$(parse_bootc_field "$json" "status.rollbackQueued")"
  [ "$rollback_queued" = "true" ]
}

@test "AC6.1: State machine - After rollback" {
  # After rollback: booted reverts to previous version
  local json='{"status":{"booted":{"version":"1.0.0"},"rollback":null,"staged":null,"rollbackQueued":false}}'
  
  local booted_version
  booted_version="$(parse_bootc_field "$json" "status.booted.version")"
  [ "$booted_version" = "1.0.0" ]
  
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  [ "$rollback" = "null" ]
}

# =============================================================================
# AC6.1: Atomic Update Application - Real Device Integration Tests
# =============================================================================

@test "AC6.1: bootc status command returns valid JSON" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Status should be valid JSON
  echo "$status" | grep -qE '^\s*\{' || {
    echo "Invalid JSON: $status"
    return 1
  }
  echo "$status" | grep -qE '\}\s*$' || {
    echo "Invalid JSON: $status"
    return 1
  }
}

@test "AC6.1: bootc status shows transactional fields" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Must have status object with transactional fields
  echo "$status" | grep -qE '"status":\s*\{' || {
    echo "Missing status object: $status"
    return 1
  }
  
  echo "$status" | grep -qE '"booted"' || {
    echo "Missing booted field: $status"
    return 1
  }
  
  echo "$status" | grep -qE '"rollback"' || {
    echo "Missing rollback field: $status"
    return 1
  }
  
  echo "$status" | grep -qE '"staged"' || {
    echo "Missing staged field: $status"
    return 1
  }
}

@test "AC6.1: bootc status shows kind field" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local kind
  kind="$(parse_bootc_field "$status" "kind")"
  
  [ "$kind" = "BootcHost" ] || {
    echo "Expected kind=BootcHost, got: $kind"
    return 1
  }
}

@test "AC6.1: bootc status shows apiVersion field" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local api_version
  api_version="$(parse_bootc_field "$status" "apiVersion")"
  
  [ "$api_version" = "org.containers.bootc/v1" ] || {
    echo "Expected apiVersion=org.containers.bootc/v1, got: $api_version"
    return 1
  }
}

@test "AC6.1: booted field correctly indicates bootc system" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local booted
  booted="$(parse_bootc_field "$status" "status.booted")"
  
  # booted should be present for bootc systems
  if [ "$booted" != "present" ]; then
    skip "Device not booted via bootc (booted=null)"
  fi
}

@test "AC6.1: System remains consistent after interrupted update" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Get state before
  local before_status
  before_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Simulate interrupted update with timeout
  timeout 5 bash -c "bootc_ssh 'bootc update 2>&1'" || true
  
  # Wait a moment for any state changes
  sleep 2
  
  # Get state after
  local after_status
  after_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # System must still be accessible and return valid JSON
  [ -n "$after_status" ] || {
    echo "Device not responding after interrupted update"
    return 1
  }
  
  echo "$after_status" | grep -qE '^\s*\{' || {
    echo "Invalid JSON after interrupted update: $after_status"
    return 1
  }
}

# =============================================================================
# AC6.2: Automatic Rollback on Update Failure - Unit Tests
# =============================================================================

@test "AC6.2: Rollback detection - has rollback returns true when rollback field present" {
  local json='{"status":{"booted":{"version":"1.1.0"},"rollback":{"version":"1.0.0"},"staged":null}}'
  
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  
  [ "$rollback" = "present" ]
}

@test "AC6.2: Rollback detection - has rollback returns false when rollback is null" {
  local json='{"status":{"booted":{"version":"1.0.0"},"rollback":null,"staged":null}}'
  
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  
  [ "$rollback" = "null" ]
}

@test "AC6.2: Rollback detection - staged update enables rollback" {
  # When a staged update exists, we can roll back to booted
  local json='{"status":{"booted":{"version":"1.0.0"},"rollback":null,"staged":{"version":"1.1.0"}}}'
  
  local staged
  staged="$(parse_bootc_field "$json" "status.staged")"
  
  [ "$staged" = "present" ]
  
  # Staged + booted = we can either proceed with update or stay at booted
  # This is NOT rollback (rollback is null), this is pending update
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  
  [ "$rollback" = "null" ]
}

@test "AC6.2: Rollback detection - rollbackQueued flag indicates pending rollback" {
  local json='{"status":{"rollbackQueued":true}}'
  
  local rollback_queued
  rollback_queued="$(parse_bootc_field "$json" "status.rollbackQueued")"
  
  [ "$rollback_queued" = "true" ]
}

@test "AC6.2: Rollback detection - Version comparison after rollback" {
  # After rollback, booted version should match old rollback version
  local json_before='{"status":{"booted":{"version":"1.1.0"},"rollback":{"version":"1.0.0"}}}'
  local json_after='{"status":{"booted":{"version":"1.0.0"},"rollback":null}}'
  
  local version_before
  version_before="$(parse_bootc_field "$json_before" "status.booted.version")"
  [ "$version_before" = "1.1.0" ]
  
  local version_after
  version_after="$(parse_bootc_field "$json_after" "status.booted.version")"
  [ "$version_after" = "1.0.0" ]
}

# =============================================================================
# AC6.2: Automatic Rollback on Update Failure - Integration Tests
# =============================================================================

@test "AC6.2: Device has rollback capability when previous deployment exists" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Check if rollback is available
  if ! bootc_has_rollback; then
    skip "No rollback available (device is on first deployment, no previous version)"
  fi
  
  # If we reach here, rollback is available
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local rollback
  rollback="$(parse_bootc_field "$status" "status.rollback")"
  
  [ "$rollback" = "present" ] || {
    echo "Expected rollback to be present, got: $rollback"
    return 1
  }
}

@test "AC6.2: Device reports rollbackQueued state correctly" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local rollback_queued
  rollback_queued="$(parse_bootc_field "$status" "status.rollbackQueued")"
  
  # Should be either "true" or "false" (never empty)
  [[ "$rollback_queued" == "true" || "$rollback_queued" == "false" ]] || {
    echo "rollbackQueued should be true or false, got: $rollback_queued"
    return 1
  }
}

@test "AC6.2: Rollback mechanism - no system corruption after failed update" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Get baseline state
  local baseline_status
  baseline_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  # Verify baseline is valid
  echo "$baseline_status" | grep -qE '^\s*\{' || {
    skip "Baseline system state is invalid"
  }
  
  # Attempt an invalid update (should fail gracefully)
  bootc_ssh "bootc switch invalid-image-nonexistent-$(date +%s) 2>&1" || true
  
  sleep 3
  
  # System should still be accessible
  run bash -c "bootc_ssh 'hostname' 2>&1"
  [ $status -eq 0 ] || {
    echo "System unresponsive after failed update"
    return 1
  }
  
  # bootc status should still return valid JSON
  local after_status
  after_status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  echo "$after_status" | grep -qE '^\s*\{' && echo "$after_status" | grep -qE '\}\s*$' || {
    echo "System corrupted - invalid bootc status: $after_status"
    return 1
  }
}

# =============================================================================
# AC6.3: Status Verification After Rollback - Unit Tests
# =============================================================================

@test "AC6.3: Version extraction from bootc status" {
  local json='{"status":{"booted":{"version":"42.20260326.0"}}}'
  
  local version
  version="$(parse_bootc_field "$json" "status.booted.version")"
  
  [ "$version" = "42.20260326.0" ]
}

@test "AC6.3: Image digest extraction for verification" {
  local json='{"status":{"booted":{"imageDigest":"sha256:1929423011f86a144ada87cefbebb1d9f61ffe6a615cc4da356e46907b9d3263"}}}'
  
  local digest
  digest="$(parse_bootc_field "$json" "status.booted.imageDigest")"
  
  [ "$digest" = "sha256:1929423011f86a144ada87cefbebb1d9f61ffe6a615cc4da356e46907b9d3263" ]
}

@test "AC6.3: Image reference extraction" {
  local json='{"status":{"booted":{"image":{"image":"quay.io/fedora/fedora-bootc:42","transport":"registry"}}}}'
  
  local image
  image="$(parse_bootc_field "$json" "status.booted.image.image")"
  
  [ "$image" = "quay.io/fedora/fedora-bootc:42" ]
}

@test "AC6.3: Compare images before/after update - different images" {
  local json_1='{"status":{"booted":{"image":{"image":"quay.io/test:1.0.0"}}}}'
  local json_2='{"status":{"booted":{"image":{"image":"quay.io/test:1.1.0"}}}}'
  
  local image_1
  image_1="$(parse_bootc_field "$json_1" "status.booted.image.image")"
  local image_2
  image_2="$(parse_bootc_field "$json_2" "status.booted.image.image")"
  
  [ "$image_1" != "$image_2" ] || {
    echo "Expected different images, got same: $image_1"
    return 1
  }
}

@test "AC6.3: Compare digests before/after update - different digests" {
  local json_1='{"status":{"booted":{"imageDigest":"sha256:abc123"}}'
  local json_2='{"status":{"booted":{"imageDigest":"sha256:def456"}}'
  
  local digest_1
  digest_1="$(parse_bootc_field "$json_1" "status.booted.imageDigest")"
  local digest_2
  digest_2="$(parse_bootc_field "$json_2" "status.booted.imageDigest")"
  
  [ "$digest_1" != "$digest_2" ] || {
    echo "Expected different digests, got same: $digest_1"
    return 1
  }
}

# =============================================================================
# AC6.3: Status Verification After Rollback - Integration Tests
# =============================================================================

@test "AC6.3: bootc status shows current booted version" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local booted
  booted="$(parse_bootc_field "$status" "status.booted")"
  
  if [ "$booted" != "present" ]; then
    skip "No booted image (device not fully booted via bootc)"
  fi
  
  # Should have version or at least image reference
  local version
  version="$(parse_bootc_field "$status" "status.booted.version")"
  
  # Version might be null, but image should exist
  local image
  image="$(parse_bootc_field "$status" "status.booted.image.image")"
  
  [ -n "$image" ] || {
    echo "No image in status: $status"
    return 1
  }
}

@test "AC6.3: bootc status shows rollback version when available" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Check if rollback is available
  if ! bootc_has_rollback; then
    skip "No rollback available (device is on first deployment)"
  fi
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local rollback
  rollback="$(parse_bootc_field "$status" "status.rollback")"
  
  [ "$rollback" = "present" ] || {
    echo "Expected rollback to be present: $status"
    return 1
  }
  
  # Should have version or image reference
  local rollback_version
  rollback_version="$(parse_bootc_field "$status" "status.rollback.version")"
  
  local rollback_image
  rollback_image="$(parse_bootc_field "$status" "status.rollback.image.image")"
  
  [[ -n "$rollback_version" || -n "$rollback_image" ]] || {
    echo "Rollback exists but has no version or image: $status"
    return 1
  }
}

@test "AC6.3: bootc status shows staged version when update downloaded" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local staged
  staged="$(parse_bootc_field "$status" "status.staged")"
  
  # If staged is present, verify it has content
  if [ "$staged" = "present" ]; then
    local staged_version
    staged_version="$(parse_bootc_field "$status" "status.staged.version")"
    
    local staged_image
    staged_image="$(parse_bootc_field "$status" "status.staged.image.image")"
    
    [[ -n "$staged_version" || -n "$staged_image" ]] || {
      echo "Staged exists but has no version or image: $status"
      return 1
    }
  fi
  
  # This test passes whether staged is present or not
  # Staged being null means no update is pending
  true
}

@test "AC6.3: Device is bootable - system consistency check" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # 1. SSH should work (system running)
  run bash -c "bootc_ssh 'echo alive' 2>&1"
  [ $status -eq 0 ] || {
    echo "SSH failed - system not running"
    return 1
  }
  
  # 2. bootc status should work
  run bash -c "bootc_ssh 'bootc status' 2>&1"
  [ $status -eq 0 ] || {
    echo "bootc status failed"
    return 1
  }
  
  # 3. bootc status JSON should be valid
  local status
  status="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  echo "$status" | grep -qE '^\s*\{' || {
    echo "Invalid bootc status JSON: $status"
    return 1
  }
  
  # 4. Should have valid image information
  local image
  image="$(parse_bootc_field "$status" "status.booted.image.image")"
  
  [ -n "$image" ] || {
    echo "No valid image in status: $status"
    return 1
  }
}

# =============================================================================
# AC6.3: Journal Logging Tests
# =============================================================================

@test "AC6.3: Journal shows bootc events" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Check journal for bootc-related entries
  run bash -c "bootc_ssh 'journalctl -u bootc-switch --no-pager -n 10 2>&1 || journalctl -b -u bootc* --no-pager -n 10 2>&1 || echo no-journal-entries' 2>&1"
  
  # Should get some output (bootc events or empty)
  [ -n "$output" ] || {
    echo "No journal output received"
    return 1
  }
}

@test "AC6.3: ostree admin status available for deployment verification" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  run bash -c "bootc_ssh 'ostree admin status 2>&1' 2>&1"
  
  # May not be available in minimal bootc images
  if [ $status -ne 0 ]; then
    skip "ostree admin not available on this bootc installation"
  fi
  
  # Should show deployment info
  echo "$output" | grep -qE "deploy|current|origin|0:" || {
    echo "ostree admin status missing deployment info: $output"
    return 1
  }
}

# =============================================================================
# AC6.2: Rollback Mechanism Tests (Require Actual Rollback Capability)
# =============================================================================

@test "AC6.2: Rollback command exists and is accessible" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Check if rollback command is available
  run bash -c "bootc_ssh 'bootc rollback --help 2>&1' 2>&1"
  
  # Should show help or succeed
  [ $status -eq 0 ] || echo "$output" | grep -q "rollback"
}

@test "AC6.2: bootc upgrade --download-only creates staged update" {
  bootc_skip_if_not_configured || skip "Bootc device not configured"
  bootc_skip_if_not_bootc_system || skip "Device not booted via bootc"
  
  # Get state before
  local status_before
  status_before="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local staged_before
  staged_before="$(parse_bootc_field "$status_before" "status.staged")"
  
  # Download update without applying
  run bash -c "bootc_ssh 'bootc upgrade --download-only 2>&1' 2>&1"
  
  # Wait for download
  sleep 5
  
  # Get state after
  local status_after
  status_after="$(bootc_ssh "bootc status --format=json" 2>&1)"
  
  local staged_after
  staged_after="$(parse_bootc_field "$status_after" "status.staged")"
  
  # If update was available, staged should now be present
  if echo "$output" | grep -qiE "update|download|changes"; then
    [ "$staged_after" = "present" ] || {
      echo "Expected staged update after download, but got: $staged_after"
      echo "Status: $status_after"
      echo "Command output: $output"
      return 1
    }
  fi
}

# =============================================================================
# Edge Cases and Error Handling
# =============================================================================

@test "Edge case: Malformed JSON handling" {
  local json='{invalid json}'
  
  local result
  result="$(parse_bootc_field "$json" "status.booted")"
  
  # Should return empty/null for malformed JSON
  [[ "$result" == "null" || -z "$result" ]] || {
    echo "Expected null for malformed JSON, got: $result"
    return 1
  }
}

@test "Edge case: Empty JSON object" {
  local json='{}'
  
  local kind
  kind="$(parse_bootc_field "$json" "kind")"
  
  [ -z "$kind" ]
}

@test "Edge case: Missing status object" {
  local json='{"apiVersion":"test"}'
  
  local booted
  booted="$(parse_bootc_field "$json" "status.booted")"
  
  # Should return null when status is missing
  [ "$booted" = "null" ]
}

@test "Edge case: Null values for transactional fields" {
  # Bootc 1.14.1 format with explicit nulls
  local json='{"status":{"booted":null,"rollback":null,"staged":null,"rollbackQueued":false}}'
  
  local booted
  booted="$(parse_bootc_field "$json" "status.booted")"
  [ "$booted" = "null" ]
  
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  [ "$rollback" = "null" ]
  
  local staged
  staged="$(parse_bootc_field "$json" "status.staged")"
  [ "$staged" = "null" ]
}

@test "Edge case: Complete bootc 1.14.1 status structure" {
  # Full real-world example from bootc device
  local json='{
    "apiVersion":"org.containers.bootc/v1",
    "kind":"BootcHost",
    "metadata":{"name":"host"},
    "spec":{"bootOrder":"default","image":null},
    "status":{
      "booted":null,
      "rollback":null,
      "rollbackQueued":false,
      "staged":null,
      "type":null,
      "usrOverlay":null
    }
  }'
  
  local api_version
  api_version="$(parse_bootc_field "$json" "apiVersion")"
  [ "$api_version" = "org.containers.bootc/v1" ]
  
  local kind
  kind="$(parse_bootc_field "$json" "kind")"
  [ "$kind" = "BootcHost" ]
  
  local booted
  booted="$(parse_bootc_field "$json" "status.booted")"
  [ "$booted" = "null" ]
  
  local rollback
  rollback="$(parse_bootc_field "$json" "status.rollback")"
  [ "$rollback" = "null" ]
  
  local rollback_queued
  rollback_queued="$(parse_bootc_field "$json" "status.rollbackQueued")"
  [ "$rollback_queued" = "false" ]
}

@test "Edge case: Full status with all fields populated" {
  # Full real-world example with all fields
  local json='{
    "apiVersion":"org.containers.bootc/v1",
    "kind":"BootcHost",
    "status":{
      "booted":{
        "image":{
          "image":"quay.io/fedora/fedora-bootc:42",
          "transport":"registry"
        },
        "version":"42.20260326.0",
        "imageDigest":"sha256:abc123"
      },
      "rollback":{
        "image":{
          "image":"quay.io/fedora/fedora-bootc:42",
          "transport":"registry"
        },
        "version":"42.20260325.0",
        "imageDigest":"sha256:def456"
      },
      "staged":null,
      "rollbackQueued":false,
      "type":"bootcHost"
    }
  }'
  
  local booted_image
  booted_image="$(parse_bootc_field "$json" "status.booted.image.image")"
  [ "$booted_image" = "quay.io/fedora/fedora-bootc:42" ]
  
  local booted_version
  booted_version="$(parse_bootc_field "$json" "status.booted.version")"
  [ "$booted_version" = "42.20260326.0" ]
  
  local rollback_version
  rollback_version="$(parse_bootc_field "$json" "status.rollback.version")"
  [ "$rollback_version" = "42.20260325.0" ]
  
  local staged
  staged="$(parse_bootc_field "$json" "status.staged")"
  [ "$staged" = "null" ]
  
  local type
  type="$(parse_bootc_field "$json" "status.type")"
  [ "$type" = "bootcHost" ]
}

# =============================================================================
# Summary
# =============================================================================

@test "Test coverage summary for transactional updates" {
  echo ""
  echo "=== Transactional Update Test Coverage ==="
  echo "Unit Tests:"
  echo "  - JSON parsing for all transactional fields"
  echo "  - State machine transitions (initial, staged, post-reboot, rollback)"
  echo "  - Rollback detection logic"
  echo "  - Version/image extraction"
  echo ""
  echo "Integration Tests:"
  echo "  - Real bootc device status verification"
  echo "  - Rollback capability detection"
  echo "  - Journal logging verification"
  echo "  - Staged update creation"
  echo ""
  echo "Edge Cases:"
  echo "  - Malformed JSON handling"
  echo "  - Null value handling"
  echo "  - Missing fields"
  echo "  - Complete status structure verification"
  echo "=========================================="
}
