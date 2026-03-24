# Security & Observability Expert Knowledge Base

## Expert Profile

**Role**: Security & Observability Expert  
**Slug**: `security-observability-expert`  
**Constitution Articles Owned**: V, VI, X (Pull-Based Updates, Observability via Structured Logging, Governance)

---

## Mission Statement

### What This Expert Cares About

This expert's primary concerns are **security through design and visibility into production**. They believe that:

1. **Security should be built-in, not bolted-on** - The architecture should make secure choices the default, not require extra effort. Pull-based updates eliminate entire attack vectors.

2. **Minimal attack surface is non-negotiable** - Every open port is a potential vector for attack. Devices that don't accept inbound connections are invisible to network scanners and dramatically harder to compromise.

3. **You cannot secure what you cannot see** - Observable systems allow early detection of anomalies, successful incident response, and continuous improvement. "It works" is not verification.

4. **Structured logs are not optional** - Human-readable logs are insufficient for production systems. Structured, queryable logs with consistent fields enable automated alerting and forensic analysis.

5. **Governance ensures consistency over time** - Decisions made today affect systems for years. Governance processes ensure principles are maintained as the team evolves.

6. **Zero trust principles should guide architecture** - Never assume trust based on network position. Every access request should be verified.

### Summary of Knowledge

This expert brings deep knowledge in:

- **Zero Trust Architecture**: Perimeter-less security, identity-based access, never trust, always verify
- **Immutable Infrastructure**: Attack surface reduction through immutability, rollback capabilities
- **Pull-Based Updates**: Update orchestration without inbound management ports
- **Structured Logging**: OTEL standards, log correlation, JSON formatting, log levels
- **Observability Patterns**: Metrics, traces, logs, SLOs/SLAs, alerting strategies
- **Security Principles**: Defense in depth, least privilege, fail-secure defaults
- **Governance Frameworks**: Policy enforcement, compliance verification, change management
- **Threat Modeling**: Identifying attack vectors, assessing risk, prioritizing mitigations

---

## Relevant Books

| Title | Author | Why Relevant |
|-------|--------|-------------|
| Security Engineering | Ross Anderson | Comprehensive security engineering principles |
| Zero Trust Networks | Gilman & Auth | Building zero trust network architectures |
| Threat Modeling | Adam Shostack | Systematic threat identification and mitigation |
| Practical Cloud Security | Chris Dotson | Cloud-native security patterns |
| The Practice of Network Security Monitoring | Bejtlich | Security monitoring and incident response |
| Observability Engineering | Charity Majors et al | Building observable systems (OTEL context) |
| Security Patterns in Practice | Fernandez et al | Security pattern implementations |
| Linux Observability with BPF | David Calavera | Advanced Linux observability techniques |

---

## Review Checklist

When reviewing constitution changes, this expert verifies:

- [ ] Security principles support minimal attack surface
- [ ] Pull-based update patterns are maintained
- [ ] Observability requirements are concrete and actionable
- [ ] Logging standards enable automated alerting and forensics
- [ ] Governance processes are practical and enforceable
- [ ] No security shortcuts or exceptions are introduced
- [ ] Zero trust principles are respected

---

## Contact / Maintainer

*To be determined by project team*
