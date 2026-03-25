# Testing Infrastructure

This directory contains the test suite for nornnet.

## Directory Structure

```
tests/
├── bats/                    # Bats testing framework helpers
│   ├── common.bash          # Common test utilities
│   ├── fixtures.bash        # Test fixtures
│   ├── ci_helpers.bash      # CI/CD integration helpers
│   └── bootc_helpers.bash   # Bootc device testing helpers
├── acceptance/               # Acceptance tests
│   ├── device-deployment.bats   # US4: Device Deployment tests
│   └── update-detection.bats    # US5: Update Detection tests
└── README.md                # This file
```

## Running Tests

### All Tests

```bash
bats tests/acceptance/
```

### Individual Test Files

```bash
bats tests/acceptance/device-deployment.bats
bats tests/acceptance/update-detection.bats
```

### With Detailed Output

```bash
bats --pretty tests/acceptance/
```

## Environment Variables for Bootc Device Testing

These tests require a bootc-managed device to run fully. The following environment variables control how tests connect to the device.

### Required for Bootc Device Tests

| Variable | Description |
|----------|-------------|
| `BOOTC_DEVICE_HOST` | IP address or hostname of a device booted via bootc. This is the primary variable for dedicated bootc testing. |
| `BOOTC_DEVICE_SSH_KEY` | SSH private key for authenticating to the bootc device (optional, falls back to `DEVICE_SSH_KEY`) |

### Legacy/Alternative Variables

| Variable | Description |
|----------|-------------|
| `DEVICE_HOST` | Alternative to `BOOTC_DEVICE_HOST` (checked second) |
| `HETZNER_SERVER_IP` | Alternative to `BOOTC_DEVICE_HOST` (checked third) |
| `DEVICE_SSH_KEY` | SSH private key (used as fallback for `BOOTC_DEVICE_SSH_KEY`) |

### Example: Running with Dedicated Bootc Server

```bash
export BOOTC_DEVICE_HOST=192.168.1.100
export BOOTC_DEVICE_SSH_KEY=~/.ssh/bootc_ed25519
bats tests/acceptance/device-deployment.bats
```

### Example: Running with Hetzner Server (if booted via bootc)

```bash
export HETZNER_SERVER_IP=192.168.1.50
export DEVICE_SSH_KEY=~/.ssh/hetzner_ed25519
bats tests/acceptance/
```

## Test Behavior

### When No Bootc Device is Configured

Tests will **skip** with a message like:

```
Bootc device not configured. Set BOOTC_DEVICE_HOST (and optionally BOOTC_DEVICE_SSH_KEY) to run these tests.
```

### When Device Exists but is Not Booted via Bootc

Individual tests will **skip** with:

```
Device is not booted via bootc. These tests require a system booted via bootc (bootc-installed system).
```

### When a Proper Bootc Device is Available

**All tests run fully** without skips, testing:
- Device connectivity and bootc availability
- Image deployment via `bootc switch`
- Update detection via `bootc update --check`
- Status reporting and rollback capabilities

## Acceptance Test Coverage

### US4: Device Deployment (device-deployment.bats)

- **AC4.1**: Deploy image from registry to device
  - Device can run bootc status before deployment
  - bootc switch deploys image from registry
  - Deployment reports progress during download
  - Deployment handles authentication for private registry

- **AC4.2**: Verify deployment completed successfully
  - bootc status shows current image after deployment
  - bootc status shows image digest
  - Device shows rollback capable status

- **AC4.3**: Deployment leaves system in consistent state
  - Device boots successfully after deployment
  - Deployment creates rollback entry
  - System journal shows successful deployment
  - Transaction log records deployment

### US5: Update Detection (update-detection.bats)

- **AC5.1**: Detect new version available
  - bootc update check queries registry for new version
  - Update available message when new version exists
  - Update check reports correct version number
  - Update detection uses configured image reference

- **AC5.2**: Report no updates when on latest
  - Update check reports no updates when current
  - Version comparison works correctly
  - Periodic update check can be scheduled

- **AC5.3**: Query available versions correctly
  - Can list all available versions from registry
  - Latest version is correctly identified
  - Version comparison is semantically correct
  - Update detection respects configured version tag
  - Rollback version is available when newer deployed

## Helper Functions

The `tests/bats/bootc_helpers.bash` module provides:

| Function | Description |
|----------|-------------|
| `bootc_device_host` | Get the configured bootc device IP |
| `bootc_device_ssh_key` | Get the configured SSH key |
| `bootc_ssh_opts` | Get SSH connection options string |
| `bootc_ssh <cmd>` | Execute command on bootc device |
| `bootc_device_configured` | Check if bootc device is configured |
| `bootc_is_bootc_system` | Check if device is booted via bootc |
| `bootc_status` | Get bootc status JSON |
| `bootc_skip_if_not_configured` | Skip test if no device configured |
| `bootc_skip_if_not_bootc_system` | Skip test if not booted via bootc |
| `bootc_skip_if_unavailable` | Combined skip check |
