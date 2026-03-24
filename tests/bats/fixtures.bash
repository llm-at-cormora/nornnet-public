# Helper functions for test fixtures

# Calculate FIXTURES_DIR relative to the tests directory
TESTS_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME}")" && pwd)"
FIXTURES_DIR="$TESTS_DIR/fixtures"

get_fixture_path() {
  local fixture_name="$1"
  echo "$FIXTURES_DIR/$fixture_name"
}

copy_fixture() {
  local fixture_name="$1"
  local dest_dir="${2:-.}"
  cp "$(get_fixture_path "$fixture_name")" "$dest_dir/"
}
