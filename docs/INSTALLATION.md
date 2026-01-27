# Installation Guide

Complete installation guide for Waydroid LXC on Proxmox with Intel N150 SoC.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Post-Installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Hardware Requirements

- **CPU**: Any x86_64 CPU (Intel N150 optimized)
- **GPU**: Intel (recommended), AMD, or software rendering
  - NVIDIA GPUs use software rendering only
- **RAM**: Minimum 4GB (8GB recommended)
- **Storage**: 20GB free space for LXC container
- **Proxmox**: Version 8.x or 9.x

### Software Requirements

- Proxmox VE installed and running
- Root access to Proxmox host
- Network connectivity for downloading packages

### Kernel Requirements

Your Proxmox host kernel must support:
- Binder modules (`binder_linux`)
- Ashmem modules (`ashmem_linux`)
- GPU drivers (i915 for Intel, amdgpu for AMD)
- IPv6 (even if not used, required for Android networking)

Check your kernel:
```bash
uname -r
# Should be 5.15 or newer
```

## Quick Start

For experienced users, run these commands on your Proxmox host:

```bash
# Clone the repository
git clone https://github.com/MvRoo/waydroid-proxmox.git
cd waydroid-proxmox

# Make scripts executable
chmod +x install/install.sh scripts/*.sh

# Optional: Configure Intel GPU (Intel users only)
./scripts/configure-intel-n150.sh

# Run interactive installer
./install/install.sh
```

The installer will prompt you for:
- **Container Type**: Privileged or Unprivileged
- **GPU Type**: Intel, AMD, NVIDIA, or Software rendering
- **GAPPS**: Install Google Play Store (yes/no)

## Detailed Installation

### Step 1: Prepare Proxmox Host

First, ensure your Proxmox host has the required kernel modules and GPU configuration.

#### 1.1 Check Your GPU Type

**Intel GPU:**
```bash
lspci | grep -i "VGA.*Intel"
```

**AMD GPU:**
```bash
lspci | grep -i "VGA.*AMD\|VGA.*Radeon"
```

**NVIDIA GPU:**
```bash
lspci | grep -i "VGA.*NVIDIA"
```
*Note: NVIDIA GPUs will use software rendering*

#### 1.2 Check GPU Devices (Intel/AMD only)

```bash
ls -la /dev/dri/
```

Expected output:
```
card0
renderD128
```

#### 1.3 Configure Intel GPU (Intel Users Only)

If you have an Intel GPU, run the configuration script:

```bash
cd waydroid-proxmox
chmod +x scripts/configure-intel-n150.sh
./scripts/configure-intel-n150.sh
```

This script will:
- Load required kernel modules (`binder_linux`, `ashmem_linux`, `i915`)
- Configure i915 module parameters for optimal performance
- Set up udev rules for GPU device permissions
- Configure modules to load automatically on boot

**Important**: If this is the first time configuring i915, reboot your Proxmox host:

```bash
reboot
```

#### 1.4 AMD GPU Configuration

For AMD GPUs, no special configuration is needed on the host. The installer will automatically configure the container.

### Step 2: Install Waydroid LXC

After the host is configured (and rebooted if necessary), install the LXC container.

#### 2.1 Run Installation Script

```bash
cd waydroid-proxmox
chmod +x install/install.sh
./install/install.sh
```

The installation script will:
1. Check for Intel GPU
2. Download Debian 12 template (if not present)
3. Create LXC container with GPU passthrough
4. Configure container for Waydroid
5. Install Waydroid, Wayland compositor, and VNC server
6. Set up Home Assistant API
7. Create systemd services

**Installation takes 10-15 minutes** depending on your internet connection.

#### 2.2 Installation Output

Upon successful installation, you'll see:

```
═══════════════════════════════════════════════
Waydroid LXC Successfully Installed!
═══════════════════════════════════════════════

Container Details:
  CTID: 100
  IP Address: 192.168.1.100
  Hostname: waydroid

Access Information:
  VNC: 192.168.1.100:5900
  Home Assistant API: http://192.168.1.100:8080
```

Note the CTID (Container ID) and IP address for future reference.

### Step 3: Start Services

Enter the container:

```bash
pct enter 100  # Replace 100 with your CTID
```

Inside the container, start the services:

