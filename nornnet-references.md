# Nornnet PoC - Reference Links

This document contains all relevant links found in the Nornnet repository for the bootc-based device management PoC.

## Main Repository

| Resource | Link |
|----------|------|
| **Main Repository** | https://github.com/OS2sandbox/nornnet |
| **Original Requirements (Issue #22)** | https://github.com/OS2sandbox/nornnet/issues/22 |
| **Automate Container Build (Issue #23)** | https://github.com/OS2sandbox/nornnet/issues/23 |
| **Operations Guide (Issue #24)** | https://github.com/OS2sandbox/nornnet/issues/24 |

---

## Open Issues (11 Total)

### Key Architecture & Requirements Issues

| Issue # | Title | Link |
|---------|-------|------|
| #1 | Remote administration of linux devices (Epic) | https://github.com/OS2sandbox/nornnet/issues/1 |
| #9 | Remote observability on linux devices (Epic) | https://github.com/OS2sandbox/nornnet/issues/9 |
| #11 | Enable kiosk functionality on client | https://github.com/OS2sandbox/nornnet/issues/11 |
| #22 | **Implement Bootable Container (bootc) image & deployment** | https://github.com/OS2sandbox/nornnet/issues/22 |
| #23 | **Automate Container Image Build and Push** | https://github.com/OS2sandbox/nornnet/issues/23 |
| #24 | **Operations guide to enable assessment of the Q1 2026 PoC** | https://github.com/OS2sandbox/nornnet/issues/24 |

### User Stories & Use Cases

| Issue # | Title | Link |
|---------|-------|------|
| #25 | User-story: Citizen usage | https://github.com/OS2sandbox/nornnet/issues/25 |
| #26 | Proposal: Strengthening Privacy Baseline with Browser Policies | https://github.com/OS2sandbox/nornnet/issues/26 |

### Infrastructure & Collaboration

| Issue # | Title | Link |
|---------|-------|------|
| #18 | Invite more collaborators | https://github.com/OS2sandbox/nornnet/issues/18 |
| #19 | Find and prepare hardware clients for the PoC | https://github.com/OS2sandbox/nornnet/issues/19 |

---

## Closed Issues (Historical Context)

| Issue # | Title | Link |
|---------|-------|------|
| #2 | Describe an architecture for a management framework | https://github.com/OS2sandbox/nornnet/issues/2 |
| #16 | Research strategic fit of immutable distros and management technologies | https://github.com/OS2sandbox/nornnet/issues/16 |
| #20 | Evaluate FleetDM as a potential platform | https://github.com/OS2sandbox/nornnet/issues/20 |
| #21 | Create a Q4 2025 solution landscape proposal | https://github.com/OS2sandbox/nornnet/issues/21 |

---

## Jan's Architecture & Design Documents

> **Jan Maack Kjerbye (@janhalen)** is the primary architect and project lead.

### Enterprise Architecture Proposals

| Document | Link |
|----------|------|
| **Device Management Architecture Proposal (Aug 2025)** | https://janhalen.github.io/enterprise-architecture-patterns/proposals/24-08-2025-device-management.html |
| Enterprise Architecture Patterns Blog | https://janhalen.github.io/enterprise-architecture-patterns/ |

### Jan's GitHub Profile

| Resource | Link |
|----------|------|
| GitHub Profile | https://github.com/janhalen |

---

## Referenced External Resources

### Bootable Containers (bootc) & OStree

| Resource | Link |
|----------|------|
| OStree Introduction | https://ostreedev.github.io/ostree/introduction/ |
| bootc: Getting Started (YouTube Video by Valentin Rothberg) | https://www.youtube.com/watch?v=bf1xqjLeA9M |
| bootc: GitOps for Noobs (YouTube Video - Recommended by Jan) | https://www.youtube.com/watch?v=5ZN_7NDvavY |

### Observability & Telemetry

| Resource | Link |
|----------|------|
| OpenTelemetry (OTEL) | https://opentelemetry.io/ |
| OpenObserve | https://github.com/openobserve/openobserve |

### Administration & Automation

| Resource | Link |
|----------|------|
| Ansible Getting Started | https://www.ansible.com/resources/get-started |
| Ansible Semaphore (Modern UI) | https://docs.ansible-semaphore.com/ |
| Semaphore Docker Setup Guide | https://computingforgeeks.com/run-semaphore-ansible-in-docker/ |

### Browser Security Policies

| Resource | Link |
|----------|------|
| Mozilla Policy Templates | https://mozilla.github.io/policy-templates/ |
| LibreWolf Browser | https://librewolf.net/ |
| Firefox Admin Documentation | https://firefox-admin-docs.mozilla.org/reference/policies/ |

### Build Tools (Referenced but Not Adopted)

| Resource | Link |
|----------|------|
| blue-build | https://blue-build.org/ |
| eu-os/workspace-images (GitLab) | https://gitlab.com/eu-os/workspace-images/eu-os-base-demo |

### Raspberry Pi Image Building

| Resource | Link |
|----------|------|
| pi-ci Project | https://github.com/ptrsr/pi-ci |

### Hardware References

| Resource | Link |
|----------|------|
| Apple DFU Restore Guide | https://support.apple.com/en-us/108900 |

---

## Related Repositories

| Repository | Description | Link |
|------------|-------------|------|
| nornnet | Main project repository | https://github.com/OS2sandbox/nornnet |
| OS2produktmodning | OS2 product documentation | https://github.com/ChatBotBerg/OS2produktmodning |

---

## Key Concepts (From README)

The Nornnet project is based on five core principles:

1. **Git as Single Source of Truth** - Fleet state version-controlled in Git via Pull Requests
2. **Secure, Standardized OS Images** - OS delivered as immutable OCI images
3. **Minimized Attack Surface** - "Pull" model for updates, no inbound management ports
4. **Robust Atomic Updates** - Transactional updates with automatic rollback
5. **Native Lifecycle Management** - Using systemd instead of third-party agents

---

## Technologies in Scope

- **bootc** - Bootable containers
- **systemd** - Native Linux service manager
- **quadlets** - systemd container management
- **podman** - Container runtime
- **OCI Images** - Container image standard
- **OpenGitOps** - GitOps methodology
- **OTEL** - OpenTelemetry for observability

---

*Last updated: 2026-03-24*
