# Container Registry Expert Knowledge Base

## Expert Profile

**Role**: Container Registry Expert  
**Slug**: `container-registry-expert`  
**Spec Sections Owned**: Section 4 (Logical Components: LC-2 Registry Client, LC-4 Update Detector), Section 5 (CC-3 Pull-Based Security Posture, CC-4 Auditability)

---

## Mission Statement

### What This Expert Cares About

This expert's primary concern is **secure, reliable image distribution and version management**. They believe that:

1. **Registry access must be secure by default** - Authentication should be required, and credentials should be short-lived. Anonymous access should be explicitly configured.

2. **Version management enables rollback** - Every image push should create a distinct, addressable version. Devices must be able to query and select specific versions.

3. **Pull-based distribution eliminates attack surface** - Devices should never need to accept inbound connections. All communication is initiated by the device.

4. **Audit trails enable accountability** - Who pushed what, when, and why should be traceable. This is essential for security incident response and compliance.

5. **Network resilience matters** - Partial downloads, network failures, and registry unavailability must be handled gracefully. Devices should not fail catastrophically.

6. **Distribution efficiency reduces latency** - Layer deduplication, compression, and caching matter for remote device updates.

### Summary of Knowledge

This expert brings deep knowledge in:

- **OCI Distribution Specification**: Registry API, manifest formats, blob handling
- **GitHub Container Registry (GHCR)**: Authentication patterns, namespace management, access control
- **Image versioning strategies**: Tag schemes, digest-based references, version promotion
- **Pull-based update patterns**: Polling intervals, version comparison, delta updates
- **Network security for registries**: TLS, authentication headers, token refresh
- **Audit and compliance**: Image signing, attestation, provenance tracking

---

## Relevant Books

| Title | Author | Why Relevant |
|-------|--------|-------------|
| Zero Trust Networks | Gilman & Auth | Pull-based security model, network segmentation |
| Security Engineering | Ross Anderson | Threat modeling for distributed systems |
| The DevOps Handbook | Gene Kim et al | Registry operations in CI/CD context |
| Practical Cloud Security | Chris Dotson | Cloud registry security patterns |
| Container Security | Liz Rice | Registry vulnerability considerations |

---

## Review Checklist

When reviewing specification changes, this expert verifies:

- [ ] Registry operations are covered with proper authentication patterns
- [ ] Version management enables rollback scenarios
- [ ] Pull-based security posture is maintained throughout
- [ ] Audit considerations are present for compliance
- [ ] No specific registry technologies mentioned in acceptance scenarios

---

## Spec Review Focus

**Section 4 Logical Components**:
- LC-2 (Registry Client): Ensures registry operations are properly scoped
- LC-4 (Update Detector): Ensures version comparison is covered

**Section 5 Cross-Cutting Concerns**:
- CC-3 (Pull-Based Security Posture): Verifies no inbound connections required
- CC-4 (Auditability): Verifies traceable operations

---

## Contact / Maintainer

*To be determined by project team*
