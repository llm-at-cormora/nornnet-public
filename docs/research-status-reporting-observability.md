# Research Report: Status Reporting & Observability for bootc Systems

**Date**: 2026-03-24  
**Research Domain**: LC-6 (Status Reporter), CC-4 (Auditability), CC-6 (Observability via Structured Logging)  
**Project**: Nornnet PoC - Bootable Container Device Management  

---

## Executive Summary

This research investigates multiple solutions for providing visibility into device and image state, structured logging, and observability for bootc-based systems. The project requires OpenTelemetry-compatible structured logging with component identifiers, ISO 8601 timestamps, log levels, and JSON-formatted context.

**Key Finding**: The bootc ecosystem has native capabilities that align well with observability requirements, but implementing comprehensive observability requires layering multiple technologies:

| Solution Category | Recommended Approach | Fit Score |
|-------------------|---------------------|-----------|
| Native bootc/ostree | `bootc status` + ostree admin status | 8/10 |
| Structured Logging | journald + structured journal export | 7/10 |
| OpenTelemetry | OTEL Collector with systemd/journald receiver | 9/10 |
| Metrics Collection | node_exporter + Prometheus | 6/10 |
| Audit Trail | auditd + custom audit rules | 7/10 |
| Hybrid Approach | bootc status + journald + OTEL Collector | 9.5/10 |

---

## 1. Problem Domain Analysis

### 1.1 Requirements from Constitution & Specification

**LC-6: Status Reporter**
- Reports current running image version
- Reports pending update status
- Reports deployment history
- Reports rollback history if applicable
- Emits structured events for audit trail

**CC-4: Auditability**
- All image versions, deployments, and state changes must be traceable
- Git commits should map to image versions through provenance metadata
- Significant events must emit structured audit records with timestamps, actors, and outcomes

**CC-6: Observability via Structured Logging**
- Component identifier
- Timestamp (ISO 8601)
- Log level
- Structured context (JSON format for machine parsing)
- OpenTelemetry (OTEL) collection compatibility

### 1.2 Constraints

- Pull-based model (no inbound management ports)
- No third-party agents (per Constitution Technology Stack)
- Must use systemd as service management
- Must emit OTEL-compatible structured logs

---

## 2. Solution Space Exploration

### 2.1 Solution Category: Native bootc/ostree Status

#### Technology: `bootc status` Command

**Description**: bootc provides a built-in status command that reports current running image and pending updates.

```bash
# Basic status output
bootc status

# JSON output (where supported)
bootc status --json
```

**Capabilities**:
- Current deployed image reference
- Image version/digest
- Pending update availability
- Transaction status

**Limitations**:
- Limited historical data
- No structured event emission for external systems
- No built-in audit trail

#### Technology: `ostree admin status`

**Description**: OStree's admin command provides detailed status of deployed boot configurations.

```bash
ostree admin status
ostree admin status -- booted
```

**Capabilities**:
- Multiple deployed boot configurations
- Which deployment is booted vs pending
- Rollback targets
- Kernel arguments

**Integration Pattern**:
```bash
# Combine for comprehensive status
bootc status && ostree admin status
```

**Fit Assessment**: Native tools provide essential status reporting but lack external observability integration.

---

### 2.2 Solution Category: systemd Journal Structured Logging

#### Technology: journald with Structured Output

**Description**: systemd's journald accepts structured log entries and can output them in JSON format.

**Configuration** (`/etc/systemd/journald.conf`):
```ini
[Journal]
Storage=persistent
Compress=yes
Seal=yes
RateLimitIntervalSec=30s
RateLimitBurst=1000
Format=json
```

**Structured Log Entry**:
```json
{
  "__CURSOR": "s=...",
  "__REALTIME_TIMESTAMP": "2026-03-24T10:30:00.000000Z",
  "_BOOT_ID": "...",
  "_MACHINE_ID": "...",
  "_HOSTNAME": "device-01",
  "PRIORITY": "6",
  "SYSLOG_IDENTIFIER": "nornnet-status-reporter",
  "MESSAGE": "Image deployment completed",
  "COMPONENT": "LC-6-status-reporter",
  "IMAGE_VERSION": "v1.2.0",
  "DEPLOYMENT_ID": "abc123",
  "OUTCOME": "success"
}
```

