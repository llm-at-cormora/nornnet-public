# Shared test utilities for nornnet tests

# Assert command succeeds
assert_success() {
  if [ $status -ne 0 ]; then
    echo "Expected success, got exit code $status"
    echo "Output: $output"
    return 1
  fi
}

# Assert command fails
assert_failure() {
  if [ $status -eq 0 ]; then
    echo "Expected failure, got success"
    echo "Output: $output"
    return 1
  fi
}

# Assert output contains string
assert_output_contains() {
  local expected="$1"
  if ! echo "$output" | grep -q "$expected"; then
    echo "Expected output to contain: $expected"
    echo "Actual output: $output"
    return 1
  fi
}

# Assert file exists
assert_file_exists() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Expected file to exist: $file"
    return 1
  fi
}

# Skip if tool not available
skip_if_tool_not_available() {
  local tool="$1"
  if ! command -v "$tool" &> /dev/null; then
    skip "$tool not installed"
  fi
}
