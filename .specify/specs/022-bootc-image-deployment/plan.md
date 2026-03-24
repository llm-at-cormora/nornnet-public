# Implementation Plan: Bootc Image Build & Deployment

**Feature Branch**: `022-bootc-image-deployment`  
**Plan Created**: 2026-03-24  
**Status**: Draft  
**Input**: GitHub Issues #22, #23

---

## RESEARCH COMPLETION CHECKLIST

- [x] Identified problem domains (NOT technologies)
- [x] Counted 8 total problem domains
- [x] Launched ONE research agent per problem domain (total: 8 agents)
- [x] Ran agents in batches of 4, waited for completion, repeated until done
- [x] Each agent completed Phase 1: Empathize (understand problem deeply)
- [x] Each agent completed Phase 2: Define (requirements & constraints)
- [x] Each agent completed Phase 3: Ideate - Discovered MULTIPLE solutions
- [x] Each agent completed Phase 4: Prototype (recommended best-fit solutions)
- [x] Reviewed all 8 research reports
- [x] Made accept/iterate decision: **ACCEPT** all recommendations

**Number of problem domains researched: 8**

---

## Problem Domains Researched

1. **Image Build Automation** - How to reliably build bootable container images in a reproducible way
2. **Registry Authentication & Operations** - How to authenticate and push/pull images to GHCR
3. **Device Deployment via bootc** - How to deploy images to target devices
4. **Transactional Updates with Rollback** - How to apply updates atomically and recover on failure
5. **Build Reproducibility** - How to ensure deterministic, verifiable builds
6. **CI/CD Pipeline Automation** - How to automate build/push workflows via GitHub Actions
7. **Test Environment Infrastructure** - How to create and manage test environments for validation
8. **Status Reporting & Observability** - How to provide visibility into device and image state
9. **Concurrent Operation Safety** - How to ensure safe handling of concurrent operations

---

# PHASE 1: PRODUCT TECHNICAL CONTEXT

## Language/Version

| Component | Language | Version | Rationale |
|-----------|----------|---------|-----------|
| Image Definition | Containerfile | Latest | Standard for bootc images |
| CI/CD Scripts | Bash/Shell | Bash 5+ | Ubiquitous, integrates with GitHub Actions |
| Testing Scripts | BATS (Bash Automated Testing) | 0.4+ | Native shell testing |
| Optional Tooling | Rust | 1.75+ | For bcvk (bootc VM testing tool) |

## Primary Dependencies

| Layer | Technology | Version | Purpose |
|-------|------------|---------|---------|
| OS Delivery | bootc | Latest | Bootable container runtime |
| Container Runtime | podman | 4.0+ | Rootless container management |
| Image Builder | bootc-image-builder | Latest | Convert containers to disk images |
| Service Management | systemd | 255+ | Native init system |
| Container Management | quadlets | Latest | systemd-native containers |
| Update Backend | OSTree | Latest | Git-like OS image replication |
| Health Checks | greenboot | Latest | Automatic rollback on failure |
| Build Tool | Buildah | Latest | Reproducible container builds |

## Storage

| Purpose | Technology | Rationale |
|---------|-----------|-----------|
| Container Images | GHCR (GitHub Container Registry) | Tight integration with GitHub |
| Image Pull Secrets | `/etc/ostree/auth.json` | Native OSTree authentication |
| Local Build Cache | podman storage | Default container storage |
| Health Check State | GRUB boot counter | Persistent across reboots |

## API Style

| Operation | Style | Tools |
|-----------|-------|-------|
| Image Build | CLI | `podman build`, `bootc-image-builder` |
| Registry Push/Pull | CLI | `podman push`, `podman pull` |
| Device Deployment | CLI | `bootc switch`, `bootc install` |
| Update Detection | CLI | `bootc upgrade --check` |
| Status Reporting | CLI | `bootc status`, `ostree admin status` |

## Project Type

**Infrastructure Definition + CI/CD Pipeline**

- Containerfile definitions for base/config/app images
- GitHub Actions workflows for automation
- Shell scripts for local development
- BATS tests for validation

## Performance Goals

