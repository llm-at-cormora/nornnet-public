# tests/bats/test_doubles.bash
# Mock implementations for testing without real podman/bootc

# Mock podman that returns success with configurable output
mock_podman() {
  local mock_output="${PODMAN_MOCK_OUTPUT:-}"
  local mock_exit_code="${PODMAN_MOCK_EXIT_CODE:-0}"
  echo "$mock_output"
  return $mock_exit_code
}

# Mock bootc that returns success with configurable output
mock_bootc() {
  local mock_output="${BOOTC_MOCK_OUTPUT:-}"
  local mock_exit_code="${BOOTC_MOCK_EXIT_CODE:-0}"
  echo "$mock_output"
  return $mock_exit_code
}

# Mock image inspector
mock_image_inspect() {
  cat <<'EOF'
{
  "Id": "sha256:abc123",
  "Config": {
    "Labels": {
      "org.opencontainers.image.version": "0.1.0"
    }
  },
  "RootFS": {
    "Layers": ["sha256:layer1", "sha256:layer2"]
  }
}
EOF
}

# Setup/teardown helpers
setup_test_environment() {
  export PODMAN_MOCK_OUTPUT=""
  export PODMAN_MOCK_EXIT_CODE=0
  export BOOTC_MOCK_OUTPUT=""
  export BOOTC_MOCK_EXIT_CODE=0
}

teardown_test_environment() {
  unset PODMAN_MOCK_OUTPUT
  unset PODMAN_MOCK_EXIT_CODE
  unset BOOTC_MOCK_OUTPUT
  unset BOOTC_MOCK_EXIT_CODE
}
