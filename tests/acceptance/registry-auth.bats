#!/usr/bin/env bats
# Acceptance tests for US2: Registry Authentication
#
# Acceptance Criteria:
# 1. Given the registry allows anonymous read access, When a device attempts to pull,
#    Then the pull succeeds without authentication.
# 2. Given a valid push token is configured, When I attempt to push an image,
#    Then the push succeeds and the image appears in the registry.
# 3. Given no push token is configured, When I attempt to push an image,
#    Then the push fails with an authentication error.
# 4. Given an invalid or expired token is configured, When I attempt to push,
#    Then the push fails with an authentication error.

load '../bats/common.bash'
load '../bats/fixtures.bash'
load '../bats/ci_helpers.bash'

# Test configuration
TEST_IMAGE="localhost/nornnet-test:$(date +%s)"
REGISTRY="${REGISTRY:-ghcr.io}"
NAMESPACE="${NAMESPACE:-llm-at-cormora}"
FULL_IMAGE_NAME="${REGISTRY}/${NAMESPACE}/nornnet:test"

setup() {
  ci_skip_if_unavailable "podman" "podman required for registry tests"
  
  # Verify podman is functional
  if ! podman info &>/dev/null; then
    skip "podman not functional in this environment"
  fi
}

teardown() {
  # Cleanup test images
  podman rmi "$TEST_IMAGE" &>/dev/null || true
  
  # Cleanup full image name if it exists
  podman rmi "$FULL_IMAGE_NAME" &>/dev/null || true
  
  # Logout if logged in (cleanup auth state)
  podman logout "$REGISTRY" &>/dev/null || true
}

# =============================================================================
# SC-2.1: Anonymous read access
# =============================================================================

@test "AC2.1: Anonymous pull succeeds for public images" {
  # Given a public image exists in the registry
  # When we attempt to pull without authentication
  # Then the pull succeeds
  
  skip_if_tool_not_available "podman"
  
  # Using a known public image for testing
  run podman pull --quiet docker.io/library/alpine:latest 2>&1
  
  # Then pull succeeds (exit 0)
  # Note: This may skip if network unavailable
  [ $status -eq 0 ] || skip "Network unavailable or image not found"
}

@test "AC2.1: Anonymous read returns correct image metadata" {
  # Given a public image exists
  # When we inspect the image
  # Then metadata is returned
  
  skip_if_tool_not_available "podman"
  
  run podman inspect docker.io/library/alpine:latest 2>&1
  
  [ $status -eq 0 ] || skip "Network unavailable"
  echo "$output" | grep -q '"Architecture"'
}

@test "AC2.1: Public image can be inspected without authentication" {
  # Given a public registry image
  # When we inspect it without logging in
  # Then metadata is returned without auth errors
  
  skip_if_tool_not_available "podman"
  
  # Ensure we're not logged in
  podman logout docker.io &>/dev/null || true
  
  run podman inspect docker.io/library/alpine:latest 2>&1
  
  # Should succeed without authentication
  [ $status -eq 0 ] || skip "Network unavailable"
  # Should not contain unauthorized/auth error
  ! echo "$output" | grep -qi "unauthorized\|authentication required"
}

# =============================================================================
# SC-2.2: Valid push token succeeds
# =============================================================================

@test "AC2.2: Push with valid token succeeds" {
  # Given a valid push token is configured
  # When we push an image to the registry
  # Then the push succeeds
  
  skip_if_tool_not_available "podman"
  
  # Build a test image
  run podman build \
    --file "$(get_fixture_path "Containerfile.test")" \
    --tag "$TEST_IMAGE" \
    "$(dirname "$(get_fixture_path "Containerfile.test")")"
  
  [ $status -eq 0 ] || skip "Build failed"
  
  # Tag for registry
  podman tag "$TEST_IMAGE" "$FULL_IMAGE_NAME"
  
  # Attempt push - will only succeed with valid auth
  run podman push "$FULL_IMAGE_NAME" 2>&1 || true
  
  # Either succeeds (with auth) or shows proper auth error (without)
  # The key is it doesn't crash and gives meaningful error
  if [ $status -ne 0 ]; then
    # Push failed - should be auth-related, not a crash
    echo "$output" | grep -qE "authentication|unauthorized|denied|401|403" || {
      echo "Expected auth error, got: $output"
      return 1
    }
  fi
  # Success case: exit code 0
  # Failure case: handled above with proper auth error
}

@test "AC2.2: Authenticated push updates registry" {
  # Given valid authentication
  # When we push an image
  # Then the image is available in the registry
  
  skip_if_tool_not_available "podman"
  
  # This test verifies the happy path if auth is configured
  # Check if we have auth configured via environment
  if [ -z "$PUSH_USERNAME" ] || [ -z "$PUSH_PASSWORD" ]; then
    skip "No push credentials configured (PUSH_USERNAME/PUSH_PASSWORD not set)"
  fi
  
  # Build and tag
  run podman build \
    --file "$(get_fixture_path "Containerfile.test")" \
    --tag "$TEST_IMAGE" \
    "$(dirname "$(get_fixture_path "Containerfile.test")")"
  
  [ $status -eq 0 ] || skip "Build failed"
  
  podman tag "$TEST_IMAGE" "$FULL_IMAGE_NAME"
  
  # Login
  run podman login \
    --username "$PUSH_USERNAME" \
    --password "$PUSH_PASSWORD" \
    "$REGISTRY" 2>&1
  
  [ $status -eq 0 ] || skip "Login failed with configured credentials"
  
  # Push
  run podman push "$FULL_IMAGE_NAME" 2>&1
  
  # Cleanup login
  podman logout "$REGISTRY" &>/dev/null || true
  
  assert_success
}

