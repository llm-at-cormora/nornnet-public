#!/usr/bin/env bats

load '../bats/common.bash'
load '../bats/test_doubles.bash'

@test "mock_podman returns configured output" {
  export PODMAN_MOCK_OUTPUT="test output"
  export PODMAN_MOCK_EXIT_CODE=0
  
  run mock_podman
  
  assert_success
  [ "$output" = "test output" ]
}

@test "mock_podman returns configured exit code" {
  export PODMAN_MOCK_OUTPUT=""
  export PODMAN_MOCK_EXIT_CODE=1
  
  run mock_podman
  
  assert_failure
}

@test "mock_bootc returns configured output" {
  export BOOTC_MOCK_OUTPUT="bootc output"
  export BOOTC_MOCK_EXIT_CODE=0
  
  run mock_bootc
  
  assert_success
  [ "$output" = "bootc output" ]
}

@test "mock_bootc returns configured exit code" {
  export BOOTC_MOCK_OUTPUT=""
  export BOOTC_MOCK_EXIT_CODE=1
  
  run mock_bootc
  
  assert_failure
}

@test "mock_image_inspect returns valid JSON structure" {
  run mock_image_inspect
  
  assert_success
  echo "$output" | grep -q '"Id"'
  echo "$output" | grep -q '"Config"'
  echo "$output" | grep -q '"RootFS"'
}

@test "setup_test_environment clears mock state" {
  export PODMAN_MOCK_OUTPUT="dirty"
  export PODMAN_MOCK_EXIT_CODE=99
  
  setup_test_environment
  
  [ -z "$PODMAN_MOCK_OUTPUT" ]
  [ "$PODMAN_MOCK_EXIT_CODE" -eq 0 ]
}
