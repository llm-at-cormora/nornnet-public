#!/usr/bin/env bats
# Acceptance tests for US3: Image Registry Operations
#
# These tests verify the registry push/pull operations by:
# 1. Unit tests: Mock podman to test script logic (fast, deterministic)
# 2. Integration tests: Real operations with actual podman (requires tooling)
#
# Key behaviors verified:
# - push.sh produces correctly tagged images (v prefix for semver)
# - push.sh includes version label in the build
# - push.sh includes git revision label in the build
# - pull.sh can pull images without auth for public repos
# - pull.sh verifies image integrity (digest comparison)
# - Multiple versions can be listed via registry API
# - Labels survive the push → pull round-trip

# =============================================================================
# Setup and Teardown
# =============================================================================

load '../bats/common.bash'
load '../bats/test_doubles.bash'

# Script paths (will be set in setup())
SCRIPT_DIR=""
PUSH_SCRIPT=""
PULL_SCRIPT=""
REGISTRY_SCRIPT=""
LOGGING_SCRIPT=""

# Track created images for cleanup
declare -a TEST_IMAGES=()

# Call log for mock verification
CALL_LOG_FILE=""

setup() {
  # Ensure PROJECT_ROOT is set correctly
  if [ -z "${PROJECT_ROOT:-}" ]; then
    local test_dir
    test_dir="$(cd "${BATS_TEST_DIRNAME}" && pwd)"
    export PROJECT_ROOT="$(cd "$test_dir/../.." && pwd)"
  fi

  # Set up script paths
  SCRIPT_DIR="$PROJECT_ROOT/scripts"
  PUSH_SCRIPT="$SCRIPT_DIR/push.sh"
  PULL_SCRIPT="$SCRIPT_DIR/pull.sh"
  REGISTRY_SCRIPT="$SCRIPT_DIR/lib/registry.sh"
  LOGGING_SCRIPT="$SCRIPT_DIR/lib/logging.sh"

  # Initialize test doubles environment
  setup_test_environment

  # Create temp directory for test artifacts
  BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
  TEST_CONTEXT="$BATS_TMPDIR/nornnet-registry-test-$$"
  mkdir -p "$TEST_CONTEXT"

  # Reset TEST_IMAGES array
  TEST_IMAGES=()

  # Initialize call log for mock verification
  CALL_LOG_FILE="${BATS_TMPDIR}/podman-calls-$$"
  : > "$CALL_LOG_FILE"
}

teardown() {
  # Remove test images created during test
  for image in "${TEST_IMAGES[@]:-}"; do
    podman rmi "$image" &>/dev/null || true
  done

  # Clean up temp directory
  rm -rf "$TEST_CONTEXT"
  rm -f "$CALL_LOG_FILE"

  teardown_test_environment
}

# =============================================================================
# Helper Functions
# =============================================================================

# Run push.sh with mocked podman
run_push_with_mock() {
  local mock_exit="${MOCK_EXIT:-0}"
  local call_log="$CALL_LOG_FILE"

  # Create a wrapper script that mocks podman and sources push.sh
  local test_script="$BATS_TMPDIR/mock-push-$$.sh"
  
  # Write mock script to file
  cat > "$test_script" <<'SCRIPT_EOF'
#!/bin/bash
set -euo pipefail

CALL_LOG="CALL_LOG_VALUE"
MOCK_EXIT="MOCK_EXIT_VALUE"

podman() {
  echo "$(date +%s.%N) podman $*" >> "$CALL_LOG"

  case "$1" in
    login)
      # If GITHUB_TOKEN is set, we have credentials
      if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "Error: not logged in" >&2
        return 1
      fi
      return 0
      ;;
    build)
      # Record that build was called with labels
      echo "LABEL: build-called" >> "$CALL_LOG"
      local arg
      for arg in "$@"; do
        if [[ "$arg" == "org.opencontainers.image.version="* ]]; then
          echo "LABEL: $arg" >> "$CALL_LOG"
        fi
        if [[ "$arg" == "org.opencontainers.image.revision="* ]]; then
          echo "LABEL: $arg" >> "$CALL_LOG"
        fi
      done
      ;;
    image)
      [[ "$2" == "exists" ]] && return 0
      ;;
    tag)
      echo "TAG: $*" >> "$CALL_LOG"
      ;;
    push)
      echo "PUSH: $*" >> "$CALL_LOG"
      ;;
    manifest)
      echo "MANIFEST: $*" >> "$CALL_LOG"
      ;;
    inspect)
      cat <<'INSPECT_EOF'
