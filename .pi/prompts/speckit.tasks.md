---
description: Generate tasks with acceptance tests, integration tests, and test scaffolding
  for each user story
handoffs:
- label: Analyze Consistency
  agent: speckit.analyze
  prompt: Run project analysis for consistency
- label: Implement Project
  agent: speckit.implement
  prompt: Start implementation using sub-agents
scripts:
  sh: scripts/bash/check-prerequisites.sh --json
  ps: scripts/powershell/check-prerequisites.ps1 -Json
---


<!-- Source: spec-as-code -->
## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before tasks)**:
- Check if `.specify/extensions.yml` exists
- If exists, read and look for `hooks.before_tasks` entries
- Filter out disabled hooks
- Execute optional/mandatory hooks as appropriate

## Overview

You are generating tasks at `.specify/specs/[###-feature-name]/tasks.md`.

**CRITICAL**: Every task related to implementing features MUST be paired with:
1. **Acceptance tests** that prove the feature works
2. **Integration tests** that prove components work together
3. **Test scaffolding** tasks to set up the testing infrastructure

**THE AGENT MUST NOT start working on a task before its tests are COMPLETE.**

## Task Generation Rules

### Task Format (STRICT)

Every task MUST follow this format:

```text
- [ ] [TASK_ID] [P?] [STORY?] Description with exact file paths
```

**Components**:
1. **Checkbox**: ALWAYS `- [ ]`
2. **Task ID**: Sequential (T001, T002...)
3. **[P] marker**: Parallelizable (different files, no dependencies)
4. **[STORY] label**: Which user story this belongs to (e.g., [US1])
5. **Description**: Action + exact file path

### Phase Structure

#### Phase 1: Test Scaffolding Setup

**Purpose**: Create the testing infrastructure BEFORE any feature work

- [ ] T001 [P] Setup acceptance test framework (e.g., Playwright, Cypress)
- [ ] T002 [P] Setup integration test framework (e.g., test containers)
- [ ] T003 [P] Setup unit test framework
- [ ] T004 Setup test data provisioning strategy
- [ ] T005 [P] Create test utilities and helpers

**Checkpoint**: Test infrastructure MUST be complete before Phase 3 begins

#### Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that ALL user stories depend on

**⚠️ CRITICAL**: No user story work until Phase 2 is complete

- [ ] T006 Setup database schema/migrations
- [ ] T007 [P] Implement core models/entities
- [ ] T008 Configure error handling and logging
- [ ] T009 Setup configuration management
- [ ] T010 Create base test fixtures

**Checkpoint**: Foundation ready → User story implementation can begin

#### Phase 3+: User Stories (One Phase Per Story)

**Structure for each user story**:

```
## Phase N: [US#] - [Story Title] (Priority: P#)

**Acceptance Test Task** (MUST be first in story phase):
- [ ] T0XX [US#] Write acceptance test for [story] in tests/acceptance/

**Integration Test Task** (MUST before implementation):
- [ ] T0XX [P] [US#] Write integration test for [component] in tests/integration/

**Implementation Tasks**:
- [ ] T0XX [P] [US#] Implement [component] in src/[path]
- [ ] T0XX [US#] Implement [component] in src/[path]

**Verification Task**:
- [ ] T0XX [US#] Verify acceptance test passes
```

### Required Task Metadata

For EVERY feature task, you MUST document:

1. **Which user story does this relate to?**
2. **Which acceptance test covers this?**
3. **Which integration tests cover this?**

```
Example:

- [ ] T015 [P] [US1] Implement UserService in src/services/user_service.py
  - User Story: US1 (User Registration)
  - Acceptance Test: T010 (test_user_registration_complete)
  - Integration Tests: T012 (test_user_service_integration)
```

## Test Task Requirements

### Acceptance Tests
- **What**: End-to-end scenarios from spec
- **Where**: `tests/acceptance/`
- **Format**: Given-When-Then scenarios
- **Data**: Must gather REAL data from system to prove it works

### Integration Tests
- **What**: Component interaction tests
- **Where**: `tests/integration/`
- **Scope**: How components communicate
- **Data**: Mock or fixture data as appropriate

### Unit Tests
- **What**: Isolated component logic
- **Where**: `tests/unit/`
- **Scope**: Single component in isolation
- **Format**: Arrange-Act-Assert

## Execution Rules

### CRITICAL: Test-Before-Code Discipline

```
┌─────────────────────────────────────────────────────────────────┐
│                   TASK COMPLETION FLOW                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. IDENTIFY task to work on                                     │
│                    ↓                                              │
│  2. FIND corresponding test task(s)                              │
│     • Acceptance test MUST exist                                 │
│     • Integration test(s) MUST exist                             │
│                    ↓                                              │
│  3. VERIFY tests are COMPLETE (not just written)                 │
│     • If tests incomplete → report issue, do NOT proceed         │
│                    ↓                                              │
│  4. RUN tests → they MUST FAIL (expected)                        │
│                    ↓                                              │
│  5. IMPLEMENT feature                                            │
│                    ↓                                              │
│  6. RUN tests → they MUST PASS                                   │
│     • If fail → fix implementation, NOT tests                    │
│     • If test is wrong → report, do NOT change                   │
│                    ↓                                              │
│  7. MARK task complete [X]                                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Sub-Agent Task Execution

**When using sub-agents for implementation**:

1. One sub-agent PER task
2. Sub-agent receives:
   - Task description with file paths
   - Link to acceptance test (must pass)
   - Link to integration tests (must pass)
3. Sub-agent MUST NOT modify tests
4. If sub-agent finds test issues → write report, do not change tests

## Validation Checklist

Before generating tasks.md, verify:

- [ ] Test scaffolding setup tasks exist (Phase 1)
- [ ] Foundational tasks exist (Phase 2) - blocks all stories
- [ ] Each user story has acceptance test task
- [ ] Each user story has integration test task(s)
- [ ] Each feature task links to its tests
- [ ] All tasks have exact file paths
- [ ] Parallel markers [P] are correct

## Output

Write to `.specify/specs/[###-feature-name]/tasks.md`

Report:
- Total task count
- Tasks per phase
- Parallel opportunities
- Test coverage per story

## Post-Execution Hooks

After tasks generation, check for `hooks.after_tasks` in `.specify/extensions.yml` and execute appropriately.