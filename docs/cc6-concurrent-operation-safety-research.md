# CC-6: Concurrent Operation Safety Research Report

## Executive Summary

This report explores **multiple solutions** for ensuring safe handling of concurrent operations in bootc-based systems. The primary concern is CC-6 from the project specification: **concurrent operations must be rejected or queued** — only one update should execute at a time.

**Key Problem**: Multiple concurrent requests (update during rollback, simultaneous update requests) can cause race conditions, leading to system corruption, update failures, or inconsistent state.

---

## Problem Domain Analysis

### Concurrency Hazards in bootc/ostree Systems

| Hazard | Description | Impact |
|--------|-------------|--------|
| **Update-Rollback Race** | Update initiated while rollback is in progress | Corrupted filesystem state |
| **Simultaneous Updates** | Two update requests arriving concurrently | Split deployments, version conflicts |
| **Partial State Exposure** | Reading state while update/rollback in progress | Stale information returned |
| **Lock Starvation** | Excessive retries blocking critical operations | System hang, timeout failures |
| **Orphaned State Files** | Crash during state transition leaves lock files | Permanent blocking |

### State Machine for Update Operations

```
[IDLE] ──update──────> [UPDATING] ──success────> [IDLE]
   │                       │
   │                       └───failure───> [ROLLBACK_NEEDED]
   │                                            │
   ├──rollback────────> [ROLLING_BACK] ──done──> [IDLE]
   │                       │
   │                       └───failure───> [DEGRADED]
   │
   └──concurrent_request──> [REJECTED] (back to IDLE)
```

---

## Multiple Solutions Discovered

### Solution 1: Advisory File Locking (flock)

**Mechanism**: POSIX file locks via `flock()` system call or shell wrapper.

```bash
# systemd service with flock protection
[Unit]
After=local-fs.target
Requires=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/flock /run/bootc-update.lock /usr/local/bin/bootc-update.sh
ExecStop=/usr/bin/rm -f /run/bootc-update.lock
```

**Rust Implementation Pattern**:
```rust
use std::fs::File;
use std::os::unix::io::AsRawFd;
use flock::{flock, LockType};

pub struct UpdateLock {
    file: File,
}

impl UpdateLock {
    pub fn acquire() -> Result<Self> {
        let file = File::create("/run/bootc-update.lock")?;
        flock(file.as_raw_fd(), LockType::Blocking)?;
        Ok(Self { file })
    }
}
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| Simplicity | ★★★★★ | Easy to implement and understand |
| Portability | ★★★★☆ | POSIX, works on Linux/macOS |
| Robustness | ★★★☆☆ | Advisory only, can be bypassed |
| Testing | ★★★☆☆ | Can test lock acquisition failures |

**Trade-offs**:
- ✅ Simple, well-understood mechanism
- ✅ Works across process boundaries
- ✅ No external dependencies
- ❌ Advisory lock can be overridden by malicious code
- ❌ No built-in timeout mechanism (requires wrapper)
- ❌ Lock file may remain on crash (needs cleanup)

---

### Solution 2: systemd-native Locking with Type=oneshot

**Mechanism**: Leverage systemd's built-in service management to serialize operations.

```ini
# /etc/systemd/system/bootc-update.service
[Unit]
Description=Bootc Update Service
After=local-fs.target
Conflicts=bootc-rollback.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/bootc-update-wrapper.sh
StandardOutput=journal
StandardError=journal

# Prevent multiple instances
LockPath=/run/bootc-update.lock
```

```bash
#!/bin/bash
# /usr/local/bin/bootc-update-wrapper.sh
set -euo pipefail

LOCKFILE="/run/bootc-update.lock"
LOCKTIMEOUT=300

# Acquire exclusive lock with timeout
flock -w "$LOCKTIMEOUT" "$LOCKFILE" || {
    echo "Failed to acquire lock within ${LOCKTIMEOUT}s" >&2
    exit 1
}

trap 'rm -f "$LOCKFILE"' EXIT

# Perform update
bootc update "$@"
```

** systemd Timer Configuration**:
```ini
# /etc/systemd/system/bootc-update.timer
[Unit]
Description=Periodic bootc Update Check

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
RandomizedDelaySec=30min

[Install]
WantedBy=timers.target
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| Integration | ★★★★★ | Native systemd integration |
| Reliability | ★★★★☆ | systemd manages service lifecycle |
| Observability | ★★★★★ | Full journal logging |
| Complexity | ★★★☆☆ | Requires systemd knowledge |

**Trade-offs**:
- ✅ Native systemd integration
- ✅ Automatic restart on failure
- ✅ Full observability via journal
- ✅ Timer support for scheduled updates
- ❌ Service file changes require reload
- ❌ Not truly atomic across service restarts