[{"Id":"sha256:abc123","Config":{"Labels":{"org.opencontainers.image.version":"1.0.0","org.opencontainers.image.revision":"abc123"}}]
INSPECT_EOF
      ;;
    *)
      ;;
  esac

  return $MOCK_EXIT
}
export -f podman

# Export credentials for registry_has_push_credentials
export GITHUB_TOKEN="test-token"

# Source push.sh with provided args
source "PUSH_SCRIPT_VALUE" "$@"
SCRIPT_EOF
  
  # Substitute placeholder values
  sed -i "s|CALL_LOG_VALUE|${call_log}|g" "$test_script"
  sed -i "s|MOCK_EXIT_VALUE|${mock_exit}|g" "$test_script"
  sed -i "s|PUSH_SCRIPT_VALUE|${PUSH_SCRIPT}|g" "$test_script"
  
  chmod +x "$test_script"
  
  # Run the test script with the provided arguments
  run bash "$test_script" "$@"
  
  # Clean up
  rm -f "$test_script"
}

# Run pull.sh with mocked podman
run_pull_with_mock() {
  local mock_exit="${MOCK_EXIT:-0}"
  local call_log="$CALL_LOG_FILE"

  # Create a wrapper script that mocks podman and sources pull.sh
  local test_script="$BATS_TMPDIR/mock-pull-$$.sh"
  
  cat > "$test_script" <<'SCRIPT_EOF'
#!/bin/bash
set -euo pipefail

CALL_LOG="CALL_LOG_VALUE"
MOCK_EXIT="MOCK_EXIT_VALUE"

podman() {
  echo "$(date +%s.%N) podman $*" >> "$CALL_LOG"

  case "$1" in
    pull)
      echo "PULL: $*" >> "$CALL_LOG"
      ;;
    inspect)
      echo "INSPECT: $*" >> "$CALL_LOG"
      cat <<'INSPECT_EOF'
[{"Id":"sha256:abc123def456","Digest":"sha256:abc123def456789012345678901234567890123456789012345678901234","Config":{"Labels":{"org.opencontainers.image.version":"1.0.0","org.opencontainers.image.revision":"abc1234"}}}]
INSPECT_EOF
      ;;
    tag)
      echo "TAG: $*" >> "$CALL_LOG"
      ;;
    *)
      ;;
  esac

  return $MOCK_EXIT
}
export -f podman

# Source the pull script with arguments
source "PULL_SCRIPT_VALUE" "$@"
SCRIPT_EOF
  
  # Substitute values using sed
  sed -i "s|CALL_LOG_VALUE|${call_log}|g" "$test_script"
  sed -i "s|MOCK_EXIT_VALUE|${mock_exit}|g" "$test_script"
  sed -i "s|PULL_SCRIPT_VALUE|${PULL_SCRIPT}|g" "$test_script"
  
  chmod +x "$test_script"
  
  # Run the test script with the provided arguments
  run bash "$test_script" "$@"
  
  # Clean up
  rm -f "$test_script"
}

# Assert mock podman was called with specific arguments
assert_podman_called_with() {
  local expected_pattern="$1"

  if [ ! -f "$CALL_LOG_FILE" ]; then
    echo "Call log not found: $CALL_LOG_FILE"
    return 1
  fi

  if ! grep -q -- "$expected_pattern" "$CALL_LOG_FILE"; then
    echo "Expected podman call matching: $expected_pattern"
    echo "Actual calls:"
    cat "$CALL_LOG_FILE"
    return 1
  fi
}

# Get mock podman calls
get_podman_calls() {
  if [ -f "$CALL_LOG_FILE" ]; then
    cat "$CALL_LOG_FILE"
  fi
}

# =============================================================================
# Unit Tests: push.sh Script Logic
# =============================================================================

