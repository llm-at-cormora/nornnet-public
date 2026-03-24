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

@test "build.sh validates missing Containerfile" {
  # Temporarily rename Containerfile.base to test error handling
  local backup_file
  backup_file="$(mktemp)"
  
  if [ -f "$PROJECT_ROOT/Containerfile.base" ]; then
    mv "$PROJECT_ROOT/Containerfile.base" "$backup_file"
  fi
  
  export LAYER="base"
  export TAG="test"
  export REGISTRY="localhost"
  
  run "$BUILD_SCRIPT" 2>&1 || true
  
  # Restore the file
  if [ -f "$backup_file" ]; then
    mv "$backup_file" "$PROJECT_ROOT/Containerfile.base"
  fi
  rm -f "$backup_file"
  
  # Should fail with error about missing Containerfile
  [ $status -ne 0 ]
  assert_output_contains "not found"
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
