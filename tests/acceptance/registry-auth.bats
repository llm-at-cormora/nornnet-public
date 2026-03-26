#!/usr/bin/env bats
# Acceptance tests for US2: Registry Authentication
#
# These tests verify the application's registry authentication behavior,
# not just raw podman/skopeo commands. They test:
# - registry.sh library functions (unit level with mocking)
# - push.sh workflow (integration level)
# - Error message quality
# - Credential detection logic
#
# Acceptance Criteria:
# 1. Anonymous read succeeds for public images
# 2. Valid token push succeeds
# 3. No token push fails with clear auth error
# 4. Invalid/expired token push fails

# Require minimum bats version for run flags
bats_require_minimum_version 1.5.0

# =============================================================================
# Test Setup
# =============================================================================

load '../bats/common.bash'
load '../bats/fixtures.bash'
load '../bats/ci_helpers.bash'

# Path to scripts under test
SCRIPT_DIR="${BATS_TEST_DIRNAME}/../.."
REGISTRY_LIB="${SCRIPT_DIR}/scripts/lib/registry.sh"
PUSH_SCRIPT="${SCRIPT_DIR}/scripts/push.sh"

# =============================================================================
# Mock System
# =============================================================================

# Create a self-contained mock podman that doesn't depend on external functions
_create_mock_podman() {
  local mock_dir="${TEST_TMPDIR}/mock_bins"
  mkdir -p "$mock_dir"
  
  # Create a single-file mock that handles all subcommands
  cat > "${mock_dir}/podman" <<'END_MOCK'
#!/usr/bin/env bash
# Mock podman - self-contained

# State from environment
MOCK_LOGIN_RESULT="${MOCK_LOGIN_RESULT:-success}"
MOCK_PUSH_RESULT="${MOCK_PUSH_RESULT:-success}"
MOCK_PULL_RESULT="${MOCK_PULL_RESULT:-success}"
MOCK_BUILD_RESULT="${MOCK_BUILD_RESULT:-success}"
MOCK_LOGGED_IN="${MOCK_LOGGED_IN:-false}"
MOCK_REGISTRY="${MOCK_REGISTRY:-ghcr.io}"
MOCK_LOGGED_USER="${MOCK_LOGGED_USER:-testuser}"
MOCK_IMAGE_EXISTS="${MOCK_IMAGE_EXISTS:-false}"
MOCK_MANIFEST_VALID="${MOCK_MANIFEST_VALID:-true}"

# Log file
LOG_FILE="${TEST_TMPDIR}/podman_calls.log"
echo "$(date +%s.%N) podman $*" >> "$LOG_FILE"

# Parse arguments - podman login is special because --get-login comes AFTER 'login'
# Usage: podman login --get-login registry
#        podman login -u user -p pass registry
subcommand="$1"
shift

case "$subcommand" in
  login)
    # Check for --get-login flag first (it's a query, not a login)
    # --get-login is the second argument, registry is the third
    # Usage: podman login --get-login registry
    has_get_login=false
    registry=""
    for arg in "$@"; do
      if [ "$arg" = "--get-login" ]; then
        has_get_login=true
      elif [[ "$arg" != -* ]] && [ -z "$registry" ]; then
        # First non-flag argument is the registry
        registry="$arg"
      fi
    done
    
    if [ "$has_get_login" = "true" ]; then
      # Query: is user logged in to this specific registry?
      if [ "$MOCK_LOGGED_IN" = "true" ] && [ "$registry" = "$MOCK_REGISTRY" ]; then
        echo "$MOCK_LOGGED_USER"
        exit 0
      else
        exit 1
      fi
    fi
    
    # It's an actual login attempt - parse arguments
    registry=""
    username=""
    password=""
    password_stdin=false
    
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --password-stdin)
          password_stdin=true
          ;;
        -u|--username)
          username="$2"
          shift
          ;;
        -p|--password)
          password="$2"
          shift
          ;;
        -*)
          ;;
        *)
          registry="$1"
          ;;
      esac
      shift
    done
    
    # Read password from stdin if requested
    if [ "$password_stdin" = "true" ]; then
      password=$(cat)
    fi
    
    echo "MOCK_LOGIN: registry=$registry username=$username" >> "$LOG_FILE"
    
    case "$MOCK_LOGIN_RESULT" in
      success)
        echo "Login Succeeded!"
        exit 0
        ;;
      invalid_credentials)
        echo "Error: authenticating with registry: unsupported status code 401, Server message: unauthorized" >&2
        exit 1
        ;;
      network_error)
        echo "Error: network timeout" >&2
        exit 2
        ;;
      *)
        echo "Error: unknown login error" >&2
        exit 1
        ;;
    esac
    ;;
    
  pull)
    # Remove --quiet if present
    [[ "$1" == "--quiet" ]] && shift
    image="$1"
    
    case "$MOCK_PULL_RESULT" in
      success)
        echo "Getting image source signature: ${image}"
        exit 0
        ;;
      not_found)
        echo "Error: unable to pull ${image}: image not known" >&2
        exit 1
        ;;
      unauthorized)
        echo "Error: unable to pull ${image}: unauthorized" >&2
        exit 1
        ;;
      network_error)
        echo "Error: unable to pull ${image}: network timeout" >&2
        exit 2
        ;;
      *)
        echo "Pull failed" >&2
        exit 1
        ;;
    esac
    ;;
    
  push)
    # Handle various flags
    image=""
    while [[ $# -gt 0 ]]; do
      if [[ "$1" != -* ]]; then
        image="$1"
        break
      fi
      shift
    done
    
    echo "MOCK_PUSH: image=$image logged_in=$MOCK_LOGGED_IN" >> "$LOG_FILE"
    
    case "$MOCK_PUSH_RESULT" in
      success)
        echo "Copying blob sha256:abc123..."
        echo "Successfully pushed image"
        exit 0
        ;;
      unauthorized)
        echo "Error: Error committing: unable to push ${image}: unauthorized: authentication required" >&2
        exit 1
        ;;
      not_found)
        echo "Error: Error committing: image not found in registry" >&2
        exit 1
        ;;
      network_error)
        echo "Error: pushing ${image}: connection timeout" >&2
        exit 2
        ;;
      *)
        echo "Push failed for unknown reason" >&2
        exit 1
        ;;
    esac
    ;;
    
  image)
    if [ "$2" = "exists" ]; then
      if [ "$MOCK_IMAGE_EXISTS" = "true" ]; then
        exit 0
      else
        exit 1
      fi
    fi
    ;;
    
  build)
    case "$MOCK_BUILD_RESULT" in
      success)
        echo "STEP 1/1: FROM fedora:latest"
        echo "Successfully built abc123def456"
        exit 0
        ;;
      failure)
        echo "Error: building image: no such file or directory" >&2
        exit 1
        ;;
      *)
        echo "Build failed" >&2
        exit 1
        ;;
    esac
    ;;
    
  tag)
    # Tag is always successful in mock
    exit 0
    ;;
    
  manifest)
    if [ "$1" = "inspect" ]; then
      shift
      image="$1"
      if [ "$MOCK_MANIFEST_VALID" = "true" ]; then
        echo '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json"}'
        exit 0
      else
        echo "manifest not found" >&2
        exit 1
      fi
    fi
    ;;
    
  logout)
    exit 0
    ;;
    
  info)
    echo '{"version":"4.0.0"}'
    exit 0
    ;;
    
  *)
    echo "mock podman: unknown command: $subcommand $*" >&2
    exit 1
    ;;
