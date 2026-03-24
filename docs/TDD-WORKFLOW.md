# TDD-Driven Development Workflow

This document describes the complete Test-Driven Development workflow for the nornnet PoC.

## Overview

The PoC is divided into phases, each implementing user stories. Every phase follows the same TDD cycle:

```
┌─────────────────────────────────────────────────────────────┐
│                    TDD CYCLE (per phase)                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. WRITE TESTS (RED)                                      │
│     - Write failing acceptance tests                        │
│     - Write failing integration tests                        │
│     - Tests MUST fail before implementation                 │
│                                                              │
│  2. CONSTITUTIONAL REVIEW (Tests)                          │
│     - Review tests against spec.md                          │
│     - Review against Constitution Articles I-VI             │
│     - Verify tests capture requirements                     │
│     - Update tests if needed                                │
│                                                              │
│  3. IMPLEMENT (GREEN)                                      │
│     - Write minimal code to pass tests                      │
│     - No feature expansion                                 │
│                                                              │
│  4. CONSTITUTIONAL REVIEW (Implementation)                 │
│     - Review implementation against spec.md                 │
│     - Expert review from appropriate expert                 │
│     - Fix any issues found                                 │
│                                                              │
│  5. VERIFY                                                 │
│     - Run all tests on Hetzner server                      │
│     - Confirm all tests pass                                │
│     - Tests reflect real functionality                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Phase Breakdown

### Pre-PoC: Test Infrastructure & US1
- [DONE] Phase 1: Test Scaffolding (T001-T005)
- [DONE] Phase 2: Foundation (T006-T009)
- [DONE] Phase 3: US1 Local Image Build (T010-T012)
- [TODO] Constitutional Review
- [TODO] Run acceptance tests on Hetzner server

### Phase 2: US2-US3
- [TODO] Write acceptance tests for US2 (Registry Authentication)
- [TODO] Write acceptance tests for US3 (Image Registry Operations)
- [TODO] Constitutional Review (Tests)
- [TODO] Implement registry authentication
- [TODO] Implement image push/pull
- [TODO] Constitutional Review (Implementation)

### Phase 3: US4-US5
- [TODO] Write acceptance tests for US4 (Device Deployment)
- [TODO] Write acceptance tests for US5 (Update Detection)
- [TODO] Constitutional Review (Tests)
- [TODO] Implement bootc switch deployment
- [TODO] Implement update detection
- [TODO] Constitutional Review (Implementation)

### Phase 4: US6-US7
- [TODO] Write acceptance tests for US6 (Transactional Updates)
- [TODO] Write acceptance tests for US7 (Automated Reboot)
- [TODO] Constitutional Review (Tests)
- [TODO] Implement greenboot rollback
- [TODO] Implement automated reboot
- [TODO] Constitutional Review (Implementation)

### Phase 5: US8
- [TODO] Write acceptance tests for US8 (Image Layer Verification)
- [TODO] Write integration tests for status reporting
- [TODO] Constitutional Review (Tests)
- [TODO] Implement status reporting
- [TODO] Implement structured logging
- [TODO] Constitutional Review (Implementation)

### Final
- [TODO] Final Constitutional Review (all experts)
- [TODO] Final verification on Hetzner server
- [TODO] Push to GitHub
- [TODO] PoC Complete

## Expert Ownership

| Expert | Owned Articles | Reviews |
|--------|---------------|---------|
| **Infrastructure & DevOps Expert** | I, II, IV | Phases 2-3 implementation |
| **Quality & Testing Expert** | III, Quality Gates | All test reviews |
| **Security & Observability Expert** | V, VI | Phases 4-5 implementation |

## Constitution Articles

### Article I: Git as Single Source of Truth
All changes via pull requests, reviewed before deployment.

### Article II: Immutable OS Images via bootc
OS delivered as immutable OCI container images.

### Article III: Test-First Development (NON-NEGOTIABLE)
- RED: Write failing test first
- GREEN: Write minimal code to pass
- REFACTOR: Improve while tests pass

### Article IV: Layered Image Architecture
Base → Config → Application layers.

### Article V: Pull-Based Updates
No inbound management ports on devices.

### Article VI: Observability via Structured Logging
JSON logs for OTEL collection.

## Hetzner Server

For acceptance tests requiring real podman/bootc:

```bash
# Server IP: 168.119.52.133
ssh -F /tmp/ssh_config -i ~/.ssh/hetzner_ed25519 root@168.119.52.133

# Clone and run tests
cd /root/nornnet
git pull
bats tests/acceptance/
```

## Task Tracking

All tasks are tracked in beads. View with:

```bash
bd list           # List all issues
bd ready         # Issues with no blockers
bd show <id>     # Issue details
```

## Quick Start

1. Claim next task: `bd update <id> --claim`
2. Implement following TDD cycle
3. Run tests: `bats tests/`
4. Run acceptance tests on Hetzner: `ssh ... "bats tests/acceptance/"`
5. Commit: `git add -A && git commit -m "feat: ..."`
6. Close task: `bd close <id>`
7. Repeat