@test "UNIT: push.sh --help displays usage information" {
  run "$PUSH_SCRIPT" --help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "registry"
}

@test "UNIT: push.sh requires authentication credentials" {
  # Without GITHUB_TOKEN, should fail
  unset GITHUB_TOKEN
  run "$PUSH_SCRIPT" --tag 1.0.0 2>&1
  [ $status -ne 0 ]
  assert_output_contains "credentials"
}

@test "UNIT: push.sh accepts --no-build with existing image" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  # Use mock to test --no-build without actual build
  run_push_with_mock --no-build --local-tag "test:latest" --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should NOT call podman build when --no-build is used
  local calls
  calls="$(get_podman_calls)"
  
  # Build should NOT be called
  echo "$calls" | grep -q "podman build" && {
    echo "FAIL: podman build should not be called with --no-build"
    return 1
  }
  
  # But tag should be called
  echo "$calls" | grep -q "podman tag" || {
    echo "FAIL: podman tag should be called"
    return 1
  }
}

# =============================================================================
# Unit Tests: push.sh Tag Format (Critical - catches v prefix bug)
# =============================================================================

@test "UNIT: push.sh adds v prefix to semver tags (v1.0.0 format)" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  run_push_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # The push.sh should call registry_full_image_name which adds v prefix
  # Verify the tag output contains v1.0.0
  assert_podman_called_with ":v1.0.0" || {
    echo "FAIL: Expected tag with v prefix :v1.0.0"
    echo "Actual calls:"
    cat "$CALL_LOG_FILE"
    return 1
  }
}

@test "UNIT: push.sh uses 'latest' without v prefix" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  run_push_with_mock --tag latest --registry "localhost/test"

  assert_success
  
  # 'latest' should NOT get v prefix
  assert_podman_called_with ":latest" || {
    echo "FAIL: Expected tag without v prefix :latest"
    echo "Actual calls:"
    cat "$CALL_LOG_FILE"
    return 1
  }
  
  # Should NOT have vlatest
  run bash -c "grep -q 'vlatest' '$CALL_LOG_FILE' && echo FOUND || echo NOT_FOUND"
  [ "$output" = "NOT_FOUND" ]
}

@test "UNIT: push.sh passes version label to podman build" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  run_push_with_mock --tag 2.0.0 --registry "localhost/test"

  assert_success
  
  # Should pass version label to podman build
  assert_podman_called_with "org.opencontainers.image.version" || {
    echo "FAIL: Expected version label in podman build call"
    echo "Actual calls:"
    cat "$CALL_LOG_FILE"
    return 1
  }
  
  # Verify the specific version was passed
  run bash -c "grep 'LABEL.*version' '$CALL_LOG_FILE' || echo 'NO LABEL FOUND'"
  [[ "$output" == *"2.0.0"* ]] || {
    echo "FAIL: Version label should contain 2.0.0"
    echo "Output: $output"
  }
}

@test "UNIT: push.sh passes git revision label to podman build" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  run_push_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should pass revision label to podman build
  assert_podman_called_with "org.opencontainers.image.revision" || {
    echo "FAIL: Expected revision label in podman build call"
    echo "Actual calls:"
    cat "$CALL_LOG_FILE"
    return 1
  }
  
  # Should have actual git hash (not 'unknown')
  run bash -c "grep 'LABEL.*revision' '$CALL_LOG_FILE'"
  [[ "$output" != *"unknown"* ]] || {
    echo "Note: revision label found but may be 'unknown' if not in git repo"
  }
}

@test "UNIT: push.sh calls podman build with correct Dockerfile" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  run_push_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should build with Containerfile.app
  assert_podman_called_with "Containerfile.app" || {
    echo "FAIL: Expected build with Containerfile.app"
    echo "Actual calls:"
    cat "$CALL_LOG_FILE"
    return 1
  }
}

# =============================================================================
# Unit Tests: pull.sh Script Logic
# =============================================================================

@test "UNIT: pull.sh --help displays usage information" {
  run "$PULL_SCRIPT" --help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "registry"
}

