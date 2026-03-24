# Feature Specification: Bootc Image Build & Deployment

**Feature Branch**: `022-bootc-image-deployment`  
**Created**: 2026-03-24  
**Status**: Draft  
**Input**: GitHub Issue #22 - Implement Bootable Container (bootc) image & deployment  
**Constitution Alignment**: Layers I, II, IV (Git as Source of Truth, Immutable OS Images, Layered Image Architecture)

---

## 1. Feature Overview

---

## Clarifications

### Session 2026-03-24

- Q: Authentication mechanism for registry operations → A: D - Anonymous read + token push model (devices pull without auth, push requires token)
- Q: Image versioning scheme → A: A - Semantic versioning with Git commit hash in image label (supports rollback semantics and audit traceability)

---

### Problem Statement

Managing Linux devices currently requires either manual configuration (error-prone, inconsistent) or third-party agents (added complexity, security risk). We need a way to deliver consistent, immutable operating systems to devices that can be updated transactionally without manual intervention or open management ports.

### Success Criteria

1. **Build Verification**: A Containerfile produces a bootable OCI image with no layer errors
2. **Registry Integration**: The image is stored in and retrievable from GitHub Container Registry (GHCR)
3. **Deployment Capability**: A target device boots from an image hosted on the registry
4. **Update Propagation**: A new image version is detected and applied automatically on the device
5. **Rollback Capability**: If an update fails, the system recovers to the previous working state

### Scope

**In Scope**:
- Building bootable container images locally
- Pushing images to GitHub Container Registry
- Deploying images to devices using bootc switch
- Verifying deployment status
- Testing automatic update propagation
- Transactional updates with rollback

**Out of Scope**:
- Multi-device fleet management
- Configuration management within images (this is the Config Image layer)
- Application deployment within images (this is the Application Image layer)
- Monitoring/alerting infrastructure
- Device enrollment/authentication

---

## 2. User Stories

### User Story 1 - Local Image Build (Priority: P1)

**Story**: As an infrastructure operator, I want to build bootable container images locally, so that I can verify my changes work before exposing them to devices.

**Why this priority**: This is the foundation. If we cannot build images locally, nothing else matters. It must work first.

**Independent Test**: Can be fully tested by running a build command and verifying the resulting image can be inspected for layers.

**Acceptance Scenarios**:

1. **Given** a clean development environment with required tools installed, **When** I execute the build command, **Then** the build completes without errors and produces an OCI image.

2. **Given** the image build completed successfully, **When** I inspect the image layers, **Then** I can verify each layer was created correctly with no errors.

3. **Given** a build failure due to an invalid instruction, **When** I fix the instruction and rebuild, **Then** the build succeeds and the previous error is not present in the output.

---

### User Story 2 - Registry Authentication (Priority: P1)

**Story**: As an infrastructure operator, I want to authenticate with the container registry, so that I can push and pull images securely.

**Why this priority**: Authentication is required before any registry operations can occur. Without this, the rest of the pipeline cannot function.

**Authentication Model**: Anonymous read + token push. Devices can pull images without authentication (read-only public access). Pushing images requires token-based authentication. This model aligns with pull-based security posture by minimizing credential exposure on devices.

**Independent Test**: Can be tested by attempting registry operations (push/pull) and verifying authentication succeeds or fails appropriately.

**Acceptance Scenarios**:

1. **Given** the registry allows anonymous read access, **When** a device attempts to pull an image, **Then** the pull succeeds without authentication.

2. **Given** a valid push token is configured, **When** I attempt to push an image to the registry, **Then** the push succeeds and the image appears in the registry.

3. **Given** no push token is configured, **When** I attempt to push an image, **Then** the push fails with an authentication error.

4. **Given** an invalid or expired token is configured, **When** I attempt to push an image, **Then** the push fails with an authentication error and no unauthorized operations occur.

---

### User Story 3 - Image Registry Operations (Priority: P1)

