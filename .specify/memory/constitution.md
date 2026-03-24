# Nornnet Constitution

## Nornnet PoC - Bootable Container Device Management

**Scope**: This constitution governs the implementation of the Nornnet proof-of-concept for bootc-based device management. It establishes principles for building, deploying, and managing immutable OS images using bootable containers.

---

## Expert Ownership

This constitution is maintained by three expert domains. Each expert owns specific articles and is responsible for reviewing changes affecting their domain.

| Expert | Knowledge Base | Owned Articles |
|--------|---------------|----------------|
| **Infrastructure & DevOps Expert** | `.knowledge/infrastructure-devops-expert/` | I, II, IV, Technology Stack |
| **Quality & Testing Expert** | `.knowledge/quality-testing-expert/` | III, Quality Gates |
| **Security & Observability Expert** | `.knowledge/security-observability-expert/` | V, VI, Governance |

---

## Core Principles

### I. Git as Single Source of Truth *(owned by: Infrastructure & DevOps Expert)*

All configuration, container definitions, and deployment specifications MUST be version-controlled in Git. Changes to the system MUST be proposed via pull requests, reviewed, and merged before deployment. This ensures auditability, reproducibility, and collaboration.

**Rationale**: Git provides a centralized, versioned record of all system state. Pull requests enable peer review and rollback capabilities essential for production-like systems.

---

### II. Immutable OS Images via bootc *(owned by: Infrastructure & DevOps Expert)*

The operating system MUST be delivered as immutable OCI container images using bootc. The booted OS MUST NOT be modified in-place; all changes MUST be delivered through new image versions.

**Rationale**: Immutability guarantees predictability and enables atomic rollback. bootc provides transactional updates with automatic rollback on failure, critical for remote device management.

---

### III. Test-First Development (NON-NEGOTIABLE) *(owned by: Quality & Testing Expert)*

**RED**: Write the failing test FIRST before any implementation. Every task MUST have a corresponding test before code is written.

**GREEN**: Write minimal code to make the test pass.

**REFACTOR**: Improve code quality while keeping tests passing.

**NEVER**: Write implementation code before its corresponding test.

### Testing Requirements

- **ACCEPTANCE TESTS**: Each user story MUST have acceptance tests that validate end-to-end behavior of the image build, deployment, and update lifecycle.
- **INTEGRATION TESTS**: Cross-component interactions (e.g., bootc ↔ podman, quadlets ↔ systemd) MUST have integration tests.
- **UNIT TESTS**: Core business logic (e.g., image building scripts, configuration generators) MUST have unit tests.
- **TASK COMPLETION**: A task is only COMPLETE when its test(s) pass.

### Test Coverage Patterns

- Containerfile/Containerfile.build testing: Layer verification, no layer errors
- Registry operations: Push/pull validation, authentication
- Deployment testing: bootc switch, bootc status verification
- Update propagation: Version detection, transactional update, rollback scenarios
- Pull model verification: No inbound management ports, update detection works

**Rationale**: Test-first ensures every feature is verifiable. Given this is infrastructure software managing remote devices, defects can cause widespread outages. Tests provide confidence and enable safe automation.

---

### IV. Layered Image Architecture *(owned by: Infrastructure & DevOps Expert)*

The system MUST use a three-layer image architecture:

1. **Base Image**: Minimal bootc-compatible OS with core runtime
2. **Config Image**: Base + system configuration (network, users, security policies)
3. **Application Image**: Config + application-specific components

Each layer MUST be independently buildable and testable. Layer changes MUST trigger appropriate rebuilds downstream.

**Rationale**: Separation of concerns enables targeted updates. Changing application configuration should not require rebuilding the entire OS base.

---

### V. Pull-Based Updates with Minimal Attack Surface *(owned by: Security & Observability Expert)*

The system MUST use a pull-based update model where devices check for and apply updates proactively. No inbound management ports MUST be opened on managed devices.

**Rationale**: The pull model eliminates the need for management ports, dramatically reducing attack surface. Devices become invisible to network scanning while still receiving updates.

---

### VI. Observability via Structured Logging *(owned by: Security & Observability Expert)*

All components MUST emit structured logs suitable for OpenTelemetry (OTEL) collection. Logs MUST include:

- Component identifier
- Timestamp (ISO 8601)
- Log level
- Structured context (JSON format for machine parsing)

