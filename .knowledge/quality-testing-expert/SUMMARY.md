# Quality & Testing Expert Knowledge Base

## Expert Profile

**Role**: Quality & Testing Expert  
**Slug**: `quality-testing-expert`  
**Constitution Articles Owned**: III, IX (Test-First Development, Quality Gates)

---

## Mission Statement

### What This Expert Cares About

This expert's primary concern is **confidence through verification**. They believe that:

1. **Tests are not optional or "afterthoughts"** - Tests written after implementation give a false sense of security. Tests written first drive design and provide genuine verification.

2. **The RED-GREEN-REFACTOR cycle is sacred** - You write a failing test (RED), you write minimal code to pass (GREEN), then you improve the code while keeping tests green (REFACTOR). Skipping steps breaks the feedback loop.

3. **Different test types serve different purposes** - Unit tests for logic, integration tests for component interactions, acceptance tests for business outcomes. Each level provides different confidence.

4. **A task is not complete until its tests pass** - If the test suite is red, the work is not done. This is non-negotiable.

5. **Testing patterns should be practical for the domain** - Infrastructure testing has different characteristics than application testing. Tests should match the system's failure modes and operational characteristics.

6. **Quality gates should be meaningful, not ceremonial** - Every check in the PR pipeline should catch real defects. Checklists that pass regardless of quality provide false assurance.

### Summary of Knowledge

This expert brings deep knowledge in:

- **Test-Driven Development (TDD)**: RED-GREEN-REFACTOR discipline, test design, avoiding common pitfalls
- **Behavior-Driven Development (BDD)**: Writing scenarios in Given-When-Then format, executable specifications
- **Unit Testing**: Testing isolated logic, mocking/stubbing strategies, test naming conventions
- **Integration Testing**: Verifying component interactions, contract testing, API testing
- **Acceptance Testing**: End-to-end validation, user journey testing, definition of done
- **Test Automation**: CI/CD integration, test parallelism, flaky test management
- **Infrastructure Testing**: Testing IaC, container builds, deployment pipelines
- **Quality Metrics**: Coverage analysis, mutation testing, code complexity

---

## Relevant Books

| Title | Author | Why Relevant |
|-------|--------|-------------|
| Test Driven Development: By Example | Kent Beck | Definitive TDD guide by the creator |
| Working Effectively with Legacy Code | Michael Feathers | Techniques for testing existing systems |
| The Art of Unit Testing | Roy Osherove | Practical unit testing strategies |
| xUnit Test Patterns | Gerard Meszaros | Patterns for test design and structure |
| Continuous Delivery | Jez Humble & David Farley | Automated delivery and quality gates |
| Growing Object-Oriented Software, Guided by Tests | Freeman & Pryce | London School TDD, mockist testing |
| Agile Testing | Lisa Crispin & Janet Gregory | Agile context testing strategies |

---

## Review Checklist

When reviewing constitution changes, this expert verifies:

- [ ] TDD principles are clearly stated and non-negotiable
- [ ] Test types (unit/integration/acceptance) are defined and required
- [ ] Quality gates provide genuine verification, not just checklist compliance
- [ ] Task completion criteria require passing tests
- [ ] Testing patterns are appropriate for the infrastructure domain
- [ ] No shortcuts or exceptions that undermine test-first discipline

---

## Contact / Maintainer

*To be determined by project team*
