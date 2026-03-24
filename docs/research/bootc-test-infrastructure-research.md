# Research Report: Test Environment Infrastructure for bootc-based Systems

**Project:** nornnet  
**Date:** 2026-03-24  
**Objective:** Discover MULTIPLE solutions for creating and managing test environments to validate bootc images, deployments, and updates

---

## Executive Summary

This research identifies **7 distinct solution categories** for bootc test environment infrastructure, ranging from lightweight container-based testing to full VM simulation with KVM/libvirt. The optimal approach combines multiple tiers based on testing depth requirements.

---

## 1. Solution Categories Discovered

### 1.1 Container-Based Testing (Podman)

| Tool | Purpose | Complexity |
|------|---------|------------|
| `podman-bootc` | Run bootc images via podman | Low |
| `bootc container lint` | Validate image compliance | Low |
| `podman run` (native) | Quick container validation | Low |

**Key Finding:** The `bootc-dev/podman-bootc` project (66⭐) enables running bootc images directly via podman for quick development iteration. Combined with `bootc container lint --fatal-warnings`, this provides fast pre-deployment validation.

### 1.2 VM-Based Testing (bcvk)

| Tool | Purpose | Complexity |
|------|---------|------------|
| `bcvk` (bootc-dev/bcvk) | VM testing CLI for bootc | Medium |
| `bcvk libvirt run` | Run in libvirt VMs | Medium |
| `bcvk to-disk` | Convert to disk images | Medium |

**Key Finding:** `bcvk` (80⭐) is the Rust-based official VM testing tool for bootc images, supporting UEFI secure boot, virtiofs, direct kernel boot, and SSH access to booted VMs.

### 1.3 Libvirt/KVM Integration

| Tool | Purpose | Complexity |
|------|---------|------------|
| `virt-install` | CLI VM provisioning | Medium |
| `libvirt` | VM lifecycle management | Medium |
| `autotest/tp-libvirt` | Enterprise testing framework | High |

**Key Finding:** The `autotest/tp-libvirt` test provider provides enterprise-grade automated testing infrastructure used by Red Hat, with `bootc_image_build_utils.py` for image conversion.

### 1.4 CI/CD Pipeline Integration

| Approach | Tools | Complexity |
|----------|-------|------------|
| GitHub Actions | `redhat-actions/buildah-build`, `push-to-registry` | Medium |
| Matrix builds | Parallel distro/arch testing | Low |
| Ephemeral VMs | `bootc-integration-test-action` | Medium |

**Key Finding:** The `secureblue/bootc-integration-test-action` (7⭐) provides automated integration tests for bootc images in ephemeral VMs within GitHub Actions.

### 1.5 Infrastructure Testing Frameworks

| Framework | Language | Strengths |
|-----------|----------|-----------|
| **Terratest** | Go | Infrastructure-as-code testing, SSH access |
| **BATS** | Bash | Simple shell script testing |
| **Testinfra** | Python | pytest integration |
| **Chef InSpec** | Ruby | Compliance/profiles |

**Key Finding:** Terratest (7.9k⭐) and BATS (5.9k⭐) are the most actively maintained options for infrastructure testing.

### 1.6 Ansible-Based Automation

| Project | Purpose |
|---------|---------|
| `arthur-r-oliveira/bootc-embedded-containers` | `ansible/roles/bootc_vm_testing/` role |
| `kayrus/deploy-vm` | Cloud image to VM deployment |

**Key Finding:** Infrastructure-as-Code approach using Ansible roles for repeatable VM provisioning and testing.

### 1.7 Automated Testing Frameworks

| Framework | Purpose |
|-----------|---------|
| `titanoboa` (ublue-os) | Automated bootc image testing with Anaconda |
| `flightctl` | VM-based fleet management |

---

## 2. Evaluation Matrix