**Rationale**: Structured logging enables automated alerting, troubleshooting, and metrics collection. Essential for managing fleets of remote devices.

---

## Technology Stack Constraints

The following technologies are the STANDARD choices and MUST be used unless explicitly justified and approved:

| Layer | Technology | Rationale |
|-------|------------|-----------|
| OS Delivery | bootc | Native bootable container support |
| Service Management | systemd | Native Linux init, no third-party agents |
| Container Runtime | podman | Rootless, daemonless, OCI-compliant |
| Container Management | quadlets | systemd-native container unit files |
| Image Registry | GHCR | Tight integration with GitHub |
| Update Transport | OStree | Git-like OS image replication |

**Prohibited Technologies**: Third-party agents, SSH-based management, push-based update mechanisms (unless explicitly approved).

---

## Development Workflow

### Phase 0: Research (Constitution Check Required)

Before any implementation, verify:
- [ ] Constitution principles are understood
- [ ] Technology choices align with stack constraints
- [ ] Testing strategy defined for the feature

### Phase 1: Design

- Define user stories with acceptance criteria
- Document data models and contracts
- Identify dependencies and risks

### Phase 2: Implementation

1. **Write tests FIRST** - Tests MUST fail before implementation
2. **Implement minimally** - Only code needed to pass tests
3. **Refactor** - Improve while keeping tests green
4. **Commit** - Small, focused commits with meaningful messages

### Phase 3: Verification

- All tests MUST pass
- Code review confirms alignment with constitution
- Documentation updated

---

## Quality Gates

All pull requests MUST pass:

1. **Test Gate**: All unit, integration, and acceptance tests passing
2. **Lint Gate**: Code formatting and style compliance
3. **Constitution Check**: Review confirms adherence to principles
4. **Documentation Gate**: User-facing changes include documentation updates

---

## Governance

This constitution supersedes all other practices. Amendments require:

1. **Documentation**: Clear description of the proposed change
2. **Compliance Review**: Verification that existing work is not invalidated
3. **Migration Plan**: Strategy for updating existing artifacts
4. **Approval**: Merge via pull request with required reviewers

**All PRs and reviews MUST verify compliance** with the principles in this document.

---

## Reference Architecture Summary

The Nornnet PoC implements:

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Image                        │
│  (Base + Config + Application Components)                  │
├─────────────────────────────────────────────────────────────┤
│                      Config Image                           │
│  (Base + System Configuration)                             │
├─────────────────────────────────────────────────────────────┤
│                      Base Image                            │
│  (Minimal bootc-compatible OS)                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                  ┌─────────────────┐
                  │  GitHub Container│
                  │    Registry      │
                  │     (GHCR)       │
                  └─────────────────┘
                            │
                            ▼ (pull-based)
         ┌──────────────────────────────────────┐
         │         Managed Devices              │
         │  bootc + systemd + quadlets + podman │
         └──────────────────────────────────────┘
```

**Version**: 1.0.0 | **Ratified**: 2026-03-24 | **Last Amended**: 2026-03-24

<!--
Sync Impact Report:
- Version: 0.0.0 → 1.0.0 (initial creation)
- Modified principles: N/A (new document)
- Added sections:
  - Expert Ownership table (3 experts identified)
  - I. Git as Single Source of Truth (owned by: Infrastructure & DevOps Expert)
  - II. Immutable OS Images via bootc (owned by: Infrastructure & DevOps Expert)
  - III. Test-First Development (NON-NEGOTIABLE) (owned by: Quality & Testing Expert)
  - IV. Layered Image Architecture (owned by: Infrastructure & DevOps Expert)
  - V. Pull-Based Updates with Minimal Attack Surface (owned by: Security & Observability Expert)
  - VI. Observability via Structured Logging (owned by: Security & Observability Expert)
  - Technology Stack Constraints
  - Development Workflow
  - Quality Gates
  - Governance (owned by: Security & Observability Expert)
  - Reference Architecture Summary
- Removed sections: N/A (new document)
- Templates requiring updates: N/A
- Knowledge bases created:
  - .knowledge/infrastructure-devops-expert/SUMMARY.md
  - .knowledge/quality-testing-expert/SUMMARY.md
  - .knowledge/security-observability-expert/SUMMARY.md
-->
