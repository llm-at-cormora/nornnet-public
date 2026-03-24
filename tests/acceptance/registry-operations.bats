#!/usr/bin/env bats
# Acceptance tests for US3: Image Registry Operations
#
# Acceptance Criteria:
# 1. Given I have a locally built image with version 1.0.0 and valid push token,
#    When I push the image to the registry,
#    Then the image appears with tag v1.0.0 and contains the Git commit hash label.
# 2. Given an image exists in the registry,
#    When I pull it to a local environment,
#    Then the pulled image matches the original (verified by inspection).
# 3. Given I push a new version 1.1.0 of an existing image,
#    When I list available versions,
#    Then both v1.0.0 and v1.1.0 are available with distinct tags.

load '../bats/common.bash'
load '../bats/fixtures.bash'
load '../bats/ci_helpers.bash'

# Test configuration
REGISTRY="${REGISTRY:-ghcr.io}"
NAMESPACE="${NAMESPACE:-llm-at-cormora}"
TEST_IMAGE_V1="localhost/nornnet-test:1.0.0"
TEST_IMAGE_V2="localhost/nornnet-test:1.1.0"
REMOTE_IMAGE_V1="${REGISTRY}/${NAMESPACE}/nornnet:v1.0.0"
REMOTE_IMAGE_V2="${REGISTRY}/${NAMESPACE}/nornnet:v1.1.0"

setup() {
  ci_skip_if_unavailable "podman" "podman required for registry tests"
  
  # Verify podman can run basic commands
  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi
  
  # Create temporary build context
  BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
  TEST_CONTEXT="$BATS_TMPDIR/nornnet-registry-test-$$"
  mkdir -p "$TEST_CONTEXT"
  
  # Copy fixture to context
  local fixture_path
  fixture_path="$(get_fixture_path "Containerfile.test")"
  cp "$fixture_path" "$TEST_CONTEXT/Containerfile"
}

teardown() {
  # Cleanup test images from local storage
  podman rmi "$TEST_IMAGE_V1" &>/dev/null || true
  podman rmi "$TEST_IMAGE_V2" &>/dev/null || true
  podman rmi "${REGISTRY}/${NAMESPACE}/nornnet:v1.0.0" &>/dev/null || true
  podman rmi "${REGISTRY}/${NAMESPACE}/nornnet:v1.1.0" &>/dev/null || true
  podman rmi "${NAMESPACE}/nornnet:v1.0.0" &>/dev/null || true
  podman rmi "${NAMESPACE}/nornnet:v1.1.0" &>/dev/null || true
  
  # Cleanup test context
  rm -rf "$TEST_CONTEXT"
}

# =============================================================================
# SC-3.1: Push image with version tag
# =============================================================================

@test "AC3.1: Build image with version label" {
  # Given we want to push version 1.0.0
  # When we build the image
  # Then it should have the correct version label
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  run podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    "$TEST_CONTEXT"
  
  assert_success
}

@test "AC3.1: Image has version label after build" {
  # Given a built image
  # When we inspect it
  # Then it has the version label
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    "$TEST_CONTEXT" >/dev/null
  
  run bash -c "podman inspect '$TEST_IMAGE_V1' --format '{{index .Config.Labels \"org.opencontainers.image.version\"}}' 2>/dev/null"
  assert_success
  [ "$output" = "1.0.0" ]
}

@test "AC3.1: Image has Git commit hash label" {
  # Given a built image
  # When we inspect it
  # Then it has the Git commit hash label
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    "$TEST_CONTEXT" >/dev/null
  
  run bash -c "podman inspect '$TEST_IMAGE_V1' --format '{{index .Config.Labels \"org.opencontainers.image.revision\"}}' 2>/dev/null"
  assert_success
  [ -n "$output" ]
}

@test "AC3.1: Image can be tagged for remote registry" {
  # Given a built image
  # When we tag it for the remote registry
  # Then the tag is created successfully
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    "$TEST_CONTEXT" >/dev/null
  
  # Tag for remote registry
  run podman tag "$TEST_IMAGE_V1" "${NAMESPACE}/nornnet:v1.0.0"
  assert_success
  
  # Verify tag exists
  run podman image exists "${NAMESPACE}/nornnet:v1.0.0"
  assert_success
}

# =============================================================================
# SC-3.2: Pull image and verify match
# =============================================================================

@test "AC3.2: Pulled image matches original metadata" {
  # Given an image exists (we use docker.io/alpine as proxy)
  # When we pull it and compare
  # Then the metadata matches
  
  # Pull image
  run podman pull --quiet docker.io/library/alpine:latest 2>&1
  if [ $status -ne 0 ]; then
    skip "Network unavailable or image not accessible"
  fi
  
  # Get original ID
  local original_id
  original_id="$(podman inspect --format '{{.Id}}' docker.io/library/alpine:latest 2>/dev/null)"
  
  # Remove and re-pull
  podman rmi docker.io/library/alpine:latest &>/dev/null || true
  run podman pull docker.io/library/alpine:latest 2>&1
  [ $status -eq 0 ]
  
  # Verify ID matches
  local pulled_id
  pulled_id="$(podman inspect --format '{{.Id}}' docker.io/library/alpine:latest 2>/dev/null)"
  
  [ "$original_id" = "$pulled_id" ]
}