**Story**: As an infrastructure operator, I want to push images to the registry, so that devices can access them for deployment.

**Why this priority**: Images must be in the registry for devices to fetch them. This is the link between build and deployment.

**Versioning**: Images use semantic versioning (major.minor.patch). The Git commit hash is stored as an OCI label for traceability. Registry tags follow the pattern: `v{version}` (e.g., `v1.0.0`).

**Independent Test**: Can be tested by pushing an image and verifying it exists in the registry via listing or inspection.

**Acceptance Scenarios**:

1. **Given** I have a locally built image with version 1.0.0 and valid push token, **When** I push the image to the registry, **Then** the image appears with tag `v1.0.0` and contains the Git commit hash label.

2. **Given** an image exists in the registry, **When** I pull it to a local environment, **Then** the pulled image matches the original (verified by inspection).

3. **Given** I push a new version 1.1.0 of an existing image, **When** I list available versions, **Then** both `v1.0.0` and `v1.1.0` are available with distinct tags.

---

### User Story 4 - Device Deployment (Priority: P1)

**Story**: As an infrastructure operator, I want to deploy an image to a target device, so that the device runs the desired OS configuration.

**Why this priority**: Deployment is the core capability. Without this, there is no device management.

**Independent Test**: Can be tested by deploying to a VM or test device and verifying the device boots from the new image.

**Acceptance Scenarios**:

1. **Given** a device running a bootc-compatible base OS, **When** I invoke the deployment command with a registry image reference, **Then** the device downloads and applies the new image.

2. **Given** the deployment command completed successfully, **When** I check the device status, **Then** the status indicates the device is running the newly deployed image.

3. **Given** a deployment is in progress, **When** the process completes, **Then** the device is in a consistent, bootable state.

---

### User Story 5 - Update Detection (Priority: P2)

**Story**: As an infrastructure operator, I want the system to detect when a new image version is available, so that I can trigger updates without manual inspection.

**Why this priority**: Pull-based management requires devices to know when updates exist. Manual inspection defeats the purpose.

**Independent Test**: Can be tested by publishing a new image version and verifying the device detects it.

**Acceptance Scenarios**:

1. **Given** a device is running version 1.0 of an image, **When** I push version 1.1 to the registry, **Then** the device detects that a new version is available.

2. **Given** a device is already running the latest version, **When** I check for updates, **Then** the system reports no updates are available.

3. **Given** multiple versions exist in the registry, **When** I query available versions, **Then** the system reports the correct latest version.

---

### User Story 6 - Transactional Update (Priority: P1)

**Story**: As an infrastructure operator, I want updates to be applied atomically, so that devices are never left in a broken or inconsistent state.

**Why this priority**: Remote devices cannot be manually fixed if an update corrupts them. Atomic updates with rollback are essential.

**Independent Test**: Can be tested by triggering an update and verifying either complete success or complete rollback.

**Acceptance Scenarios**:

1. **Given** a device is running version 1.0, **When** I trigger an update to version 1.1, **Then** the device either completes the update to 1.1 or remains on 1.0 (never partially updated).

2. **Given** an update is in progress, **When** the update process fails mid-way, **Then** the device automatically rolls back to the previous working state.

3. **Given** a rollback occurred due to update failure, **When** I check the device status, **Then** the device reports it is running the previous version and no corruption is evident.

---

### User Story 7 - Automated Reboot (Priority: P2)

**Story**: As an infrastructure operator, I want the device to reboot automatically after applying an update, so that the new image is active without manual intervention.

**Why this priority**: Manual reboot defeats the automation goal. Updates should be hands-off end-to-end.

**Independent Test**: Can be tested by observing the device reboots automatically after update application.

**Acceptance Scenarios**:

1. **Given** an update has been downloaded and applied, **When** the update process is complete, **Then** the device reboots automatically to activate the new image.

2. **Given** a reboot is in progress, **When** the system comes back online, **Then** the device is running the new image version (verified by status check).

---

