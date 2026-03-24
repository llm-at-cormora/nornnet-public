#!/usr/bin/env bats

load '../bats/common.bash'

@test "Containerfile.base exists" {
  assert_file_exists "Containerfile.base"
}

@test "Containerfile.base has FROM instruction" {
  run grep -q "^FROM" Containerfile.base
  assert_success
}

@test "Containerfile.base has bootc label" {
  run grep -q 'containers.bootc="1"' Containerfile.base
  assert_success
}

@test "Containerfile.config exists" {
  assert_file_exists "Containerfile.config"
}

@test "Containerfile.config uses ARG for base image" {
  run grep -q "^ARG BASE_IMAGE" Containerfile.config
  assert_success
}

@test "Containerfile.app exists" {
  assert_file_exists "Containerfile.app"
}

@test "Containerfile.app has CMD instruction" {
  run grep -q "^CMD" Containerfile.app
  assert_success
}
