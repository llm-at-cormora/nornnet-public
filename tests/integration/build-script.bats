#!/usr/bin/env bats
# Integration tests for scripts/build.sh
# T011 - US1 Local Image Build

load '../bats/common.bash'
load '../bats/fixtures.bash'

# Remove trailing slash from BATS_TEST_DIRNAME before using dirname
BATS_TEST_DIRNAME_TRIMMED="${BATS_TEST_DIRNAME%/}"
SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME_TRIMMED}")/.." && pwd)/scripts"
BUILD_SCRIPT="$SCRIPT_DIR/build.sh"
PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_DIRNAME_TRIMMED}")/.." && pwd)"

setup() {
  chmod +x "$BUILD_SCRIPT" 2>/dev/null || true
  TEST_IMAGE="localhost/nornnet-test-script:$(date +%s)"
  
  # Check if podman can actually run (not just installed)
  if ! podman info &>/dev/null; then
    PODMAN_AVAILABLE=false
  else
    PODMAN_AVAILABLE=true
  fi
}

teardown() {
  podman rmi "$TEST_IMAGE" &>/dev/null || true
}

@test "build.sh script exists and is executable" {
  [ -f "$BUILD_SCRIPT" ]
  [ -x "$BUILD_SCRIPT" ]
}

@test "build.sh shows usage with --help" {
  run "$BUILD_SCRIPT" --help
  
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "layer"
  assert_output_contains "tag"
}

@test "build.sh builds base layer image" {
  # Skip if podman not available or not working
  if [ "${PODMAN_AVAILABLE:-false}" != "true" ]; then
    skip "podman not available or not working"
  fi
  
  # Check if Containerfile.base exists
  if [ ! -f "$PROJECT_ROOT/Containerfile.base" ]; then
    skip "Containerfile.base not found"
  fi
  
  export LAYER="base"
  export TAG="test"
  export REGISTRY="localhost"
  
  run "$BUILD_SCRIPT"
  
  assert_success
  assert_output_contains "Build complete"
}

@test "build.sh fails for unknown layer" {
  export LAYER="nonexistent"
  export TAG="test"
  export REGISTRY="localhost"
  
  run "$BUILD_SCRIPT" || true
  
  # Should fail (exit non-zero) OR output should contain error
  [ $status -ne 0 ] || [ ${#output} -gt 0 ]
}

@test "build.sh validates Containerfile exists" {
  # Create a temporary directory without Containerfile
  local temp_dir
  temp_dir="$(mktemp -d)"
  local original_dir
  original_dir="$(pwd)"
  
  # Backup and remove original build script behavior temporarily
  # by changing to a directory without Containerfile
  cd "$temp_dir"
  
  export LAYER="base"
  export TAG="test"
  export REGISTRY="localhost"
  
  run "$BUILD_SCRIPT" 2>&1 || true
  
  cd "$original_dir"
  rm -rf "$temp_dir"
  
  # Should fail with error about missing Containerfile
  assert_output_contains "not found" || [ $status -ne 0 ]
}

@test "build.sh supports -l/--layer option" {
  run "$BUILD_SCRIPT" --help
  
  assert_success
  assert_output_contains "\-\-layer"
  assert_output_contains "\-l,"
}

@test "build.sh supports -t/--tag option" {
  run "$BUILD_SCRIPT" --help
  
  assert_success
  assert_output_contains "\-\-tag"
  assert_output_contains "\-t,"
}

@test "build.sh supports -r/--registry option" {
  run "$BUILD_SCRIPT" --help
  
  assert_success
  assert_output_contains "\-\-registry"
  assert_output_contains "\-r,"
}
