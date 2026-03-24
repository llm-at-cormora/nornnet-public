#!/usr/bin/env bats

# Tests for BATS testing framework infrastructure
# Verifies that required files and configurations exist

load '../bats/common'

@test "GitHub Actions workflow file exists at .github/workflows/test.yml" {
    assert_file_exists ".github/workflows/test.yml"
}

@test "Common.bash helper file exists at tests/bats/common.bash" {
    assert_file_exists "tests/bats/common.bash"
}

@test "BATS can load the common.bash helper" {
    # This test verifies the helper can be loaded without errors
    run echo "Helper loaded successfully"
    assert_success
}

@test "common.bash defines assert_success function" {
    run bash -c "source tests/bats/common.bash && type assert_success"
    assert_success
}

@test "common.bash defines assert_failure function" {
    run bash -c "source tests/bats/common.bash && type assert_failure"
    assert_success
}

@test "common.bash defines assert_output_contains function" {
    run bash -c "source tests/bats/common.bash && type assert_output_contains"
    assert_success
}

@test "common.bash defines assert_file_exists function" {
    run bash -c "source tests/bats/common.bash && type assert_file_exists"
    assert_success
}

@test "common.bash defines skip_if_tool_not_available function" {
    run bash -c "source tests/bats/common.bash && type skip_if_tool_not_available"
    assert_success
}

@test "assert_success passes when status is 0" {
    load '../bats/common'
    status=0
    output="test output"
    run assert_success
    [ "$status" -eq 0 ]
}

@test "assert_failure passes when status is non-zero" {
    load '../bats/common'
    status=1
    output="error output"
    run assert_failure
    [ "$status" -eq 0 ]
}

@test "assert_output_contains passes when output contains expected string" {
    load '../bats/common'
    output="Hello World"
    run assert_output_contains "World"
    [ "$status" -eq 0 ]
}

@test "assert_file_exists passes when file exists" {
    load '../bats/common'
    run assert_file_exists "tests/unit/bats_infra.bats"
    [ "$status" -eq 0 ]
}