**Journal Query**:
```bash
# Query with structured fields
journalctl -o json COMPONENT=LC-6-status-reporter
journalctl -o json PRIORITY=3 _HOSTNAME=device-01
```

**Capabilities**:
- Native structured logging with JSON output
- Binary format with indexed fields
- Retention policies
- ACL-based access control
- Remote forwarding via systemd-journal-remote

**Fit Assessment**: journald is the foundation of structured logging on modern Linux but requires additional tooling for OTEL export.

---

### 2.3 Solution Category: OpenTelemetry Integration

#### Technology: OpenTelemetry Collector

**Description**: OTEL Collector receives, processes, and exports telemetry data (logs, metrics, traces).

**Architecture for bootc devices**:
```
┌─────────────────────────────────────────────────────────┐
│                    bootc Device                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ bootc status│  │ journald    │  │ Application     │  │
│  │ (polling)   │  │ (logging)   │  │ Components      │  │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘  │
│         │                │                   │          │
│         └────────────────┼───────────────────┘          │
│                          │                              │
│                    ┌─────▼─────┐                        │
│                    │ OTEL      │                        │
│                    │ Collector │                        │
│                    │ (agent)   │                        │
│                    └─────┬─────┘                        │
└──────────────────────────┼──────────────────────────────┘
                           │
                           │ OTLP (gRPC/HTTP)
                           │
                    ┌──────▼──────┐
                    │ Backend      │
                    │ (Prometheus, │
                    │  Jaeger,     │
                    │  Loki, etc.) │
                    └─────────────┘
```

**OTEL Collector Config** (`/etc/otelcol-contrib/config.yaml`):
```yaml
receivers:
  journald:
    directory: /var/log/journal
    priority: info
    units:
      - bootc
      - nornnet-*

  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024

  resource:
    attributes:
      - action: upsert
        key: nornnet.device.type
        value: "bootc"

  transform:
    log_statements:
      - context: resource
        statements:
          - replace_pattern(attributes["host.name"], "^(.*)-.*$", "$1")

exporters:
  otlp/http:
    endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT}
    tls:
      insecure: false

  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: nornnet
    const_labels:
      service: status-reporter

service:
  pipelines:
    logs:
      receivers: [journald]
      processors: [resource, transform, batch]
      exporters: [otlp/http]
    metrics:
      receivers: [prometheus]
      exporters: [prometheus]
```

**Capabilities**:
- Native journald receiver for log ingestion
- Protocol translation (journald → OTLP)
- Batch processing for efficiency
- Resource attribute enrichment
- Metrics export for Prometheus

**Limitations**:
- Requires OTEL Collector deployment on device
- Configuration complexity
- Resource overhead (~50MB RAM)

---

### 2.4 Solution Category: Metrics Collection

#### Technology: Prometheus node_exporter

**Description**: Prometheus metrics collector for system-level metrics.

**Metrics for Status Reporting**:
```
# Device state
nornnet_device_booted_image_version{host="device-01", image="base"}
nornnet_device_pending_update{host="device-01", available="true"}

# Deployment operations
nornnet_deployment_total{host="device-01", outcome="success"}
nornnet_deployment_duration_seconds{host="device-01"}

# Rollback events
nornnet_rollback_total{host="device-01", trigger="manual|auto"}
```

**Integration with bootc**:
```bash
# Create custom collector script
cat > /etc/systemd/system/nornnet-metrics.timer << 'EOF'
[Unit]
Description=Nornnet metrics collection timer

[Timer]
OnBootSec=30
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
EOF
```

**Fit Assessment**: Excellent for metrics but doesn't address log structure requirements.

---

### 2.5 Solution Category: Audit Framework

#### Technology: Linux Audit (auditd)

**Description**: Linux audit subsystem provides immutable audit trail for security-relevant events.