### User Story 8 - Image Layer Verification (Priority: P1)

**Story**: As a quality assurance engineer, I want to verify image layers are correct, so that I can ensure build reproducibility and catch errors early.

**Why this priority**: Layer verification catches build errors before they reach devices. This supports test-first development.

**Independent Test**: Can be tested by inspecting image layers and verifying expected content.

**Acceptance Scenarios**:

1. **Given** a built image, **When** I inspect the layers, **Then** each layer contains the expected content and no extraneous files are present.

2. **Given** a rebuild of the same source, **When** I compare layers, **Then** the layers are identical (deterministic build).

---

## 3. Acceptance Scenarios

### SC-001: Local Build Success
**Given** the development environment has all required tools installed and network access to base image sources  
**When** the build command is executed  
**Then** the build completes successfully and produces a valid OCI image artifact

### SC-002: Image Push to Registry
**Given** a successfully built image and valid registry credentials  
**When** the push command is executed  
**Then** the image appears in the registry with the specified tag and can be pulled by authorized clients

### SC-003: Device Image Deployment
**Given** a target device with bootc installed and network access to the registry  
**When** the deployment command is executed  
**Then** the device downloads the image, applies it, and boots into the new OS state

### SC-004: Update Detection
**Given** a device running an image from the registry  
**When** a new image version is published to the registry  
**Then** the device detects the new version is available for download

### SC-005: Atomic Update Application
**Given** a device running version N  
**When** an update to version N+1 is triggered  
**Then** the update completes atomically (all-or-nothing) and the device boots into version N+1

### SC-006: Automatic Rollback on Failure
**Given** a device is updating from version N to N+1  
**When** the update fails during application  
**Then** the device rolls back to version N and boots successfully without manual intervention

### SC-007: Automated Post-Update Reboot
**Given** an update has been successfully downloaded and applied  
**When** the update process completes  
**Then** the device automatically reboots to activate the new image

### SC-008: Deployment Status Verification
**Given** a device has been deployed with an image from the registry  
**When** the status command is executed on the device  
**Then** the status reflects the correct image version and source registry

---

## 4. Logical Components

### LC-1: Image Builder

**Responsibility**: Transform source definitions into deployable bootable container images.

**What it does**: 
- Processes source files and dependencies
- Constructs layered image following system requirements
- Validates image structure before completion
- Produces deterministic, reproducible artifacts
- Tags images with semantic version (major.minor.patch) and Git commit hash as OCI label

**Boundary**: Takes source definitions as input, produces OCI images as output.

---

### LC-2: Registry Client

**Responsibility**: Manage interactions between local environment and remote image registry.

**What it does**:
- Handles authentication with registry
- Pushes images to registry with version tags
- Pulls images from registry
- Queries available image versions
- Handles transient failures with appropriate retry strategies

**Boundary**: Operates between local build environment and external registry service.

---

### LC-3: Deployment Orchestrator

**Responsibility**: Coordinate the process of applying new images to target devices during normal operation.

**What it does**:
- Initiates image downloads on target devices
- Tracks deployment progress through completion
- Manages boot configuration changes (switching active image)
- Triggers post-deployment verification
- Delegates to Rollback Manager if failures occur

**Boundary**: Coordinates between registry and device bootloader/init system. Owns the "happy path" from download through successful activation.

**Note**: Boot entry switching (changing which image boots) is owned by this component during normal deployment.

---

### LC-4: Update Detector

**Responsibility**: Identify when new image versions are available in the registry.

**What it does**:
- Compares current device version against registry using semantic version comparison (device-resident, outbound-initiated polling)
- Reports when newer versions are available (higher semantic version)
- Reports current version status
- Emits events or status for consumption by Deployment Orchestrator or operators
- Reads version information from image labels (semantic version and Git commit hash)

**Boundary**: Monitors registry state on behalf of managed devices. Operates passively (detects and reports) rather than actively initiating deployments.

**Note**: Detection is device-initiated outbound communication only; no inbound connections are required or accepted.

