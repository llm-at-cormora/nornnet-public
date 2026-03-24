# Research Report: Registry Authentication & Operations for GitHub Container Registry (GHCR)

**Project**: Nornnet PoC - Bootable Container Device Management  
**Research Phase**: IDEATE - Problem Domain Exploration  
**Date**: 2026-03-24  
**Status**: COMPLETED

---

## Executive Summary

This report presents multiple solutions for authenticating with and performing operations on GitHub Container Registry (GHCR) using podman, aligned with the Nornnet project's pull-based security posture and auditability requirements. Five distinct approaches have been identified, ranging from simple CLI-based authentication to programmatic API access with full audit capabilities.

---

## 1. Problem Context

### 1.1 Project Constraints (from Constitution)

| Constraint | Requirement |
|------------|-------------|
| Container Runtime | podman (daemonless, rootless) |
| Image Registry | GitHub Container Registry (GHCR) |
| Security Model | Pull-based (CC-3: No inbound management ports) |
| Auditability | CC-4: All operations must be auditable |
| Technology Stack | Standard: bootc, systemd, quadlets |

### 1.2 User Stories & Acceptance Criteria

**User Story 2: Registry Authentication**
> As the system, I need to authenticate with the container registry so that I can access images.

**User Story 3: Image Registry Operations**
> As the system, I need to perform image registry operations (pull, inspect, list) so that I can manage container images.

### 1.3 Key Considerations for Pull-Based Model

- Devices must authenticate *outbound* to pull images
- No server-side push operations required (security advantage)
- Token lifecycle management critical for long-running devices
- Audit logs must capture authentication events

---

## 2. Solutions Discovered

### Solution 1: Personal Access Token (PAT) via Podman Login

**Approach**: Use GitHub Personal Access Tokens with `podman login` for credential management.

#### Authentication Flow
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Device    │────▶│   Podman     │────▶│   GHCR      │
│  (systemd)  │     │   auth.json │     │  (ghcr.io)  │
└─────────────┘     └──────────────┘     └─────────────┘
       │                   │
       │ 1. Service starts │
       │ 2. Login with PAT │
       │ 3. Credentials    │
       │    stored in      │
       │    auth.json      │
       └───────────────────┘
```

#### Implementation Examples

**Interactive Login:**
```bash
podman login ghcr.io -u <GITHUB_USERNAME>
# Enter PAT when prompted
```

**Non-Interactive (CI/Automation):**
```bash
export GHCR_TOKEN=<your_pat_token>
echo "$GHCR_TOKEN" | podman login ghcr.io -u <GITHUB_USERNAME> --password-stdin
```

**GitHub Actions Integration:**
```yaml
- name: Login to GHCR
  run: |
    echo "${{ secrets.GITHUB_TOKEN }}" | \
    podman login ghcr.io -u ${{ github.actor }} --password-stdin
```

#### Token Scopes Required

| Scope | Purpose | Use Case |
|-------|---------|----------|
| `read:packages` | Pull images, read metadata | Pull-only operations |
| `write:packages` | Push images, write metadata | Push operations |
| `delete:packages` | Delete images/blobs | Cleanup operations |

#### Pros
- ✅ Simple, well-documented approach
- ✅ Native podman integration
- ✅ Supports `--password-stdin` for non-interactive use
- ✅ Credentials stored in `~/.config/containers/auth.json`
- ✅ Works with both PAT classic and fine-grained PATs

#### Cons
- ❌ PATs are long-lived credentials (security risk)
- ❌ Token expiration requires manual renewal
- ❌ PAT scope applies to entire GitHub account (classic PAT)
- ❌ Fine-grained PATs have limited GHCR support (as of 2024)
- ❌ Credential rotation requires re-login

#### Fit Score: **7/10**
Best for: Development, CI/CD pipelines, single-device deployments

---

### Solution 2: GITHUB_TOKEN via GitHub Actions

**Approach**: Use GitHub's built-in `GITHUB_TOKEN` for authentication within GitHub Actions workflows.

#### Authentication Flow
```
┌──────────────────────────────────────────────┐
│           GitHub Actions Runner               │
│  ┌────────────┐    ┌────────────┐           │
│  │  Workflow  │───▶│ GITHUB_    │           │
│  │  Step      │    │ TOKEN      │           │
│  └────────────┘    └─────┬──────┘           │
│                          │                   │
│                   ┌──────▼──────┐           │
│                   │   GHCR      │           │
│                   │  (ghcr.io)  │           │
│                   └─────────────┘           │
└──────────────────────────────────────────────┘
```

#### Implementation
```yaml
name: Build and Push Image
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      packages: write
      contents: read
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push
        run: |
          podman build -t ghcr.io/${{ github.repository }}:latest .
          podman push ghcr.io/${{ github.repository }}:latest
