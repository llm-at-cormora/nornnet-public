#!/usr/bin/env bats

# Tests for CI/CD helper utilities

load '../bats/common'
load '../bats/ci_helpers'

@test "is_ci returns true when CI is set" {
  export CI=true
  unset GITHUB_ACTIONS
  
  run is_ci
  
  assert_success
}

@test "is_ci returns false when CI is not set" {
  unset CI
  unset GITHUB_ACTIONS
  
  run is_ci
  
  [ $status -ne 0 ]
}

@test "is_ci returns true when GITHUB_ACTIONS is set" {
  export GITHUB_ACTIONS=true
  unset CI
  
  run is_ci
  
  assert_success
}

@test "ci_skip_if_unavailable skips when tool missing" {
  run ci_skip_if_unavailable "nonexistent_tool_xyz_12345" "Test tool missing"
  
  [ $status -eq 0 ]
}

@test "ci_test_summary outputs in CI format when CI=true" {
  export CI=true
  
  run ci_test_summary
  
  assert_output_contains "Test Results"
}

@test "ci_helpers.bash defines is_ci function" {
  run bash -c "source tests/bats/ci_helpers.bash && type is_ci"
  assert_success
}

@test "ci_helpers.bash defines ci_test_summary function" {
  run bash -c "source tests/bats/ci_helpers.bash && type ci_test_summary"
  assert_success
}

@test "ci_helpers.bash defines ci_skip_if_unavailable function" {
  run bash -c "source tests/bats/ci_helpers.bash && type ci_skip_if_unavailable"
  assert_success
}

@test "ci_helpers.bash defines require_version function" {
  run bash -c "source tests/bats/ci_helpers.bash && type require_version"
  assert_success
}
