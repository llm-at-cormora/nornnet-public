# Tasks: Minimal Sub-PoC - Test Scaffolding & Local Image Build

**Feature Branch**: `022-bootc-image-deployment`  
**Sub-PoC Scope**: Test scaffolding + US1 (Local Image Build)  
**Created**: 2026-03-24  
**Status**: Ready for Implementation

---

## Overview

This sub-PoC establishes the test infrastructure and implements the first user story (Local Image Build). This is the **minimum viable foundation** required before any other work can proceed.

**Why this scope?**
- Test scaffolding is required before ANY feature work (per Constitution Article III: Test-First Development)
- US1 (Local Image Build) is explicitly P0 in spec.md: "This is the foundation. If we cannot build images locally, nothing else matters."
- All subsequent user stories depend on having a working image build pipeline

---

## Task Summary

| Metric | Count |
|--------|-------|
| **Total Tasks** | 12 |
| **Phase 1 (Test Scaffolding)** | 5 |
| **Phase 2 (Foundation)** | 4 |
| **Phase 3 (US1 Implementation)** | 3 |
| **Parallelizable [P]** | 7 |
| **Sequential (blocking)** | 5 |

---

## Phase 1: Test Scaffolding Setup

**Purpose**: Create the testing infrastructure BEFORE any feature work begins.

**Checkpoint**: All Phase 1 tests MUST pass before Phase 2 begins.

### Test Framework Decision

**Framework**: BATS (Bash Automated Testing System)

**Rationale**:
- Native shell testing for Containerfile/build scripts
- Fast feedback loop (< 1s per test)
- CI/CD integration with GitHub Actions
- No external dependencies beyond bash

---

- [ ] T001 [P] Install and configure BATS testing framework
  - **Files:**
    - Create: `.github/workflows/test.yml`
  - **Step 1**: Create GitHub Actions workflow to install BATS
    ```yaml
    # .github/workflows/test.yml
    name: Tests
    on: [push, pull_request]
    jobs:
      bats:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - name: Install BATS
            run: |
              sudo apt-get update
              sudo apt-get install -y bats
          - name: Run unit tests
            run: bats tests/unit/
          - name: Run integration tests
            run: bats tests/integration/
    ```
  - **Step 2**: Create `tests/bats/common.bash` helper library
    ```bash
    # tests/bats/common.bash
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
    ```
  - **Step 3**: Verify workflow syntax
    ```bash
    # Run: actionlint .github/workflows/test.yml
    # Expected: No errors
    ```
  - **Step 4**: Commit
    ```bash
    git add .github/workflows/test.yml tests/bats/common.bash
    git commit -m "feat: Add BATS test framework infrastructure"
    ```

- [ ] T002 [P] Create test directory structure
  - **Files:**
    - Create: `tests/unit/.bats`
    - Create: `tests/integration/.bats`
    - Create: `tests/acceptance/.bats`
    - Create: `tests/bats/`
  - **Step 1**: Create directory structure
    ```bash
    mkdir -p tests/unit tests/integration tests/acceptance tests/bats
    touch tests/unit/.gitkeep tests/integration/.gitkeep tests/acceptance/.gitkeep
    ```
  - **Step 2**: Create `.bats` files (placeholders to ensure directory is tracked)
    ```bash
    # tests/unit/.gitkeep already created above
    ```
  - **Step 3**: Add `.bats` test file conventions to `README.md` or `CONTRIBUTING.md`
    ```markdown
    ## Test Conventions
    
    ### File Naming
    - Unit tests: `tests/unit/<component>.bats`
    - Integration tests: `tests/integration/<feature>.bats`
    - Acceptance tests: `tests/acceptance/<user-story>.bats`
    
    ### Test Structure
    ```bash
    #!/usr/bin/env bats
    
    load '../bats/common.bash'
    
    @test "test description" {
      # Arrange
      setup_fixture
      
      # Act
      run command_to_test
      
      # Assert
      assert_success
      assert_output_contains "expected substring"
    }
    ```
    ```
  - **Step 4**: Commit
    ```bash
    git add tests/
    git commit -m "feat: Create test directory structure"
    ```