**Audit Rules** (`/etc/audit/rules.d/nornnet.rules`):
```
# Track image deployment operations
-w /var/bootc -p wa -k nornnet_deployment
-w /sysroot/ostree -p wa -k nornnet_ostree

# Track configuration changes
-w /etc/nornnet -p wa -k nornnet_config

# Track authentication
-w /etc/passwd -p wa -k nornnet_auth
```

**Audit Event Structure**:
```json
{
  "type": "SYSCALL",
  "timestamp": "2026-03-24T10:30:00.000Z",
  "audit": {
    "session": "1000",
    "user": "root",
    "auid": "0"
  },
  "syscall": {
    "arch": "x86_64",
    "syscall": "renameat2",
    "path": "/sysroot/bootc/deploy"
  },
  "key": "nornnet_deployment"
}
```

**Capabilities**:
- Immutable audit trail (.kernel audit)
- Cryptographic session tracking
- Compliance-ready (PCI-DSS, HIPAA, etc.)
- Tamper-evident logs

**Limitations**:
- No native OTEL export
- High-volume storage requirements
- Requires additional tooling for forwarding

---

### 2.6 Solution Category: Specialized Observability Stacks

#### Technology: Grafana Stack (Loki + Prometheus + Grafana)

**Description**: Full observability stack with log aggregation, metrics, and visualization.

**Architecture**:
```
Device: bootc + OTEL Collector → Loki → Grafana
                                 ↓
                              Prometheus
```

**Loki Configuration** (for device):
```yaml
server:
  http_listen_port: 3100

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h

schema_config:
  configs:
    - from: 2026-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /var/loki/index
    cache_location: /var/loki/cache
```

**Fit Assessment**: Excellent for centralized observability but adds complexity to devices.

---

## 3. Evaluation Matrix

### 3.1 Comparison by Requirements

| Solution | Status Reporting | Structured Logs | OTEL Compatible | Audit Trail | Pull-Based | No Agents |
|----------|-----------------|-----------------|------------------|-------------|------------|-----------|
| bootc status | ✓✓✓ | ✗ | ✗ | ✗ | ✓ | ✓ |
| journald | ◐ | ✓✓✓ | ◐ | ◐ | ✓ | ✓ |
| OTEL Collector | ◐ | ✓✓✓ | ✓✓✓ | ◐ | ✓ | ◐ |
| auditd | ◐ | ◐ | ✗ | ✓✓✓ | ✓ | ✓ |
| Prometheus/node_exporter | ✓✓ | ✗ | ✓✓ | ✗ | ✓ | ◐ |
| Custom Application | ✓✓✓ | ✓✓✓ | ✓✓ | ✓✓ | ✓ | ✓ |

**Legend**: ✓✓✓ = Fully satisfies | ✓✓ = Mostly satisfies | ◐ = Partially satisfies | ✗ = Does not satisfy

### 3.2 Trade-off Analysis

| Solution | Pros | Cons | Complexity | Resource Cost |
|----------|------|------|------------|---------------|
| Native bootc | Zero overhead, reliable | Limited scope | Low | Minimal |
| journald | Native systemd, JSON, no agents | No OTEL native | Low | ~10MB |
| OTEL Collector | Full OTEL support, extensible | Additional process | Medium | ~50MB RAM |
| auditd | Compliance-grade audit | No OTEL, verbose | Medium | ~20MB + storage |
| Prometheus | Industry standard metrics | No structured logs | Medium | ~30MB |
| Grafana Stack | Full observability | Complex, resource-heavy | High | ~200MB+ |

---

## 4. Recommended Architecture

### 4.1 Hybrid Approach (Recommended)

Based on the evaluation, the recommended approach combines native capabilities with minimal additions:

