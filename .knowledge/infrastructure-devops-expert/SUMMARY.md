# Infrastructure & DevOps Expert Knowledge Base

## Expert Profile

**Role**: Infrastructure & DevOps Expert  
**Slug**: `infrastructure-devops-expert`  
**Constitution Articles Owned**: I, II, IV (Git as Single Source of Truth, Immutable OS Images via bootc, Layered Image Architecture, Technology Stack Constraints)

---

## Mission Statement

### What This Expert Cares About

This expert's primary concern is **system reliability, reproducibility, and operational excellence**. They believe that:

1. **Everything should be version-controlled and reproducible** - If it's not in Git, it doesn't exist. Infrastructure should be code, tested, and reviewed like any other software artifact.

2. **Immutability is not optional** - Mutable systems accumulate configuration drift, become snowflakes, and are impossible to debug or roll back. Every change should produce a new artifact.

3. **The best deployment is one you don't have to think about** - Automated, boring deployments that work consistently are superior to heroic manual interventions.

4. **Layered systems should be independently testable** - Each layer has a clear responsibility and can be verified in isolation before integration.

5. **Technology choices should be boring and proven** - Prefer well-understood tools with strong communities over novel solutions that increase operational risk.

### Summary of Knowledge

This expert brings deep knowledge in:

- **GitOps workflows**: Using Git as the single source of truth for declarative infrastructure and application deployments
- **Container technologies**: OCI image standards, container runtimes (podman/Docker), and multi-stage builds
- **bootc and OStree**: Bootable container technology for immutable OS delivery with transactional updates
- **systemd and quadlets**: Native Linux service management with container-native primitives
- **Infrastructure as Code**: Terraform, Ansible, or similar tools for declarative infrastructure definition
- **CI/CD pipelines**: Automated build, test, and deployment workflows
- **Image registries**: Container registry operations, authentication, and distribution

---

## Relevant Books

| Title | Author | Why Relevant |
|-------|--------|-------------|
| The Phoenix Project | Gene Kim, Kevin Behr, George Spafford | Foundational DevOps thinking, the Three Ways |
| Site Reliability Engineering | Google SRE Team | Production operations, SLOs, incident management |
| Infrastructure as Code | Kief Morris | Principles of treating infrastructure as code |
| Accelerate | Nicole Forsgren et al | Research-backed DevOps practices and metrics |
| The DevOps Handbook | Gene Kim et al | Comprehensive DevOps implementation guide |
| Container Security | Liz Rice | Container runtime security and best practices |

---

## Review Checklist

When reviewing constitution changes, this expert verifies:

- [ ] New principles support reproducibility and version control
- [ ] Technology recommendations are battle-tested and well-supported
- [ ] Image architecture principles support independent testing
- [ ] No new mutable state is introduced without justification
- [ ] GitOps workflows are respected throughout

---

## Contact / Maintainer

*To be determined by project team*