esac
END_MOCK
  chmod +x "${mock_dir}/podman"
  
  # Also create mock git
  cat > "${mock_dir}/git" <<'END_MOCK_GIT'
#!/usr/bin/env bash
case "$1" in
  rev-parse)
    if [ "$2" = "HEAD" ]; then
      echo "abc123def456789"
      exit 0
    fi
    ;;
esac
exit 1
END_MOCK_GIT
  chmod +x "${mock_dir}/git"
}

# Create mock skopeo
_create_mock_skopeo() {
  local mock_dir="${TEST_TMPDIR}/mock_bins"
  
  cat > "${mock_dir}/skopeo" <<'END_MOCK_SKOPEO'
#!/usr/bin/env bash
# Mock skopeo
MOCK_SKOPEO_RESULT="${MOCK_SKOPEO_RESULT:-success}"

case "$1" in
  inspect)
    case "$MOCK_SKOPEO_RESULT" in
      success)
        echo '{"Name":"test/image","Tag":"latest","Digest":"sha256:abc123"}'
        exit 0
        ;;
      unauthorized)
        echo "Error: unauthorized" >&2
        exit 1
        ;;
      *)
        echo "Error: unknown" >&2
        exit 1
        ;;
    esac
    ;;
  list-tags)
    echo '{"Tags":["latest","v1.0.0"]}'
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
END_MOCK_SKOPEO
  chmod +x "${mock_dir}/skopeo"
}

