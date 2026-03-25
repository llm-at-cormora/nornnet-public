# Constitutional Review - Phase 3 Tests (nornnet-bt6)

**Review Date:** 2026-03-25
**Reviewer:** orchestrator
**Task:** nornnet-bt6
**Files Reviewed:**
- `tests/acceptance/device-deployment.bats` (US4 tests)
- `tests/acceptance/update-detection.bats` (US5 tests)

---

## Constitution Article III Compliance: Test-First Development

### VERDICT: **FAIL**

The Phase 3 tests have significant constitutional compliance issues that must be addressed.

---

## Issues Found

### 1. CRITICAL: Tests Assert Success Without Distinguishing Implementation Status

**Location:** Multiple tests in both files

**Problem:** Several tests use `assert_success` to validate commands that will only work AFTER implementation exists. This violates the Test-First principle because:

- Tests should verify BEHAVIOR, not assume implementation exists
- Some tests have comments like "This test will fail until implementation exists" but still use `assert_success`
- Tests cannot distinguish between "feature not implemented" and "feature working correctly"

**Examples:**

```bats
# device-deployment.bats
@test "AC4.1: bootc switch deploys image from registry" {
  ...
  run bash -c "ssh ... 'bootc switch --disable-fsync ${target_image}' 2>&1"
  
  # Deployment should succeed (exit 0)
  # This test will fail until implementation exists  <-- Comment acknowledges missing impl
  assert_success  <-- Should handle gracefully or skip
}

# update-detection.bats  
@test "AC5.1: bootc update check queries registry for new version" {
  ...
  # The command should succeed (exit 0)
  # This test will fail until implementation exists  <-- Comment acknowledges missing impl
  assert_success  <-- Should handle gracefully or skip
}
```

**Required Fix:** Tests should either:
1. Use `skip "Feature not yet implemented"` when implementation doesn't exist
2. Use conditional assertions that clearly distinguish "not implemented" from "failed"
3. Check for expected behavior, not just exit codes

---

### 2. MODERATE: Inconsistent Skip Patterns

**Location:** Throughout both files

**Problem:** Skip conditions are applied inconsistently. Some tests skip appropriately when environment is unavailable, but others assume the feature will work without checking prerequisites.

**Examples of GOOD skip patterns:**
```bats
if [ -z "$device_ip" ]; then
  skip "No device IP configured"
fi

[ $status -eq 0 ] || skip "Device not reachable or bootc not installed"
```

**Examples of INCONSISTENT patterns:**
```bats
# Some tests assume podman works without checking
run bash -c "podman build ..."

# Some tests assume SSH will work
ssh root@${device_ip} 'bootc switch ...'
```

**Required Fix:** All tests that depend on external resources (podman, SSH connectivity, device availability) should use consistent skip patterns in `setup()` or at test start.

---

### 3. MODERATE: Given-When-Then Format Inconsistently Applied

**Location:** Both files

**Problem:** The Constitution emphasizes Given-When-Then testing patterns, but:

1. Test names use "AC4.X: [description]" format, which is acceptable
2. Comments inside tests use Given-When-Then blocks, which is good
3. Some tests lack the Given-When-Then comment blocks entirely

**Examples of GOOD format:**
```bats
@test "AC4.1: bootc switch deploys image from registry" {
  # Given device with bootc and registry image exists
  # When deployment command runs with registry image
  # Then device downloads and applies new image
  
  skip_if_tool_not_available "podman"
  ...
}
```

**Examples of MISSING format:**
```bats
@test "AC5.2: Periodic update check can be scheduled" {
  # No Given-When-Then comments
  # Just implementation checks
  ...
}
```

**Required Fix:** Add Given-When-Then comment blocks to ALL tests, even if they seem obvious.

---

### 4. LOW: Test Quality - Some Tests Check Multiple Behaviors

**Location:** `update-detection.bats` - `AC5.2: Version comparison works correctly`

**Problem:** A single test checks multiple behaviors:
1. Gets current version
2. Runs update check
3. Accepts either success OR failure

```bats
assert_success || {
  # Non-zero is also acceptable for "no update"
  echo "$output"
}
```

This makes test failure diagnosis difficult.

**Required Fix:** Split into separate tests or clarify the expected behavior.

---

### 5. LOW: Transaction Log Test Has Unclear Validation

**Location:** `device-deployment.bats` - `AC4.3: Transaction log records deployment`

**Problem:**
```bats
echo "$output" | grep -qE "deploy|current|origin" || {
  echo "No deployment status found: $output"
  return 1
}
```

The regex `deploy|current|origin` is too broad and could match unrelated output.

**Required Fix:** Use more specific assertions based on expected bootc/ostree output format.

---

## Summary Table

| Issue | Severity | File(s) Affected | Count |
|-------|----------|------------------|-------|
| assert_success without implementation check | CRITICAL | Both | 4 |
| Inconsistent skip patterns | MODERATE | Both | 8 |
| Missing Given-When-Then blocks | MODERATE | update-detection.bats | 3 |
| Multi-behavior tests | LOW | update-detection.bats | 1 |
| Vague validation regex | LOW | device-deployment.bats | 1 |

---

## What Works Well

Despite the issues, the tests demonstrate good understanding of:

1. **Bats framework usage:** Proper setup/teardown functions
2. **Load statements:** Correct use of common.bash, fixtures.bash, ci_helpers.bash
3. **Skip logic:** Most tests skip when dependencies unavailable
4. **Remote execution:** Proper SSH command handling with timeouts
5. **Acceptance criteria mapping:** Tests clearly reference AC4.X and AC5.X criteria
6. **Cleanup:** teardown() functions properly clean up test artifacts

---

## Required Actions

Before these tests can be considered constitutional compliant:

1. **[CRITICAL]** Replace `assert_success` in tests where implementation is acknowledged as missing with proper skip or conditional handling
2. **[MODERATE]** Standardize skip patterns across all tests
3. **[MODERATE]** Add Given-When-Then comment blocks to tests that lack them
4. **[LOW]** Split multi-behavior tests or clarify expected outcomes
5. **[LOW]** Improve validation regex specificity

---

## Test Coverage Assessment

**US4 (Device Deployment):**
- ✅ AC4.1 covered (4 tests)
- ✅ AC4.2 covered (3 tests)
- ✅ AC4.3 covered (4 tests)
- **Total: 11 tests**

**US5 (Update Detection):**
- ✅ AC5.1 covered (4 tests)
- ✅ AC5.2 covered (3 tests)
- ✅ AC5.3 covered (5 tests)
- **Total: 12 tests**

**Overall Coverage: ADEQUATE** - All acceptance criteria have corresponding tests.

---

## Constitutional Compliance Checklist

| Requirement | Status | Notes |
|-------------|--------|-------|
| Tests written before implementation | ⚠️ PARTIAL | Some tests acknowledge missing impl but still assert success |
| Each user story has acceptance tests | ✅ PASS | US4 and US5 fully covered |
| Given-When-Then format | ⚠️ PARTIAL | Most tests have it, some missing |
| Tests skip appropriately | ⚠️ PARTIAL | Inconsistent patterns |
| Test structure (setup/teardown) | ✅ PASS | Properly implemented |
| Load statements correct | ✅ PASS | All use correct load paths |

---

## Final Recommendation

**DO NOT CLOSE nornnet-bt6**

The tests need revision to address the CRITICAL issue #1 before they can be considered constitutionally compliant. Article III is explicitly marked as "NON-NEGOTIABLE."

A subagent should be launched to fix the critical issues, then this review should be re-run.

---

**Reviewed by:** orchestrator
**Review status:** FAIL - Action required