---

### LC-5: Rollback Manager

**Responsibility**: Ensure devices recover to a known-good state when updates fail.

**What it does**:
- Maintains previous image version on device (previous-state preservation)
- Detects update failures through monitoring
- Initiates rollback to previous state
- Manages boot entry switching during rollback
- Verifies rollback completed successfully

**Boundary**: Operates within the device's boot and update subsystem. Activates when failures are detected, either through autonomous monitoring or delegation from Deployment Orchestrator.

**Note**: Rollback operations must also follow pull-based security posture (no inbound connections).

---

### LC-6: Status Reporter

**Responsibility**: Provide visibility into device and image state.

**What it does**:
- Reports current running image version
- Reports pending update status
- Reports deployment history
- Reports rollback history if applicable
- Emits structured events for audit trail

**Boundary**: Exposes state to operators and automated systems.

---

## 5. Cross-Cutting Concerns

### CC-1: Build Reproducibility

**Description**: Image builds must be deterministic. The same source must produce bit-for-bit identical images. This ensures that tests run against a local build match what devices receive. Build environment conditions must remain stable (tool versions, base layer references, host characteristics).

**Why it spans all components**: Build tools, registry operations, and deployment must all support reproducible artifacts. Non-reproducible builds undermine testing confidence.

**Owner**: Quality & Testing Expert

---

### CC-2: Transactional Integrity

**Description**: Updates must be atomic. A device is never in a "partial update" state. Either the update completes fully, or the previous state is preserved. Post-update verification confirms the new state is stable before permanent commitment. If verification fails, rollback occurs automatically.

**Why it spans all components**: Affects how images are structured (Image Builder), how deployments are orchestrated (Deployment Orchestrator), how rollback operates (Rollback Manager), and how state is tracked (Status Reporter). All components must support atomicity.

**Owner**: Infrastructure & DevOps Expert

---

### CC-3: Pull-Based Security Posture

**Description**: Devices initiate all communication. No inbound connections are required for management. This eliminates entire classes of network-based attacks. Registry access uses anonymous read + token push model: devices pull images without credentials (read-only public access), while pushing images requires token-based authentication. This minimizes credential exposure on remote devices.

**Why it spans all components**: All communication patterns must be outbound-initiated. Registry clients (LC-2), update detection (LC-4), rollback operations (LC-5), and status reporting (LC-6) must work within this constraint.

**Owner**: Security & Observability Expert

---

### CC-4: Auditability

**Description**: All image versions, deployments, and state changes must be traceable. Git commits map to image versions through provenance metadata (semantic version + Git commit hash embedded as OCI labels). Significant events must emit structured audit records with timestamps, actors, and outcomes. This enables full traceability from source commit to deployed device state.

**Why it spans all components**: Build processes (LC-1), registry operations (LC-2), update detection decisions (LC-4), and deployment status (LC-6) must maintain audit trails for compliance and troubleshooting.

**Owner**: Security & Observability Expert

---

### CC-5: Minimal Dependency Surface

**Description**: The system should minimize external dependencies. Images should be self-contained and not require runtime downloads. Operations should be resilient to network interruptions (retry capability, resume after failure).

**Why it spans all components**: Affects image construction (Image Builder), registry distribution (Registry Client), and offline operation (Deployment Orchestrator, Rollback Manager).

**Owner**: Infrastructure & DevOps Expert

---

### CC-6: Concurrent Operation Safety

**Description**: The system must handle multiple simultaneous operations safely. Only one update operation should occur at a time per device. Concurrent requests must be rejected or queued safely.

**Why it spans all components**: Affects Deployment Orchestrator (LC-3), Update Detector (LC-4), and Rollback Manager (LC-5). State transitions must be protected against race conditions.

**Owner**: Quality & Testing Expert

---

### CC-7: Network Resilience

**Description**: The system must handle network failures gracefully. Partial downloads must be resumable. Registry unavailability must not leave devices in inconsistent states. Retry strategies with backoff must be applied.