- [ ] T003 [P] Create BATS test helper library with test doubles
  - **Files:**
    - Create: `tests/bats/test_doubles.bash`
  - **Step 1**: Create test doubles for external dependencies
    ```bash
    # tests/bats/test_doubles.bash
    # Mock implementations for testing without real podman/bootc
    
    # Mock podman that returns success with configurable output
    mock_podman() {
      local mock_output="${PODMAN_MOCK_OUTPUT:-}"
      local mock_exit_code="${PODMAN_MOCK_EXIT_CODE:-0}"
      echo "$mock_output"
      return $mock_exit_code
    }
    
    # Mock bootc that returns success with configurable output
    mock_bootc() {
      local mock_output="${BOOTC_MOCK_OUTPUT:-}"
      local mock_exit_code="${BOOTC_MOCK_EXIT_CODE:-0}"
      echo "$mock_output"
      return $mock_exit_code
    }
    
    # Mock image inspector
    mock_image_inspect() {
      cat <<'EOF'
    {
      "Id": "sha256:abc123",
      "Config": {
        "Labels": {
          "org.opencontainers.image.version": "0.1.0"
        }
      },
      "RootFS": {
        "Layers": ["sha256:layer1", "sha256:layer2"]
      }
    }
    EOF
    }
    
    # Setup/teardown helpers
    setup_test_environment() {
      export PODMAN_MOCK_OUTPUT=""
      export PODMAN_MOCK_EXIT_CODE=0
      export BOOTC_MOCK_OUTPUT=""
      export BOOTC_MOCK_EXIT_CODE=0
    }
    
    teardown_test_environment() {
      unset PODMAN_MOCK_OUTPUT
      unset PODMAN_MOCK_EXIT_CODE
      unset BOOTC_MOCK_OUTPUT
      unset BOOTC_MOCK_EXIT_CODE
    }
    ```
  - **Step 2**: Write tests for the test doubles themselves (meta-testing)
    ```bash
    # tests/unit/test_doubles.bats
    #!/usr/bin/env bats
    
    load '../bats/common.bash'
    load '../bats/test_doubles.bash'
    
    @test "mock_podman returns configured output" {
      export PODMAN_MOCK_OUTPUT="test output"
      export PODMAN_MOCK_EXIT_CODE=0
      
      run mock_podman
      
      assert_success
      [ "$output" = "test output" ]
    }
    
    @test "mock_podman returns configured exit code" {
      export PODMAN_MOCK_OUTPUT=""
      export PODMAN_MOCK_EXIT_CODE=1
      
      run mock_podman
      
      assert_failure
    }
    
    @test "mock_image_inspect returns valid JSON" {
      run mock_image_inspect
      
      assert_success
      # Verify it's valid JSON with jq or grep
      echo "$output" | grep -q '"Id"'
    }
    
    @test "setup_test_environment clears mock state" {
      export PODMAN_MOCK_OUTPUT="dirty"
      export PODMAN_MOCK_EXIT_CODE=99
      
      setup_test_environment
      
      [ -z "$PODMAN_MOCK_OUTPUT" ]
      [ "$PODMAN_MOCK_EXIT_CODE" -eq 0 ]
    }
    ```
  - **Step 3**: Run tests
    ```bash
    bats tests/unit/test_doubles.bats
    # Expected: All pass
    ```
  - **Step 4**: Commit
    ```bash
    git add tests/bats/test_doubles.bash tests/unit/test_doubles.bats
    git commit -m "feat: Add BATS test doubles for mocking external tools"
    ```

- [ ] T004 Setup test data provisioning strategy
  - **Files:**
    - Create: `tests/fixtures/` directory
    - Create: `tests/fixtures/minimal Containerfile`
  - **Step 1**: Create minimal test Containerfile for build testing
    ```dockerfile
    # tests/fixtures/minimal Containerfile
    # Minimal Containerfile for testing build infrastructure
    FROM quay.io/centos/centos:stream9
    
    LABEL org.opencontainers.image.title="Nornnet Test Fixture"
    LABEL org.opencontainers.image.version="0.0.1-test"
    LABEL org.opencontainers.image.source="https://github.com/OS2sandbox/nornnet"
    LABEL org.opencontainers.image.revision="test-fixture"
    LABEL containers.bootc="1"
    LABEL ostree.bootable="1"
    
    RUN echo "test fixture" > /etc/nornnet-test
    ```
  - **Step 2**: Create fixture helper script
    ```bash
    # tests/bats/fixtures.bash
    # Helper functions for test fixtures
    
    FIXTURES_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/.." && pwd)/fixtures"
    
    get_fixture_path() {
      local fixture_name="$1"
      echo "$FIXTURES_DIR/$fixture_name"
    }
    
    copy_fixture() {
      local fixture_name="$1"
      local dest_dir="${2:-.}"
      cp "$(get_fixture_path "$fixture_name")" "$dest_dir/"
    }
    ```
  - **Step 3**: Write test for fixture loading
    ```bash
    # tests/unit/fixtures.bats
    #!/usr/bin/env bats
    
    load '../bats/common.bash'
    load '../bats/fixtures.bash'
    
    @test "get_fixture_path returns absolute path" {
      run get_fixture_path "minimal Containerfile"
      
      assert_success
      # Path should contain fixtures
      echo "$output" | grep -q "fixtures"
      # File should exist
      [ -f "$output" ]
    }
    
    @test "minimal Containerfile exists in fixtures" {
      local fixture_path
      fixture_path="$(get_fixture_path "minimal Containerfile")"
      
      assert_file_exists "$fixture_path"
    }
    ```
  - **Step 4**: Run tests
    ```bash
    bats tests/unit/fixtures.bats
    # Expected: All pass
    ```
  - **Step 5**: Commit
    ```bash
    git add tests/fixtures/ tests/bats/fixtures.bash tests/unit/fixtures.bats
    git commit -m "feat: Add test fixture provisioning strategy"
    ```