| Metric | Target | Notes |
|--------|--------|-------|
| Build Time | < 15 min | For full layered image |
| Image Size | < 2 GB | For base image |
| Update Detection | < 30 sec | Network check latency |
| Rollback Time | < 5 min | To previous deployment |

## Constraints

| Constraint | Impact |
|------------|--------|
| Offline-capable | Images must be self-contained |
| No third-party agents | Must use systemd-native tools only |
| < 100MB memory for agent | Resource-constrained devices |
| Pull-based only | No inbound management ports |

---

# PHASE 2: TEST SCAFFOLDING TECHNICAL CONTEXT

## Test Framework

| Test Type | Framework | Rationale |
|-----------|-----------|-----------|
| Unit Tests | BATS (Bash) | Shell scripts, fast feedback |
| Container Tests | `bootc container lint` | Native bootc validation |
| Integration Tests | Terratest (Go) | Infrastructure testing |
| VM Tests | bcvk (Rust CLI) | Full boot chain testing |

## Acceptance Test Tools

| Tool | Purpose | Integration |
|------|---------|-------------|
| `bootc container lint` | Pre-push validation | CI/CD pipeline |
| BATS | Shell script testing | Local + CI |
| Terratest | Infrastructure validation | CI/CD |
| `bcvk` | VM boot testing | CI/CD self-hosted runners |

## Integration Test Tools

| Tool | Purpose |
|------|---------|
| GitHub Actions | CI/CD execution |
| Self-hosted runners | VM-based testing |
| `podman` | Local container operations |
| `libvirt` | VM management |

## Test Data Strategy

| Strategy | Implementation |
|----------|----------------|
| Test Images | Separate GHCR namespace (`ghcr.io/os2sandbox/nornnet-test:*`) |
| Version Tagging | `test-<date>-<commit>` for CI images |
| Cleanup | GitHub Actions artifact retention policy |

## Failure Testing Scenarios (Required by spec.md Section 6)

Per spec.md requirements, the test environment MUST support these negative testing scenarios:

| Scenario | Test Oracle | Pass Criteria |
|----------|------------|---------------|
| **Network Interruption** | Simulate network failure mid-download | Download resumes from interruption point or rollback occurs |
| **Registry Unavailability** | Temporarily block registry access | Retry with backoff succeeds when registry returns |
| **Partial State Injection** | Kill process during update | System recovers via rollback, no corruption |
| **Power Loss Simulation** | Abrupt VM shutdown mid-update | VM restarts to previous deployment |
| **Disk Full** | Limit available storage | Graceful error, no partial download |

## Concurrency Testing Scenarios (Required by spec.md Section 6)

| Scenario | Test Oracle | Pass Criteria |
|----------|------------|---------------|
| **Simultaneous Updates** | Two update requests at same time | Only one proceeds, other rejected |
| **Update During Rollback** | Update request while rollback running | Update rejected |
| **Detection During Deployment** | Check for updates while deploying | Returns "busy" status |

## Test Environment Instrumentation (Required by spec.md Section 6)

Tests must be able to observe device state:

| Capability | Implementation |
|------------|----------------|
| **Console Access** | Serial console logs captured via bcvk `--console-log` |
| **State Queries** | `scripts/status.sh` outputs machine-parseable JSON |
| **Event Capture** | journald logs with structured JSON, timestamped |
| **Timeline Reconstruction** | Events include `event_id`, `timestamp`, `component` |

---

# PHASE 3: COMPONENT MAPPING

## Logical to Technical Component Mapping

