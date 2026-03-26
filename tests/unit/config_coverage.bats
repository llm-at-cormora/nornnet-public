#!/usr/bin/env bats

# Code Coverage tests for config.sh library
# Tests error paths, edge cases, and boundary conditions

load '../bats/common.bash'

# =============================================================================
# Test setup and teardown
# =============================================================================

setup() {
  # Save original environment
  ORIGINAL_CONFIG_FILE="${CONFIG_FILE:-}"
  # Clear CONFIG_FILE to ensure clean state for each test
  unset CONFIG_FILE
}

teardown() {
  # Restore original environment
  if [ -n "$ORIGINAL_CONFIG_FILE" ]; then
    export CONFIG_FILE="$ORIGINAL_CONFIG_FILE"
  else
    unset CONFIG_FILE
  fi
}

# =============================================================================
# load_config() tests
# =============================================================================

@test "load_config loads valid config file" {
  # Create a temp config file with known values
  local temp_config
  temp_config="$(mktemp)"
  
  # Write test config
  cat > "$temp_config" << 'EOF'
TEST_VAR="test_value"
TEST_NUM="42"
EOF
  
  export CONFIG_FILE="$temp_config"
  
  # Source and call load_config
  load() { load_config; }
  run bash -c "source scripts/lib/config.sh && load_config && echo \"TEST_VAR=\${TEST_VAR}\""
  
  rm -f "$temp_config"
  
  assert_success
  assert_output_contains "TEST_VAR=test_value"
}

@test "load_config with missing file does not error" {
  # Set CONFIG_FILE to non-existent path
  export CONFIG_FILE="/nonexistent/path/$(date +%s)_config_$$"
  
  # Source and call load_config - should succeed silently
  run bash -c "source scripts/lib/config.sh && load_config"
  
  assert_success
}

@test "load_config uses CONFIG_FILE env var" {
  # Create a temp config file with unique marker
  local temp_config
  temp_config="$(mktemp)"
  echo 'CUSTOM_MARKER="it_works"' > "$temp_config"
  
  export CONFIG_FILE="$temp_config"
  
  # Source and verify the custom config was loaded
  run bash -c "source scripts/lib/config.sh && load_config && echo \"CUSTOM_MARKER=\${CUSTOM_MARKER}\""
  
  rm -f "$temp_config"
  
  assert_success
  assert_output_contains "CUSTOM_MARKER=it_works"
}

@test "load_config defaults to config/default.conf" {
  # When CONFIG_FILE not set, verify default is used
  # default.conf should exist and be loadable
  run bash -c "source scripts/lib/config.sh && load_config && echo 'loaded'"
  
  assert_success
}

@test "load_config sources file with shell variables" {
  # Test that shell variable expansion works
  local temp_config
  temp_config="$(mktemp)"
  
  cat > "$temp_config" << 'EOF'
BASE_DIR="/opt"
DATA_DIR="${BASE_DIR}/data"
EOF
  
  export CONFIG_FILE="$temp_config"
  
  run bash -c "source scripts/lib/config.sh && load_config && echo \"DATA_DIR=\${DATA_DIR}\""
  
  rm -f "$temp_config"
  
  assert_success
  assert_output_contains "DATA_DIR=/opt/data"
}

# =============================================================================
# get_config() tests
# =============================================================================

@test "get_config returns value from environment" {
  # Set an env var, call get_config
  export MY_CUSTOM_VAR="from_environment"
  
  run bash -c "source scripts/lib/config.sh && get_config 'MY_CUSTOM_VAR'"
  
  assert_success
  [ "$output" = "from_environment" ]
}

@test "get_config returns default when key not set" {
  # Don't set UNSET_VAR_TEST, call get_config with default
  unset UNSET_VAR_TEST
  
  run bash -c "source scripts/lib/config.sh && get_config 'UNSET_VAR_TEST' 'default_value'"
  
  assert_success
  [ "$output" = "default_value" ]
}

@test "get_config with empty default returns empty string" {
  # Call get_config with empty string as default
  unset EMPTY_DEFAULT_TEST
  
  run bash -c "source scripts/lib/config.sh && get_config 'EMPTY_DEFAULT_TEST' ''"
  
  assert_success
  [ "$output" = "" ]
}

@test "get_config with special characters in value" {
  # Test values with spaces, quotes, special chars
  export SPECIAL_VAR='value with spaces'
  
  run bash -c "source scripts/lib/config.sh && get_config 'SPECIAL_VAR'"
  
  assert_success
  [ "$output" = "value with spaces" ]
}

@test "get_config with quotes in value" {
  export QUOTES_VAR='value with "double quotes" and '\''single'\'' quotes'
  
  run bash -c "source scripts/lib/config.sh && get_config 'QUOTES_VAR'"
  
  assert_success
  [ "$output" = 'value with "double quotes" and '\''single'\'' quotes' ]
}

@test "get_config with backslash in value" {
  export BACKSLASH_VAR='path\\with\\backslashes'
  
  run bash -c "source scripts/lib/config.sh && get_config 'BACKSLASH_VAR'"
  
  assert_success
  [ "$output" = 'path\\with\\backslashes' ]
}

@test "get_config with newline in value" {
  export NEWLINE_VAR=$'line1\nline2\nline3'
  
  run bash -c "source scripts/lib/config.sh && get_config 'NEWLINE_VAR'"
  
  assert_success
  [ "$output" = $'line1\nline2\nline3' ]
}

@test "get_config with empty env var returns empty string" {
  # Set var but make it empty
  export EMPTY_VAR=""
  
  run bash -c "source scripts/lib/config.sh && get_config 'EMPTY_VAR'"
  
  assert_success
  [ "$output" = "" ]
}

@test "get_config with no arguments returns usage error" {
  run bash -c "source scripts/lib/config.sh && get_config"
  
  # Should fail because $1 (key) is empty
  assert_failure
}

@test "get_config with only key (no default) for unset var" {
  # Call get_config with unset variable and no default
  unset NONEXISTENT_VAR
  
  run bash -c "source scripts/lib/config.sh && get_config 'NONEXISTENT_VAR'"
  
  assert_success
  [ "$output" = "" ]
}

@test "get_config with number values" {
  export INT_VAR="12345"
  export FLOAT_VAR="3.14159"
  
  run bash -c "source scripts/lib/config.sh && get_config 'INT_VAR'"
  assert_success
  [ "$output" = "12345" ]
  
  run bash -c "source scripts/lib/config.sh && get_config 'FLOAT_VAR'"
  assert_success
  [ "$output" = "3.14159" ]
}

@test "get_config with unicode characters" {
  export UNICODE_VAR="Héllo Wörld 🎉"
  
  run bash -c "source scripts/lib/config.sh && get_config 'UNICODE_VAR'"
  
  assert_success
  [ "$output" = "Héllo Wörld 🎉" ]
}

@test "get_config prioritizes env over default" {
  export TEST_PRIORITY="from_env"
  
  run bash -c "source scripts/lib/config.sh && get_config 'TEST_PRIORITY' 'from_default'"
  
  assert_success
  [ "$output" = "from_env" ]
}

@test "get_config default value with special characters" {
  unset SPECIAL_DEFAULT
  
  run bash -c "source scripts/lib/config.sh && get_config 'SPECIAL_DEFAULT' 'default with spaces and \"quotes\"'"
  
  assert_success
  [ "$output" = 'default with spaces and "quotes"' ]
}