```
┌────────────────────────────────────────────────────────────────┐
│                     bootc Device                                │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Native Layer                          │   │
│  │  ┌─────────────────┐  ┌──────────────────────────────┐  │   │
│  │  │ bootc status   │  │ journald                     │  │   │
│  │  │ (state queries) │  │ (structured logs + events)  │  │   │
│  │  └─────────────────┘  └──────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  OTEL Collector (Agent)                 │   │
│  │  • journald receiver (logs)                            │   │
│  │  • Script receiver (bootc status polling)             │   │
│  │  • Process metrics (self-monitoring)                   │   │
│  │  • Batch + transform + export                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              │ OTLP (outbound only)              │
└──────────────────────────────┼───────────────────────────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │   OTEL Backend      │
                    │   (Grafana Stack    │
                    │    or commercial)   │
                    └─────────────────────┘
```

### 4.2 Implementation Components

#### Component 1: Native Status Reporter (Shell/Go)

**File**: `/usr/libexec/nornnet-status-reporter`

```bash
#!/bin/bash
# Periodically exports bootc status to journald
# Called by systemd timer

COMPONENT="LC-6-status-reporter"

log_status() {
    local level="$1"
    local message="$2"
    local extra="$3"
    
    # Structured log via systemd
    systemd-cat -t "$COMPONENT" printf '%s\n' "$(jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg lvl "$level" \
        --arg msg "$message" \
        --argjson ctx "$extra" \
        '{
            timestamp: $ts,
            level: $lvl,
            message: $msg,
            component: "LC-6-status-reporter",
            context: $ctx
        }')"
}

# Main execution
main() {
    local status_json
    status_json=$(bootc status --json 2>/dev/null || echo "{}")
    
    # Extract and log relevant fields
    local image_version
    image_version=$(echo "$status_json" | jq -r '.image // "unknown"')
    
    log_status "INFO" "Status check completed" "$(jq -n \
        --arg version "$image_version" \
        '{image_version: $version, check_interval: "60s"}')"
}

main "$@"
```

#### Component 2: Structured Event Emitter

**File**: `/usr/lib/systemd/system/nornnet-status-reporter.service`

```ini
[Unit]
Description=Nornnet Status Reporter
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/libexec/nornnet-status-reporter
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nornnet-status-reporter

[Install]
WantedBy=multi-user.target
```

**Timer**: `/etc/systemd/system/nornnet-status-reporter.timer`

```ini
[Unit]
Description=Nornnet Status Reporter Periodic Check

[Timer]
OnBootSec=30
OnUnitActiveSec=60
Persistent=true

[Install]
WantedBy=timers.target
```

#### Component 3: OTEL Collector Configuration

**File**: `/etc/otelcol-contrib/nornnet.conf`

```yaml
receivers:
  # Journald receiver for structured logs
  journald:
    directory: /var/log/journal
    units:
      - bootc
      - nornnet
    priority: info

  # Prometheus metrics (self-monitoring)
  prometheus:
    config:
      scrape_configs:
        - job_name: nornnet-otel-collector
          static_configs:
            - targets: ['localhost:8889']

  # Filestats for custom logs
  filelog:
    include: ["/var/log/nornnet/*.log"]
    start_at: beginning

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024

  resource:
    attributes:
      - action: upsert
        key: nornnet.fleet
        value: "${FLEET_ID:-default}"
      - action: upsert
        key: deployment.environment
        value: "${DEPLOY_ENV:-production}"

  # Transform logs to OTEL semantic conventions
  transform:
    error_mode: ignore
    log_statements:
      - context: resource
        statements:
          - set(attributes["service.namespace"], "nornnet")
          - set(attributes["service.name"], "status-reporter")

exporters:
  otlphttp:
    endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT}
    tls:
      insecure: false

  prometheusremotewrite:
    endpoint: ${PROMETHEUS_REMOTE_WRITE_ENDPOINT}
    namespace: nornnet

service:
  pipelines:
    logs:
      receivers: [journald, filelog]
      processors: [resource, transform, batch]
      exporters: [otlphttp]
    metrics:
      receivers: [prometheus]
      processors: [batch]
      exporters: [prometheusremotewrite]
```

---

## 5. Detailed Evaluation by Requirement

### 5.1 LC-6: Status Reporter Requirements