```bash
# Start Waydroid with VNC
systemctl start waydroid-vnc
systemctl enable waydroid-vnc

# Start Home Assistant API
systemctl start waydroid-api
systemctl enable waydroid-api
```

### Step 4: Initialize Waydroid

The first time Waydroid starts, it will automatically initialize and download Android images (~500MB). This happens automatically when you start the `waydroid-vnc` service.

To manually initialize:

```bash
waydroid init -s GAPPS -f
```

Options:
- `-s GAPPS`: Install Google Apps (Play Store, etc.)
- `-f`: Force reinitialization

## Post-Installation

### Access Waydroid via VNC

Use any VNC client to connect:

```
Host: <container-ip>:5900
Password: (none - no authentication by default)
```

Recommended VNC clients:
- **Windows**: TigerVNC, RealVNC
- **macOS**: Screen Sharing (built-in)
- **Linux**: Remmina, TigerVNC
- **Web**: noVNC (can be set up separately)

### Verify Installation

Run the test script inside the container:

```bash
pct enter 100  # Replace with your CTID
cd /root
./test-setup.sh  # If copied to container
```

Or manually check:

```bash
# Check GPU access
ls -la /dev/dri/

# Check Waydroid status
waydroid status

# Check services
systemctl status waydroid-vnc
systemctl status waydroid-api
```

### Install Android Apps

Connect via VNC, then use one of these methods:

#### Method 1: Google Play Store (if GAPPS installed)

1. Connect via VNC
2. Open Google Play Store
3. Sign in with Google account
4. Install apps normally

#### Method 2: ADB (Android Debug Bridge)

From the container:

```bash
# Install ADB
apt-get install -y adb

# Connect to Waydroid
adb connect localhost:5555

# Install APK
adb install app.apk
```

#### Method 3: Command Line

```bash
# Launch Play Store
waydroid app launch com.android.vending

# Install APK
waydroid app install app.apk
```

## Troubleshooting

### Container won't start

**Symptom**: `pct start` fails

**Solution**:
```bash
# Check container configuration
cat /etc/pve/lxc/<ctid>.conf

# Check kernel modules on host
lsmod | grep binder
lsmod | grep ashmem

# Reload modules
modprobe -r binder_linux ashmem_linux
modprobe binder_linux ashmem_linux
```

### No GPU access in container

**Symptom**: `/dev/dri/` is empty in container

**Solution**:
```bash
# On Proxmox host, check devices
ls -la /dev/dri/

# Check container config
grep -A 5 "GPU Passthrough" /etc/pve/lxc/<ctid>.conf

# Restart container
pct stop <ctid>
pct start <ctid>
```

### Waydroid fails to start

**Symptom**: `waydroid status` shows errors

**Solution**:
```bash
# Check logs
journalctl -u waydroid-container -f

# Reinitialize Waydroid
waydroid init -f

# Check GPU in container
ls -la /dev/dri/
groups  # Should include 'render' and 'video'
```

### VNC not accessible

**Symptom**: Cannot connect to VNC

**Solution**:
```bash
# Check if service is running
systemctl status waydroid-vnc

# Check if port is listening
netstat -tuln | grep 5900

# Check firewall (if enabled)
iptables -L -n | grep 5900

# Restart service
systemctl restart waydroid-vnc
```

### API not responding

**Symptom**: API endpoints return errors

**Solution**:
```bash
# Check service
systemctl status waydroid-api

# Check logs
journalctl -u waydroid-api -f

# Test manually
python3 /usr/local/bin/waydroid-api.py

# Restart service
systemctl restart waydroid-api
```

### Black screen in VNC

**Symptom**: VNC connects but shows black screen

**Solution**:
```bash
# Check compositor
ps aux | grep sway

# Restart Waydroid services
systemctl restart waydroid-vnc

# Check Wayland display
echo $WAYLAND_DISPLAY

# Check logs
journalctl -xe
```

## Next Steps

- [Configuration Guide](CONFIGURATION.md) - Customize your setup
- [Home Assistant Integration](HOME_ASSISTANT.md) - Automate with HA
- [Performance Tuning](PERFORMANCE.md) - Optimize for your use case

## Support

- **Issues**: [GitHub Issues](https://github.com/MvRoo/waydroid-proxmox/issues)
- **Documentation**: [Full docs](https://github.com/MvRoo/waydroid-proxmox/docs)
- **Waydroid Docs**: [Official Waydroid Documentation](https://docs.waydro.id)