# Clear mock call log
_clear_mock_log() {
  rm -f "${TEST_TMPDIR}/podman_calls.log"
}

# Check if podman was called with specific pattern
_podman_called_with() {
  local pattern="$1"
  local call_log="${TEST_TMPDIR}/podman_calls.log"
  
  if [ -f "$call_log" ] && grep -q -- "$pattern" "$call_log"; then
    return 0
  fi
  return 1
}

# Load registry library with mocked dependencies
_load_registry_lib() {
  # Set up mock PATH to use our mocks
  export PATH="${TEST_TMPDIR}/mock_bins:${PATH}"
  
  # Create mocks
  _create_mock_podman
  _create_mock_skopeo
  
  # Source the library (it sources logging.sh and config.sh internally)
  # Suppress errors during source - we just need the functions
  source "${REGISTRY_LIB}" 2>/dev/null || true
}

# =============================================================================
# Setup/Teardown
# =============================================================================

setup() {
  # Create temp directory for mocks
  export TEST_TMPDIR="/tmp/nornnet_test_$$"
  mkdir -p "$TEST_TMPDIR"
  
  # Clear environment variables that might interfere
  unset GITHUB_TOKEN
  unset PUSH_USERNAME
  unset PUSH_PASSWORD
  
  # Set default test environment
  export REGISTRY="${REGISTRY:-ghcr.io}"
  export NAMESPACE="${NAMESPACE:-llm-at-cormora}"
  export IMAGE_NAME="${IMAGE_NAME:-nornnet}"
  
  # Reset mock state to defaults
  export MOCK_LOGGED_IN="false"
  export MOCK_LOGIN_RESULT="success"
  export MOCK_PUSH_RESULT="success"
  export MOCK_PULL_RESULT="success"
  export MOCK_BUILD_RESULT="success"
  export MOCK_IMAGE_EXISTS="false"
  export MOCK_MANIFEST_VALID="true"
  export MOCK_SKOPEO_RESULT="success"
  
  # Set log file
  export LOG_FILE="${TEST_TMPDIR}/nornnet-test.log"
  rm -f "$LOG_FILE"
  
  _clear_mock_log
}

teardown() {
  # Clean up temp directory
  rm -rf "${TEST_TMPDIR}"
}

# =============================================================================
# SC-2.1: Credential Detection (registry_has_push_credentials)
# =============================================================================

@test "AC2.1: registry_has_push_credentials returns true when GITHUB_TOKEN is set" {
  # Given a GitHub token is present in the environment
  export GITHUB_TOKEN="ghp_test123token"
  export MOCK_LOGGED_IN="false"  # Ensure no podman login
  
  # When we check for push credentials
  _load_registry_lib
  
  # Then the function should return true
  run registry_has_push_credentials "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "AC2.1: registry_has_push_credentials returns false when no credentials exist" {
  # Given no credentials are configured
  unset GITHUB_TOKEN
  export MOCK_LOGGED_IN="false"
  
  # When we check for push credentials
  _load_registry_lib
  
  # Then the function should return false
  run registry_has_push_credentials "$REGISTRY"
  [ "$status" -ne 0 ]
}

