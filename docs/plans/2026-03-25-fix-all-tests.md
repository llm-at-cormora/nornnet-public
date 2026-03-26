# Fix All Integration & Acceptance Tests Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Fix all integration and acceptance tests to properly capture requirements and actually assert behavior (not just pass).

**Architecture:** Each test file will be fixed by a dedicated subagent. Tests will be modified to:
1. Actually assert expected behavior (not "always pass")
2. Fix broken imports
3. Add missing cleanup
4. Add missing coverage for requirements

**Tech Stack:** BATS (Bash Automated Testing System)

---

## Task 1: Fix image-build.bats

**File:** `tests/acceptance/image-build.bats`

**Issues to fix:**
1. Line 227: Inverted grep logic - fix to actually assert no FAIL messages
2. TEST_IMAGES array reset in setup() - ensure cleanup works correctly
3. Line 84-93: Mock podman --build-arg case doesn't consume value properly
4. Lines 398-427: Remove duplicate semver validation tests (already in unit)
5. Line 335: Use `run` for podman inspect to capture $status
6. Add test for build reproducibility (CC-1 requirement)

**Steps:**
1. Fix the grep assertion pattern
2. Ensure TEST_IMAGES cleanup persists across tests
3. Fix mock podman --build-arg handling
4. Remove duplicate semver tests
5. Add `run` for podman inspect calls
6. Add deterministic build test

---

## Task 2: Fix registry-auth.bats

**File:** `tests/acceptance/registry-auth.bats`

**Issues to fix:**
1. Lines 12-19: `run -1` is non-standard BATS syntax - change to `[ "$status" -ne 0 ]`
2. registry_check_anonymous_read ignores registry argument - add test with different registry
3. Add test that stdin actually receives password (not just --password-stdin flag)
4. Add network error handling tests (MOCK_*_RESULT="network_error" exists but unused)
5. Add test for registry_login function

**Steps:**
1. Fix run -1 syntax to standard pattern
2. Add test verifying registry argument is used
3. Add stdin content verification test
4. Add network error scenario tests
5. Add registry_login unit test with mocked podman

---

## Task 3: Fix registry-operations.bats

**File:** `tests/acceptance/registry-operations.bats`

**Issues to fix:**
1. validate_registry test doesn't check $status - add assertion
2. Missing negative test cases for validate_version (1.0, 1.0.0.0, v.1.0.0, 1.a.0, empty)
3. Mock script path escaping - use printf %q for safe escaping
4. Missing registry_login() function test
5. Add network error simulation test

**Steps:**
1. Add status check to validate_registry test
2. Add comprehensive negative version tests
3. Fix sed escaping in mock creation
4. Add registry_login unit test
5. Add network error simulation test

---

## Task 4: Fix device-deployment.bats

**File:** `tests/acceptance/device-deployment.bats`

**Issues to fix:**
1. device_teardown() is defined but never called - add teardown() function
2. device_setup() must be called in each test - verify all tests call it
3. Duplicate function definitions between bootc_helpers.bash and common.bash
4. bootc_has_rollback regex doesn't handle multi-line JSON - fix or use jq
5. wait_for_reboot is exported but never used - either use it or remove
6. "Deployment to different image changes staged state" is documentation-only - rename or implement
7. TEST_CONTEXT shared global state - use BATS_TEST_NAME for isolation

**Steps:**
1. Add teardown() function calling device_teardown
2. Verify all tests call device_setup
3. Document which helper file takes precedence
4. Fix regex to handle multi-line JSON
5. Use wait_for_reboot in reboot tests or add comment why not
6. Rename documentation-only test to indicate it's informational
7. Use BATS_TEST_NAME in TEST_CONTEXT for parallel safety

---

## Task 5: Fix update-detection.bats

**File:** `tests/acceptance/update-detection.bats`

**Issues to fix:**
1. Lines 8-10: Fragile load paths - use BATS_TEST_DIRNAME
2. Duplicate function in common.bash + bootc_helpers.bash
3. fixtures.bash is loaded but not used

