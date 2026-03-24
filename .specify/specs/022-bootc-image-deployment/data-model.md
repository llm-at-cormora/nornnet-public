# Data Model: Bootc Image Build & Deployment

This document defines the data structures and interfaces for the bootc image build and deployment system.

---

## Entity Definitions

### Image

```yaml
Image:
  id: string              # SHA256 digest (e.g., sha256:abc123...)
  registry: string        # Registry URL (e.g., ghcr.io/os2sandbox)
  repository: string      # Repository name (e.g., nornnet)
  tag: string            # Version tag (e.g., 0.1.0, latest)
  digest: string         # Full digest reference
  layers: Layer[]         # Image layers
  created_at: timestamp   # ISO 8601 creation time
  size_bytes: int64      # Compressed size
```

### Layer

```yaml
Layer:
  digest: string         # Layer digest
  media_type: string     # OCI media type
  size_bytes: int64      # Layer size
  instructions: string[] # Dockerfile instructions that created this layer
```

### Deployment

```yaml
Deployment:
  id: string             # UUID
  device_id: string      # Target device identifier
  image_id: string      # Deployed image reference
  status: DeploymentStatus
  started_at: timestamp  # When deployment began
  completed_at: timestamp # When deployment completed (null if in progress)
  deployed_by: string    # Actor who triggered deployment
  commit: string         # Git commit SHA
```

### DeploymentStatus

```yaml
enum DeploymentStatus:
  PENDING    # Deployment queued
  DOWNLOADING # Downloading image
  APPLYING   # Applying changes
  REBOOTING  # Rebooting to new image
  VERIFIED   # Health checks passed
  FAILED     # Deployment failed
  ROLLED_BACK # Reverted to previous version
```

### Device

```yaml
Device:
  id: string             # Unique device identifier
  hostname: string       # Device hostname
  current_image: string  # Currently running image reference
  status: DeviceStatus
  last_seen: timestamp   # Last communication time
  ostree_version: string # OSTree deployment version
```

### DeviceStatus

```yaml
enum DeviceStatus:
  ONLINE     # Device is reachable
  OFFLINE    # Device not responding
  UPDATING   # Update in progress
  DEGRADED   # Health checks failing
  ROLLED_BACK # Recovered via rollback
```

### UpdateAvailable

```yaml
UpdateAvailable:
  current_version: string  # Currently running version
  available_version: string # New version available
  release_notes: string    # Changes in new version
  size_bytes: int64       # Download size
  created_at: timestamp   # When version was published
```

### HealthCheckResult

```yaml
HealthCheckResult:
  check_name: string      # Name of health check
  passed: boolean         # Whether check passed
  output: string           # Check output/logs
  duration_ms: int         # Check duration
  executed_at: timestamp   # When check ran
```

---

## Interface Contracts

### RegistryClient

```typescript
interface RegistryClient {
  // Authenticate with registry
  login(url: string, credentials: Credentials): Promise<void>;
  
  // Push image to registry
  push(image: Image, tag: string): Promise<string>;
  
  // Pull image from registry
  pull(reference: string): Promise<Image>;
  
  // List available tags
  listTags(repository: string): Promise<string[]>;
  
  // Get image digest
  getDigest(reference: string): Promise<string>;
}
```

### ImageBuilder

```typescript
interface ImageBuilder {
  // Build image from Containerfile
  build(context: string, dockerfile: string, tags: string[]): Promise<Image>;
  
  // Validate image for bootc compatibility
  lint(image: Image): Promise<ValidationResult>;
  
  // Convert container to disk image
  toDisk(image: Image, format: DiskFormat): Promise<string>;
}
```

### DeploymentOrchestrator

```typescript
interface DeploymentOrchestrator {
  // Deploy image to device
  deploy(device: Device, image: Image): Promise<Deployment>;
  
  // Check for available updates
  checkForUpdates(device: Device): Promise<UpdateAvailable | null>;
  
  // Apply staged update
  applyUpdate(device: Device): Promise<Deployment>;
  
  // Get deployment status
  getStatus(deploymentId: string): Promise<Deployment>;
}
```

### RollbackManager

