#!/usr/bin/env bats

load '../bats/common.bash'

@test "scripts/build.sh exists" {
  assert_file_exists "scripts/build.sh"
}

@test "scripts/build.sh is executable" {
  run test -x scripts/build.sh
  assert_success
}

@test "scripts/build.sh --help shows usage" {
  run scripts/build.sh --help
  assert_success
  assert_output_contains "Usage:"
  assert_output_contains "layer"
  assert_output_contains "tag"
}

@test "scripts/lib/logging.sh exists" {
  assert_file_exists "scripts/lib/logging.sh"
}

@test "logging.sh defines log_info function" {
  run grep -q "^log_info()" scripts/lib/logging.sh
  assert_success
}

@test "logging.sh defines log_error function" {
  run grep -q "^log_error()" scripts/lib/logging.sh
  assert_success
}

@test "logging.sh defines log_debug function" {
  run grep -q "^log_debug()" scripts/lib/logging.sh
  assert_success
}