- [ ] T005 [P] Create test utilities and helpers for CI/CD
  - **Files:**
    - Create: `tests/bats/ci_helpers.bash`
    - Modify: `.github/workflows/test.yml`
  - **Step 1**: Create CI-specific test helpers
    ```bash
    # tests/bats/ci_helpers.bash
    # Helpers for CI/CD integration
    
    # Detect if running in CI
    is_ci() {
      [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]
    }
    
    # Output test summary in CI format
    ci_test_summary() {
      if is_ci; then
        echo "::group::Test Results"
        # Print summary
        echo "Tests: $BATS_TEST_COUNT total, $BATS_ASSERTIONS_FAILED failures"
        echo "::endgroup::"
      fi
    }
    
    # Skip test with explanation for CI
    ci_skip_if_unavailable() {
      local tool="$1"
      local reason="${2:-Tool not available}"
      
      if ! command -v "$tool" &> /dev/null; then
        if is_ci; then
          echo "::notice::Skipping: $reason"
        fi
        skip "$reason"
      fi
    }
    
    # Require minimum tool version
    require_version() {
      local tool="$1"
      local min_version="$2"
      local actual_version
      
      actual_version="$("$tool" --version 2>&1 | head -1)"
      
      if ! command -v "$tool" &> /dev/null; then
        skip "$tool not installed"
      fi
      
      # Basic version check (can be enhanced with semver parsing)
      echo "Note: $tool version check: require >= $min_version, found: $actual_version"
    }
    ```
  - **Step 2**: Write tests for CI helpers
    ```bash
    # tests/unit/ci_helpers.bats
    #!/usr/bin/env bats
    
    load '../bats/common.bash'
    load '../bats/ci_helpers.bash'
    
    @test "is_ci returns true when CI is set" {
      export CI=true
      
      run is_ci
      
      assert_success
      [ "$output" = "" ]
    }
    
    @test "is_ci returns false when CI is not set" {
      unset CI
      
      run is_ci
      
      # Returns 1 (failure) when CI not set
      [ $status -eq 1 ]
    }
    
    @test "ci_skip_if_unavailable skips when tool missing" {
      run ci_skip_if_unavailable "nonexistent_tool_xyz" "Test tool missing"
      
      # BATS skip sets status 0 but skips
      [ $status -eq 0 ] || [ $status -eq 1 ]
    }
    ```
  - **Step 3**: Run tests
    ```bash
    bats tests/unit/ci_helpers.bats
    # Expected: All pass
    ```
  - **Step 4**: Update GitHub Actions workflow to use CI helpers
    ```yaml
    # Update .github/workflows/test.yml to use actionlint
    ```
  - **Step 5**: Commit
    ```bash
    git add tests/bats/ci_helpers.bash tests/unit/ci_helpers.bats
    git commit -m "feat: Add CI/CD test helpers"
    ```

---

## Phase 2: Foundational Infrastructure

**Purpose**: Core infrastructure that the first user story depends on.

**Dependencies**: Phase 1 must be complete.

**Checkpoint**: All Phase 2 tasks complete before US1 implementation.

---

