#!/usr/bin/env bats
# Integration tests for configuration management

load '../bats/common.bash'

# Remove trailing slash from BATS_TEST_DIRNAME before using dirname
BATS_TEST_DIRNAME_TRIMMED="${BATS_TEST_DIRNAME%/}"
PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_DIRNAME_TRIMMED}")/.." && pwd)"
SCRIPT_DIR="${PROJECT_ROOT}/scripts"

setup() {
  export CONFIG_FILE="${PROJECT_ROOT}/config/default.conf"
}

teardown() {
  unset CONFIG_FILE
}

@test "config loader reads default config" {
  source "$SCRIPT_DIR/lib/config.sh"
  load_config
  
  [ -n "$DEFAULT_REGISTRY" ]
  [ -n "$DEFAULT_IMAGE_TAG" ]
}

@test "get_config returns value for known key" {
  source "$SCRIPT_DIR/lib/config.sh"
  load_config
  
  local registry
  registry="$(get_config "DEFAULT_REGISTRY")"
  
  [ -n "$registry" ]
  [ "$registry" = "ghcr.io/os2sandbox" ]
}

@test "get_config returns default for unknown key" {
  source "$SCRIPT_DIR/lib/config.sh"
  load_config
  
  local value
  value="$(get_config "UNKNOWN_KEY" "default-value")"
  
  [ "$value" = "default-value" ]
}
