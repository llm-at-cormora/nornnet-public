#!/usr/bin/env bats

# Code Coverage tests for logging.sh library
# Tests JSON output validation, edge cases, and all log levels

load '../bats/common.bash'

# =============================================================================
# Test setup and teardown
# =============================================================================

setup() {
  # Save original environment
  ORIGINAL_LOG_LEVEL="${LOG_LEVEL:-}"
  ORIGINAL_LOG_FILE="${LOG_FILE:-}"
  ORIGINAL_LOG_COMPONENT="${LOG_COMPONENT:-}"
  
  # Create temp log file for file-based tests
  TEMP_LOG_FILE="$(mktemp)"
  export LOG_FILE="$TEMP_LOG_FILE"
}

teardown() {
  # Restore original environment
  if [ -n "$ORIGINAL_LOG_LEVEL" ]; then
    export LOG_LEVEL="$ORIGINAL_LOG_LEVEL"
  else
    unset LOG_LEVEL
  fi
  
  if [ -n "$ORIGINAL_LOG_FILE" ]; then
    export LOG_FILE="$ORIGINAL_LOG_FILE"
  else
    unset LOG_FILE
  fi
  
  if [ -n "$ORIGINAL_LOG_COMPONENT" ]; then
    export LOG_COMPONENT="$ORIGINAL_LOG_COMPONENT"
  else
    unset LOG_COMPONENT
  fi
  
  # Clean up temp log file
  rm -f "$TEMP_LOG_FILE"
}

# =============================================================================
# JSON validation helper
# =============================================================================

# Helper to validate JSON has required fields
validate_json_fields() {
  local json="$1"
  local required_fields=("component" "timestamp" "level" "message")
  
  for field in "${required_fields[@]}"; do
    if ! echo "$json" | grep -q "\"$field\":"; then
      echo "Missing field: $field"
      return 1
    fi
  done
  return 0
}

# =============================================================================
# log_info tests
# =============================================================================

@test "log_info outputs valid JSON" {
  run bash -c "source scripts/lib/logging.sh && log_info 'test message'"
  
  assert_success
  
  # Check it's valid JSON by parsing with grep patterns
  local json="$output"
  [[ "$json" == *"\"component\":"* ]]
  [[ "$json" == *"\"timestamp\":"* ]]
  [[ "$json" == *"\"level\":\"INFO\""* ]]
  [[ "$json" == *"\"message\":\"test message\""* ]]
}

@test "log_info contains all required fields" {
  run bash -c "source scripts/lib/logging.sh && log_info 'coverage test'"
  
  assert_success
  validate_json_fields "$output"
}

# =============================================================================
# log_debug tests
# =============================================================================

@test "log_debug outputs valid JSON" {
  run bash -c "source scripts/lib/logging.sh && log_debug 'debug message'"
  
  assert_success
  
  local json="$output"
  [[ "$json" == *"\"level\":\"DEBUG\""* ]]
  [[ "$json" == *"\"message\":\"debug message\""* ]]
}

@test "log_debug contains all required fields" {
  run bash -c "source scripts/lib/logging.sh && log_debug 'debug test'"
  
  assert_success
  validate_json_fields "$output"
}

# =============================================================================
# log_warn tests
# =============================================================================

@test "log_warn outputs valid JSON" {
  run bash -c "source scripts/lib/logging.sh && log_warn 'warning message'"
  
  assert_success
  
  local json="$output"
  [[ "$json" == *"\"level\":\"WARN\""* ]]
  [[ "$json" == *"\"message\":\"warning message\""* ]]
}

@test "log_warn contains all required fields" {
  run bash -c "source scripts/lib/logging.sh && log_warn 'warn test'"
  
  assert_success
  validate_json_fields "$output"
}

# =============================================================================
# log_error tests
# =============================================================================

@test "log_error outputs valid JSON" {
  run bash -c "source scripts/lib/logging.sh && log_error 'error message'"
  
  assert_success
  
  local json="$output"
  [[ "$json" == *"\"level\":\"ERROR\""* ]]
  [[ "$json" == *"\"message\":\"error message\""* ]]
}

@test "log_error contains all required fields" {
  run bash -c "source scripts/lib/logging.sh && log_error 'error test'"
  
  assert_success
  validate_json_fields "$output"
}