| Solution | Setup Complexity | VM Simulation | Boot Chain | CI/CD Ready | Cost | Scalability |
|----------|------------------|---------------|------------|-------------|------|-------------|
| **podman-bootc** | ⭐ Low | ❌ Container only | ❌ No | ✅ Yes | Free | High |
| **bcvk** | ⭐⭐ Medium | ✅ Full VM | ✅ Yes | ✅ Yes | Free | Medium |
| **libvirt + virt-install** | ⭐⭐⭐ Medium-High | ✅ Full VM | ✅ Yes | ⚠️ Manual | Free | Low |
| **autotest/tp-libvirt** | ⭐⭐⭐⭐ High | ✅ Full VM | ✅ Yes | ✅ Yes | Free | High |
| **GitHub Actions + VM** | ⭐⭐⭐ Medium | ✅ Nested Virt | ✅ Yes | ✅ Yes | $ | Medium |
| **Terratest** | ⭐⭐⭐ Medium | ✅ Via SSH | ✅ Yes | ✅ Yes | Free | High |
| **Ansible Playbooks** | ⭐⭐⭐ Medium | ✅ Via libvirt | ✅ Yes | ✅ Yes | Free | High |

---

## 3. Recommendations

### 3.1 Tiered Testing Strategy (Recommended)

Based on the project context (bootc, podman, systemd, quadlets), the recommended approach is a **tiered testing pyramid**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Testing Pyramid                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                         ▲                                        │
│                        /█\     Tier 4: VM Integration Tests      │
│                       /███\    (bcvk + libvirt + Terratest)      │
│                      /█████\                                      │
│                     /███████\   Tier 3: Boot Chain Tests         │
│                    /█████████\  (bcvk + cloud-init)               │
│                   /███████████\                                   │
│                  /█████████████\  Tier 2: Container Validation    │
│                 /███████████████\ (bootc container lint)          │
│                /█████████████████\                                │
│               /███████████████████\ Tier 1: Unit Tests            │
│              /█████████████████████\ (bats, pytest)              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Specific Tool Recommendations

| Test Type | Primary Tool | Rationale |
|-----------|--------------|-----------|
| **Image linting** | `bootc container lint --fatal-warnings` | Built-in, fast, catches common issues |
| **Container validation** | `podman run --privileged` | Quick iteration, no VM overhead |
| **Unit tests** | BATS | Simple, TAP output, shell script testing |
| **VM provisioning** | `bcvk` | Official Rust tool, active development |
| **VM orchestration** | `libvirt` + `virt-install` | Industry standard, flexible |
| **Infrastructure testing** | Terratest (Go) or BATS | SSH access, retry mechanisms |
| **CI/CD integration** | GitHub Actions + `bootc-integration-test-action` | Ephemeral VMs, matrix builds |

### 3.3 GitHub Actions Pipeline Design

```yaml
name: bootc test pipeline

on: [push, pull_request]

jobs:
  # Tier 1: Fast unit tests
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Lint Containerfile
        run: hadolint Containerfile

  # Tier 2: Container validation
  container-test:
    runs-on: ubuntu-latest
    steps:
      - name: Build image
        uses: redhat-actions/buildah-build@v2
        with:
          image: nornnet-test
          tags: ${{ github.sha }}
      
      - name: Run bootc lint
        run: |
          podman run --rm ${{ steps.build.outputs.image }} bootc container lint --fatal-warnings

  # Tier 3: VM boot chain tests
  vm-test:
    needs: container-test
    runs-on: self-hosted  # For nested KVM
    steps:
      - name: Convert to disk
        run: bcvk to-disk --output nornnet.qcow2
      
      - name: Boot VM
        run: bcvk libvirt run --name nornnet-test
      
      - name: Run SSH tests
        run: |
          sleep 30  # Wait for boot
          sshpass -p 'test' ssh -o StrictHostKeyChecking=no \
            test@$VM_IP "systemctl is-active podman.socket"

  # Tier 4: Integration tests
  integration:
    needs: vm-test
    runs-on: self-hosted
    steps:
      - name: Run Terratest suite
        run: |
          go test -v ./tests/... \
            -timeout 30m \
            -retry-count 3
```

---

## 4. Trade-offs and Risks

### 4.1 Podman-Only Testing

| Trade-off | Risk |
|-----------|------|
| ✅ Fast feedback loop | ❌ Missing boot chain validation |
| ✅ No VM overhead | ❌ SELinux context differs |
| ✅ Easy CI integration | ❌ No systemd boot sequence |
| ❌ No GRUB/UEFI testing | ⚠️ Insufficient for production validation |

**Mitigation:** Use podman testing for TDD fast feedback, but always follow with VM tests before production.

### 4.2 VM Testing Complexity