---

### Solution 3: State File with Atomic Operations (Rust tokio + Mutex)

**Mechanism**: Application-level state machine with async mutex protection.

```rust
use tokio::sync::Mutex;
use std::sync::Arc;
use tokio::time::{timeout, Duration};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UpdateState {
    Idle,
    Updating,
    RollingBack,
    Degraded,
}

pub struct UpdateManager {
    state: Arc<Mutex<UpdateState>>,
}

impl UpdateManager {
    pub async fn try_start_update(&self) -> Result<(), UpdateError> {
        let mut state = self.state.lock().await;
        
        match *state {
            UpdateState::Idle => {
                *state = UpdateState::Updating;
                Ok(())
            }
            UpdateState::Updating => Err(UpdateError::AlreadyUpdating),
            UpdateState::RollingBack => Err(UpdateError::RollbackInProgress),
            UpdateState::Degraded => Err(UpdateError::SystemDegraded),
        }
    }
    
    pub async fn complete_update(&self, success: bool) {
        let mut state = self.state.lock().await;
        *state = if success {
            UpdateState::Idle
        } else {
            UpdateState::RollingBack
        };
    }
}
```

**With Persistent State**:
```rust
use std::path::PathBuf;

pub struct PersistentUpdateManager {
    state_file: PathBuf,
    state: Arc<tokio::sync::Mutex<UpdateState>>,
}

impl PersistentUpdateManager {
    pub async fn new(state_file: PathBuf) -> Result<Self> {
        let state = Self::load_state(&state_file).await?;
        Ok(Self {
            state_file,
            state: Arc::new(tokio::sync::Mutex::new(state)),
        })
    }
    
    async fn load_state(path: &PathBuf) -> UpdateState {
        match tokio::fs::read_to_string(path).await {
            Ok(content) => content.trim().parse().unwrap_or(UpdateState::Idle),
            Err(_) => UpdateState::Idle,
        }
    }
    
    async fn persist_state(&self, state: UpdateState) -> Result<()> {
        tokio::fs::write(&self.state_file, format!("{:?}", state)).await?;
        Ok(())
    }
}
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| Control | ★★★★★ | Full programmatic control |
| Testing | ★★★★★ | Can mock/timer control in tests |
| Async | ★★★★★ | Non-blocking operations |
| Persistence | ★★★★☆ | State survives restarts |

**Trade-offs**:
- ✅ Fine-grained control over state transitions
- ✅ Testable with mocked time
- ✅ Async-native for high concurrency
- ✅ State can persist across restarts
- ❌ In-process only (doesn't protect against other processes)
- ❌ Requires careful lock handling

---

### Solution 4: D-Bus Based Locking

**Mechanism**: Use D-Bus for inter-process locking and state management.

```rust
use zbus::Connection;
use zvariant::ObjectPath;

#[dbus_interface(name = "com.example.BootcUpdate")]
pub trait BootcUpdate {
    async fn acquire_lock(&self) -> Result<bool, String>;
    
    async fn release_lock(&self) -> Result<(), String>;
    
    async fn start_update(&self, image: String) -> Result<(), String>;
    
    async fn get_state(&self) -> Result<UpdateState, String>;
}

#[dbus_interface(interface = "com.example.BootcUpdate")]
impl BootcUpdate {
    async fn acquire_lock(&self) -> Result<bool, String> {
        // Check if lock is available
        if self.current_holder.is_some() {
            return Ok(false);
        }
        self.current_holder = Some(std::process::id());
        Ok(true)
    }
}
```

**Client Usage**:
```rust
use zbus::blocking::Connection;

pub fn perform_update(image: &str) -> Result<(), Box<dyn std::error::Error>> {
    let conn = Connection::session()?;
    let proxy = conn.entry("com.example.BootcUpdate")?;
    
    if !proxy.acquire_lock()? {
        return Err("Update already in progress".into());
    }
    
    // Perform update...
    
    proxy.release_lock()?;
    Ok(())
}
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| IPC | ★★★★★ | Native inter-process communication |
| Policy | ★★★★★ | Can enforce authorization policies |
| Observability | ★★★★★ | D-Bus monitoring available |
| Ecosystem | ★★★☆☆ | Requires D-Bus setup |

**Trade-offs**:
- ✅ Standard Linux IPC mechanism
- ✅ Built-in authorization support
- ✅ Well-monitored (dbus-monitor)
- ✅ PolicyKit integration possible
- ❌ Complex setup and configuration
- ❌ Not available on all systems

---

### Solution 5: PostgreSQL Advisory Locks (For Centralized Systems)

**Mechanism**: Database-backed locking for systems with central coordination.

