---
description: Execute implementation using sub-agents with test-first discipline and
  verification gates
scripts:
  sh: scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
  ps: scripts/powershell/check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
---


<!-- Source: spec-as-code -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before implementation)**:
- Check if `.specify/extensions.yml` exists
- If exists, read and look for `hooks.before_implement` entries
- Filter out disabled hooks
- Execute optional/mandatory hooks as appropriate

## Overview

You are executing implementation tasks from `.specify/specs/[###-feature-name]/tasks.md`.

**CRITICAL IMPLEMENTATION RULES**:

1. **Use sub-agents for EVERY task** - do not implement directly
2. **Test-first discipline** - tests MUST fail before implementation
3. **Verification required** - tasks only complete when tests pass
4. **Test integrity** - if tests have issues, REPORT but do NOT change them

## Execution Flow

### Step 1: Prerequisites Check

Run `{SCRIPT}` and verify:
- FEATURE_DIR exists
- tasks.md exists and is complete
- plan.md exists (for tech stack context)

### Step 2: Load Context

Read these files:
- `tasks.md` - complete task list and execution plan
- `plan.md` - tech stack, architecture, file structure
- `data-model.md` - entities and relationships (if exists)
- `contracts/` - API specifications (if exists)
- `research.md` - technical decisions (if exists)
- `constitution.md` - principles to follow

### Step 3: Checklist Status Check

**If checklists exist in FEATURE_DIR/checklists/**:
1. Scan all checklist files
2. Count completed vs incomplete items
3. Display status table
4. **If incomplete**: STOP and ask user if they want to proceed
5. **If complete**: Proceed automatically

### Step 4: Parse Tasks

Extract from tasks.md:
- Task phases (Setup, Tests, Core, Integration, Polish)
- Dependencies (sequential vs parallel)
- Task details (ID, description, file paths, [P] markers)
- Test associations (which tests cover which tasks)

### Step 5: Sub-Agent Implementation (CRITICAL)

```
┌─────────────────────────────────────────────────────────────────┐
│                 SUB-AGENT IMPLEMENTATION FLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PHASE EXECUTION (sequential):                                   │
│  1. Complete Phase 1: Test Scaffolding                           │
│  2. Complete Phase 2: Foundational (blocks all stories)          │
│  3. For each user story phase (3+):                             │
│     a. ACCEPTANCE TEST first (must pass)                        │
│     b. INTEGRATION TESTS (must pass)                           │
│     c. IMPLEMENTATION (parallel where [P])                      │
│     d. VERIFY tests pass                                       │
│                                                                  │
│  SUB-AGENT BATCHING (4 at a time max):                         │
│  1. Identify up to 4 tasks that can run in parallel            │
│  2. Dispatch 4 sub-agents simultaneously                       │
│  3. Wait for all to complete                                   │
│  4. On failure: report, do not batch failed task's story        │
│  5. Repeat with remaining tasks                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Sub-Agent Task Dispatch

**For EACH task, dispatch a sub-agent with this structure**:

```
Task: Implement [task description]

Context:
- Feature: [feature name]
- User Story: [US#]
- Task ID: T###
- File Path: [exact path from tasks.md]

Test Requirements (MUST PASS before task is complete):
- Acceptance Test: [path to acceptance test]
- Integration Tests: [path to integration tests]

Constitution Principles:
- Follow test-first development
- RED: Write failing test first
- GREEN: Write minimal code to pass
- REFACTOR: Improve without breaking

Constraints:
- DO NOT modify any test files
- If test has issues → report to parent, do not change test
- Only implement what is described in the task

Success Criteria:
- All acceptance tests pass
- All integration tests pass
- Code follows constitution principles
```

### Step 6: Verification Gates

After each phase:

1. **Run all tests for the phase**
2. **If tests fail**:
   - Identify which task caused the failure
   - Dispatch fix sub-agent for that specific task ONLY
   - Do NOT proceed to next phase until all tests pass
3. **If tests pass**: Proceed to next phase

### Step 7: Progress Tracking

After each completed task:
- Mark task as [X] in tasks.md
- Report progress: "T001-T005 complete, T006-T010 remaining"

### Step 8: Completion Validation

After ALL tasks:
1. Run full test suite
2. Verify against spec.md acceptance scenarios
3. Confirm implementation matches plan.md
4. Report final status

## CRITICAL RULES

### Test-First Enforcement

```
❌ WRONG: Implement feature → then write tests
✅ RIGHT: Write test → see it fail → implement → see test pass
```

### Test Integrity

```
❌ WRONG: Test fails → modify test to pass
✅ RIGHT: Test fails → fix implementation to pass test

❌ WRONG: Test is hard to pass → skip or simplify test
✅ RIGHT: Test is hard to pass → report issue, escalate
```

### Sub-Agent Discipline

```
❌ WRONG: Implement multiple tasks myself
✅ RIGHT: Dispatch sub-agent for each task

❌ WRONG: Let sub-agents modify tests to pass
✅ RIGHT: Sub-agents implement ONLY, do not touch tests

❌ WRONG: Skip tests to "save time"
✅ RIGHT: Tests are MANDATORY gate for completion
```

### Verification Before Claims

```
❌ WRONG: "I implemented X" → assume it works
✅ RIGHT: "I implemented X and ran tests that prove it works"
```

## Red Flags - STOP

If you find yourself doing ANY of these, STOP immediately:

- Implementing tasks directly (use sub-agents)
- Skipping tests to move faster
- Modifying tests to make them pass
- Claiming task complete without test verification
- Running <4 sub-agents when more could run in parallel

## Post-Execution Hooks

After implementation, check for `hooks.after_implement` in `.specify/extensions.yml` and execute appropriately.

## Output

Report:
- Completed task count
- Failed task count (and why)
- Test results summary
- Remaining work (if any)