| Logical Component | Implementation | File(s) | Test Coverage |
|-----------------|----------------|---------|---------------|
| LC-1: Image Builder | Containerfile + podman | `Containerfile.base`, `Containerfile.config`, `Containerfile.app` | `tests/unit/image-builder.bats` |
| LC-2: Registry Client | podman + GHCR | `.github/workflows/build-push.yml` | `tests/integration/registry-operations.bats` |
| LC-3: Deployment Orchestrator | `bootc switch` + scripts | `scripts/deploy.sh` | `tests/acceptance/deployment.bats` |
| LC-4: Update Detector | `bootc upgrade --check` | `scripts/check-updates.sh` | `tests/acceptance/update-detection.bats` |
| LC-5: Rollback Manager | greenboot + OSTree | `config/greenboot/` | `tests/acceptance/rollback.bats` |
| LC-6: Status Reporter | `bootc status` + journald | `scripts/status.sh` | `tests/integration/status-reporting.bats` |
| CC-1: Build Reproducibility | Buildah + SOURCE_DATE_EPOCH | `Containerfile.*` | `tests/unit/reproducibility.bats` |
| CC-6: Concurrent Safety | flock + systemd unit | `systemd/nornnet-update.service` | `tests/unit/concurrency.bats` |
| **CC-7: Network Resilience** | OSTree delta + retry logic | `config/ostree/` | `tests/acceptance/network-resilience.bats` |
| **CC-8: Resource Constraints** | Image size limits + storage mgmt | `scripts/storage-check.sh` | `tests/unit/resource-constraints.bats` |

---

# PHASE 4: CONSTITUTION CHECK

## Alignment Verification

| Constitution Principle | Status | Evidence |
|----------------------|--------|---------|
| I. Git as Single Source of Truth | ✅ | All artifacts in Git, PR-based workflow |
| II. Immutable OS Images via bootc | ✅ | Containerfile-based image definitions |
| III. Test-First Development | ✅ | BATS tests before implementation (RED-GREEN-REFACTOR enforced) |
| IV. Layered Image Architecture | ✅ | Base/Config/App layer separation |
| V. Pull-Based Updates | ✅ | `bootc switch`, no inbound ports |
| VI. Observability via Structured Logging | ✅ | journald + OTEL Collector |

## Cross-Cutting Concerns Verification

| CC | Status | Implementation |
|----|--------|----------------|
| CC-1: Build Reproducibility | ✅ | SOURCE_DATE_EPOCH, Buildah timestamp |
| CC-2: Transactional Integrity | ✅ | OSTree A/B deployments, greenboot health checks |
| CC-3: Pull-Based Security | ✅ | Device-initiated only, no inbound ports |
| CC-4: Auditability | ✅ | Structured JSON logs, event timestamps |
| CC-5: Minimal Dependency Surface | ✅ | Self-contained images, no runtime downloads |
| CC-6: Concurrent Operation Safety | ✅ | flock + systemd unit locking |
| **CC-7: Network Resilience** | ✅ | OSTree delta updates, retry with backoff |
| **CC-8: Resource Constraint Awareness** | ✅ | Storage limits, memory checks |

## TDD Enforcement (NON-NEGOTIABLE per Constitution Article III)

**Every task MUST follow RED-GREEN-REFACTOR:**

### RED Phase (REQUIRED first)
1. Write the failing test **before** any implementation code
2. Test MUST fail with meaningful error message
3. Commit: "RED: Add failing test for [feature]"

### GREEN Phase
1. Write **minimal** code to make test pass
2. No feature expansion, only what's needed
3. Commit: "GREEN: Implement [feature] to pass test"

### REFACTOR Phase
1. Improve code quality while tests remain green
2. Commit: "REFACTOR: Improve [aspect] without changing behavior"

### TASK COMPLETION
- **Task is NOT complete until all tests pass**
- CI pipeline MUST be green
- No exceptions for "urgent" fixes

### Example Task Flow (Task 1):

```
1.1 Create tests/unit/image-builder.bats → COMMIT (RED)
1.2 Run bats tests/unit/image-builder.bats → VERIFY FAILS
1.3 Create Containerfile.base → COMMIT (GREEN)
1.4 Run bats tests/unit/image-builder.bats → VERIFY PASSES
1.5 Refactor Containerfile.base if needed → COMMIT (REFACTOR)
1.6 Final verification: ALL tests pass → TASK COMPLETE
```

### Prohibited Actions
- ❌ Writing implementation code before its test
- ❌ Skipping tests for "simple" features
- ❌ Merging code with failing tests
- ❌ Disabling tests to meet deadlines

---

# PHASE 5: PROJECT STRUCTURE