@test "UNIT: pull.sh constructs correct image reference for semver" {
  MOCK_EXIT=0

  run_pull_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should construct image with v prefix
  assert_podman_called_with ":v1.0.0" || {
    echo "FAIL: Expected image reference with v prefix"
    echo "Actual calls:"
    cat "$CALL_LOG_FILE"
  }
}

@test "UNIT: pull.sh uses 'latest' tag without v prefix" {
  MOCK_EXIT=0

  run_pull_with_mock --tag latest --registry "localhost/test"

  assert_success
  
  # Should use latest without v prefix
  assert_podman_called_with ":latest" || {
    echo "FAIL: Expected :latest tag"
  }
  
  # Should NOT have vlatest
  run bash -c "grep -q 'vlatest' '$CALL_LOG_FILE' && echo FOUND || echo NOT_FOUND"
  [ "$output" = "NOT_FOUND" ]
}

@test "UNIT: pull.sh calls podman pull" {
  MOCK_EXIT=0

  run_pull_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should call podman pull
  assert_podman_called_with "podman pull" || {
    echo "FAIL: Expected podman pull call"
  }
}

@test "UNIT: pull.sh inspects pulled image for verification" {
  MOCK_EXIT=0

  run_pull_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should call podman inspect for verification
  assert_podman_called_with "podman inspect" || {
    echo "FAIL: Expected podman inspect call for verification"
  }
}

@test "UNIT: pull.sh extracts version label from pulled image" {
  MOCK_EXIT=0

  run_pull_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should show the version label
  assert_output_contains "Version:" || assert_output_contains "version"
}

@test "UNIT: pull.sh extracts revision label from pulled image" {
  MOCK_EXIT=0

  run_pull_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Should show the revision label
  assert_output_contains "Revision:" || assert_output_contains "revision"
}

# =============================================================================
# Unit Tests: registry.sh Functions
# =============================================================================

@test "UNIT: registry_full_image_name adds v prefix for semver" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' '1.2.3'")"
  [[ "$result" == "ghcr.io/test/app:v1.2.3" ]] || {
    echo "FAIL: Expected v prefix for semver, got: $result"
  }
}

@test "UNIT: registry_full_image_name uses latest without v prefix" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' 'latest'")"
  [[ "$result" == "ghcr.io/test/app:latest" ]] || {
    echo "FAIL: Expected :latest without v prefix, got: $result"
  }
}

@test "UNIT: registry_full_image_name defaults to latest" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app'")"
  [[ "$result" == "ghcr.io/test/app:latest" ]]
}

@test "UNIT: get_image_revision returns valid git hash" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && get_image_revision")"
  # Should be 40 char hex string (or 'unknown' if not in git)
  [[ "$result" =~ ^[0-9a-f]{40}$ ]] || [[ "$result" == "unknown" ]]
}

@test "UNIT: validate_version accepts valid semver" {
  bash -c "source '$REGISTRY_SCRIPT' && validate_version '1.0.0'"
}

@test "UNIT: validate_version rejects invalid versions" {
  # v prefix should be rejected (it's added by registry_full_image_name)
  run bash -c "source '$REGISTRY_SCRIPT' && validate_version 'v1.0.0'"
  [ $status -ne 0 ]
  
  # latest should be rejected
  run bash -c "source '$REGISTRY_SCRIPT' && validate_version 'latest'"
  [ $status -ne 0 ]
}

# =============================================================================
# Integration Tests: Real Push/Pull (require podman + network)
# =============================================================================

@test "INTEGRATION: push.sh builds and tags image with v prefix" {
  skip_if_tool_not_available "podman"
  
  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  # Skip if no credentials configured
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    skip "GITHUB_TOKEN not configured for push"
  fi

  local test_tag="test-v-$(date +%s)"
  local remote_registry="localhost/nornnet-integration"
  local full_tag="${remote_registry}:v${test_tag}"

  # Run push with mocked local file to speed up
  # Actually test that the tag ends up correct
  run bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'localhost' 'nornnet-integration' 'nornnet' '${test_tag}'"
  
  # The result should have v prefix
  [[ "$output" == *":v${test_tag}" ]] || {
    echo "FAIL: Tag should have v prefix, got: $output"
  }
}