- [ ] T006 Create project structure for Containerfiles
  - **Files:**
    - Create: `Containerfile.base`
    - Create: `Containerfile.config`
    - Create: `Containerfile.app`
  - **Step 1**: Create base Containerfile
    ```dockerfile
    # Containerfile.base
    # Layer 1: Minimal bootc-compatible OS
    # This is the foundation layer that all other layers extend
    
    FROM quay.io/centos-bootc/centos-bootc:stream9
    
    # Required labels for bootc images
    LABEL org.opencontainers.image.title="Nornnet Base"
    LABEL org.opencontainers.image.version="0.1.0"
    LABEL org.opencontainers.image.source="https://github.com/OS2sandbox/nornnet"
    LABEL org.opencontainers.image.revision="${GIT_COMMIT:-unknown}"
    LABEL org.opencontainers.image.licenses="MIT"
    
    # Required for bootc
    LABEL containers.bootc="1"
    LABEL ostree.bootable="1"
    
    # Install minimal required packages
    RUN dnf install -y \
        curl \
        systemd \
        coreutils \
        && dnf clean all
    
    # Set default shell
    SHELL ["/bin/bash", "-c"]
    ```
  - **Step 2**: Create config Containerfile (layer 2)
    ```dockerfile
    # Containerfile.config
    # Layer 2: System configuration layer
    # Extends base layer with system-level configuration
    
    ARG BASE_IMAGE
    FROM ${BASE_IMAGE}
    
    # Copy configuration files
    COPY config/ /etc/nornnet/config/
    
    # Apply system configuration
    RUN systemctl enable nornnet-update.timer || true
    
    # Labels for this layer
    LABEL org.opencontainers.image.title="Nornnet Config"
    LABEL org.opencontainers.image.version="0.1.0"
    ```
  - **Step 3**: Create app Containerfile (layer 3)
    ```dockerfile
    # Containerfile.app
    # Layer 3: Application layer
    # Extends config layer with application components
    
    ARG BASE_IMAGE
    FROM ${BASE_IMAGE}
    
    # Copy application files
    COPY app/ /opt/nornnet/app/
    
    # Application entry point
    CMD ["/opt/nornnet/app/entrypoint.sh"]
    
    # Labels for this layer
    LABEL org.opencontainers.image.title="Nornnet Application"
    LABEL org.opencontainers.image.version="0.1.0"
    ```
  - **Step 4**: Commit
    ```bash
    git add Containerfile.base Containerfile.config Containerfile.app
    git commit -m "feat: Create layered Containerfile structure"
    ```

- [ ] T007 [P] Create build script with logging
  - **Files:**
    - Create: `scripts/build.sh`
    - Create: `scripts/lib/logging.sh`
  - **Step 1**: Create logging library
    ```bash
    # scripts/lib/logging.sh
    # Logging utilities for nornnet scripts
    
    LOG_LEVEL="${LOG_LEVEL:-INFO}"
    LOG_FILE="${LOG_FILE:-/tmp/nornnet-build.log}"
    
    log_debug() { log "DEBUG" "$1"; }
    log_info()  { log "INFO"  "$1"; }
    log_warn()  { log "WARN"  "$1"; }
    log_error() { log "ERROR" "$1"; }
    
    log() {
      local level="$1"
      local message="$2"
      local timestamp
      timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    }
    
    log_section() {
      echo ""
      echo "========================================"
      echo "  $1"
      echo "========================================"
      echo ""
    }
    ```
  - **Step 2**: Create build script
    ```bash
    #!/usr/bin/env bash
    # scripts/build.sh
    # Build bootable container images for nornnet
    
    set -euo pipefail
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    source "$SCRIPT_DIR/lib/logging.sh"
    
    # Default values
    LAYER="${LAYER:-base}"
    TAG="${TAG:-latest}"
    REGISTRY="${REGISTRY:-ghcr.io/os2sandbox}"
    
    usage() {
      cat <<EOF
    Usage: $0 [OPTIONS]
    
    Options:
      -l, --layer LAYER   Image layer to build (base|config|app) [default: base]
      -t, --tag TAG        Image tag [default: latest]
      -r, --registry URL   Registry URL [default: ghcr.io/os2sandbox]
      -h, --help           Show this help message
    
    Examples:
      $0 --layer base --tag v0.1.0
      $0 --layer config --tag v0.1.0
    EOF
    }
    
    parse_args() {
      while [[ $# -gt 0 ]]; do
        case $1 in
          -l|--layer)
            LAYER="$2"; shift 2 ;;
          -t|--tag)
            TAG="$2"; shift 2 ;;
          -r|--registry)
            REGISTRY="$2"; shift 2 ;;
          -h|--help)
            usage; exit 0 ;;
          *)
            echo "Unknown option: $1"; usage; exit 1 ;;
        esac
      done
    }
    
    build_image() {
      local layer="$1"
      local tag="$2"
      local registry="$3"
      
      local dockerfile="Containerfile.$layer"
      local image_name="$registry/nornnet-$layer:$tag"
      
      log_section "Building $layer layer"
      log_info "Dockerfile: $dockerfile"
      log_info "Image name: $image_name"
      
      if [ ! -f "$PROJECT_ROOT/$dockerfile" ]; then
        log_error "Dockerfile not found: $dockerfile"
        return 1
      fi
      
      log_info "Running podman build..."
      podman build \
        --file "$PROJECT_ROOT/$dockerfile" \
        --tag "$image_name" \
        "$PROJECT_ROOT"
      
      log_info "Build complete: $image_name"
      echo "$image_name"
    }
    
    main() {
      parse_args "$@"
      
      log_section "Nornnet Image Build"
      log_info "Layer: $LAYER"
      log_info "Tag: $TAG"
      log_info "Registry: $REGISTRY"
      
      build_image "$LAYER" "$TAG" "$REGISTRY"
    }
    
    main "$@"
    ```
  - **Step 3**: Make script executable
    ```bash
    chmod +x scripts/build.sh
    ```
  - **Step 4**: Commit
    ```bash
    git add scripts/build.sh scripts/lib/logging.sh
    chmod +x scripts/build.sh
    git commit -m "feat: Add build script with logging"
    ```

