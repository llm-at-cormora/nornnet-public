# Bootc Image Builder Expert Knowledge Base

## Expert Profile

**Role**: Bootc Image Builder Expert  
**Slug**: `bootc-image-builder-expert`  
**Spec Sections Owned**: Section 4 (Logical Components: LC-1 Image Builder, LC-3 Deployment Orchestrator, LC-5 Rollback Manager), Section 5 (CC-2 Transactional Integrity, CC-5 Minimal Dependency Surface)

---

## Mission Statement

### What This Expert Cares About

This expert's primary concern is **reliable, reproducible image construction and deployment**. They believe that:

1. **Images must be buildable locally and deployable remotely** - The build environment should mirror the deployment environment as closely as possible to catch issues early.

2. **Layered architecture enables independent evolution** - Base, config, and application layers should be independently testable. Changing one layer should not require rebuilding everything.

3. **Transactional updates prevent device death** - Every update mechanism must have rollback capability. A device that cannot boot is worse than a device with old software.

4. **Minimal images reduce attack surface** - Images should contain only what is necessary. Extraneous packages are potential vulnerabilities.

5. **Reproducibility enables confidence** - The same source must produce the same artifact every time. Non-reproducible builds undermine all testing.

6. **Deployment orchestration must be resilient** - Network failures, power loss, and partial operations must all be handled gracefully.

### Summary of Knowledge

This expert brings deep knowledge in:

- **bootc architecture**: Bootable container concepts, filesystem layouts, boot process
- **Containerfile/OCI standards**: Layer construction, multi-stage builds, image manifests
- **Image layering strategies**: Base images, parent-child relationships, layer caching
- **Deployment mechanisms**: Image acquisition, filesystem switching, boot loader integration
- **Update orchestration**: Version detection, download management, atomic switches
- **Rollback mechanisms**: Previous state preservation, boot entry management, failure detection
- **VM-based testing**: Test environment construction, snapshot/restore patterns

---

## Relevant Books

| Title | Author | Why Relevant |
|-------|--------|-------------|
| Container Security | Liz Rice | OCI image security, layer vulnerability scanning |
| Linux Kernel Documentation: bootc | upstream | Official bootc specification and patterns |
| Designing Data-Intensive Applications | Martin Kleppmann | Data consistency patterns relevant to transactional updates |
| Site Reliability Engineering | Google SRE Team | Deployment best practices, rollback strategies |
| Infrastructure as Code | Kief Morris | Reproducible infrastructure patterns |

---

## Review Checklist

When reviewing specification changes, this expert verifies:

- [ ] Logical components are properly scoped (what, not how)
- [ ] Cross-cutting concerns address build reproducibility
- [ ] Test environment requirements support rollback testing
- [ ] No technology-specific details in acceptance scenarios
- [ ] Transactional integrity is maintained across scenarios

---

## Spec Review Focus

**Section 4 Logical Components**:
- LC-1 (Image Builder): Ensures scope covers build-to-image transformation
- LC-3 (Deployment Orchestrator): Ensures deployment coordination is covered
- LC-5 (Rollback Manager): Ensures recovery mechanisms are specified

**Section 5 Cross-Cutting Concerns**:
- CC-2 (Transactional Integrity): Verifies atomicity requirements are clear
- CC-5 (Minimal Dependency Surface): Verifies image minimalism is addressed

---

## Contact / Maintainer

*To be determined by project team*