```
nornnet/
├── Containerfile.base           # Layer 1: Minimal bootc OS
├── Containerfile.config         # Layer 2: System configuration
├── Containerfile.app            # Layer 3: Application components
├── config/
│   ├── greenboot/               # Health checks for rollback
│   │   ├── check/
│   │   │   └── required.d/
│   │   │       └── 50-verify-system.sh
│   │   └── red.d/
│   │       └── cleanup.sh
│   ├── ostree/                  # OSTree configuration (CC-7)
│   │   └── sysroot.conf
│   └── systemd/
│       └── nornnet-update.service
├── scripts/
│   ├── build.sh                 # Local image build
│   ├── deploy.sh                # Device deployment
│   ├── check-updates.sh        # Update detection
│   ├── status.sh                # Status reporting
│   ├── rollback.sh              # Manual rollback trigger
│   └── storage-check.sh         # Resource constraint checks (CC-8)
├── tests/
│   ├── unit/
│   │   ├── image-builder.bats
│   │   ├── reproducibility.bats
│   │   ├── concurrency.bats
│   │   └── resource-constraints.bats   # CC-8
│   ├── integration/
│   │   ├── registry-operations.bats
│   │   └── status-reporting.bats
│   └── acceptance/
│       ├── deployment.bats
│       ├── update-detection.bats
│       ├── rollback.bats
│       ├── network-resilience.bats      # CC-7
│       └── failure-injection.bats       # Failure scenarios
├── .github/
│   └── workflows/
│       ├── build.yml            # CI: Image build
│       ├── push.yml             # CI: Push to GHCR
│       └── test.yml            # CI: Acceptance tests
├── docs/
│   └── research/                # Research reports
│       ├── bootc-cicd-pipeline-solutions.md
│       ├── bootc-test-infrastructure-research.md
│       └── cc6-concurrent-operation-safety-research.md
└── README.md
```

---

# IMPLEMENTATION TASKS

## Task 1: Base Image Definition (P0)

**Owner**: Infrastructure & DevOps Expert  
**User Story**: US-1 (Local Image Build)

| Step | Action | Verification |
|------|--------|--------------|
| 1.1 | Create `Containerfile.base` | File exists |
| 1.2 | Write unit test `tests/unit/image-builder.bats` | Test fails (RED) |
| 1.3 | Build base image locally | `podman build -f Containerfile.base` |
| 1.4 | Verify with `bootc container lint` | No errors |
| 1.5 | Commit and push | PR review complete |

## Task 2: Registry Authentication (P0)

**Owner**: Infrastructure & DevOps Expert  
**User Story**: US-2 (Registry Authentication)

| Step | Action | Verification |
|------|--------|--------------|
| 2.1 | Configure GHCR auth in GitHub Actions | Workflow uses `GITHUB_TOKEN` |
| 2.2 | Write integration test | Test auth flow |
| 2.3 | Test PAT authentication locally | `podman login ghcr.io` |
| 2.4 | Document authentication | README updated |

## Task 3: CI/CD Pipeline (P0)

**Owner**: Infrastructure & DevOps Expert  
**User Story**: US-3 (Image Registry Operations)

| Step | Action | Verification |
|------|--------|--------------|
| 3.1 | Create `.github/workflows/build.yml` | File exists |
| 3.2 | Add Red Hat Actions for build | Uses `redhat-actions/buildah-build@v2` |
| 3.3 | Create push workflow | Uses `redhat-actions/push-to-registry@v2` |
| 3.4 | Write integration tests | Tests pass |
| 3.5 | Verify push to GHCR | Image visible in registry |

## Task 4: Device Deployment (P0)

**Owner**: Infrastructure & DevOps Expert  
**User Story**: US-4 (Device Deployment)

| Step | Action | Verification |
|------|--------|--------------|
| 4.1 | Create `scripts/deploy.sh` | Script exists |
| 4.2 | Write acceptance test | Test exists |
| 4.3 | Test on VM (bcvk) | VM boots from image |
| 4.4 | Verify with `bootc status` | Correct version shown |
| 4.5 | Document deployment process | README updated |

## Task 5: Update Detection (P1)

**Owner**: Security & Observability Expert  
**User Story**: US-5 (Update Detection)

| Step | Action | Verification |
|------|--------|--------------|
| 5.1 | Create `scripts/check-updates.sh` | Script exists |
| 5.2 | Write acceptance test | Test detects new version |
| 5.3 | Push new image version | Version in registry |
| 5.4 | Verify detection | Script reports update available |