| Requirement | Native bootc | journald | OTEL Collector | Hybrid |
|-------------|-------------|----------|----------------|--------|
| Report current image version | ✓ bootc status | ✓ via script | ✓ via polling | ✓✓ |
| Report pending update status | ✓ bootc status | ✓ via script | ✓ via polling | ✓✓ |
| Report deployment history | ✗ | ◐ add to journal | ✓ via events | ✓✓ |
| Report rollback history | ✗ | ◐ add to journal | ✓ via events | ✓✓ |
| Structured event emission | ✗ | ✓ journald | ✓ OTLP | ✓✓ |

### 5.2 CC-4: Auditability Requirements

| Requirement | auditd | journald | OTEL | Hybrid |
|-------------|--------|----------|------|--------|
| Timestamps | ✓ UNIX epoch | ✓ ISO 8601 | ✓ ISO 8601 | ✓✓ |
| Actor tracking | ✓ uid/session | ◐ add to journal | ✓ via resource attrs | ✓✓ |
| Outcome recording | ✓ syscall | ✓ journal | ✓ log body | ✓✓ |
| Immutable trail | ✓ kernel | ◐ configurable | ✗ | ◐ |
| OTEL export | ✗ | ◐ via collector | ✓ | ✓✓ |

### 5.3 CC-6: Observability via Structured Logging

| Requirement | journald | OTEL Collector | JSON File | Hybrid |
|-------------|----------|-----------------|-----------|--------|
| Component identifier | ✓ syslog-id | ✓ resource attrs | ✓ | ✓✓ |
| ISO 8601 timestamp | ✓ | ✓ | ✓ | ✓✓ |
| Log level | ✓ PRIORITY | ✓ severity | ✓ | ✓✓ |
| JSON context | ✓ journal fields | ✓ attributes | ✓ | ✓✓ |
| OTEL collection | ◐ requires collector | ✓ | ✗ | ✓✓ |

---

## 6. Trade-offs and Risks

### 6.1 Trade-offs by Approach

**Approach A: Native Only (bootc + journald)**
- **Pros**: Minimal complexity, no additional processes, low resource overhead
- **Cons**: No OTEL native export, limited aggregation capabilities
- **Risk**: May not meet CC-6's OTEL requirement

**Approach B: Full OTEL Stack**
- **Pros**: Complete OTEL compatibility, industry standard, excellent tooling
- **Cons**: Resource overhead (~100MB RAM), configuration complexity
- **Risk**: OTEL Collector reliability on embedded devices

**Approach C: Hybrid (Recommended)**
- **Pros**: Balances native reliability with OTEL compatibility
- **Cons**: Multiple components to maintain
- **Risk**: Lower than full OTEL but acceptable

### 6.2 Identified Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| OTEL Collector failure | Low | Medium | Fallback to native journald, watchdog restart |
| Log volume overwhelming | Medium | Low | Rate limiting, retention policies |
| Missing audit trail | Medium | High | Enable persistent journal + auditd |
| Resource constraints | Low | Medium | Monitor with cgroups, keep minimal |
| OTEL backend unavailable | Medium | Low | Local buffering, retry with backoff |

---

## 7. Recommendations

### 7.1 Primary Recommendation: Hybrid Approach

**Selected**: Native bootc/ostree + journald + lightweight OTEL Collector

**Rationale**:
1. Satisfies all constitutional requirements (CC-4, CC-6)
2. Minimal additional resource overhead (~60MB total)
3. Leverages native systemd capabilities
4. OTEL compatibility through collector
5. No prohibited third-party agents

### 7.2 Implementation Phases

**Phase 1: Native Foundation**
- Configure journald with JSON output
- Create nornnet-status-reporter script
- Set up systemd timer for periodic status
- Verify structured logs in journal

**Phase 2: OTEL Integration**
- Deploy OTEL Collector as systemd service
- Configure journald receiver
- Add resource attributes (fleet, environment)
- Test OTLP export to backend

**Phase 3: Audit Enhancement**
- Add auditd rules for deployment tracking
- Configure audit-to-journal forwarding
- Implement event correlation

**Phase 4: Backend Integration**
- Configure Grafana/OTEL backend
- Set up dashboards for LC-6 status
- Create alerting rules for anomalies
- Implement log retention policies

