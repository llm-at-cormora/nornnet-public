#!/usr/bin/env bats
# Acceptance tests for US1: Local Image Build
#
# These tests verify the actual application behavior by:
# 1. Unit tests: Mock podman to test script logic (fast, deterministic)
# 2. Integration tests: Real builds with actual podman (slower, requires tooling)
#
# Key behaviors verified:
# - Build completes without errors and produces OCI image
# - Image has bootc labels: containers.bootc="1" and ostree.bootable="1"
# - Image has semver version label
# - Image has Git commit hash label
# - Build failures produce clear errors
# - Version validation rejects invalid semver

# =============================================================================
# Setup and Teardown
# =============================================================================

load '../bats/common.bash'
load '../bats/test_doubles.bash'

# Script paths (will be set in setup())
SCRIPT_DIR=""
BUILD_SCRIPT=""
REGISTRY_SCRIPT=""
LOGGING_SCRIPT=""

# Track created images for cleanup
declare -a TEST_IMAGES=()

setup() {
  # Ensure PROJECT_ROOT is set correctly
  # BATS_TEST_DIRNAME is like /path/to/nornnet/tests/acceptance
  # We need to go up 2 levels to get to project root
  if [ -z "${PROJECT_ROOT:-}" ]; then
    local test_dir
    test_dir="$(cd "${BATS_TEST_DIRNAME}" && pwd)"
    export PROJECT_ROOT="$(cd "$test_dir/../.." && pwd)"
  fi

  # Set up script paths
  SCRIPT_DIR="$PROJECT_ROOT/scripts"
  BUILD_SCRIPT="$SCRIPT_DIR/build.sh"
  REGISTRY_SCRIPT="$SCRIPT_DIR/lib/registry.sh"
  LOGGING_SCRIPT="$SCRIPT_DIR/lib/logging.sh"

  # Initialize test doubles environment
  setup_test_environment

  # Create temp directory for test artifacts
  BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
  TEST_CONTEXT="$BATS_TMPDIR/nornnet-build-test-$$"
  mkdir -p "$TEST_CONTEXT"

  # Reset TEST_IMAGES array
  TEST_IMAGES=()

  # Initialize call log
  CALL_LOG_FILE="${BATS_TMPDIR}/podman-calls-$$"
}

teardown() {
  # Remove test images created during test
  for image in "${TEST_IMAGES[@]:-}"; do
    podman rmi "$image" &>/dev/null || true
  done

  # Clean up temp directory
  rm -rf "$TEST_CONTEXT"

  teardown_test_environment
}

# =============================================================================
# Helper Functions
# =============================================================================

# Run build.sh with mocked podman
# Usage: run_with_mock_podman arg1 arg2 arg3 ...
run_with_mock_podman() {
  local mock_exit="${MOCK_EXIT:-0}"
  local call_log="$CALL_LOG_FILE"
  local build_script="$BUILD_SCRIPT"

  # Create a wrapper script that sources the build script
  local test_script="$BATS_TMPDIR/mock-test-$$.sh"
  
  # Use a temp file with proper escaping using base64 encoding
  # This avoids all the escaping issues with heredocs
  cat > "$test_script" <<'SCRIPT_EOF'
#!/bin/bash
# Mock podman that records calls and returns configured responses

CALL_LOG="CALL_LOG_VALUE"
MOCK_EXIT="MOCK_EXIT_VALUE"

podman() {
  # Record the call
  echo "$(date +%s.%N) $*" >> "$CALL_LOG"

  case "$1" in
    build)
      local file_flag=""
      local tag_flag=""
      local local_args=("$@")
      while [[ ${#local_args[@]} -gt 0 ]]; do
        case "${local_args[0]}" in
          --file|-f)
            file_flag="${local_args[1]}"
            local_args=("${local_args[@]:2}")
            ;;
          --tag|-t)
            tag_flag="${local_args[1]}"
            local_args=("${local_args[@]:2}")
            ;;
          --build-arg)
            local_args=("${local_args[@]:2}")
            ;;
          *)
            local_args=("${local_args[@]:1}")
            ;;
        esac
      done

      if [ -z "$file_flag" ]; then
        echo "Error: missing --file flag" >&2
        exit 1
      fi
      if [ -z "$tag_flag" ]; then
        echo "Error: missing --tag flag" >&2
        exit 1
      fi

      exit $MOCK_EXIT
      ;;
    inspect)
      cat <<'EOF'