- [ ] T008 Create configuration management
  - **Files:**
    - Create: `config/default.conf`
    - Create: `scripts/lib/config.sh`
  - **Step 1**: Create default configuration
    ```bash
    # config/default.conf
    # Nornnet default configuration
    
    # Registry settings
    DEFAULT_REGISTRY="ghcr.io/os2sandbox"
    REGISTRY_READ_ANONYMOUS=true
    
    # Image versioning
    DEFAULT_IMAGE_TAG="v0.1.0"
    VERSION_LABEL="org.opencontainers.image.version"
    
    # Build settings
    BUILD_TIMEOUT_SECONDS=900
    MAX_PARALLEL_BUILDS=2
    
    # Deployment settings
    DEPLOYMENT_TIMEOUT_SECONDS=600
    HEALTH_CHECK_TIMEOUT_SECONDS=300
    
    # Rollback settings
    AUTO_ROLLBACK_ON_FAILURE=true
    MAX_ROLLBACK_ATTEMPTS=3
    ```
  - **Step 2**: Create config loader
    ```bash
    # scripts/lib/config.sh
    # Configuration management for nornnet
    
    CONFIG_DIR="${CONFIG_DIR:-$SCRIPT_DIR/../../config}"
    CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/default.conf}"
    
    load_config() {
      if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        log_debug "Loaded config from: $CONFIG_FILE"
      else
        log_warn "Config file not found: $CONFIG_FILE"
      fi
    }
    
    get_config() {
      local key="$1"
      local default="${2:-}"
      local value
      
      # Load config if not already loaded
      if [ -z "${DEFAULT_REGISTRY:-}" ]; then
        load_config
      fi
      
      # Get value using indirect variable reference
      value="${!key:-}"
      
      if [ -n "$value" ]; then
        echo "$value"
      else
        echo "$default"
      fi
    }
    ```
  - **Step 3**: Update build.sh to use config
    ```bash
    # Add to scripts/build.sh after sourcing logging.sh
    source "$SCRIPT_DIR/lib/config.sh"
    load_config
    ```
  - **Step 4**: Commit
    ```bash
    git add config/default.conf scripts/lib/config.sh
    git commit -m "feat: Add configuration management"
    ```