## Task 6: Transactional Updates (P0)

**Owner**: Infrastructure & DevOps Expert  
**User Story**: US-6 (Transactional Update)

| Step | Action | Verification |
|------|--------|--------------|
| 6.1 | Configure OSTree for transactional updates | A/B deployments enabled |
| 6.2 | Write acceptance test | Test verifies atomic update |
| 6.3 | Trigger update | System updates atomically |
| 6.4 | Verify no partial state | No corruption on failure |

## Task 7: Rollback with Greenboot (P0)

**Owner**: Quality & Testing Expert  
**User Story**: US-6 (Rollback)

| Step | Action | Verification |
|------|--------|--------------|
| 7.1 | Install greenboot | Package installed |
| 7.2 | Configure health checks | `config/greenboot/check/required.d/` |
| 7.3 | Write acceptance test | Test triggers rollback |
| 7.4 | Inject failure and verify rollback | System recovers |
| 7.5 | Document rollback procedure | README updated |

## Task 8: Automated Reboot (P2)

**Owner**: Infrastructure & DevOps Expert  
**User Story**: US-7 (Automated Reboot)

| Step | Action | Verification |
|------|--------|--------------|
| 8.1 | Configure `bootc upgrade --apply` | Reboot triggered |
| 8.2 | Write acceptance test | Test verifies reboot |
| 8.3 | Verify post-reboot state | New version active |

## Task 9: Status Reporting (P2)

**Owner**: Security & Observability Expert  
**User Story**: US-8 (Image Layer Verification)

| Step | Action | Verification |
|------|--------|--------------|
| 9.1 | Configure journald JSON logging | Structured logs enabled |
| 9.2 | Create `scripts/status.sh` | Reports version/state |
| 9.3 | Write integration test | Test verifies output |
| 9.4 | Configure OTEL Collector | Lightweight agent mode |

## Task 10: Concurrency Safety (P1)

**Owner**: Quality & Testing Expert  
**Cross-Cutting**: CC-6 (Concurrent Operation Safety)

| Step | Action | Verification |
|------|--------|--------------|
| 10.1 | Create systemd unit with `flock` | Prevents concurrent runs |
| 10.2 | Write unit test | Test concurrent rejection |
| 10.3 | Document concurrency behavior | README updated |

### Test Oracles for Concurrency:

| Scenario | Precondition | Trigger | Pass Criteria | Fail Criteria |
|----------|-------------|---------|--------------|---------------|
| TC-10.1: Concurrent Update Rejection | Device idle, no update in progress | Second update request while first running | Second request returns error "Update already in progress" | Second update starts |
| TC-10.2: Update During Rollback | Rollback in progress | Update request arrives | Request rejected, returns error "Rollback in progress" | Update proceeds |
| TC-10.3: Detection During Deployment | Deployment in progress | Check for updates request | Returns "Deployment in progress, check back later" | Returns version info |

---

## Task 11: Network Resilience (P1)

**Owner**: Infrastructure & DevOps Expert  
**Cross-Cutting**: CC-7 (Network Resilience)

| Step | Action | Verification |
|------|--------|--------------|
| 11.1 | Configure OSTree for delta updates | Partial downloads resumable |
| 11.2 | Implement retry with exponential backoff | Network interruption handled gracefully |
| 11.3 | Write acceptance tests | Tests verify resume on failure |
| 11.4 | Test network interruption scenarios | System recovers |

### Test Oracles for Network Resilience:

| Scenario | Precondition | Trigger | Pass Criteria | Fail Criteria |
|----------|-------------|---------|--------------|---------------|
| TC-11.1: Download Resume | Download interrupted at 50% | Network restored, resume | Download completes from 50% mark | Download restarts from 0% |
| TC-11.2: Registry Timeout | Registry temporarily unavailable | First request times out | Retry succeeds after backoff | Error returned without retry |
| TC-11.3: Partial State Recovery | Network loss during update | Power cycle | OSTree rollback to previous deployment | Device unbootable |

---

## Task 12: Resource Constraint Awareness (P2)