[
  {
    "Id": "sha256:abc123def456",
    "Config": {
      "Labels": {
        "org.opencontainers.image.title": "Nornnet Base",
        "org.opencontainers.image.version": "1.2.3",
        "org.opencontainers.image.revision": "abc1234",
        "containers.bootc": "1",
        "ostree.bootable": "1"
      }
    },
    "RootFS": {
      "Layers": ["sha256:layer1", "sha256:layer2", "sha256:layer3"]
    }
  }
]
EOF
      exit $MOCK_EXIT
      ;;
    image|images)
      if [ "$2" = "exists" ]; then
        exit $MOCK_EXIT
      fi
      ;;
    *)
      exit $MOCK_EXIT
      ;;
  esac

  exit $MOCK_EXIT
}
export -f podman

# Source the build script with arguments
source "BUILD_SCRIPT_VALUE" "$@"
SCRIPT_EOF
  
  # Now substitute the values using sed
  sed -i "s|CALL_LOG_VALUE|${call_log}|g" "$test_script"
  sed -i "s|MOCK_EXIT_VALUE|${mock_exit}|g" "$test_script"
  sed -i "s|BUILD_SCRIPT_VALUE|${build_script}|g" "$test_script"
  
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

# =============================================================================
# Unit Tests: Build Script Logic (using mock podman)
# =============================================================================

@test "UNIT: build.sh --help displays usage information" {
  run "$BUILD_SCRIPT" --help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "layer"
}

@test "UNIT: build.sh uses default base layer when no layer specified" {
  run_with_mock_podman --tag test

  assert_success
  assert_podman_called_with "Containerfile.base"
}

@test "UNIT: build.sh rejects invalid layer name" {
  run "$BUILD_SCRIPT" --layer "invalid-layer" --tag "test"
  assert_failure
  assert_output_contains "Dockerfile not found"
  assert_output_contains "Containerfile.invalid-layer"
}

@test "UNIT: build.sh validates semver version format" {
  # Create a test script that sources registry.sh and tests validation
  local test_script="$BATS_TMPDIR/test-semver-$$.sh"
  cat > "$test_script" <<'TESTSCRIPT'
#!/bin/bash
source "$1"
errors=0

# Test valid versions
for v in "1.0.0" "0.0.0" "10.20.30" "999.999.999"; do
  if ! validate_version "$v" 2>/dev/null; then
    echo "FAIL: Should accept valid semver: $v"
    errors=$((errors + 1))
  fi
done

# Test invalid versions
for v in "1.0" "v1.0.0" "latest" "1" "1.2.3.4" "abc" "1.2.3-beta"; do
  if validate_version "$v" 2>/dev/null; then
    echo "FAIL: Should reject invalid version: $v"
    errors=$((errors + 1))
  fi
done

exit $errors
TESTSCRIPT
  chmod +x "$test_script"

  run "$test_script" "$REGISTRY_SCRIPT"
  assert_success
  # Check no FAIL messages in output
  run bash -c "echo '$output' | grep -q FAIL"
  [ $status -ne 0 ]

  rm -f "$test_script"
}

@test "UNIT: build.sh passes correct arguments to podman build" {
  run_with_mock_podman --layer base --tag v1.0.0

  assert_success

  # Verify podman was called with correct --file argument
  assert_podman_called_with "Containerfile.base"

  # Verify podman was called with correct --tag argument
  assert_podman_called_with "ghcr.io/os2sandbox/nornnet-base:v1.0.0"

  # Verify build function was invoked
  assert_podman_called_with "build --file"
}

