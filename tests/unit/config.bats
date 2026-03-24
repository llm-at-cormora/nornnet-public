#!/usr/bin/env bats

load '../bats/common.bash'

@test "config/default.conf exists" {
  assert_file_exists "config/default.conf"
}

@test "config/default.conf defines DEFAULT_REGISTRY" {
  run grep -q 'DEFAULT_REGISTRY=' config/default.conf
  assert_success
}

@test "config/default.conf defines DEFAULT_IMAGE_TAG" {
  run grep -q 'DEFAULT_IMAGE_TAG=' config/default.conf
  assert_success
}

@test "scripts/lib/config.sh exists" {
  assert_file_exists "scripts/lib/config.sh"
}

@test "config.sh defines load_config function" {
  run grep -q "^load_config()" scripts/lib/config.sh
  assert_success
}

@test "config.sh defines get_config function" {
  run grep -q "^get_config()" scripts/lib/config.sh
  assert_success
}