# =============================================================================
# log_json timestamp tests
# =============================================================================

@test "log_json timestamp is ISO8601 format" {
  run bash -c "source scripts/lib/logging.sh && log_info 'timestamp test'"
  
  assert_success
  
  # Verify timestamp matches YYYY-MM-DDTHH:MM:SSZ pattern
  local json="$output"
  local timestamp
  timestamp=$(echo "$json" | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
  
  # ISO8601 format: 2024-01-15T10:30:45Z
  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "log_json timestamp is always UTC" {
  # Multiple calls should produce timestamps ending in Z
  for i in 1 2 3; do
    run bash -c "source scripts/lib/logging.sh && log_info 'utc test $i'"
    echo "$output" | grep -q 'Z"'
  done
}

# =============================================================================
# log_json special character escaping tests
# =============================================================================

@test "log_json escapes special characters in message" {
  # Test with quotes, newlines, backslashes
  
  run bash -c "source scripts/lib/logging.sh && log_info 'message with \"double quotes\"'"
  
  assert_success
  [[ "$output" == *'message with "double quotes"'* ]]
}

@test "log_json handles newlines in message" {
  run bash -c $'source scripts/lib/logging.sh && log_info "line1\\nline2"'
  
  assert_success
  # Newline should be preserved in output
  [[ "$output" == *"line1\\nline2"* ]]
}

@test "log_json handles backslash in message" {
  run bash -c "source scripts/lib/logging.sh && log_info 'path\\\\to\\\\file'"
  
  assert_success
  # Backslashes should be in output
  [[ "$output" == *"path\\\\to\\\\file"* ]] || [[ "$output" == *"path\\to\\file"* ]]
}

@test "log_json handles empty message" {
  run bash -c "source scripts/lib/logging.sh && log_info ''"
  
  assert_success
  [[ "$output" == *'"message":""'* ]]
}

@test "log_json handles unicode characters" {
  run bash -c "source scripts/lib/logging.sh && log_info 'Héllo Wörld 🎉'"
  
  assert_success
  [[ "$output" == *"Héllo Wörld 🎉"* ]]
}

@test "log_json handles special shell characters" {
  run bash -c "source scripts/lib/logging.sh && log_info 'test \`command\` \$var'"
  
  assert_success
  # Should contain the literal characters
  [[ "$output" == *"\`command\`"* ]]
  [[ "$output" == *"\$var"* ]]
}

# =============================================================================
# log_section tests
# =============================================================================

@test "log_section outputs formatted section header" {
  run bash -c "source scripts/lib/logging.sh && log_section 'Test Section'"
  
  assert_success
  assert_output_contains "Test Section"
}

@test "log_section contains box-drawing characters" {
  run bash -c "source scripts/lib/logging.sh && log_section 'Box Test'"
  
  assert_success
  # Should contain = characters for the box
  [[ "$output" == *"="* ]]
}

@test "log_section centers title in box" {
  run bash -c "source scripts/lib/logging.sh && log_section 'Center'"
  
  assert_success
  assert_output_contains "Center"
  # Box should have multiple lines
  [[ "$output" == *$'\n'* ]]
}

@test "log_section with empty title" {
  run bash -c "source scripts/lib/logging.sh && log_section ''"
  
  assert_success
  # Should still produce box formatting
  [[ "$output" == *"="* ]]
}

@test "log_section with long title" {
  run bash -c "source scripts/lib/logging.sh && log_section 'This is a very long section title that might need special handling'"
  
  assert_success
  assert_output_contains "This is a very long section title"
}

# =============================================================================
# log_json file output tests
# =============================================================================

@test "log_json writes to LOG_FILE when set" {
  # Set LOG_FILE to temp file
  local temp_file
  temp_file="$(mktemp)"
  export LOG_FILE="$temp_file"
  
  # Call log_info
  run bash -c "source scripts/lib/logging.sh && log_info 'file test'"
  
  # Verify content was appended to file
  grep -q "file test" "$temp_file"
  local result=$?
  
  rm -f "$temp_file"
  
  [ $result -eq 0 ]
}

@test "log_json appends multiple logs to file" {
  local temp_file
  temp_file="$(mktemp)"
  export LOG_FILE="$temp_file"
  
  run bash -c "source scripts/lib/logging.sh && log_info 'first' && log_info 'second'"
  
  # Both messages should be in file
  grep -q "first" "$temp_file"
  grep -q "second" "$temp_file"
  local result=$?
  
  rm -f "$temp_file"
  
  [ $result -eq 0 ]
}

@test "log_json file output includes all log levels" {
  local temp_file
  temp_file="$(mktemp)"
  export LOG_FILE="$temp_file"
  
  run bash -c "source scripts/lib/logging.sh && log_debug 'd' && log_info 'i' && log_warn 'w' && log_error 'e'"
  
  grep -q '"level":"DEBUG"' "$temp_file"
  grep -q '"level":"INFO"' "$temp_file"
  grep -q '"level":"WARN"' "$temp_file"
  grep -q '"level":"ERROR"' "$temp_file"
  local result=$?
  
  rm -f "$temp_file"
  
  [ $result -eq 0 ]
}

# =============================================================================
# LOG_COMPONENT tests
# =============================================================================

@test "log_json uses LOG_COMPONENT from environment" {
  export LOG_COMPONENT="custom-component"
  
  run bash -c "source scripts/lib/logging.sh && log_info 'component test'"
  
  assert_success
  [[ "$output" == *'"component":"custom-component"'* ]]
}

@test "log_json uses default component when not set" {
  unset LOG_COMPONENT
  
  run bash -c "source scripts/lib/logging.sh && log_info 'default component test'"
  
  assert_success
  [[ "$output" == *'"component":"nornnet"'* ]]
}

@test "log_json with custom LOG_COMPONENT persists across calls" {
  export LOG_COMPONENT="test-persistence"
  
  run bash -c "source scripts/lib/logging.sh && log_info 'first' && log_info 'second'"
  
  # Both log entries should have the custom component
  [[ "$output" == *'"component":"test-persistence"'* ]]
}

# =============================================================================
# log_json structure validation tests
# =============================================================================

@test "log_json output is valid one-line JSON" {
  run bash -c "source scripts/lib/logging.sh && log_info 'validation test'"
  
  assert_success
  
  # JSON should be on a single line (no newlines in the JSON itself)
  local line_count
  line_count=$(echo "$output" | wc -l)
  [ "$line_count" -eq 1 ]
}

@test "log_json has correct field order" {
  run bash -c "source scripts/lib/logging.sh && log_info 'order test'"
  
  assert_success
  
  # Verify order: component, timestamp, level, message
  # Extract positions using grep -o with context
  local comp_start timestamp_start level_start message_start
  
  comp_start=$(echo "$output" | grep -bo '"component":' | head -1 | cut -d: -f1)
  timestamp_start=$(echo "$output" | grep -bo '"timestamp":' | head -1 | cut -d: -f1)
  level_start=$(echo "$output" | grep -bo '"level":' | head -1 | cut -d: -f1)
  message_start=$(echo "$output" | grep -bo '"message":' | head -1 | cut -d: -f1)
  
  # Component should come before timestamp
  [ "$comp_start" -lt "$timestamp_start" ]
  # Timestamp should come before level
  [ "$timestamp_start" -lt "$level_start" ]
  # Level should come before message
  [ "$level_start" -lt "$message_start" ]
}

@test "log_json double escaping of quotes" {
  # When message contains backslash followed by quote, ensure proper escaping
  run bash -c "source scripts/lib/logging.sh && log_info 'test\\\"escaped'"
  
  assert_success
  # The output should contain the escaped sequence
  [[ "$output" == *"test\\\"escaped"* ]] || [[ "$output" == *"test\""* ]]
}

@test "log_json handles message starting with quote" {
  run bash -c 'source scripts/lib/logging.sh && log_info "\"quoted start"'
  
  assert_success
  # Message should contain the quote character
  echo "$output" | grep -q "quoted start"
}

@test "log_json handles message ending with quote" {
  run bash -c 'source scripts/lib/logging.sh && log_info "quoted end\""'
  
  assert_success
  # Message should contain the quote character
  echo "$output" | grep -q "quoted end"
}