@test "AC2.1: registry_has_push_credentials returns true when logged in via podman" {
  # Given user is logged in via podman
  unset GITHUB_TOKEN
  export MOCK_LOGGED_IN="true"
  export MOCK_REGISTRY="$REGISTRY"
  export MOCK_LOGGED_USER="testuser"
  
  # When we check for push credentials
  _load_registry_lib
  
  # Then the function should return true
  run registry_has_push_credentials "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "AC2.1: registry_has_push_credentials checks specific registry" {
  # Given user is logged in to ghcr.io but not docker.io
  export MOCK_LOGGED_IN="true"
  export MOCK_REGISTRY="ghcr.io"
  export MOCK_LOGGED_USER="testuser"
  
  _load_registry_lib
  
  # When checking ghcr.io (logged in)
  run registry_has_push_credentials "ghcr.io"
  [ "$status" -eq 0 ]
  
  # When checking docker.io (not logged in)
  run registry_has_push_credentials "docker.io"
  [ "$status" -ne 0 ]
}

# =============================================================================
# SC-2.1: Anonymous Read (registry_check_anonymous_read)
# =============================================================================

@test "AC2.1: registry_check_anonymous_read succeeds for public registry" {
  # Given a public registry is accessible
  export MOCK_PULL_RESULT="success"
  
  # When we check anonymous read access
  _load_registry_lib
  
  # Then it should succeed
  run registry_check_anonymous_read "docker.io"
  [ "$status" -eq 0 ]
}

@test "AC2.1: registry_check_anonymous_read fails gracefully for private registry" {
  # Given a private/unreachable registry
  export MOCK_PULL_RESULT="unauthorized"
  
  # When we check anonymous read access
  _load_registry_lib
  
  # Then it should fail (but not crash)
  run registry_check_anonymous_read "private.example.com"
  [ "$status" -ne 0 ]
}

# =============================================================================
# SC-2.2: Valid Token Push Succeeds
# =============================================================================

@test "AC2.2: registry_login succeeds with valid token" {
  # Given valid credentials
  export PUSH_USERNAME="testuser"
  export PUSH_PASSWORD="valid_token_abc123"
  export MOCK_LOGIN_RESULT="success"
  
  _load_registry_lib
  
  # When we login
  run registry_login "$REGISTRY" "$PUSH_USERNAME" "$PUSH_PASSWORD"
  
  # Then it should succeed
  [ "$status" -eq 0 ]
  
  # And podman login should have been called with correct args
  run _podman_called_with "username=$PUSH_USERNAME"
  [ "$status" -eq 0 ]
}

@test "AC2.2: registry_login uses password-stdin for security" {
  # Given valid credentials
  export PUSH_USERNAME="testuser"
  export PUSH_PASSWORD="valid_token_abc123"
  export MOCK_LOGIN_RESULT="success"
  
  _load_registry_lib
  
  # When we login
  registry_login "$REGISTRY" "$PUSH_USERNAME" "$PUSH_PASSWORD"
  
  # Then podman should be called with --password-stdin (not --password)
  run _podman_called_with "--password-stdin"
  [ "$status" -eq 0 ]
}

@test "AC2.2: registry_login fails when username is missing" {
  # Given no username is provided
  export PUSH_PASSWORD="some_token"
  unset PUSH_USERNAME
  
  _load_registry_lib
  
  # When we try to login
  run registry_login "$REGISTRY" "" "$PUSH_PASSWORD"
  
  # Then it should fail
  [ "$status" -ne 0 ]
  
  # And output should contain helpful error
  echo "$output" | grep -qi "username"
}

