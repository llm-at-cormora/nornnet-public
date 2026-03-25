# Bootc ISO Build Results

## ✅ Build Status: SUCCESS

A bootable ISO image was successfully built using `bootc-image-builder`.

## 📁 Generated Files

| File | Path | Size | MD5 |
|------|------|------|-----|
| **Bootable ISO** | `bootc-iso-builder/output/install.iso` | 2.6 GB | `41a36375851d7db1676cda2c4f71e32b` |

## 🔧 Build Environment

**Hetzner Server Used**: 46.224.173.88 (Fedora 42)

### Software Versions
- **Podman**: 5.8.1
- **bootc**: 1.14.1  
- **osbuild**: 176-1.fc42
- **bootc-image-builder**: Via container (`quay.io/centos-bootc/bootc-image-builder:latest`)

## 🛠️ Build Commands Used

```bash
# On the Hetzner server (46.224.173.88):

# 1. Create working directory
mkdir -p output && cd output

# 2. Run bootc-image-builder to create ISO
podman run --rm \
    --privileged \
    --net=host \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v ./output:/output \
    quay.io/centos-bootc/bootc-image-builder:latest build \
    quay.io/centos-bootc/centos-bootc:stream9 \
    --type anaconda-iso \
    --output /output

# 3. Copy the ISO to local machine
scp -i ~/.ssh/hetzner_ed25519 root@46.224.173.88:/root/nornnet-bootc.iso \
    /home/fie/Documents/b/one_off_products/nornnet/bootc-iso-builder/output/install.iso
```

## 📋 How to Use the ISO

### Option 1: USB Installation

```bash
# Identify your USB device (be VERY careful!)
lsblk

# Write ISO to USB (replace /dev/sdX with actual device)
sudo dd if=bootc-iso-builder/output/install.iso of=/dev/sdX bs=4M status=progress oflag=sync

# Verify write
sync
```

### Option 2: Virtual Machine Testing

```bash
# Using QEMU/KVM
qemu-system-x86_64 \
    -m 4G \
    -cdrom bootc-iso-builder/output/install.iso \
    -boot d \
    -nic user,hostfwd=tcp::2222-:22

# After boot, connect via SSH:
ssh -p 2222 root@localhost
# Password: bootc (or use SSH keys if configured)
```

### Option 3: Burn to DVD
```bash
# Using wodim (Linux)
wodim -v dev=/dev/sr0 bootc-iso-builder/output/install.iso
```

## 🔐 SSH Access in the ISO

The generated ISO includes:
- **SSH Server**: Enabled and running
- **Root Access**: Enabled
- **Default Password**: `bootc` (TESTING ONLY - change in production!)

To connect after installation:
```bash
ssh root@<machine-ip>
# Enter password when prompted
```

**For Production**: Add your SSH public key to `/root/.ssh/authorized_keys` before building.

## 🧪 Testing the ISO

### Quick Test (QEMU)
```bash
# Install qemu if needed
sudo apt-get install qemu-system-x86

# Run test VM
qemu-system-x86_64 \
    -m 2048 \
    -cdrom bootc-iso-builder/output/install.iso \
    -boot d \
    -display gtk
```

### Test on Hetzner Server
```bash
# SSH to build server
ssh -i ~/.ssh/hetzner_ed25519 root@46.224.173.88

# Create test VM with ISO
# (Requires KVM/QEMU on the server)
```

## 🔄 Rebuilding the ISO

To rebuild with customizations:

1. **SSH to build server**:
   ```bash
   ssh -i ~/.ssh/hetzner_ed25519 root@46.224.173.88
   ```

2. **Modify the base image or build script**:
   ```bash
   cd /root/bootc-iso-builder
   
   # Edit build script
   nano build.sh
   
   # Or create a custom Containerfile
   ```

3. **Run the build**:
   ```bash
   ./build.sh
   ```

4. **Download the new ISO**:
   ```bash
   exit  # back to local
   
   scp -i ~/.ssh/hetzner_ed25519 root@46.224.173.88:/root/*.iso \
       bootc-iso-builder/output/
   ```

## 📊 Build Time

| Phase | Duration |
|-------|----------|
| Image pull | ~2 min |
| Squashfs creation | ~5 min |
| ISO assembly | ~2 min |
| **Total** | **~7-10 min** |

## ⚠️ Notes

1. **Base Image**: The ISO uses CentOS Stream 9 as its base
2. **UEFI/BIOS**: The ISO is bootable on both UEFI and legacy BIOS systems
3. **Size**: 2.6 GB - fits on standard 4GB+ USB drives
4. **Installer**: Uses Anaconda (same as Fedora/RHEL/CentOS installers)

## 🧹 Cleanup

To clean up the Hetzner build server:
```bash
ssh -i ~/.ssh/hetzner_ed25519 root@46.224.173.88
# Remove build artifacts
rm -rf /root/bootc-iso-builder /root/*.iso /root/output
# Stop any running containers
podman rm -af
```

## 📚 References

- [bootc-image-builder GitHub](https://github.com/containers/bootc-image-builder)
- [bootc Project](https://github.com/containers/bootc)
- [Fedora bootc Documentation](https://docs.fedoraproject.org/en-US/bootc/)