**Steps:**
1. Fix load paths to use BATS_TEST_DIRNAME
2. Document function precedence
3. Either use fixtures or remove the load

---

## Task 6: Fix transactional-update.bats

**File:** `tests/acceptance/transactional-update.bats`

**Issues to fix:**
1. **CRITICAL: Broken import paths** - `load '../bats/*.bash'` → `../../bats/*.bash`
2. Dead code: bootc_get_status() defined but never used
3. Unused BOOTC_SSH_CONFIG in setup/teardown
4. Brittle JSON parsing for status.booted.image.image
5. No cleanup for state-modifying tests (staged updates accumulate)
6. Missing actual rollback execution tests (only detection, not execution)
7. parse_bootc_field silently fails on unsupported fields
8. "Malformed JSON handling" test too lenient

**Steps:**
1. FIX IMPORT PATHS FIRST (tests won't run without this)
2. Remove dead code (bootc_get_status, BOOTC_SSH_CONFIG)
3. Add jq-based JSON parsing with proper error handling
4. Add teardown cleanup for staged updates
5. Add test that actually executes bootc rollback
6. Make parse_bootc_field fail visibly on unsupported fields
7. Strengthen malformed JSON test assertions

---

## Task 7: Fix automated-reboot.bats

**File:** `tests/acceptance/automated-reboot.bats`

**Issues to fix:**
1. Lines 275-296: "bootc status is stable during normal operation" - `diff || true` never fails
2. Lines 298-315: "can detect image change" - only checks image exists, not change detection
3. Lines 453-472: Services test - only prints warnings, never asserts
4. Lines 489-496: Skips entire workflow when no update available - could still test other things
5. Section 1 unit tests re-implement wait_for_reboot instead of using helper
6. Line 97-110: Flaky timing test (2-second tolerance)
7. Lines 359-385: Integration test doesn't verify reboot initiated

**Steps:**
1. Fix "stable during normal operation" to actually assert stability
2. Fix "detect image change" to capture pre/post and compare
3. Add actual service status assertions
4. Test pre-reboot state capture even when no update available
5. Document why unit tests reimplement wait_for_reboot
6. Increase timing tolerance or mock-based testing
7. Fail/skip if reboot doesn't initiate

---

## Task 8: Fix integration/build-script.bats

**File:** `tests/integration/build-script.bats`

**Issues to fix:**
1. Line 50: `[ $status -ne 0 ] || [ ${#output} -gt 0 ]` - always passes
2. No test for environment variable overrides (LAYER=, TAG=, REGISTRY=)
3. No test for actual image build output verification
4. Missing test for parse_args() function error handling

**Steps:**
1. Fix the always-passing assertion
2. Add environment variable override tests
3. Add test verifying actual image was created
4. Add parse_args error handling tests

---

## Task 9: Fix integration/config_integration.bats

**File:** `tests/integration/config_integration.bats`

**Issues to fix:**
1. Line 33: Hardcoded registry value - use constant instead

**Steps:**
1. Replace hardcoded value with constant from config file

---

## Task 10: Add Missing Coverage Tests

**New files to create:** 
- `tests/acceptance/build-reproducibility.bats`
- `tests/acceptance/audit-trails.bats`
- `tests/acceptance/concurrent-safety.bats`
- `tests/acceptance/network-resilience.bats`

**CC-1: Build Reproducibility Test:**
- Build same source twice
- Compare layer digests
- Assert identical

**CC-4: Audit Trail Test:**
- Verify deployment emits structured events
- Verify version info includes Git commit hash

**CC-6: Concurrent Safety Test:**
- Test that simultaneous update requests are rejected/queued safely

**CC-7: Network Resilience Test:**
- Test retry with backoff on transient failures

---

## Verification

After all fixes:
1. Run: `bats tests/acceptance/ tests/integration/`
2. Verify no tests "pass" without actually asserting
3. Verify broken imports are fixed (transactional-update should run)
