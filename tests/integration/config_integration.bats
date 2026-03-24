#!/usr/bin/env bats
# Integration tests for configuration management

load '../bats/common.bash'

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/../../.." && pwd)/scripts"

@test "config loader reads default config" {
  export CONFIG_FILE="config/default.conf"
  
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