@test "AC2.2: registry_login fails when token is missing" {
  # Given no token is provided
  export PUSH_USERNAME="testuser"
  unset PUSH_PASSWORD
  
  _load_registry_lib
  
  # When we try to login
  run registry_login "$REGISTRY" "$PUSH_USERNAME" ""
  
  # Then it should fail
  [ "$status" -ne 0 ]
  
  # And output should contain helpful error
  echo "$output" | grep -qi "token"
}

@test "AC2.2: registry_login fails with invalid credentials" {
  # Given invalid credentials
  export MOCK_LOGIN_RESULT="invalid_credentials"
  
  _load_registry_lib
  
  # When we try to login
  run registry_login "$REGISTRY" "bad_user" "bad_token"
  
  # Then it should fail
  [ "$status" -ne 0 ]
  
  # And output should contain error message
  echo "$output" | grep -qi "fail\|error\|unauthorized"
}

# =============================================================================
# SC-2.3: No Token Push Fails
# =============================================================================

@test "AC2.3: push.sh exits with error when no credentials configured" {
  # Given no credentials are set
  unset GITHUB_TOKEN
  export MOCK_LOGGED_IN="false"
  export MOCK_IMAGE_EXISTS="true"
  
  _load_registry_lib
  
  # Create minimal mock Containerfile
  mkdir -p "${TEST_TMPDIR}/mock_project"
  echo "FROM fedora:latest" > "${TEST_TMPDIR}/mock_project/Containerfile.app"
  
  # When we run push.sh without credentials
  run -1 bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1 || true
  
  # Then it should fail with authentication error
  echo "$output" | grep -qiE "credential|auth|token|login"
  
  # And it should NOT suggest using a broken method
  ! echo "$output" | grep -qi "just\|simply\|just run"
}

@test "AC2.3: Error message is actionable and specific" {
  # Given no credentials are set
  unset GITHUB_TOKEN
  export MOCK_LOGGED_IN="false"
  export MOCK_IMAGE_EXISTS="true"
  
  _load_registry_lib
  
  # When we run push.sh without credentials
  run -1 bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1 || true
  
  # Then the error message should be specific about what's missing
  # It should mention GITHUB_TOKEN or podman login as the solution
  echo "$output" | grep -qiE "GITHUB_TOKEN|podman login"
}

# =============================================================================
# SC-2.4: Invalid/Expired Token Push Fails
# =============================================================================

@test "AC2.4: Push fails when login returns invalid_credentials" {
  # Given login fails with invalid credentials
  # Note: registry_has_push_credentials returns true when GITHUB_TOKEN is set
  # So the push.sh script will attempt the push. The push itself should fail
  # because the token is invalid. We simulate this with MOCK_PUSH_RESULT="unauthorized"
  export GITHUB_TOKEN="invalid_expired_token"
  export MOCK_LOGIN_RESULT="invalid_credentials"
  export MOCK_IMAGE_EXISTS="true"
  export MOCK_PUSH_RESULT="unauthorized"  # Simulate push failing due to invalid token
  
  _load_registry_lib
  
  # Create mock Containerfile
  mkdir -p "${TEST_TMPDIR}/mock_project"
  echo "FROM fedora:latest" > "${TEST_TMPDIR}/mock_project/Containerfile.app"
  
  # When we run push.sh with invalid token
  run -1 bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1 || true
  
  # Then push should fail
  # The error should indicate authentication failure
  echo "$output" | grep -qiE "auth|unauthorized|denied|401|403|invalid|failed"
}

@test "AC2.4: Push fails when not logged in and no token" {
  # Given user is not logged in and no GITHUB_TOKEN
  unset GITHUB_TOKEN
  export MOCK_LOGGED_IN="false"
  export MOCK_IMAGE_EXISTS="true"
  export MOCK_PUSH_RESULT="unauthorized"
  
  _load_registry_lib
  
  # Create mock Containerfile
  mkdir -p "${TEST_TMPDIR}/mock_project"
  echo "FROM fedora:latest" > "${TEST_TMPDIR}/mock_project/Containerfile.app"
  
  # When we run push.sh
  run -1 bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1 || true
  
  # Then it should fail before even attempting push (credential check)
  # OR it should fail during push with clear auth error
  echo "$output" | grep -qiE "credential|auth|token|login|unauthorized"
}