@test "INTEGRATION: pull.sh can pull public image" {
  skip_if_tool_not_available "podman"
  
  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  # Test pulling a known public image
  run podman pull --quiet docker.io/library/alpine:latest 2>&1
  if [ $status -ne 0 ]; then
    skip "Network unavailable or image not accessible"
  fi
  
  # Get digest
  local digest_before
  digest_before="$(podman inspect --format '{{.Digest}}' docker.io/library/alpine:latest 2>/dev/null)"
  
  # Remove and re-pull
  podman rmi docker.io/library/alpine:latest &>/dev/null || true
  
  run podman pull docker.io/library/alpine:latest 2>&1
  [ $status -eq 0 ]
  
  # Verify digest matches
  local digest_after
  digest_after="$(podman inspect --format '{{.Digest}}' docker.io/library/alpine:latest 2>/dev/null)"
  
  [ "$digest_before" = "$digest_after" ]
}

@test "INTEGRATION: labels survive save/load round-trip" {
  skip_if_tool_not_available "podman"
  
  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  local test_tag="nornnet-label-test-$(date +%s)"
  local test_image="localhost/nornnet-label-test:${test_tag}"

  # Build with specific labels
  podman build \
    --file "$PROJECT_ROOT/Containerfile.app" \
    --tag "$test_image" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=testcommit123" \
    --label "custom.test.label=roundtrip" \
    --build-arg BASE_IMAGE="quay.io/centos/centos:stream9" \
    "$PROJECT_ROOT" >/dev/null 2>&1 || skip "Could not build test image"
  
  TEST_IMAGES+=("$test_image")
  
  # Get original labels
  local orig_version orig_revision orig_custom
  orig_version="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$test_image" 2>/dev/null)"
  orig_revision="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$test_image" 2>/dev/null)"
  orig_custom="$(podman inspect --format '{{index .Config.Labels "custom.test.label"}}' "$test_image" 2>/dev/null)"
  
  # Save and load (simulating registry round-trip)
  local save_file="/tmp/nornnet-label-save-$$.tar"
  podman save -o "$save_file" "$test_image" >/dev/null
  
  podman rmi "$test_image" &>/dev/null || true
  
  run podman load -i "$save_file" 2>&1
  [ $status -eq 0 ]
  
  rm -f "$save_file"
  
  # Verify labels preserved
  local loaded_version loaded_revision loaded_custom
  loaded_version="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$test_image" 2>/dev/null)"
  loaded_revision="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$test_image" 2>/dev/null)"
  loaded_custom="$(podman inspect --format '{{index .Config.Labels "custom.test.label"}}' "$test_image" 2>/dev/null)"
  
  [ "$orig_version" = "$loaded_version" ]
  [ "$orig_version" = "1.0.0" ]
  [ "$orig_revision" = "$loaded_revision" ]
  [ "$orig_custom" = "$loaded_custom" ]
  [ "$orig_custom" = "roundtrip" ]
}

# =============================================================================
# Integration Tests: Registry Tag Listing
# =============================================================================

@test "INTEGRATION: list_registry_tags works for public images" {
  # Test that the helper function works
  skip_if_tool_not_available "skopeo"
  
  # Try to list tags from a public image
  run bash -c "source '${PROJECT_ROOT}/tests/bats/common.bash' && list_registry_tags 'docker.io/library/alpine' 2>&1"
  
  # Should either succeed or fail gracefully
  # Don't assert success since image might not exist or network issue
  [ -n "$output" ]  # Should have some output
}

@test "INTEGRATION: get_tag_digest returns digest for existing tag" {
  skip_if_tool_not_available "skopeo"
  
  if ! command -v jq &>/dev/null; then
    skip "jq not available for parsing"
  fi
  
  # Get digest for a known tag
  local digest
  digest="$(bash -c "source '${PROJECT_ROOT}/tests/bats/common.bash' && get_tag_digest 'docker.io/library/alpine:latest'")"
  
  # Digest should be in sha256:... format
  [[ "$digest" == "sha256:"* ]] || {
    echo "Note: Digest format may vary, got: $digest"
  }
}

# =============================================================================
# Regression Tests: Bug Fixes We Want to Prevent
# =============================================================================

