#!/usr/bin/env bats

load '../bats/common.bash'
load '../bats/fixtures.bash'

@test "get_fixture_path returns absolute path" {
  run get_fixture_path "minimal Containerfile"
  
  assert_success
  echo "$output" | grep -q "fixtures"
  [ -f "$output" ]
}

@test "minimal Containerfile exists in fixtures" {
  local fixture_path
  fixture_path="$(get_fixture_path "minimal Containerfile")"
  
  assert_file_exists "$fixture_path"
}

@test "minimal Containerfile has bootc labels" {
  local fixture_path
  fixture_path="$(get_fixture_path "minimal Containerfile")"
  
  run grep -q 'containers.bootc="1"' "$fixture_path"
  assert_success
}

@test "copy_fixture copies file to destination" {
  local temp_dir
  temp_dir="$(mktemp -d)"
  
  run copy_fixture "minimal Containerfile" "$temp_dir"
  assert_success
  
  [ -f "$temp_dir/minimal Containerfile" ]
  
  rm -rf "$temp_dir"
}
