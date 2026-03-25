# Bootc ISO Builder

This directory contains files for building bootable bootc ISO images using `bootc-image-builder`.

## Overview

`bootc-image-builder` is a tool for creating bootable system images from container images. It can generate:
- Anaconda ISOs (for installation)
- Disk images (qcow2, raw, vhd)
- Container images

## Requirements

### For Local Building (Fedora/RHEL/CentOS)
- Fedora 38+ or RHEL 9+ or CentOS Stream 9
- `bootc-image-builder` package
- `podman` with v5+ and CRIU support
- Sufficient disk space (~50GB recommended)

### For Container-Based Building
- Podman with v5+ (may work on any Linux distribution)
- Access to `/var/lib/containers/storage` (rootless or rootful)

## Quick Start

### Option 1: Using the Build Script

```bash
cd bootc-iso-builder
./build.sh
```

### Option 2: Manual Build

```bash
# Pull the base image
podman pull quay.io/centos-bootc/centos-bootc:stream9

# Run bootc-image-builder
podman run --rm \
    --privileged \
    --net=host \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v ./output:/output \
    -e IMAGE=quay.io/centos-bootc/centos-bootc:stream9 \
    -e TAG=latest \
    -e TYPE=anaconda-iso \
    quay.io/centos-bootc/bootc-image-builder:latest
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BASE_IMAGE` | Base bootc image to use | `quay.io/centos-bootc/centos-bootc:stream9` |
| `TARGET_IMAGE_NAME` | Name for customized image | `custom-bootc` |
| `CONTAINER_ENGINE` | Container runtime | `podman` |
| `OS_RELEASE_ID` | OS identifier for Anaconda | `centos` |

### SSH Access Configuration

SSH is configured to allow root login for testing purposes. **For production, use SSH keys instead.**

To configure SSH keys, edit `ks.cfg` and replace `PLACEHOLDER_SSH_KEY` with your public key.

## Output

Generated ISOs will be placed in the `output/` directory.

## Using the Generated ISO

### For Installation
1. Write the ISO to a USB drive: `dd if=output/*.iso of=/dev/sdX bs=4M status=progress`
2. Boot the target machine from the USB
3. Follow the Anaconda installer prompts

### For Virtual Machine Testing
```bash
# Using qemu
qemu-system-x86_64 \
    -m 4G \
    -cdrom output/*.iso \
    -boot d \
    -nic user,hostfwd=tcp::2222-:22
```

Connect via SSH: `ssh -p 2222 root@localhost`

## Troubleshooting

### "Image type anaconda-iso is not supported"
You need a newer version of bootc-image-builder or a different base image.

### "Cannot connect to storage"
Ensure podman has access to `/var/lib/containers/storage`.

### Build fails with SELinux errors
Either disable SELinux or ensure proper labels: `setsebool -P container_use_cephfs 1`

## References

- [bootc-image-builder GitHub](https://github.com/containers/bootc-image-builder)
- [bootc project](https://github.com/containers/bootc)
- [Fedora bootc documentation](https://docs.fedoraproject.org/en-US/bootc/)