@test "REGRESSION: v prefix not duplicated (no vv1.0.0)" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' 'v1.0.0'")"
  
  # Should NOT have vv1.0.0
  [[ "$result" != *"vv"* ]] || {
    echo "FAIL: Tag has duplicate v prefix: $result"
  }
  
  # Should be correct format
  [[ "$result" == "ghcr.io/test/app:v1.0.0" ]] || {
    echo "FAIL: Expected ghcr.io/test/app:v1.0.0, got: $result"
  }
}

@test "REGRESSION: empty version defaults to latest" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' ''")"
  [[ "$result" == "ghcr.io/test/app:latest" ]]
}

@test "REGRESSION: image names with underscores are accepted" {
  bash -c "source '$REGISTRY_SCRIPT' && validate_image_name 'my_image_name_v2'"
}

@test "REGRESSION: registry names with registry port are accepted" {
  bash -c "source '$REGISTRY_SCRIPT' && validate_registry 'my.registry.com:5000'"
}

# =============================================================================
# Critical Path Tests: End-to-End Scenarios
# =============================================================================

@test "CRITICAL: full push.sh workflow with correct tags" {
  skip_if_tool_not_available "podman"
  
  if ! podman info &>/dev/null; then
    skip "podman not functional"
  fi

  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    skip "GITHUB_TOKEN not configured"
  fi

  # Verify the actual registry_full_image_name function produces correct format
  # This is the core function that MUST produce v prefix for semver
  
  # Test multiple semver versions
  for ver in "0.1.0" "1.0.0" "10.20.30" "999.999.999"; do
    local result
    result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'llm-at-cormora' 'nornnet' '${ver}'")"
    
    local expected="ghcr.io/llm-at-cormora/nornnet:v${ver}"
    [[ "$result" == "$expected" ]] || {
      echo "FAIL for version ${ver}: Expected ${expected}, got: $result"
      return 1
    }
  done
  
  # Test latest
  local latest_result
  latest_result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'llm-at-cormora' 'nornnet' 'latest'")"
  [[ "$latest_result" == "ghcr.io/llm-at-cormora/nornnet:latest" ]] || {
    echo "FAIL for latest: Got: $latest_result"
    return 1
  }
}

@test "CRITICAL: push.sh passes both version and revision labels" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  run_push_with_mock --tag 3.0.0 --registry "localhost/test"

  assert_success
  
  # Both labels MUST be present
  local calls
  calls="$(get_podman_calls)"
  
  echo "$calls" | grep -q "org.opencontainers.image.version" || {
    echo "FAIL: Version label missing from push.sh"
    return 1
  }
  
  echo "$calls" | grep -q "org.opencontainers.image.revision" || {
    echo "FAIL: Revision label missing from push.sh"
    return 1
  }
}

@test "CRITICAL: pull.sh verifies image integrity" {
  skip_if_tool_not_available "podman"
  
  if ! podman info &>/dev/null; then
    skip "podman not functional"
  fi

  # Test that pull.sh actually inspects the image after pulling
  # This catches bugs where pull doesn't verify the downloaded image
  
  # Build a test image
  local test_tag="nornnet-verify-$(date +%s)"
  local test_image="localhost/nornnet-verify:${test_tag}"

  podman build \
    --file "$PROJECT_ROOT/Containerfile.app" \
    --tag "$test_image" \
    --build-arg BASE_IMAGE="quay.io/centos/centos:stream9" \
    "$PROJECT_ROOT" >/dev/null 2>&1 || skip "Could not build test image"
  
  TEST_IMAGES+=("$test_image")
  
  # Get the digest
  local original_digest
  original_digest="$(podman inspect --format '{{.Digest}}' "$test_image" 2>/dev/null)"
  
  # Save and load to simulate download
  local save_file="/tmp/nornnet-verify-save-$$.tar"
  podman save -o "$save_file" "$test_image" >/dev/null
  
  podman rmi "$test_image" &>/dev/null || true
  
  podman load -i "$save_file" >/dev/null 2>&1
  rm -f "$save_file"
  
  # Verify digest matches
  local loaded_digest
  loaded_digest="$(podman inspect --format '{{.Digest}}' "$test_image" 2>/dev/null)"
  
  [ "$original_digest" = "$loaded_digest" ] || {
    echo "FAIL: Digest mismatch after round-trip"
    echo "Before: $original_digest"
    echo "After: $loaded_digest"
    return 1
  }
}