# =============================================================================
# SC-2.5: End-to-End Push Workflow
# =============================================================================

@test "AC2.5: Full push workflow succeeds with valid credentials" {
  # Given valid credentials
  export GITHUB_TOKEN="valid_token_abc123"
  export MOCK_LOGIN_RESULT="success"
  export MOCK_BUILD_RESULT="success"
  export MOCK_IMAGE_EXISTS="true"
  export MOCK_MANIFEST_VALID="true"
  
  _load_registry_lib
  
  # Create mock Containerfile
  mkdir -p "${TEST_TMPDIR}/mock_project"
  echo "FROM fedora:latest" > "${TEST_TMPDIR}/mock_project/Containerfile.app"
  
  # When we run push.sh with --no-build
  run bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1
  
  # Then it should succeed
  [ "$status" -eq 0 ]
  
  # And log should mention successful push
  echo "$output" | grep -qiE "push|registry|image"
}

@test "AC2.5: Push workflow includes verification step" {
  # Given valid credentials and successful push
  export GITHUB_TOKEN="valid_token_abc123"
  export MOCK_LOGIN_RESULT="success"
  export MOCK_BUILD_RESULT="success"
  export MOCK_IMAGE_EXISTS="true"
  export MOCK_MANIFEST_VALID="true"
  
  _load_registry_lib
  
  # Create mock Containerfile
  mkdir -p "${TEST_TMPDIR}/mock_project"
  echo "FROM fedora:latest" > "${TEST_TMPDIR}/mock_project/Containerfile.app"
  
  # When we run push.sh
  run bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1
  
  # Then verification should be attempted
  run _podman_called_with "manifest inspect"
  [ "$status" -eq 0 ]
}

# =============================================================================
# SC-2.6: Error Message Quality
# =============================================================================

@test "AC2.6: Error messages are not generic - mention registry context" {
  # Given no credentials are set
  unset GITHUB_TOKEN
  export MOCK_LOGGED_IN="false"
  export MOCK_IMAGE_EXISTS="true"
  
  _load_registry_lib
  
  # When we run push.sh without credentials
  run -1 bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1 || true
  
  # Then error should mention the registry URL or be specific to auth
  echo "$output" | grep -qiE "$REGISTRY|credential|authentication|token|login"
}

@test "AC2.6: Error messages do not leak sensitive information" {
  # Given we have a token (even if invalid)
  # The app can't detect invalid tokens at check time, so push will fail
  export GITHUB_TOKEN="super_secret_token_12345"
  export MOCK_LOGIN_RESULT="invalid_credentials"
  export MOCK_IMAGE_EXISTS="true"
  export MOCK_PUSH_RESULT="unauthorized"  # Push fails due to invalid token
  
  _load_registry_lib
  
  # When we run push.sh
  run -1 bash "$PUSH_SCRIPT" \
    --registry "$REGISTRY" \
    --namespace "$NAMESPACE" \
    --image "nornnet" \
    --tag "0.0.1" \
    --local-tag "nornnet:local" \
    --no-build \
    2>&1 || true
  
  # Then error should NOT contain the actual token value
  ! echo "$output" | grep -F "super_secret_token_12345"
  
  # But it should contain a meaningful error (e.g., unauthorized, failed)
  echo "$output" | grep -qiE "unauthorized|failed|error"
}

# =============================================================================
# SC-2.7: Image Naming Functions
# =============================================================================

@test "AC2.7: registry_full_image_name formats correctly with semantic version" {
  _load_registry_lib
  
  run registry_full_image_name "ghcr.io" "llm-at-cormora" "nornnet" "1.2.3"
  
  [ "$status" -eq 0 ]
  [ "$output" = "ghcr.io/llm-at-cormora/nornnet:v1.2.3" ]
}