**Owner**: Infrastructure & DevOps Expert  
**Cross-Cutting**: CC-8 (Resource Constraint Awareness)

| Step | Action | Verification |
|------|--------|--------------|
| 12.1 | Define image size limits | Base image < 2GB, total < 4GB |
| 12.2 | Create storage management script | `scripts/storage-check.sh` |
| 12.3 | Write unit tests | Tests verify size constraints |
| 12.4 | Test with constrained disk | System handles low storage gracefully |

### Test Oracles for Resource Constraints:

| Scenario | Precondition | Trigger | Pass Criteria | Fail Criteria |
|----------|-------------|---------|--------------|---------------|
| TC-12.1: Image Size Limit | Disk with 1GB free | Attempt to download 2GB image | Error "Insufficient disk space" before download | Download starts, fails later |
| TC-12.2: Memory Constraint | Device with < 100MB available | Update operation starts | Operation fails gracefully with memory warning | OOM kill |
| TC-12.3: Storage Growth Bounded | Device with limited storage | 10 sequential updates | Storage usage remains bounded (old deployments pruned) | Storage grows unbounded |

---

# ARTIFACTS

## Research Reports

| Report | Location | Key Finding |
|--------|----------|-------------|
| Image Build Automation | `docs/research/` | bootc-image-builder + BuildKit/SLSA |
| Registry Authentication | `docs/research-registry-authentication.md` | GITHUB_TOKEN for CI, PAT for devices |
| Device Deployment | `docs/research/` | bootc-image-builder + bootc switch |
| Transactional Updates | `docs/research/` | bootc + Greenboot |
| CI/CD Pipeline | `docs/research/bootc-cicd-pipeline-solutions.md` | Red Hat Actions (buildah-build) |
| Test Infrastructure | `docs/research/bootc-test-infrastructure-research.md` | bcvk + Terratest |
| Status Reporting | `docs/research-status-reporting-observability.md` | bootc + journald + OTEL Collector |
| Concurrency Safety | `docs/cc6-concurrent-operation-safety-research.md` | flock + systemd + Rust State Machine |

---

## Test Oracles for User Stories (Required by spec.md Section 6)

Per spec.md: "For each test scenario, the following must be defined: Preconditions, Trigger, Expected Outcome, Failure Conditions, Postconditions"

### US-1: Local Image Build

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-1.1 | Clean environment, tools installed | Execute build command | Build completes, OCI image produced | Build fails with error | Image exists in local storage |
| SC-1.2 | Image built successfully | Inspect layers | Each layer correct, no errors | Layer inspection fails | Layers match expected content |
| SC-1.3 | Build failure scenario | Fix invalid instruction, rebuild | Build succeeds, error absent | Same error persists | Image builds successfully |

### US-2: Registry Authentication

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-2.1 | Valid credentials configured | Authenticate with registry | Auth succeeds, operations authorized | Auth fails | Operations can proceed |
| SC-2.2 | Invalid credentials | Attempt authentication | Auth fails, clear error, no ops occur | Auth succeeds | Unauthorized state prevented |
| SC-2.3 | Previously successful auth | Credentials expired/revoked | Operations fail, re-auth required | Operations still work | System requires re-auth |

### US-3: Image Registry Operations

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-3.1 | Built image + valid auth | Push to registry | Image in registry with correct tag | Push fails | Image retrievable from registry |
| SC-3.2 | Image in registry | Pull to local | Pulled image matches original | Pull fails or mismatch | Image identical to original |
| SC-3.3 | Existing image versions | Push new version | Both versions available with distinct tags | New version missing | Multiple versions listed |

### US-4: Device Deployment

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-4.1 | Device with bootc, network to registry | Deploy command with image ref | Device downloads, applies, boots new OS | Download fails, boot fails | Device running new image |
| SC-4.2 | Deployment completed | Check device status | Status shows new image version | Status wrong | Status accurate |
| SC-4.3 | Deployment in progress | Process completes | Device in consistent, bootable state | Device unbootable | Device operational |