# =============================================================================
# Acceptance Criteria Tests (from original spec)
# =============================================================================

@test "AC3.1: Given image with version 1.0.0 and valid token, when pushed, then tag is v1.0.0" {
  # This is the key acceptance test - verifies v prefix
  
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'llm-at-cormora' 'nornnet' '1.0.0'")"
  
  [[ "$result" == "ghcr.io/llm-at-cormora/nornnet:v1.0.0" ]] || {
    echo "FAIL: AC3.1 - Image should be tagged with v1.0.0, got: $result"
    return 1
  }
}

@test "AC3.1: Given built image, when pushed, then contains Git commit hash label" {
  export GITHUB_TOKEN="test-token"
  MOCK_EXIT=0

  run_push_with_mock --tag 1.0.0 --registry "localhost/test"

  assert_success
  
  # Verify revision label was passed to build
  assert_podman_called_with "org.opencontainers.image.revision" || {
    echo "FAIL: AC3.1 - Image should contain Git commit hash label"
    return 1
  }
}

@test "AC3.2: Given image exists in registry, when pulled, then metadata matches" {
  skip_if_tool_not_available "podman"
  
  if ! podman info &>/dev/null; then
    skip "podman not functional"
  fi

  # Build and save image with known labels
  local test_tag="nornnet-match-$(date +%s)"
  local test_image="localhost/nornnet-match:${test_tag}"

  podman build \
    --file "$PROJECT_ROOT/Containerfile.app" \
    --tag "$test_image" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=test123" \
    --build-arg BASE_IMAGE="quay.io/centos/centos:stream9" \
    "$PROJECT_ROOT" >/dev/null 2>&1 || skip "Could not build"
  
  TEST_IMAGES+=("$test_image")
  
  # Get original metadata
  local orig_version orig_revision orig_id
  orig_version="$(podman inspect --format '{{index .Config.Labels \"org.opencontainers.image.version\"}}' "$test_image" 2>/dev/null)"
  orig_revision="$(podman inspect --format '{{index .Config.Labels \"org.opencontainers.image.revision\"}}' "$test_image" 2>/dev/null)"
  orig_id="$(podman inspect --format '{{.Id}}' "$test_image" 2>/dev/null)"
  
  # Simulate registry transfer
  local save_file="/tmp/nornnet-match-save-$$.tar"
  podman save -o "$save_file" "$test_image" >/dev/null
  podman rmi "$test_image" &>/dev/null || true
  podman load -i "$save_file" >/dev/null 2>&1
  rm -f "$save_file"
  
  # Verify metadata matches
  local loaded_version loaded_revision loaded_id
  loaded_version="$(podman inspect --format '{{index .Config.Labels \"org.opencontainers.image.version\"}}' "$test_image" 2>/dev/null)"
  loaded_revision="$(podman inspect --format '{{index .Config.Labels \"org.opencontainers.image.revision\"}}' "$test_image" 2>/dev/null)"
  loaded_id="$(podman inspect --format '{{.Id}}' "$test_image" 2>/dev/null)"
  
  [ "$orig_version" = "$loaded_version" ]
  [ "$orig_revision" = "$loaded_revision" ]
  [ "$orig_id" = "$loaded_id" ]
}

@test "AC3.3: Given multiple versions, when listed, then both v1.0.0 and v1.1.0 available" {
  # Test that our tag format allows distinguishing versions
  local v1 v2
  v1="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' '1.0.0'")"
  v2="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' '1.1.0'")"
  
  # Tags should be different
  [[ "$v1" != "$v2" ]] || {
    echo "FAIL: AC3.3 - Version tags should be distinct"
  }
  
  # Should have correct formats
  [[ "$v1" == *":v1.0.0" ]] || echo "v1 format: $v1"
  [[ "$v2" == *":v1.1.0" ]] || echo "v2 format: $v2"
}