```rust
use tokio_postgres::NoTls;
use tokio::sync::Mutex;

pub struct DbLockManager {
    pool: deadpool_postgres::Pool,
}

impl DbLockManager {
    pub async fn acquire_update_lock(&self) -> Result<bool, Error> {
        let client = self.pool.get().await?;
        
        // PostgreSQL advisory lock with key 12345
        let result = client
            .query_one("SELECT pg_try_advisory_lock(12345)", &[])
            .await?;
        
        Ok(result.get(0))
    }
    
    pub async fn release_update_lock(&self) -> Result<(), Error> {
        let client = self.pool.get().await?;
        
        client
            .execute("SELECT pg_advisory_unlock(12345)", &[])
            .await?;
        
        Ok(())
    }
}
```

**With State Machine**:
```sql
-- State table for update operations
CREATE TABLE update_operations (
    id SERIAL PRIMARY KEY,
    state VARCHAR(20) NOT NULL DEFAULT 'idle',
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    CONSTRAINT valid_state CHECK (state IN ('idle', 'updating', 'rollback', 'completed', 'failed'))
);

-- Exclusive state transition
CREATE OR REPLACE FUNCTION start_update()
RETURNS BOOLEAN AS $$
DECLARE
    can_start BOOLEAN;
BEGIN
    -- Only allow if idle
    SELECT state = 'idle' INTO can_start
    FROM update_operations
    ORDER BY id DESC
    LIMIT 1 FOR UPDATE;
    
    IF can_start THEN
        INSERT INTO update_operations (state, started_at)
        VALUES ('updating', NOW());
        RETURN TRUE;
    END IF;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| Centralization | ★★★★★ | Single source of truth |
| Transactions | ★★★★★ | Full ACID guarantees |
| Auditability | ★★★★★ | Complete operation history |
| Complexity | ★★☆☆☆ | Requires database infrastructure |

**Trade-offs**:
- ✅ Complete audit trail
- ✅ Transactional consistency
- ✅ Works across distributed systems
- ❌ Requires database infrastructure
- ❌ Network dependency for locking
- ❌ Added complexity and cost

---

### Solution 6: etcd/Consul Distributed Locking (For Clusters)

**Mechanism**: Distributed coordination for multi-node systems.

```rust
use etcd_client::{Client, LockOptions};

pub struct DistributedLockManager {
    client: Client,
}

impl DistributedLockManager {
    pub async fn acquire_lock(&self, ttl_secs: u64) -> Result<LockToken> {
        let lock = self.client.lock(
            "bootc-update",
            LockOptions::new().with_ttl(ttl_secs),
        ).await?;
        
        Ok(LockToken(lock.key().to_string()))
    }
    
    pub async fn release_lock(&self, token: LockToken) -> Result<()> {
        self.client.unlock(token.0).await?;
        Ok(())
    }
}
```

| Aspect | Rating | Notes |
|--------|--------|-------|
| Distribution | ★★★★★ | Works across nodes |
| High Availability | ★★★★★ | Consensus-based |
| Complexity | ★★☆☆☆ | Requires cluster setup |
| Latency | ★★★☆☆ | Network round-trips |

**Trade-offs**:
- ✅ Works in distributed/clustered environments
- ✅ High availability with consensus
- ✅ Automatic leader election
- ❌ Complex infrastructure
- ❌ Network dependency
- ❌ Potential split-brain scenarios

---

## Evaluation Matrix

| Solution | Simplicity | Robustness | Testing | Persistence | Multi-process | Distributed |
|----------|------------|------------|---------|--------------|---------------|-------------|
| **1. flock** | ★★★★★ | ★★★☆☆ | ★★★☆☆ | ★☆☆☆☆ | ★★★★☆ | ★☆☆☆☆ |
| **2. systemd-native** | ★★★★☆ | ★★★★☆ | ★★★☆☆ | ★★☆☆☆ | ★★★★☆ | ★☆☆☆☆ |
| **3. State Machine (Rust)** | ★★★★☆ | ★★★★★ | ★★★★★ | ★★★★☆ | ★★☆☆☆ | ★☆☆☆☆ |
| **4. D-Bus** | ★★★☆☆ | ★★★★☆ | ★★★☆☆ | ★★★★☆ | ★★★★★ | ★★☆☆☆ |
| **5. PostgreSQL** | ★★☆☆☆ | ★★★★★ | ★★★★☆ | ★★★★★ | ★★★★★ | ★★★☆☆ |
| **6. etcd/Consul** | ★★☆☆☆ | ★★★★★ | ★★★★☆ | ★★★★★ | ★★★★★ | ★★★★★ |

---

## Recommendations

### For Single-Device bootc Systems

**Recommended**: **Solution 3 (Rust State Machine) + Solution 1 (flock fallback)**

**Rationale**: Most nornnet clients are single devices without centralized coordination. A Rust-based state machine provides:
- Fine-grained control over update/rollback state transitions
- Async operation support for non-blocking updates
- Easy testability with mocked time and state
- Persistence across restarts

**Implementation Pattern**:
```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio::time::{timeout, Duration};