```

#### Key Features
- **Short-lived**: Token expires after workflow completion
- **Automatic**: No manual token management
- **Audit-friendly**: All actions tied to GitHub user/workflow
- **Granular permissions**: Via `permissions` key in workflow

#### GitHub-Specific Considerations

**Container Registry Settings:**
```
Repository Settings → Codespaces and Actions → 
  Container registry → Enable improved container support
```

**Workflow Permissions:**
```yaml
permissions:
  packages: write    # For push operations
  contents: read     # Standard for checkout
```

#### Pros
- ✅ Short-lived credentials (security best practice)
- ✅ No manual token management
- ✅ Automatically scoped to workflow permissions
- ✅ Full audit trail via GitHub
- ✅ GitHub recommends this over PATs

#### Cons
- ❌ Only available within GitHub Actions
- ❌ Requires GitHub repository context
- ❌ Not suitable for standalone devices
- ❌ Cannot be used from on-premises runners without VPN

#### Fit Score: **8/10**
Best for: CI/CD pipelines, GitHub Actions-based workflows

---

### Solution 3: GitHub App Installation Token

**Approach**: Use GitHub App for authentication with scoped permissions independent of user accounts.

#### Authentication Flow
```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│   Device    │────▶│  GitHub App  │────▶│   GHCR Token    │
│             │     │  (Installed)  │     │   Exchange      │
└─────────────┘     └──────────────┘     └────────┬────────┘
                                                    │
                                             ┌──────▼──────┐
                                             │   GHCR      │
                                             │  (ghcr.io)  │
                                             └─────────────┘
```

#### Implementation

**Step 1: Create GitHub App**
- Go to: GitHub Settings → Developer Settings → GitHub Apps
- Set permissions: `packages: read` / `packages: write`
- Enable repository access for specific repos

**Step 2: Generate Installation Token**
```bash
# Get installation ID
INSTALL_ID=$(curl -s \
  -H "Authorization: Bearer $GITHUB_APP_TOKEN" \
  https://api.github.com/app/installations | \
  jq '.[0].id')