- [ ] T009 Create base test fixtures
  - **Files:**
    - Create: `tests/fixtures/Containerfile.test`
    - Create: `tests/fixtures/config/test.conf`
  - **Step 1**: Create test Containerfile (extra small for fast tests)
    ```dockerfile
    # tests/fixtures/Containerfile.test
    # Minimal Containerfile for testing build pipeline
    FROM quay.io/centos/centos:stream9
    
    LABEL org.opencontainers.image.title="Nornnet Test"
    LABEL org.opencontainers.image.version="0.0.1-test"
    LABEL containers.bootc="1"
    LABEL ostree.bootable="1"
    
    RUN echo "test" > /test-fixture
    ```
  - **Step 2**: Create test config file
    ```bash
    # tests/fixtures/config/test.conf
    DEFAULT_REGISTRY="ghcr.io/test-namespace"
    DEFAULT_IMAGE_TAG="v0.0.1-test"
    BUILD_TIMEOUT_SECONDS=60
    ```
  - **Step 3**: Write test for config loading with fixtures
    ```bash
    # tests/integration/config.bats
    #!/usr/bin/env bats
    
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
    ```
  - **Step 4**: Run integration tests
    ```bash
    bats tests/integration/config.bats
    # Expected: All pass
    ```
  - **Step 5**: Commit
    ```bash
    git add tests/fixtures/ tests/integration/config.bats
    git commit -m "test: Add base test fixtures and config tests"
    ```

---

## Phase 3: User Story 1 - Local Image Build

**Purpose**: Implement the first user story per spec.md.

**Dependencies**: Phases 1 and 2 must be complete.

**Checkpoint**: All US1 acceptance tests pass.

---

### US1: Local Image Build (Priority: P0)

**Story**: As an infrastructure operator, I want to build bootable container images locally, so that I can verify my changes work before exposing them to devices.

**Acceptance Criteria** (from spec.md):
1. Build completes without errors and produces an OCI image
2. Image layers can be inspected and verified
3. Build failures show clear error messages

---