// Protected by file lock at systemd service level
// + async mutex for in-process safety
pub struct BootcUpdateManager {
    state: Arc<RwLock<UpdateState>>,
    state_file: PathBuf,
}

impl BootcUpdateManager {
    pub async fn begin_update(&self) -> Result<(), UpdateError> {
        // Check state
        let state = self.state.read().await;
        match *state {
            UpdateState::Idle => Ok(()),
            UpdateState::Updating => Err(UpdateError::UpdateInProgress),
            UpdateState::RollingBack => Err(UpdateError::RollbackInProgress),
            UpdateState::Degraded => Err(UpdateError::SystemDegraded),
        }
    }
}
```

### For Fleet Management Scenarios

**Recommended**: **Solution 5 (PostgreSQL) for coordination + Solution 3 (Rust) for local**

**Rationale**: When managing multiple devices:
- Central database tracks fleet-wide update state
- Each device runs local state machine
- Database provides global locking and audit trail
- Local state machine provides fast local decisions

---

## Trade-offs and Risks Summary

| Solution | Key Risk | Mitigation |
|----------|----------|------------|
| **flock** | Lock file orphans on crash | Add systemd service with cleanup |
| **systemd-native** | Reload required for changes | Version control service files |
| **State Machine** | In-process only | Combine with file lock |
| **D-Bus** | Not universally available | Graceful fallback |
| **PostgreSQL** | Network dependency | Local SQLite cache |
| **etcd/Consul** | Split-brain potential | Quorum requirements |

---

## Testing Strategy

### Unit Testing State Machine
```rust
#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_concurrent_update_rejection() {
        let manager = UpdateManager::new().await;
        
        // First update should succeed
        manager.begin_update().await.unwrap();
        
        // Second concurrent update should fail
        let result = manager.begin_update().await;
        assert!(matches!(result, Err(UpdateError::UpdateInProgress)));
        
        // Complete first update
        manager.complete(true).await;
        
        // Now second update should succeed
        manager.begin_update().await.unwrap();
    }
}
```

### Integration Testing with testcontainers
```rust
#[tokio::test]
async fn test_fleet_concurrent_update() {
    // Spin up test PostgreSQL
    let _postgres = Container::postgresql().start().await;
    
    // Create multiple "devices"
    let devices: Vec<UpdateManager> = (0..3)
        .map(|_| create_manager())
        .collect();
    
    // Attempt concurrent updates
    let results: Vec<bool> = futures::future::join_all(
        devices.iter().map(|d| d.begin_update())
    ).await;
    
    // Only one should succeed
    assert_eq!(results.iter().filter(|&&r| r).count(), 1);
}
```

---

## Fit Score with Project Context

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| **Rust-based project** | 5/5 | Native fit for Solution 3 |
| **Single-device focus** | 5/5 | Solutions 1-3 are optimal |
| **systemd integration** | 5/5 | Solution 2 aligns with project |
| **Minimal dependencies (CC-5)** | 5/5 | Solutions 1-3 have minimal deps |
| **Testing requirements** | 5/5 | State machine approach is testable |
| **Transactional integrity (CC-2)** | 5/5 | State machine enforces atomicity |

---

## Implementation Recommendation

**Primary**: **Hybrid Approach combining Solution 2 + Solution 3**

1. **Systemd service level** (Solution 2):
   - `bootc-update.service` with `flock` protection
   - Prevents multiple service invocations
   - Provides journal logging and restart on failure

2. **Application level** (Solution 3):
   - Rust state machine for fine-grained control
   - Persisted state for crash recovery
   - Async-friendly for API responsiveness

3. **Optional PostgreSQL** (Solution 5):
   - For fleet-wide coordination
   - Centralized audit trail
   - Global locking across devices

This approach provides defense in depth while maintaining simplicity for the common single-device case.

---

## References

- [systemd.service(5)](https://www.freedesktop.org/software/systemd/man/systemd.service.html) - Type=oneshot, RemainAfterExit
- [flock(1)](https://man7.org/linux/man-pages/man1/flock.1.html) - Advisory file locking
- [tokio::sync](https://docs.rs/tokio/latest/tokio/sync/) - Async synchronization primitives
- [bootc documentation](https://github.com/containers/bootc) - Container-based OS updates
- [PostgreSQL Advisory Locks](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS) - Database locking
