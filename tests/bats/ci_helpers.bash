# Helpers for CI/CD integration

# Detect if running in CI
is_ci() {
  [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]
}

# Output test summary in CI format
ci_test_summary() {
  if is_ci; then
    echo "::group::Test Results"
    echo "Tests: $BATS_TEST_COUNT total, $BATS_ASSERTIONS_FAILED failures"
    echo "::endgroup::"
  fi
}

# Skip test with explanation for CI
ci_skip_if_unavailable() {
  local tool="$1"
  local reason="${2:-Tool not available}"
  
  if ! command -v "$tool" &> /dev/null; then
    if is_ci; then
      echo "::notice::Skipping: $reason"
    fi
    skip "$reason"
  fi
}

# Require minimum tool version
require_version() {
  local tool="$1"
  local min_version="$2"
  
  if ! command -v "$tool" &> /dev/null; then
    skip "$tool not installed"
  fi
  
  local actual_version
  actual_version="$("$tool" --version 2>&1 | head -1)"
  echo "Note: $tool version check: require >= $min_version, found: $actual_version"
}