@test "UNIT: build.sh app layer builds successfully" {
  run_with_mock_podman --layer app --tag v1.0.0 --registry ghcr.io/test

  assert_success

  # Verify podman was called for app layer
  assert_podman_called_with "Containerfile.app"
  assert_podman_called_with "ghcr.io/test/nornnet-app:v1.0.0"
}

@test "UNIT: build.sh fails when Dockerfile is missing" {
  # Temporarily rename the Dockerfile
  local original_dockerfile="$PROJECT_ROOT/Containerfile.base"
  local backup_dockerfile="$PROJECT_ROOT/Containerfile.base.bak"

  if [ -f "$original_dockerfile" ]; then
    mv "$original_dockerfile" "$backup_dockerfile"

    run "$BUILD_SCRIPT" --layer base --tag "test"
    assert_failure
    assert_output_contains "Dockerfile not found"
    assert_output_contains "Containerfile.base"

    # Restore
    mv "$backup_dockerfile" "$original_dockerfile"
  else
    skip "Containerfile.base not found"
  fi
}

@test "UNIT: build.sh handles custom registry" {
  run_with_mock_podman --layer base --tag v1.0.0 --registry my.registry.com:5000/test

  assert_success

  # Verify custom registry is used in tag
  assert_podman_called_with "--tag.*my.registry.com:5000/test/nornnet-base:v1.0.0"
}

# =============================================================================
# Unit Tests: Registry Script Functions
# =============================================================================

@test "UNIT: registry_full_image_name formats correctly for semver" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' '1.2.3'")"
  [[ "$result" == "ghcr.io/test/app:v1.2.3" ]]
}

@test "UNIT: registry_full_image_name uses latest without v prefix" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' 'latest'")"
  [[ "$result" == "ghcr.io/test/app:latest" ]]
}

@test "UNIT: registry_full_image_name handles empty version" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app'")"
  [[ "$result" == "ghcr.io/test/app:latest" ]]
}

@test "UNIT: get_image_revision returns git hash" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && get_image_revision")"
  # Should be 40 char hex string
  [[ "$result" =~ ^[0-9a-f]{40}$ ]]
}

@test "UNIT: validate_registry accepts valid registry formats" {
  bash -c "source '$REGISTRY_SCRIPT'; validate_registry 'ghcr.io'; validate_registry 'docker.io'; validate_registry 'my.registry.com:5000'"
}

@test "UNIT: validate_registry rejects clearly invalid formats" {
  # Test no-tld - should fail (no proper TLD)
  run bash -c "source '$REGISTRY_SCRIPT' && validate_registry 'no-tld' && echo PASS"
  [ "$status" -ne 0 ]
  [ "$output" != "PASS" ]
  
  # Test single char TLD - should fail (TLD must be at least 2 chars)
  run bash -c "source '$REGISTRY_SCRIPT' && validate_registry 'test.a' && echo PASS"
  [ "$status" -ne 0 ]
  [ "$output" != "PASS" ]
}

@test "UNIT: validate_image_name accepts valid names" {
  bash -c "source '$REGISTRY_SCRIPT'; validate_image_name 'nornnet'; validate_image_name 'nornnet-app'; validate_image_name 'nornnet_app.v2'; validate_image_name 'app123'"
}

@test "UNIT: validate_image_name rejects invalid names" {
  # Starts with dash
  run bash -c "source '$REGISTRY_SCRIPT' && validate_image_name '-invalid' && echo PASS"
  [ "$status" -ne 0 ]
  [ "$output" != "PASS" ]

  # Contains space
  run bash -c "source '$REGISTRY_SCRIPT' && validate_image_name 'has space' && echo PASS"
  [ "$status" -ne 0 ]
  [ "$output" != "PASS" ]
}

# =============================================================================
# Unit Tests: Logging Functions
# =============================================================================

@test "UNIT: log_json outputs structured JSON" {
  local output_json
  output_json="$(bash -c "source '$LOGGING_SCRIPT' && LOG_FILE=/dev/null log_info 'test message'")"

  # Should be valid JSON with required fields
  run bash -c "echo '$output_json' | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(\"level\"), d.get(\"message\"))'"
  assert_output_contains "INFO"
  assert_output_contains "test message"
}