### US-5: Update Detection

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-5.1 | Device on v1.0 | Push v1.1 to registry | Device detects new version available | Detection fails | Update known to device |
| SC-5.2 | Device on latest version | Check for updates | System reports no updates | Reports update exists | Correct status reported |
| SC-5.3 | Multiple versions in registry | Query available versions | Correct latest version reported | Wrong version reported | Accurate version list |

### US-6: Transactional Update

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-6.1 | Device on v1.0 | Trigger update to v1.1 | Complete update OR remain on v1.0 | Partial update state | Atomic outcome |
| SC-6.2 | Update in progress, fails mid-way | Update process fails | Auto-rollback to v1.0 | No rollback, corrupted state | Previous state restored |
| SC-6.3 | Rollback occurred | Check device status | Running previous version, no corruption | Corruption present | Device functional |

### US-7: Automated Reboot

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-7.1 | Update downloaded and applied | Update process completes | Device reboots automatically | No reboot, manual required | Device reboots |
| SC-7.2 | Reboot in progress | System comes back online | Running new image version | Old version still running | New version active |

### US-8: Image Layer Verification

| Criterion | Precondition | Trigger | Expected Outcome | Failure Condition | Postcondition |
|-----------|--------------|---------|-----------------|------------------|---------------|
| SC-8.1 | Built image | Inspect layers | Each layer has expected content, no extras | Extraneous files present | Clean layer content |
| SC-8.2 | Same source rebuild | Compare layers | Layers identical (deterministic) | Layers differ | Reproducible build |

---

# QUICKSTART

## Prerequisites

```bash
# Install required tools
brew install podman buildah bootc  # macOS/Linux
# or
dnf install podman buildah bootc   # Fedora/RHEL

# Verify installation
podman --version
bootc --version
```

## Build Local Image

```bash
# Clone and build
git checkout -b 022-bootc-image-deployment
podman build -f Containerfile.base -t nornnet-base:latest .
podman run --rm --privileged -v ./output:/output \
  quay.io/centos-bootc/bootc-image-builder:latest \
  nornnet-base:latest
```

## Run Tests

```bash
# Install BATS
brew install bats

# Run unit tests
bats tests/unit/

# Run integration tests
bats tests/integration/

# Run acceptance tests (requires VM)
bats tests/acceptance/
```

## Deploy to Device

```bash
# Authenticate with registry
podman login ghcr.io

# Deploy image
./scripts/deploy.sh ghcr.io/os2sandbox/nornnet:0.1.0

# Check status
./scripts/status.sh
```

---

# DECISION SUMMARY

## Research Acceptance

All 8 research reports were reviewed and **ACCEPTED**. Key decisions:

| Domain | Accepted Recommendation | Notes |
|--------|------------------------|-------|
| Image Build | bootc-image-builder + BuildKit provenance | ✅ |
| Registry Auth | GITHUB_TOKEN (CI) + PAT (devices) | ✅ |
| CI/CD | Red Hat Actions (buildah-build) | ✅ |
| Deployment | `bootc switch` only | ⚠️ **NO Flight Control** (fleet mgmt is out of scope per spec) |
| Updates | bootc + Greenboot | ✅ |
| Observability | bootc + journald + OTEL Collector | ✅ |
| Testing | bcvk + Terratest + BATS | ✅ |
| Concurrency | flock + systemd unit | ✅ |

### ⚠️ Corrected Deployment Approach

Per spec.md: "Out of Scope: Multi-device fleet management"

**Only implement:**
- `bootc switch` for direct device deployment
- `bootc install to-disk` for initial installation

**Do NOT implement:**
- Flight Control (fleet management platform)
- Any centralized orchestration server

This is a **correction** from research recommendation which suggested Flight Control.

## Technology Stack

**Product Stack**:
- bootc, podman, OSTree, systemd, quadlets
- GHCR, bootc-image-builder, greenboot

**Test Stack**:
- BATS, Terratest, bcvk
- GitHub Actions, Self-hosted runners

---

**Plan Version**: 1.1.0  
**Last Updated**: 2026-03-24

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-03-24 | Initial plan created |
| 1.1.0 | 2026-03-24 | Fixed conflict (removed Flight Control), added CC-7, CC-8, test oracles, failure/concurrency testing scenarios, explicit TDD enforcement |