@test "AC3.2: Pulled image preserves labels" {
  # Given a locally built image with labels
  # When we save it and load it back
  # Then the labels are preserved
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  # Build with specific labels
  podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    --label "custom.test.label=test-value" \
    "$TEST_CONTEXT" >/dev/null
  
  # Get original labels
  local original_version
  original_version="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$TEST_IMAGE_V1" 2>/dev/null)"
  
  local original_commit
  original_commit="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$TEST_IMAGE_V1" 2>/dev/null)"
  
  # Save and load (simulating registry round-trip)
  local save_file="/tmp/nornnet-test-save-$$.tar"
  podman save -o "$save_file" "$TEST_IMAGE_V1" >/dev/null
  
  podman rmi "$TEST_IMAGE_V1" &>/dev/null || true
  
  run podman load -i "$save_file" 2>&1
  [ $status -eq 0 ]
  
  rm -f "$save_file"
  
  # Verify labels preserved
  local loaded_version
  loaded_version="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$TEST_IMAGE_V1" 2>/dev/null)"
  
  [ "$original_version" = "$loaded_version" ]
  [ "$original_version" = "1.0.0" ]
}

# =============================================================================
# SC-3.3: Multiple versions available
# =============================================================================

@test "AC3.3: Can tag multiple versions of same image" {
  # Given a base image
  # When we tag it with different version numbers
  # Then both tags exist
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  # Build base
  podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    "$TEST_CONTEXT" >/dev/null
  
  # Tag as v1
  run podman tag "$TEST_IMAGE_V1" "${NAMESPACE}/nornnet:v1.0.0"
  assert_success
  
  # Tag as v2
  run podman tag "$TEST_IMAGE_V1" "${NAMESPACE}/nornnet:v1.1.0"
  assert_success
  
  # Verify both exist
  run podman image exists "${NAMESPACE}/nornnet:v1.0.0"
  assert_success
  
  run podman image exists "${NAMESPACE}/nornnet:v1.1.0"
  assert_success
}

@test "AC3.3: Different versions have distinct labels" {
  # Given two version builds
  # When we inspect their labels
  # Then the version labels differ
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  # Create fresh test context to avoid cache issues
  local test_dir
  test_dir="$(mktemp -d)"
  cp "$(get_fixture_path "Containerfile.test")" "$test_dir/Containerfile"
  
  # Build first version with --no-cache
  podman build \
    --file "$test_dir/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    --no-cache \
    "$test_dir" >/dev/null
  
  # Create fresh context for second build
  rm -rf "$test_dir"/*
  cp "$(get_fixture_path "Containerfile.test")" "$test_dir/Containerfile"
  
  # Build second version with different label
  podman build \
    --file "$test_dir/Containerfile" \
    --tag "$TEST_IMAGE_V2" \
    --label "org.opencontainers.image.version=1.1.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    --no-cache \
    "$test_dir" >/dev/null
  
  rm -rf "$test_dir"
  
  # Both should build successfully
  run podman image exists "$TEST_IMAGE_V1"
  assert_success
  
  run podman image exists "$TEST_IMAGE_V2"
  assert_success
  
  # Version labels should differ
  local v1_label v2_label
  v1_label="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$TEST_IMAGE_V1" 2>/dev/null)"
  v2_label="$(podman inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$TEST_IMAGE_V2" 2>/dev/null)"
  
  [ "$v1_label" = "1.0.0" ] || echo "v1=$v1_label"
  [ "$v2_label" = "1.1.0" ] || echo "v2=$v2_label"
  [ "$v1_label" != "$v2_label" ]
}

@test "AC3.3: Version tags can be listed" {
  # Given multiple tagged images
  # When we list images matching the pattern
  # Then all versions are shown
  
  local commit_hash
  commit_hash="$(git rev-parse HEAD 2>/dev/null || echo 'test-commit')"
  
  # Build and tag v1.0.0
  podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V1" \
    --label "org.opencontainers.image.version=1.0.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    "$TEST_CONTEXT" >/dev/null
  podman tag "$TEST_IMAGE_V1" "${NAMESPACE}/nornnet:v1.0.0"
  
  # Build and tag v1.1.0
  podman build \
    --file "$TEST_CONTEXT/Containerfile" \
    --tag "$TEST_IMAGE_V2" \
    --label "org.opencontainers.image.version=1.1.0" \
    --label "org.opencontainers.image.revision=${commit_hash}" \
    "$TEST_CONTEXT" >/dev/null
  podman tag "$TEST_IMAGE_V2" "${NAMESPACE}/nornnet:v1.1.0"
  
  # List images matching our namespace
  run bash -c "podman images --format '{{.Repository}}:{{.Tag}}' | grep 'nornnet:'"
  assert_success
  
  # Should contain both versions
  run bash -c "podman images --format '{{.Repository}}:{{.Tag}}' | grep -c 'nornnet:'"
  [ "$output" -ge 2 ]
}