| Trade-off | Risk |
|-----------|------|
| ✅ Full boot chain simulation | ❌ Slower execution (30-60s boot) |
| ✅ Real SELinux/bootloader | ❌ Higher resource requirements |
| ✅ Hardware driver testing | ❌ More complex CI infrastructure |
| ❌ Self-hosted runners needed | ⚠️ GitHub-hosted lacks nested virt |

**Mitigation:** Use `bcvk` for simplified VM testing; self-hosted runners for CI.

### 4.3 Framework Selection

| Framework | Trade-off |
|-----------|-----------|
| **Terratest** | ✅ Feature-rich | ❌ Requires Go expertise |
| **BATS** | ✅ Simple | ❌ Limited advanced features |
| **Testinfra** | ✅ Python integration | ❌ Additional dependencies |
| **InSpec** | ✅ Compliance profiles | ❌ Ruby overhead |

**Mitigation:** Match framework to team expertise; BATS is simplest for shell scripts.

---

## 5. Fit Score with Project Context

| Context Requirement | Fit Score | Notes |
|---------------------|-----------|-------|
| **TDD (test-first)** | ⭐⭐⭐⭐⭐ | Podman enables fast TDD cycles |
| **All tests pass before completion** | ⭐⭐⭐⭐⭐ | CI/CD pipeline enforces this |
| **bootc technology** | ⭐⭐⭐⭐⭐ | `bootc container lint`, `bcvk` are purpose-built |
| **podman technology** | ⭐⭐⭐⭐⭐ | Podman-native testing tools available |
| **VM technology** | ⭐⭐⭐⭐⭐ | bcvk, libvirt provide VM testing |
| **Local Build Testing** | ⭐⭐⭐⭐⭐ | `bcvk to-disk` + `bcvk libvirt run` |
| **Registry Integration** | ⭐⭐⭐⭐ | `redhat-actions/push-to-registry` in Actions |
| **Update Propagation** | ⭐⭐⭐ | Requires full VM for ostree rollback testing |
| **Rollback Testing** | ⭐⭐⭐ | Full VM required |
| **Failure Scenarios** | ⭐⭐⭐⭐ | Terratest retry/assert patterns |
| **Concurrency Testing** | ⭐⭐ | Requires multi-VM setup |

### Overall Fit: **4.2/5**

The bootc ecosystem has mature testing tools, but concurrency/multi-host testing requires additional infrastructure.

---

## 6. Implementation Recommendations

### Phase 1: Foundation (Week 1)
1. Add `bootc container lint` to CI pipeline
2. Create BATS test suite for shell scripts
3. Set up `bcvk` locally for manual testing

### Phase 2: VM Automation (Week 2)
1. Configure self-hosted runners with KVM
2. Add `bcvk to-disk` + `bcvk libvirt run` to CI
3. Create basic VM boot tests

### Phase 3: Integration (Week 3-4)
1. Integrate Terratest for infrastructure testing
2. Add update/rollback scenario tests
3. Implement failure injection tests

### Phase 4: Scale (Ongoing)
1. Add matrix builds for multi-distro testing
2. Implement concurrent VM tests for race conditions
3. Add hardware-in-the-loop testing if needed

---

## 7. Key References

| Resource | URL |
|----------|-----|
| Main bootc project | https://github.com/bootc-dev/bootc |
| bcvk (VM testing) | https://github.com/bootc-dev/bcvk |
| podman-bootc | https://github.com/bootc-dev/podman-bootc |
| bootc-integration-test-action | https://github.com/secureblue/bootc-integration-test-action |
| autotest/tp-libvirt | https://github.com/autotest/tp-libvirt |
| Terratest | https://github.com/gruntwork-io/terratest |
| BATS | https://github.com/bats-core/bats-core |
| workflow-bootc examples | https://github.com/mrguitar/workflow-bootc |

---

## 8. Conclusion

The bootc ecosystem provides **sufficient testing infrastructure** for the project's needs. The recommended approach is:

1. **Use `bootc container lint` for fast pre-commit validation**
2. **Use `bcvk` + libvirt for VM boot chain testing**
3. **Use BATS/Terratest for infrastructure validation**
4. **Use GitHub Actions with self-hosted runners for CI**

This tiered approach balances speed (TDD fast feedback) with thoroughness (full boot chain validation) while remaining compatible with the project's technology stack (bootc, podman, systemd, quadlets).