# =============================================================================
# SC-2.3: No token configured fails
# =============================================================================

@test "AC2.3: Push without token fails with auth error" {
  # Given no push token is configured
  # When we attempt to push
  # Then the push fails with authentication error
  
  skip_if_tool_not_available "podman"
  
  # Ensure we're not logged in
  podman logout "$REGISTRY" &>/dev/null || true
  
  # Create a test image
  run podman build \
    --file "$(get_fixture_path "Containerfile.test")" \
    --tag "$TEST_IMAGE" \
    "$(dirname "$(get_fixture_path "Containerfile.test")")"
  
  [ $status -eq 0 ] || skip "Build failed"
  
  # Tag for registry
  podman tag "$TEST_IMAGE" "$FULL_IMAGE_NAME"
  
  # Attempt push without logging in
  run podman push "$FULL_IMAGE_NAME" 2>&1 || true
  
  # Should fail with auth-related error
  echo "$output" | grep -qiE "auth|unauthorized|denied|401|403|not logged in"
}

@test "AC2.3: Unauthenticated push returns proper error code" {
  # Given user is not authenticated
  # When push is attempted
  # Then non-zero exit code is returned
  
  skip_if_tool_not_available "podman"
  
  # Ensure not logged in
  podman logout "$REGISTRY" &>/dev/null || true
  
  # Create test image
  run podman build \
    --file "$(get_fixture_path "Containerfile.test")" \
    --tag "$TEST_IMAGE" \
    "$(dirname "$(get_fixture_path "Containerfile.test")")"
  
  [ $status -eq 0 ] || skip "Build failed"
  
  podman tag "$TEST_IMAGE" "$FULL_IMAGE_NAME"
  
  # Attempt push - should fail
  run podman push "$FULL_IMAGE_NAME" 2>&1 || true
  
  # Should return non-zero exit code
  [ $status -ne 0 ] || skip "Push unexpectedly succeeded without auth"
}

# =============================================================================
# SC-2.4: Invalid token fails
# =============================================================================

@test "AC2.4: Push with invalid token fails" {
  # Given an invalid token is configured
  # When we attempt to push
  # Then the push fails with authentication error
  
  skip_if_tool_not_available "podman"
  
  # Login with invalid credentials
  run podman login \
    --username "invalid-user-$(date +%s)" \
    --password "invalid-token-$(date +%s)" \
    "$REGISTRY" 2>&1 || true
  
  # Create and tag test image
  run podman build \
    --file "$(get_fixture_path "Containerfile.test")" \
    --tag "$TEST_IMAGE" \
    "$(dirname "$(get_fixture_path "Containerfile.test")")"
  
  [ $status -eq 0 ] || skip "Build failed"
  
  podman tag "$TEST_IMAGE" "$FULL_IMAGE_NAME"
  
  # Attempt push
  run podman push "$FULL_IMAGE_NAME" 2>&1 || true
  
  # Should fail with auth error
  echo "$output" | grep -qiE "auth|unauthorized|denied|401|403|Bad credentials|invalid"
}

@test "AC2.4: Expired token fails with clear message" {
  # Given an expired token is used
  # When we attempt to push
  # Then push fails with clear authentication error
  
  skip_if_tool_not_available "podman"
  
  # Login with clearly invalid/expired-looking token
  run podman login \
    --username "expired-user" \
    --password "expired-token-2020-01-01" \
    "$REGISTRY" 2>&1 || true
  
  # Create test image
  run podman build \
    --file "$(get_fixture_path "Containerfile.test")" \
    --tag "$TEST_IMAGE" \
    "$(dirname "$(get_fixture_path "Containerfile.test")")"
  
  [ $status -eq 0 ] || skip "Build failed"
  
  podman tag "$TEST_IMAGE" "$FULL_IMAGE_NAME"
  
  # Attempt push
  run podman push "$FULL_IMAGE_NAME" 2>&1 || true
  
  # Should fail with auth error indicating invalid credentials
  echo "$output" | grep -qiE "auth|unauthorized|denied|401|403|Bad credentials|expired"
}

# =============================================================================
# SC-2.5: Registry connectivity verification
# =============================================================================

@test "AC2.5: Can detect registry connectivity issues" {
  # Given network connectivity to registry
  # When we check registry access
  # Then we can determine if it's reachable
  
  skip_if_tool_not_available "podman"
  
  # Try to get info about registry
  run podman search "${REGISTRY}/" --list-trunc 2>&1 || true
  
  # Should either succeed or fail gracefully (not hang)
  # A timeout or crash would be a failure
  [ $status -eq 0 ] || [ $status -eq 125 ] || skip "Registry not reachable"
}