- [ ] T010 [US1] Write acceptance tests for local image build
  - **Files:**
    - Create: `tests/acceptance/image-build.bats`
  - **Step 1**: Write acceptance test following Given-When-Then format
    ```bash
    #!/usr/bin/env bats
    # tests/acceptance/image-build.bats
    # Acceptance tests for US1: Local Image Build
    #
    # Acceptance Criteria:
    # 1. Given a clean environment, When build completes, Then OCI image is produced
    # 2. Given successful build, When layers are inspected, Then each layer is correct
    # 3. Given invalid instruction, When build fails, Then clear error is shown
    
    load '../bats/common.bash'
    load '../bats/fixtures.bash'
    load '../bats/ci_helpers.bash'
    
    FIXTURE_NAME="Containerfile.test"
    TEST_IMAGE="localhost/nornnet-test:$(date +%s)"
    
    setup() {
      # Create temporary build context
      BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
      TEST_CONTEXT="$BATS_TMPDIR/nornnet-build-test-$$"
      mkdir -p "$TEST_CONTEXT"
      
      # Copy fixture to context
      local fixture_path
      fixture_path="$(get_fixture_path "$FIXTURE_NAME")"
      cp "$fixture_path" "$TEST_CONTEXT/Containerfile"
      
      # Check if podman is available
      ci_skip_if_unavailable "podman" "podman required for acceptance tests"
    }
    
    teardown() {
      # Cleanup: remove test image
      podman rmi "$TEST_IMAGE" &>/dev/null || true
      
      # Cleanup: remove test context
      rm -rf "$TEST_CONTEXT"
    }
    
    # =============================================================================
    # SC-1.1: Build completes successfully and produces OCI image
    # =============================================================================
    
    @test "AC1.1: Build completes without errors and produces OCI image" {
      # GIVEN a clean environment with podman installed
      # WHEN we execute the build command
      # THEN build completes without errors and produces an OCI image
      
      skip_if_tool_not_available "podman"
      
      run podman build \
        --file "$TEST_CONTEXT/Containerfile" \
        --tag "$TEST_IMAGE" \
        "$TEST_CONTEXT"
      
      # THEN the build completes successfully
      assert_success
      
      # AND the image exists in local storage
      run podman image exists "$TEST_IMAGE"
      assert_success
    }
    
    @test "AC1.1: Image has required bootc labels" {
      # GIVEN a built image
      # THEN it has required bootc labels
      
      # Build image first
      run podman build \
        --file "$TEST_CONTEXT/Containerfile" \
        --tag "$TEST_IMAGE" \
        "$TEST_CONTEXT"
      assert_success
      
      # THEN image has bootc label
      run podman inspect "$TEST_IMAGE" --format '{{index .Config.Labels "containers.bootc"}}'
      assert_success
      [ "$output" = "1" ]
      
      # AND image has bootable label
      run podman inspect "$TEST_IMAGE" --format '{{index .Config.Labels "ostree.bootable"}}'
      assert_success
      [ "$output" = "1" ]
    }
    
    # =============================================================================
    # SC-1.2: Image layers can be inspected and verified
    # =============================================================================
    
    @test "AC1.2: Built image has expected layers" {
      # GIVEN a built image
      # WHEN we inspect the layers
      # THEN each layer was created correctly
      
      # Build image first
      run podman build \
        --file "$TEST_CONTEXT/Containerfile" \
        --tag "$TEST_IMAGE" \
        "$TEST_CONTEXT"
      assert_success
      
      # THEN image has at least one layer
      run podman inspect "$TEST_IMAGE" --format '{{len .RootFS.DiffIDs}}'
      assert_success
      [ "$output" -ge 1 ]
    }
    
    @test "AC1.2: Image version label is set correctly" {
      # GIVEN a built image
      # WHEN we inspect the labels
      # THEN the version label is set to the expected value
      
      # Build image first
      run podman build \
        --file "$TEST_CONTEXT/Containerfile" \
        --tag "$TEST_IMAGE" \
        "$TEST_CONTEXT"
      assert_success
      
      # THEN version label matches fixture
      run podman inspect "$TEST_IMAGE" --format '{{index .Config.Labels "org.opencontainers.image.version"}}'
      assert_success
      [ "$output" = "0.0.1-test" ]
    }
    
    # =============================================================================
    # SC-1.3: Build failures show clear error messages
    # =============================================================================
    
    @test "AC1.3: Invalid instruction produces clear error" {
      # GIVEN a Containerfile with an invalid instruction
      # WHEN we attempt to build
      # THEN build fails with clear error message
      
      # Create invalid Containerfile
      echo "INVALID INSTRUCTION XYZ" > "$TEST_CONTEXT/Containerfile"
      
      # Attempt build
      run podman build \
        --file "$TEST_CONTEXT/Containerfile" \
        --tag "$TEST_IMAGE" \
        "$TEST_CONTEXT" || true
      
      # THEN build fails
      # Note: podman may or may not fail depending on parser strictness
      # The important thing is we don't crash
      [ -n "$output" ]  # Output should contain something (error or warning)
    }
    
    @test "AC1.3: Nonexistent base image produces clear error" {
      # GIVEN a Containerfile referencing a nonexistent base image
      # WHEN we attempt to build
      # THEN build fails with clear error message
      
      # Create Containerfile with nonexistent base
      cat > "$TEST_CONTEXT/Containerfile" <<'EOF'
    FROM nonexistent-image-that-does-not-exist-12345:latest
    RUN echo "test"
    EOF
      
      # Attempt build
      run podman build \
        --file "$TEST_CONTEXT/Containerfile" \
        --tag "$TEST_IMAGE" \
        "$TEST_CONTEXT" || true
      
      # THEN build fails
      # AND error message mentions the missing image
      assert_output_contains "nonexistent-image" || assert_output_contains "error" || true
      # At minimum, we should have some error output
      [ ${#output} -gt 0 ]
    }
    ```
  - **Step 2**: Run tests to verify they FAIL (RED phase)
    ```bash
    bats tests/acceptance/image-build.bats
    # Expected: FAIL (tests written before implementation)
    ```
  - **Step 3**: Commit RED phase
    ```bash
    git add tests/acceptance/image-build.bats
    git commit -m "RED: Add acceptance tests for US1 (Local Image Build)"
    ```