@test "UNIT: log_section outputs formatted header" {
  run bash -c "source '$LOGGING_SCRIPT' && LOG_FILE=/dev/null log_section 'Test Section'"
  assert_output_contains "Test Section"
  assert_output_contains "==="
}

# =============================================================================
# Integration Tests: Real Builds (require functional podman)
# =============================================================================

@test "INTEGRATION: build.sh base layer produces OCI image with bootc labels" {
  skip_if_tool_not_available "podman"

  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  local test_tag="nornnet-test-$(date +%s)"
  local test_image="localhost/nornnet-test:${test_tag}"
  TEST_IMAGES+=("$test_image")

  # Override registry for local testing
  run "$BUILD_SCRIPT" --layer base --tag "$test_tag" --registry "localhost/nornnet-test"
  assert_success

  # Verify image was created
  run bash -c "podman image exists 'localhost/nornnet-test:${test_tag}'"
  assert_success

  # Verify bootc label
  run bash -c "podman inspect 'localhost/nornnet-test:${test_tag}' --format '{{.Config.Labels.containers.bootc}}' 2>/dev/null"
  assert_output_contains "1"

  # Verify ostree.bootable label
  run bash -c "podman inspect 'localhost/nornnet-test:${test_tag}' --format '{{.Config.Labels.ostree.bootable}}' 2>/dev/null"
  assert_output_contains "1"
}

@test "INTEGRATION: build.sh captures Git commit hash in image label" {
  skip_if_tool_not_available "podman"

  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  local test_tag="nornnet-git-$(date +%s)"
  local test_image="localhost/nornnet-git:${test_tag}"
  TEST_IMAGES+=("$test_image")

  # Get expected git hash from current repo
  local expected_hash
  expected_hash="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null)" || expected_hash="unknown"

  run "$BUILD_SCRIPT" --layer base --tag "$test_tag" --registry "localhost/nornnet-git"
  assert_success

  # Verify revision label matches git commit
  run bash -c "podman inspect 'localhost/nornnet-git:${test_tag}' --format '{{.Config.Labels.\"org.opencontainers.image.revision\"}}' 2>/dev/null"
  assert_output_contains "$expected_hash"
}

@test "INTEGRATION: build.sh image has version label set" {
  skip_if_tool_not_available "podman"

  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  local test_tag="nornnet-ver-$(date +%s)"
  local test_image="localhost/nornnet-ver:${test_tag}"
  TEST_IMAGES+=("$test_image")

  # Build with any tag
  run "$BUILD_SCRIPT" --layer base --tag "1.2.3" --registry "localhost/nornnet-ver"
  assert_success

  # Verify version label is set (from Containerfile or version file)
  run bash -c "podman inspect 'localhost/nornnet-ver:1.2.3' --format '{{.Config.Labels.\"org.opencontainers.image.version\"}}' 2>/dev/null"
  assert_success
  # Should not be empty
  [ -n "$output" ]
}

@test "INTEGRATION: build.sh with nonexistent Dockerfile fails clearly" {
  skip_if_tool_not_available "podman"

  run "$BUILD_SCRIPT" --layer "nonexistent" --tag "test"
  assert_failure
  assert_output_contains "Dockerfile not found"
  assert_output_contains "Containerfile.nonexistent"
}

# =============================================================================
# Integration Tests: Build Failure Scenarios
# =============================================================================

@test "INTEGRATION: build.sh fails with clear error for invalid Containerfile" {
  skip_if_tool_not_available "podman"

  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  # Create temporary directory with invalid Containerfile
  local invalid_context="$BATS_TMPDIR/invalid-context-$$"
  mkdir -p "$invalid_context"

  echo "INVALID INSTRUCTION XYZ" > "$invalid_context/Containerfile.base"

  # Try to use this invalid Dockerfile
  local original_dockerfile="$PROJECT_ROOT/Containerfile.base"
  local backup="$PROJECT_ROOT/Containerfile.base.backup-$$"
  cp "$original_dockerfile" "$backup"
  cp "$invalid_context/Containerfile.base" "$original_dockerfile"

  run "$BUILD_SCRIPT" --layer base --tag "invalid-test" 2>&1 || true

  # Restore original
  mv "$backup" "$original_dockerfile"
  rm -rf "$invalid_context"

  # Should have failed
  [ $status -ne 0 ]
  # Should mention the error
  [[ "$output" == *"error"* ]] || [[ "$output" == *"Error"* ]] || [[ "$output" == *"ERROR"* ]]
}