**Why it spans all components**: Affects Registry Client (LC-2), Deployment Orchestrator (LC-3), Update Detector (LC-4), and Rollback Manager (LC-5).

**Owner**: Infrastructure & DevOps Expert

---

### CC-8: Resource Constraint Awareness

**Description**: Operations must be aware of device limitations (storage capacity, memory for dual-boot scenarios, bandwidth constraints). Images must be deployable within real device operational bounds. Storage growth must be bounded over time.

**Why it spans all components**: Affects Image Builder (LC-1), Deployment Orchestrator (LC-3), Rollback Manager (LC-5), and Status Reporter (LC-6).

**Owner**: Infrastructure & DevOps Expert

---

## 6. Test Environment Requirements

### End-to-End Test Environment Design

The test environment for this feature must support the following test scenarios:

#### Local Build Testing
- **Required**: Build environment with container runtime and build tools
- **Verification**: Image layers can be inspected, build logs captured
- **Isolation**: Builds can run in parallel without interference

#### Registry Integration Testing
- **Required**: Access to container registry with test namespace
- **Verification**: Push/pull operations succeed, authentication errors handled gracefully
- **Isolation**: Test images use distinct tags to avoid production conflicts

#### Device Deployment Testing
- **Required**: 
  - Virtual machine or physical device with compatible base OS
  - Network access from device to registry
  - Serial console or network console for observation
- **Verification**: Device boots from deployed image, status commands work
- **Isolation**: Test devices are separate from production fleet

#### Update Propagation Testing
- **Required**: Deployed device with monitoring capability
- **Verification**: Update detection works, update application succeeds, reboot occurs
- **Isolation**: Update tests can run without affecting other tests

#### Rollback Testing
- **Required**: Deployed device with previous version preserved
- **Verification**: Rollback occurs automatically on failure, device recovers
- **Isolation**: Rollback tests should use dedicated test devices

### Test Environment Patterns

1. **VM-Based Testing**: Use VMs for most tests (faster, cheaper, repeatable)
2. **Containerized Registries**: Use local registry mirrors for isolated testing
3. **Snapshot/Restore**: Use VM snapshots to reset device state between tests
4. **Network Isolation**: Test environment should not reach production registry without explicit configuration

### Failure Testing Requirements

The test environment must support negative testing scenarios:

- **Network Interruption**: Simulate network failure mid-download to verify resume or rollback behavior
- **Registry Unavailability**: Simulate registry being unavailable during operations
- **Partial State Injection**: Verify system recovers gracefully from interrupted operations
- **Power Loss Simulation**: Verify transactional integrity after simulated power loss during update
- **Disk Full Scenarios**: Verify graceful handling when storage is exhausted

### Concurrency Testing Requirements

The test environment must support testing concurrent operations:

- **Simultaneous Updates**: Multiple update requests arriving concurrently
- **Update During Rollback**: Update triggered while rollback is in progress
- **Detection During Deployment**: Update detection while deployment is ongoing

### Test Oracles

For each test scenario, the following must be defined:

| Oracle Element | Description |
|----------------|-------------|
| **Preconditions** | State that must exist before test begins |
| **Trigger** | Action that starts the test |
| **Expected Outcome** | Specific, observable result that constitutes PASS |
| **Failure Conditions** | Specific results that constitute FAIL |
| **Postconditions** | State that must hold after test completes (pass or fail) |

### Test Instrumentation

Tests must be able to observe device state during execution:

- **Console Access**: Ability to capture boot logs and system output
- **State Queries**: Ability to query current image version, pending updates, deployment status
- **Event Capture**: Ability to capture and timestamp significant events (update start, download complete, reboot initiated)
- **Timeline Reconstruction**: Ability to reconstruct operation timeline from event log

### Environment Lifecycle Management