```typescript
interface RollbackManager {
  // Trigger rollback to previous version
  rollback(device: Device): Promise<Deployment>;
  
  // Get rollback history
  getHistory(device: Device): Promise<Deployment[]>;
  
  // Check if rollback is available
  canRollback(device: Device): Promise<boolean>;
}
```

### StatusReporter

```typescript
interface StatusReporter {
  // Get current device status
  getDeviceStatus(device: Device): Promise<DeviceStatus>;
  
  // Get current image version
  getImageVersion(device: Device): Promise<string>;
  
  // Get deployment history
  getDeploymentHistory(device: Device): Promise<Deployment[]>;
  
  // Run health checks
  runHealthChecks(device: Device): Promise<HealthCheckResult[]>;
}
```

---

## Event Schemas

### DeploymentStarted

```json
{
  "event": "deployment.started",
  "timestamp": "2026-03-24T10:00:00Z",
  "deployment_id": "uuid",
  "device_id": "device-001",
  "image": "ghcr.io/os2sandbox/nornnet:0.1.0",
  "triggered_by": "github-actions[workflow:build.yml]"
}
```

### DeploymentCompleted

```json
{
  "event": "deployment.completed",
  "timestamp": "2026-03-24T10:05:00Z",
  "deployment_id": "uuid",
  "device_id": "device-001",
  "status": "verified",
  "duration_seconds": 300,
  "image_version": "0.1.0"
}
```

### DeploymentFailed

```json
{
  "event": "deployment.failed",
  "timestamp": "2026-03-24T10:05:00Z",
  "deployment_id": "uuid",
  "device_id": "device-001",
  "status": "failed",
  "error": "Health check 'network' failed after 3 retries",
  "rollback_initiated": true
}
```

### RollbackTriggered

```json
{
  "event": "rollback.triggered",
  "timestamp": "2026-03-24T10:05:00Z",
  "device_id": "device-001",
  "from_version": "0.1.0",
  "to_version": "0.0.9",
  "reason": "Health check 'network' failed",
  "automatic": true
}
```

---

## Configuration Schemas

### Containerfile Labels

```dockerfile
# Required labels for bootc images
LABEL org.opencontainers.image.title="Nornnet Base"
LABEL org.opencontainers.image.version="0.1.0"
LABEL org.opencontainers.image.source="https://github.com/OS2sandbox/nornnet"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.licenses="MIT"

# Required for bootc
LABEL containers.bootc="1"
LABEL ostree.bootable="1"
```

### Greenboot Health Check

```bash
#!/bin/bash
# /etc/greenboot/check/required.d/50-verify-system.sh

set -euo pipefail

# Check critical services
for svc in sshd docker.socket; do
    systemctl is-active --quiet "$svc" || {
        echo "CRITICAL: $svc is not running"
        exit 1
    }
done

# Verify network connectivity (optional)
ping -c 1 -W 5 8.8.8.8 > /dev/null 2>&1 || true

# Check disk space
df -h / | awk 'NR==2 {gsub("%","",$5); if ($5 > 90) exit 1}'

echo "Health check passed"
exit 0
```

### Systemd Unit for Update Locking

```ini
[Unit]
Description=Nornnet Image Update Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bootc upgrade --apply
Locking=fail
# Prevent concurrent executions
ExecStartPre=/usr/bin/flock /run/nornnet-update.lock -c 'test $$ -eq $$'
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nornnet-update

[Install]
WantedBy=multi-user.target
```

---

## Audit Trail Events

All significant state changes must emit structured audit events:

| Event | When | Fields |
|--------|------|--------|
| `image.built` | Image build completes | image_id, commit, duration |
| `image.pushed` | Image pushed to registry | image_id, registry, tag |
| `deployment.started` | Deployment begins | deployment_id, device, image |
| `deployment.completed` | Deployment succeeds | deployment_id, duration |
| `deployment.failed` | Deployment fails | deployment_id, error, rollback_initiated |
| `update.detected` | New version available | device, from_version, to_version |
| `rollback.triggered` | Rollback initiates | device, from, to, automatic |
| `rollback.completed` | Rollback succeeds | device, duration |
| `health_check.passed` | Health check succeeds | device, check_name |
| `health_check.failed` | Health check fails | device, check_name, error |