# Generate installation access token
INSTALLATION_TOKEN=$(curl -s \
  -X POST \
  -H "Authorization: Bearer $GITHUB_APP_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations/$INSTALL_ID/access_tokens | \
  jq -r '.token')
```

**Step 3: Login to GHCR**
```bash
echo "$INSTALLATION_TOKEN" | podman login ghcr.io -u <github-app-name> --password-stdin
```

#### Key Features
- **User-independent**: Not tied to individual user accounts
- **Scoped permissions**: Granular access control
- **Installation-based**: Works across organization repos
- **Revocable**: Can revoke app installation without affecting users

#### Pros
- ✅ Independent of individual user accounts
- ✅ Fine-grained repository permissions
- ✅ Can be installed organization-wide
- ✅ Single point of management
- ✅ Better audit trail (app-based, not user-based)

#### Cons
- ❌ More complex setup than PATs
- ❌ Token generation requires API calls
- ❌ Installation token expires (typically 1 hour)
- ❌ Requires token refresh logic for long-running operations
- ❌ App must be created and maintained

#### Fit Score: **7/10**
Best for: Organization-level automation, multi-repository access, production deployments

---

### Solution 4: Raw Registry API (Docker Distribution HTTP API v2)

**Approach**: Directly interact with the Docker Registry HTTP API v2 for full programmatic control.

#### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v2/` | GET | API version check |
| `/v2/<name>/blobs/<digest>` | GET/HEAD | Download blob |
| `/v2/<name>/manifests/<ref>` | GET/PUT | Get/push manifest |
| `/v2/<name>/tags/list` | GET | List tags |
| `/token?service=ghcr.io&scope=...` | GET | Get Bearer token |

#### Authentication Protocol

**Step 1: Get Bearer Token**
```bash
# Request anonymous token for public images
curl -s "https://ghcr.io/token?service=ghcr.io&scope=repository:owner/image:pull"

# Response
{"token": "eyJ...", "access_token": "...", "expires_in": 300}
```

**Step 2: Use Token for API Calls**
```bash
# Get image manifest
curl -s \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  https://ghcr.io/v2/owner/image/manifests/latest
```

**Full Authentication with PAT:**
```bash
# Encode credentials for Basic auth
CREDENTIALS=$(echo -n "username:PAT_TOKEN" | base64)

# Get Bearer token
TOKEN=$(curl -s \
  -H "Authorization: Basic $CREDENTIALS" \
  "https://ghcr.io/token?service=ghcr.io&scope=repository:owner/image:pull" | \
  jq -r '.token')

# Use token for registry operations
curl -s \
  -H "Authorization: Bearer $TOKEN" \
  https://ghcr.io/v2/owner/image/manifests/latest
```

#### Pros
- ✅ Full programmatic control
- ✅ Works without podman CLI
- ✅ Supports all registry operations
- ✅ Can implement custom caching/retry logic
- ✅ Lightweight for simple operations

#### Cons
- ❌ Requires implementing HTTP API handling
- ❌ Token lifecycle management is manual
- ❌ No built-in credential storage
- ❌ Higher complexity for error handling
- ❌ Must handle rate limiting manually

#### Fit Score: **6/10**
Best for: Custom tooling, embedded systems, specific protocol requirements

---

### Solution 5: Credential Helpers & Secrets Management

**Approach**: Use podman credential helpers or external secrets management for secure credential handling.

#### 5a. Podman Credential Helpers

**OCI Secret Service:**
```bash
# Store credentials in systemd secret service
export REGISTRY_AUTH_FILE=/run/containers/secrets/auth.json

# Login stores credentials securely
podman login ghcr.io -u $GITHUB_USER --authfile $REGISTRY_AUTH_FILE
```

**Keyring Integration:**
```bash
# Use libsecret (GNOME Keyring)
dnf install libsecret

# Configure podman to use keyring
mkdir -p ~/.config/containers
cat > ~/.config/containers/registries.conf <<EOF
[registries.search]
registries = ['docker.io', 'quay.io', 'ghcr.io']
EOF

# Store credential
echo "$PAT" | podman login ghcr.io -u $USER --authfile ~/.config/containers/auth.json
```

#### 5b. External Secrets Management

**HashiCorp Vault Integration:**
```bash
# Fetch credential from Vault
export GHCR_TOKEN=$(vault kv get -field=token secret/ghcr)

# Login with fetched credential
echo "$GHCR_TOKEN" | podman login ghcr.io -u $USER --password-stdin
```

**Kubernetes Secrets (for K8s deployments):**
```bash
# Create secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=$GITHUB_USER \
  --docker-password=$GITHUB_TOKEN \
  --docker-email=$EMAIL

# Use in pod spec
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: ghcr.io/owner/image:latest
  imagePullSecrets:
  - name: ghcr-secret
```

#### 5c. systemd Credential Passing

For bootc-based systems using systemd:
```ini
# /etc/systemd/system/podman-pull.service
[Service]
LoadCredential=ghcr_token:/run/credentials/ghcr.token
ExecStartPre=/usr/bin/bash -c 'echo $CREDENTIALS_GHCR_TOKEN | podman login ghcr.io -u ${GITHUB_USER} --password-stdin'
```

#### Pros
- ✅ Credentials never stored in plaintext
- ✅ Supports hardware security keys (HSM)
- ✅ Integration with enterprise secrets management
- ✅符合 CC-4 Auditability requirements
- ✅符合 Pull-Based Security posture

#### Cons
- ❌ Additional complexity for credential retrieval
- ❌ Requires secret management infrastructure
- ❌ May require network access to secrets service
- ❌ Token refresh adds latency

#### Fit Score: **8/10**
Best for: Production deployments, enterprise environments, security-critical applications

---

## 3. Evaluation Matrix

| Criteria | PAT Login | GITHUB_TOKEN | GitHub App | Raw API | Credential Helpers |
|----------|-----------|--------------|------------|---------|-------------------|
| **Ease of Setup** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐ | ⭐⭐ |
| **Security** | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Token Lifespan** | Long-lived | Ephemeral | Short-lived | Manual | Variable |
| **Auditability** | Limited | Full | Full | Manual | Configurable |
| **Offline Support** | Yes | No | Yes | Yes | Yes |
| **CI/CD Fit** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Production Fit** | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Pull Model Support** | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 4. Recommendations

### 4.1 Primary Recommendation: Hybrid Approach

For the Nornnet project, a **hybrid approach** is recommended based on the specific constraints:

#### For GitHub Actions CI/CD Pipeline:
**Use GITHUB_TOKEN** (Solution 2)
```yaml
- name: Login to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

#### For Device-Level Image Pulling:
**Use PAT with Credential Helper** (Solutions 1 + 5)

Rationale:
1. **Pull-only requirement**: Devices only need to pull images (no push)
2. **Minimal attack surface**: PAT with `read:packages` scope limits exposure
3. **Offline capability**: Credentials can be pre-provisioned
4. **Audit trail**: GitHub logs all authentication events

### 4.2 Implementation Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                    Architecture                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  CI/CD Pipeline (GitHub Actions)                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ • Uses GITHUB_TOKEN for push operations              │  │
│  │ • Full audit trail via GitHub                        │  │
│  │ • Short-lived credentials                            │  │
│  └──────────────────────────────────────────────────────┘  │
│                            │                                 │
│                            ▼                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              GHCR (ghcr.io)                          │  │
│  │   • Stores bootable container images                 │  │
│  │   • Public + private image support                   │  │
│  │   • OCI distribution spec compliant                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                            │                                 │
│                            ▼ (pull-based)                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Managed Devices (bootc + systemd + quadlets)        │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │ • Uses PAT with read:packages scope             │  │  │
│  │  │ • Credential stored in systemd secret service   │  │  │
│  │  │ • Refresh logic for token rotation             │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 Security Considerations for Pull-Based Model

1. **Token Scoping**: Use minimum required scopes (`read:packages` for devices)
2. **Token Rotation**: Implement periodic token refresh
3. **Credential Storage**: Use systemd credential passing or encrypted storage
4. **Network Isolation**: Devices initiate outbound-only connections
5. **Audit Logging**: Enable GitHub audit log for all registry access

---

## 5. Trade-offs and Risks

### Trade-off Analysis

| Decision | Benefit | Cost |
|----------|---------|------|
| PAT over GITHUB_TOKEN | Works outside GitHub | Security risk of long-lived cred |
| Embedded credentials | Offline capable | Harder to rotate |
| Credential helper | Better security | Additional complexity |
| Anonymous pull (public) | No auth needed | Only works for public images |

### Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| PAT expiration | Medium | High | Implement token refresh logic |
| Credential exposure | Low | Critical | Use encrypted storage + keyring |
| Rate limiting | Medium | Medium | Implement exponential backoff |
| Network failures | Medium | Low | Retry with backoff, local cache |
| Token scope too broad | Low | High | Use fine-grained PATs when available |

---

## 6. Implementation Artifacts (For Next Phase)

### 6.1 Registry Client Interface (LC-2)

```rust
// Concept: RegistryClient trait
trait RegistryClient {
    /// Authenticate with the registry
    fn login(&mut self, credentials: RegistryCredentials) -> Result<()>;
    
    /// Pull an image manifest
    fn get_manifest(&self, image: &ImageRef) -> Result<Manifest>;
    
    /// List image tags
    fn list_tags(&self, image: &str) -> Result<Vec<String>>;
    
    /// Check if image exists
    fn image_exists(&self, image: &ImageRef) -> Result<bool>;
    
    /// Pull image layers (for update detection)
    fn pull_layer(&self, image: &ImageRef, digest: &str) -> Result<Layer>;
}
```

### 6.2 Authentication Module Structure

```
src/
├── registry/
│   ├── mod.rs              # Module exports
│   ├── client.rs           # RegistryClient trait
│   ├── auth/
│   │   ├── mod.rs
│   │   ├── pat.rs          # PAT-based authentication
│   │   ├── github_token.rs # GITHUB_TOKEN auth (GitHub Actions)
│   │   └── github_app.rs   # GitHub App authentication
│   ├── operations/
│   │   ├── mod.rs
│   │   ├── manifest.rs     # Manifest operations
│   │   ├── blob.rs         # Blob/layer operations
│   │   └── catalog.rs      # Repository listing
│   └── error.rs            # Error types
```

### 6.3 Unit Test Skeleton

```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_pat_authentication_flow() {
        // Test PAT login and credential storage
    }
    
    #[test]
    fn test_manifest_fetch() {
        // Test manifest retrieval from GHCR
    }
    
    #[test]
    fn test_anonymous_public_access() {
        // Test pulling public images without auth
    }
}
```

---

## 7. References

### Documentation Sources
- [GitHub Container Registry Documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Podman Login Documentation](https://github.com/redhat-actions/podman-login)
- [Docker Registry HTTP API v2](https://distribution.github.io/distribution/spec/api/)
- [GitHub Actions Authentication](https://docs.github.com/en/actions/security-guides/automatic-token-authentication)

### Key GitHub Resources
- [Packages Container Registry supports GITHUB_TOKEN](https://github.blog/changelog/2021-03-24-packages-container-registry-now-supports-github_token/)
- [About permissions for GitHub Packages](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages)

---

## 8. Appendix: Authentication Comparison Details

### A. PAT Types

| Type | Scope | GHCR Support | Recommendation |
|------|-------|--------------|----------------|
| Classic PAT | Account-wide | Full | Use with caution |
| Fine-grained PAT | Repository-specific | Limited (as of 2024) | Monitor GitHub updates |
| GITHUB_TOKEN | Workflow-specific | Full | Preferred for CI/CD |

### B. Token Expiration Behavior

| Token Type | Default Expiration | Refresh Mechanism |
|------------|-------------------|------------------|
| Classic PAT | Configurable (max 1 year) | Manual rotation |
| Fine-grained PAT | Configurable (max 1 year) | Manual rotation |
| GITHUB_TOKEN | Workflow duration | Automatic |
| GitHub App Token | 1 hour (default) | Re-request via API |

### C. Required API Endpoints

| Operation | Endpoint | Auth Required |
|-----------|----------|--------------|
| Check API version | `GET /v2/` | No |
| List repositories | `GET /v2/_catalog` | Yes (write:packages) |
| Get manifest | `GET /v2/<name>/manifests/<ref>` | Yes (read:packages) |
| List tags | `GET /v2/<name>/tags/list` | Yes (read:packages) |
| Get blob | `GET /v2/<name>/blobs/<digest>` | Yes (read:packages) |

---

*Report Generated: 2026-03-24*  
*Research Phase: IDEATE*  
*Next Phase: PROTOTYPE*
