#!/usr/bin/env bats

@test "tests/unit/ directory exists and is a directory" {
    [ -d "tests/unit" ]
}

@test "tests/integration/ directory exists and is a directory" {
    [ -d "tests/integration" ]
}

@test "tests/acceptance/ directory exists and is a directory" {
    [ -d "tests/acceptance" ]
}

@test "tests/bats/ directory exists and is a directory" {
    [ -d "tests/bats" ]
}

@test "tests/fixtures/ directory exists and is a directory" {
    [ -d "tests/fixtures" ]
}