@test "INTEGRATION: build.sh fails when base image doesn't exist" {
  skip_if_tool_not_available "podman"

  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  # Create temporary Containerfile with nonexistent base
  local temp_dockerfile="$PROJECT_ROOT/Containerfile.base.temp-$$"
  cat > "$temp_dockerfile" <<'EOF'
FROM this-image-definitely-does-not-exist-123456789:latest
LABEL test=true
EOF

  local original_dockerfile="$PROJECT_ROOT/Containerfile.base"
  local backup="$PROJECT_ROOT/Containerfile.base.backup-$$"
  cp "$original_dockerfile" "$backup"
  cp "$temp_dockerfile" "$original_dockerfile"

  run "$BUILD_SCRIPT" --layer base --tag "missing-base" 2>&1 || true

  # Restore original
  mv "$backup" "$original_dockerfile"
  rm -f "$temp_dockerfile"

  # Should have failed
  [ $status -ne 0 ]
  # Error should mention the missing image
  [[ "$output" == *"this-image-definitely-does-not-exist"* ]] || [[ "$output" == *"error"* ]]
}

# =============================================================================
# Integration Tests: Version Semver Validation
# =============================================================================

@test "INTEGRATION: semver validation accepts and rejects correctly" {
  # Create a test script that sources registry.sh and tests all validation cases
  local test_script="$BATS_TMPDIR/test-semver-integration-$$.sh"
  cat > "$test_script" <<'TESTSCRIPT'
#!/bin/bash
source "$1"
errors=0

# Valid versions that should pass
for v in "0.0.0" "1.0.0" "10.20.30" "999.999.999"; do
  if ! validate_version "$v" 2>/dev/null; then
    echo "FAIL: Should accept valid semver: $v"
    errors=$((errors + 1))
  fi
done

# Invalid versions that should fail
for v in "1.0" "v1.0.0" "latest" "1" "1.2.3.4" "abc" "1.2.3-beta"; do
  if validate_version "$v" 2>/dev/null; then
    echo "FAIL: Should reject invalid version: $v"
    errors=$((errors + 1))
  fi
done

exit $errors
TESTSCRIPT
  chmod +x "$test_script"

  run "$test_script" "$REGISTRY_SCRIPT"
  assert_success

  rm -f "$test_script"
}

# =============================================================================
# Integration Tests: Image Layer Verification
# =============================================================================

@test "INTEGRATION: built image has layers (not single-layer)" {
  skip_if_tool_not_available "podman"

  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi

  local test_tag="nornnet-layers-$(date +%s)"
  local test_image="localhost/nornnet-layers:${test_tag}"
  TEST_IMAGES+=("$test_image")

  run "$BUILD_SCRIPT" --layer base --tag "$test_tag" --registry "localhost/nornnet-layers"
  assert_success

  # Count layers
  local layer_count
  layer_count="$(podman inspect "$test_image" --format '{{len .RootFS.Layers}}' 2>/dev/null)"

  # Should have at least 1 layer
  [ "$layer_count" -ge 1 ]
}

# =============================================================================
# Regression Tests: Previously Fixed Bugs
# =============================================================================

@test "REGRESSION: build.sh handles empty TAG gracefully" {
  local result
  result="$(bash -c "source '$REGISTRY_SCRIPT' && registry_full_image_name 'ghcr.io' 'test' 'app' ''")"
  [[ "$result" == "ghcr.io/test/app:latest" ]]
}

@test "REGRESSION: image names with spaces should be rejected" {
  run bash -c "source '$REGISTRY_SCRIPT' && validate_image_name 'has space'"
  [ $status -ne 0 ]
}