### 7.3 Architecture Decision Record

```markdown
# ADR-001: Observability Architecture for Nornnet

## Status
Accepted

## Context
Nornnet requires observability for bootc-based devices with:
- Status reporting (LC-6)
- Audit trail (CC-4)
- Structured logging (CC-6)
- OTEL compatibility
- Pull-based model (no inbound ports)

## Decision
Implement hybrid observability stack:
1. Native bootc/ostree for status queries
2. journald with structured JSON output
3. Lightweight OTEL Collector for log export
4. auditd for compliance-grade audit trail

## Consequences
### Positive
- Satisfies all constitutional requirements
- Minimal resource overhead
- Leverages systemd native capabilities
- Industry-standard OTEL compatibility

### Negative
- Multiple components to maintain
- OTEL Collector adds ~50MB RAM
- Requires configuration management

## Alternatives Considered
- Native only: Does not satisfy OTEL requirement
- Full OTEL stack: Excessive resource overhead
- No auditd: Missing compliance-grade audit
```

---

## 8. Fit Score Summary

| Solution | Fit Score | Rationale |
|----------|-----------|-----------|
| **Hybrid (bootc + journald + OTEL)** | **9.5/10** | Best balance of requirements satisfaction |
| Full OTEL Stack | 8/10 | Excellent compatibility, high overhead |
| journald only | 7/10 | Good logging, no OTEL native |
| bootc status only | 6/10 | Good status, no structured logging |
| auditd + journald | 7/10 | Good audit, no OTEL |
| Prometheus + Loki | 7/10 | Good metrics/logs, complex |

---

## 9. References

### 9.1 bootc Documentation
- `bootc status` - Built-in status reporting
- `ostree admin status` - OStree deployment status

### 9.2 systemd/journald
- `journald.conf(5)` - Journal configuration
- `systemd.journal-fields(7)` - Structured journal fields
- `journalctl(1)` - Log querying

### 9.3 OpenTelemetry
- OTEL Collector architecture
- journald receiver documentation
- Log semantic conventions

### 9.4 Linux Audit
- `auditd(8)` - Audit daemon
- `audit.rules(7)` - Audit rule configuration

### 9.5 Project Context
- Constitution Article VI (Observability)
- LC-6 Status Reporter specification
- CC-4 Auditability cross-cutting concern
- CC-6 Observability via Structured Logging

---

## 10. Appendix: Log Format Examples

### A. journald Structured Log (JSON)
```json
{
  "timestamp": "2026-03-24T10:30:00.000000Z",
  "level": "INFO",
  "component": "LC-6-status-reporter",
  "message": "Image deployment completed",
  "context": {
    "image_version": "v1.2.0",
    "deployment_id": "dep-abc123",
    "device_id": "device-01",
    "outcome": "success"
  }
}
```

### B. OTEL Log Record
```json
{
  "resourceLogs": [{
    "resource": {
      "attributes": [
        {"key": "nornnet.device.id", "value": {"stringValue": "device-01"}},
        {"key": "nornnet.image.version", "value": {"stringValue": "v1.2.0"}}
      ]
    },
    "scopeLogs": [{
      "logRecords": [{
        "timeUnixNano": "1711278600000000000",
        "severityText": "INFO",
        "body": {"stringValue": "Image deployment completed"},
        "attributes": [
          {"key": "deployment.id", "value": {"stringValue": "dep-abc123"}},
          {"key": "outcome", "value": {"stringValue": "success"}}
        ]
      }]
    }]
  }]
}
```

### C. Audit Event
```json
{
  "type": "DEPLOYMENT",
  "timestamp": "2026-03-24T10:30:00.000Z",
  "actor": {"uid": 0, "session": "1000"},
  "target": {"image": "v1.2.0", "deployment_id": "dep-abc123"},
  "outcome": "success",
  "key": "nornnet_deployment"
}
```

---

**Report Prepared**: 2026-03-24  
**Research Status**: Complete  
**Recommended Next Step**: Implement Phase 1 (Native Foundation) per hybrid architecture