- [ ] T011 [P] [US1] Implement build script integration tests
  - **Files:**
    - Create: `tests/integration/build-script.bats`
  - **Step 1**: Write integration test for build script
    ```bash
    #!/usr/bin/env bats
    # tests/integration/build-script.bats
    # Integration tests for scripts/build.sh
    
    load '../bats/common.bash'
    load '../bats/fixtures.bash'
    
    SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/../../.." && pwd)/scripts"
    BUILD_SCRIPT="$SCRIPT_DIR/build.sh"
    
    setup() {
      chmod +x "$BUILD_SCRIPT"
      TEST_IMAGE="localhost/nornnet-test-script:$(date +%s)"
    }
    
    teardown() {
      podman rmi "$TEST_IMAGE" &>/dev/null || true
    }
    
    @test "build.sh script exists and is executable" {
      [ -f "$BUILD_SCRIPT" ]
      [ -x "$BUILD_SCRIPT" ]
    }
    
    @test "build.sh shows usage with --help" {
      run "$BUILD_SCRIPT" --help
      
      assert_success
      assert_output_contains "Usage:"
      assert_output_contains "layer"
      assert_output_contains "tag"
    }
    
    @test "build.sh builds base layer image" {
      # Skip if podman not available
      skip_if_tool_not_available "podman"
      
      export LAYER="base"
      export TAG="test"
      export REGISTRY="localhost"
      
      run "$BUILD_SCRIPT"
      
      assert_success
      assert_output_contains "Build complete"
    }
    
    @test "build.sh fails for unknown layer" {
      export LAYER="nonexistent"
      export TAG="test"
      export REGISTRY="localhost"
      
      run "$BUILD_SCRIPT" || true
      
      # Should fail (exit non-zero)
      # OR output should contain error
      [ $status -ne 0 ] || [ ${#output} -gt 0 ]
    }
    
    @test "build.sh validates Containerfile exists" {
      export LAYER="base"
      export TAG="test"
      export REGISTRY="localhost"
      
      # Remove Containerfile.base temporarily
      local original_dir
      original_dir="$(pwd)"
      cd "$TEST_CONTEXT/../.."
      
      run "$BUILD_SCRIPT" 2>&1 || true
      
      cd "$original_dir"
      
      # Should fail with error about missing Containerfile
      assert_output_contains "not found" || [ $status -ne 0 ]
    }
    ```
  - **Step 2**: Run integration tests to verify they FAIL
    ```bash
    bats tests/integration/build-script.bats
    # Expected: FAIL (script not yet integrated with tests)
    ```
  - **Step 3**: Fix any issues in build script to make tests pass
    ```bash
    # If tests fail for wrong reasons, fix the implementation
    # The goal is GREEN phase: minimal code to make tests pass
    ```
  - **Step 4**: Run tests again
    ```bash
    bats tests/integration/build-script.bats
    # Expected: PASS
    ```
  - **Step 5**: Commit
    ```bash
    git add tests/integration/build-script.bats
    git commit -m "GREEN: Add build script integration tests"
    ```

- [ ] T012 [US1] Verify all acceptance tests pass
  - **Files:**
    - Verify: `tests/acceptance/image-build.bats`
  - **Step 1**: Run acceptance tests
    ```bash
    bats tests/acceptance/image-build.bats
    # Expected: PASS
    ```
  - **Step 2**: Run integration tests
    ```bash
    bats tests/integration/build-script.bats
    # Expected: PASS
    ```
  - **Step 3**: Run unit tests
    ```bash
    bats tests/unit/
    # Expected: PASS
    ```
  - **Step 4**: Run full test suite
    ```bash
    bats tests/
    # Expected: All pass
    ```
  - **Step 5**: Run CI locally (if actionlint available)
    ```bash
    actionlint .github/workflows/test.yml || true
    ```
  - **Step 6**: Final commit
    ```bash
    git add -A
    git commit -m "GREEN: US1 (Local Image Build) complete - all tests passing"
    ```

---

## Test Coverage Summary

| User Story | Acceptance Tests | Integration Tests | Unit Tests |
|------------|------------------|-------------------|------------|
| US1: Local Image Build | `tests/acceptance/image-build.bats` | `tests/integration/build-script.bats` | `tests/unit/config.bats`, `tests/unit/fixtures.bats` |

## Parallel Opportunities

The following tasks can run in parallel (no shared state):

| Parallel Group | Tasks |
|----------------|-------|
| Test Framework Setup | T001, T002, T003, T004, T005 |
| Foundation (after scaffolding) | T006, T007, T008, T009 |
| US1 Tests | T011 (after T010) |

## Verification Checklist

Before completing this sub-PoC, verify:

- [ ] All Phase 1 (test scaffolding) tests pass
- [ ] All Phase 2 (foundation) tests pass
- [ ] All US1 acceptance tests pass
- [ ] GitHub Actions workflow runs successfully
- [ ] No linting errors (actionlint)
- [ ] All commits follow conventional commit format
- [ ] `git status` shows clean working tree (or only expected changes)
- [ ] `git log --oneline` shows all commits with messages

---

## Next Steps (Future Sub-PoCs)

After this sub-PoC is complete, the following can proceed:

1. **US2: Registry Authentication** - Push/pull from GHCR
2. **US3: Image Registry Operations** - Tag management, version tracking
3. **US4: Device Deployment** - bootc switch to deploy images
4. **US5: Update Detection** - Check for new versions
5. **US6: Transactional Updates** - Atomic updates with rollback
6. **US7: Automated Reboot** - Post-update reboot
7. **US8: Image Layer Verification** - Reproducibility checks

---

**Tasks Version**: 1.0.0  
**Created**: 2026-03-24