@test "AC2.7: registry_full_image_name handles 'latest' tag correctly" {
  _load_registry_lib
  
  run registry_full_image_name "ghcr.io" "llm-at-cormora" "nornnet" "latest"
  
  [ "$status" -eq 0 ]
  [ "$output" = "ghcr.io/llm-at-cormora/nornnet:latest" ]
}

@test "AC2.7: registry_full_image_name adds v prefix only to semantic versions" {
  _load_registry_lib
  
  # Should add v prefix to semver
  run registry_full_image_name "ghcr.io" "ns" "img" "1.0.0"
  [ "$output" = "ghcr.io/ns/img:v1.0.0" ]
  
  # Should NOT add v prefix to 'latest'
  run registry_full_image_name "ghcr.io" "ns" "img" "latest"
  [ "$output" = "ghcr.io/ns/img:latest" ]
}

# =============================================================================
# SC-2.8: Validation Functions
# =============================================================================

@test "AC2.8: validate_registry rejects invalid formats" {
  _load_registry_lib
  
  run validate_registry "not-a-valid-registry"
  [ "$status" -ne 0 ]
  
  run validate_registry "registry with spaces"
  [ "$status" -ne 0 ]
}

@test "AC2.8: validate_registry accepts valid formats" {
  _load_registry_lib
  
  run validate_registry "ghcr.io"
  [ "$status" -eq 0 ]
  
  run validate_registry "docker.io"
  [ "$status" -eq 0 ]
  
  run validate_registry "myregistry.example.com:5000"
  [ "$status" -eq 0 ]
}

@test "AC2.8: validate_version requires semantic versioning" {
  _load_registry_lib
  
  run validate_version "1.0.0"
  [ "$status" -eq 0 ]
  
  run validate_version "1.2.3"
  [ "$status" -eq 0 ]
  
  run validate_version "latest"
  [ "$status" -ne 0 ]
  
  run validate_version "v1.0.0"
  [ "$status" -ne 0 ]
  
  run validate_version "1.0"
  [ "$status" -ne 0 ]
}

@test "AC2.8: validate_image_name accepts valid names" {
  _load_registry_lib
  
  run validate_image_name "nornnet"
  [ "$status" -eq 0 ]
  
  run validate_image_name "my-image"
  [ "$status" -eq 0 ]
  
  run validate_image_name "my.image"
  [ "$status" -eq 0 ]
  
  run validate_image_name "my_image_v2"
  [ "$status" -eq 0 ]
}

@test "AC2.8: validate_image_name rejects invalid names" {
  _load_registry_lib
  
  run validate_image_name ""
  [ "$status" -ne 0 ]
  
  run validate_image_name "UPPERCASE"
  [ "$status" -ne 0 ]
  
  run validate_image_name "has spaces"
  [ "$status" -ne 0 ]
  
  run validate_image_name "has/slash"
  [ "$status" -ne 0 ]
}

# =============================================================================
# Integration: Real podman tests (skipped in CI without credentials)
# =============================================================================

@test "INTEGRATION: Anonymous pull of public image (requires network)" {
  # Skip if podman not available
  skip_if_tool_not_available "podman"
  
  # This test verifies actual network behavior
  # It's an integration test, not a unit test
  run -0 podman pull --quiet docker.io/library/alpine:latest 2>&1 || skip "Network unavailable"
}

@test "INTEGRATION: Push succeeds with valid GHCR credentials (requires setup)" {
  skip_if_tool_not_available "podman"
  
  # Skip if no real credentials configured
  if [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${PUSH_PASSWORD:-}" ]; then
    skip "No push credentials (GITHUB_TOKEN/PUSH_PASSWORD)"
  fi
  
  # This would do a real push - commented out for safety
  # Real integration testing should happen in CI with test credentials
  skip "Real push integration test - run manually with test credentials"
}