- **Provisioning**: Automated setup of test environments with consistent baseline state
- **Cleanup**: Automated teardown after tests complete (image removal, state reset)
- **Retention**: How long test environments persist before cleanup
- **Access Control**: Who can provision, access, and modify test environments

### Production Parity

Test environment should approximate production conditions:

- **Network Characteristics**: Similar latency/bandwidth constraints if possible
- **Registry Configuration**: Same authentication patterns as production
- **Device Characteristics**: Similar hardware specs as target deployment fleet
- **Deviations Documented**: Any differences from production must be documented and justified

---

## 7. Acceptance Checklist

- [ ] Each user story has acceptance criteria written in Given-When-Then format
- [ ] Each acceptance criterion is independently testable
- [ ] Acceptance scenarios cover all user stories
- [ ] No technology/implementation details in acceptance scenarios (e.g., no mention of Containerfile, podman, systemd, bootc commands)
- [ ] Logical components are at domain level (describes what, not how)
- [ ] Cross-cutting concerns cover quality attributes that span all components
- [ ] Test environment requirements clearly describe what is needed and why
- [ ] Failure testing scenarios are defined
- [ ] Concurrency testing scenarios are defined
- [ ] Test oracles specify pass/fail criteria for each scenario
- [ ] No specific technologies or numbers in the document (those come in Plan phase)
- [ ] All sections are present per template structure
- [ ] Expert review feedback has been incorporated
- [ ] Component boundaries are clearly defined (especially LC-3/LC-5)
- [ ] All cross-cutting concerns are assigned to experts

---

## 8. Expert Review Summary

Expert reviews conducted on 2026-03-24.

### Bootc Image Builder Expert (LC-1, LC-3, LC-5, CC-2, CC-5)

**Key Feedback Applied**:
- Clarified LC-3/LC-5 boundary: LC-3 owns happy path, LC-5 handles failure recovery
- Explicitly stated Deployment Orchestrator owns boot entry switching during normal deployment
- Added failure handling to LC-2 (Registry Client)
- Extended CC-2 to include post-update verification pattern
- Added CC-7 (Network Resilience) for handling partial downloads and retry strategies

### Container Registry Expert (LC-2, LC-4, CC-3, CC-4)

**Key Feedback Applied**:
- Clarified LC-4 operates passively (device-resident, outbound-initiated polling)
- Extended CC-3 to address credential distribution security
- Extended CC-4 to include provenance metadata and audit event requirements
- Clarified LC-4 boundary does not require inbound connections

### Quality & Testing Expert (Cross-Cutting Concerns)

**Key Feedback Applied**:
- Added CC-6 (Concurrent Operation Safety) for handling simultaneous operations
- Added CC-8 (Resource Constraint Awareness) for storage and operational bounds
- Added failure testing requirements (network interruption, registry unavailability, power loss)
- Added concurrency testing requirements
- Added test oracle definitions with preconditions, triggers, expected outcomes, failure conditions, postconditions
- Added test instrumentation requirements
- Added environment lifecycle management patterns
- Added production parity specification

### Changes Summary

| Section | Change Type | Description |
|---------|-------------|-------------|
| LC-2 | Enhanced | Added retry/failure handling responsibility |
| LC-3 | Enhanced | Clarified ownership of happy path and boot entry switching |
| LC-4 | Enhanced | Clarified passive detection and outbound-initiated operation |
| LC-5 | Enhanced | Clarified activation model and rollback operations |
| CC-2 | Enhanced | Added post-update verification requirement |
| CC-3 | Enhanced | Added credential distribution security |
| CC-4 | Enhanced | Added provenance and audit event requirements |
| CC-5 | Enhanced | Added network resilience consideration |
| CC-6 | Added | Concurrent operation safety |
| CC-7 | Added | Network resilience |
| CC-8 | Added | Resource constraint awareness |
| Section 6 | Enhanced | Added failure testing, concurrency testing, test oracles, instrumentation, lifecycle management, production parity |

---

**Version**: 1.1.0 | **Status**: Draft | **Last Updated**: 2026-03-24
