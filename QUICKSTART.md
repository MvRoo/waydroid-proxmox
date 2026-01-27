# Waydroid Proxmox Quick Start Guide

Get Android running on Proxmox in 5, 10, or 30 minutes depending on your needs.

---

## ⚠️ IMPORTANT: Debian 13 (Trixie) Recommended

**For VNC Access:** Use **Debian 13 (Trixie)** containers instead of Debian 12 (Bookworm).

**Why?** Debian 12's WayVNC 0.5.0 with neatvnc 0.5.4 has authentication issues that prevent VNC connections. Debian 13 includes WayVNC 0.8.0+ and neatvnc 0.8.1+ which:
- ✅ Properly support `enable_auth=false` for passwordless VNC
- ✅ Fix CVE-2024-42458 (critical authentication bypass vulnerability)
- ✅ Work with standard VNC clients (TigerVNC, RealVNC, etc.)

**See:** [DEBIAN-13-MIGRATION.md](DEBIAN-13-MIGRATION.md) for migration guide and details.

**If you're on Debian 12 and experiencing "No matching security types" VNC errors:**
- Read [HANDOVER.md](HANDOVER.md) for root cause analysis
- Follow [DEBIAN-13-MIGRATION.md](DEBIAN-13-MIGRATION.md) to migrate

---

## Table of Contents

- [5-Minute Quick Start](#5-minute-quick-start)
- [10-Minute Setup (with GPU)](#10-minute-setup-with-gpu-acceleration)
- [30-Minute Complete Setup](#30-minute-complete-setup)
- [Common Use Cases](#common-use-cases)
- [Troubleshooting Quick Reference](#troubleshooting-quick-reference)
- [Command Cheat Sheet](#command-cheat-sheet)

---

## 5-Minute Quick Start

**Goal**: Get Waydroid running with minimal configuration (software rendering, no extras)

### Prerequisites
- Proxmox VE 7.x or 8.x installed
- SSH access to Proxmox host
- 20GB free storage, 4GB RAM

### Steps

```bash
# 1. SSH to your Proxmox host
ssh root@your-proxmox-ip

# 2. Clone the repository
cd /tmp
git clone https://github.com/MvRoo/waydroid-proxmox.git
cd waydroid-proxmox

# 3. Make scripts executable
chmod +x install/install.sh scripts/*.sh

# 4. Run the installer (answer prompts as shown below)
./install/install.sh
```

**Installer Prompts** (5-minute setup):
- Container type? → `Unprivileged` (press `2`)
- GPU type? → `Software rendering` (press `4`)
- Install GAPPS? → `no` (press `n`)

**That's it!** Your container will be created in ~3-5 minutes.

### Access Your Android

```bash
# Find your container IP (look for "IP:" in output)
pct exec <CTID> -- ip addr show eth0 | grep inet

# Connect via VNC (use any VNC viewer)
# Host: <container-ip>:5900
# Password: (none - press enter)
```

**Next Steps**: See [Common Use Cases](#common-use-cases) to start using Android.

---

## 10-Minute Setup (with GPU Acceleration)

**Goal**: Hardware-accelerated Android with GPU passthrough

### What You'll Get
- Full GPU acceleration (Intel/AMD)
- Smooth graphics performance
- Google Play Store support
- Remote VNC access

### Prerequisites
- Intel or AMD GPU (check: `lspci | grep -i vga`)
- Proxmox host kernel 5.15+

### Steps

#### Step 1: Configure Host (Intel GPU only - 2 minutes)

```bash
# SSH to Proxmox host
ssh root@your-proxmox-ip
cd /tmp/waydroid-proxmox

# Check if you have Intel GPU
lspci | grep -i "VGA.*Intel"

# If YES, configure it (AMD users skip this)
./scripts/configure-intel-n150.sh

# If this is first time, reboot
reboot
```

Wait for Proxmox to restart, then SSH back in.

#### Step 2: Install Container (5 minutes)

```bash
cd /tmp/waydroid-proxmox

# Run installer
./install/install.sh
```

**Installer Prompts** (10-minute setup):
- Container type? → `Privileged` (press `1`) - **Required for GPU**
- GPU type? → `Intel` or `AMD` (press `1` or `2`)
- Install GAPPS? → `yes` (press `y`) - **For Play Store**

Installation takes ~5 minutes (downloads Android + GAPPS).

#### Step 3: Access & Verify (2 minutes)

```bash
# Get container IP
pct exec <CTID> -- hostname -I

# Connect via VNC
# Use TigerVNC, RealVNC, or any VNC client
# Host: <container-ip>:5900
```

**Verify GPU is working**:
```bash
# Inside VNC, open terminal or via SSH
pct enter <CTID>

# Check GPU access
ls -la /dev/dri/
# Should see: card0, renderD128

# Check Waydroid is using GPU
waydroid status
# Should show: Session: RUNNING, Container: RUNNING
```

**You're done!** Android is running with GPU acceleration.

---

## 30-Minute Complete Setup

**Goal**: Production-ready setup with all features enabled

### What You'll Get
- GPU acceleration
- Secure VNC with TLS encryption
- Audio passthrough
- Clipboard sharing (copy/paste between host and Android)
- Performance optimization
- Home Assistant API ready
- Monitoring and health checks

### Architecture Overview

```
┌─────────────────────────────────────────────────┐
│           Proxmox Host                          │
│  ┌───────────────────────────────────────────┐  │
│  │     Waydroid LXC Container                │  │
│  │                                           │  │
│  │  ┌──────────┐    ┌──────────────────┐    │  │
│  │  │   Sway   │◄──►│ WayVNC :5900     │────┼──┼─► VNC Clients
│  │  │Compositor│    │ (TLS Encrypted)   │    │  │   (TigerVNC, noVNC)
│  │  └────┬─────┘    └──────────────────┘    │  │
│  │       │                                   │  │
│  │  ┌────▼─────┐    ┌──────────────────┐    │  │
│  │  │ Waydroid │    │   REST API       │────┼──┼─► Home Assistant
│  │  │ Android  │    │   :8080          │    │  │
│  │  └────┬─────┘    └──────────────────┘    │  │
│  │       │                                   │  │
│  │  ┌────▼──────────────────────────────┐   │  │
│  │  │  GPU: /dev/dri/card0              │   │  │
│  │  │       /dev/dri/renderD128         │   │  │
│  │  └───────────────────────────────────┘   │  │
│  └───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────┘
```

### Installation Steps

#### Step 1: Prepare Host (5 minutes)

```bash
# SSH to Proxmox host
ssh root@your-proxmox-ip

# Clone repository
cd /tmp
git clone https://github.com/MvRoo/waydroid-proxmox.git
cd waydroid-proxmox
chmod +x install/install.sh scripts/*.sh

# For Intel GPU users - configure host
lspci | grep -i "VGA.*Intel" && ./scripts/configure-intel-n150.sh

# Reboot if Intel i915 was just configured
# (script will tell you if reboot is needed)
# reboot
```

#### Step 2: Install Waydroid (10 minutes)

```bash
cd /tmp/waydroid-proxmox
./install/install.sh
```

**Installer Prompts**:
- Container type? → `Privileged` (for GPU)
- GPU type? → `Intel`, `AMD`, or `Software rendering`
- Install GAPPS? → `yes` (for Play Store)

Wait for installation to complete (~8-10 minutes).

#### Step 3: Enhance VNC (3 minutes)

```bash
# Note your container ID from previous step (e.g., 100)
CTID=<your-container-id>

# Setup secure VNC with TLS, password, and performance tuning
./scripts/enhance-vnc.sh \
  --enable-tls \
  --fps 60 \
  --enable-monitoring \
  --install-novnc \
  $CTID

# Service will restart automatically
```

**Features enabled**:
- TLS encryption for secure remote access
- Password authentication (shown in output)
- 60 FPS for smooth graphics
- Connection monitoring and logging
- Web-based access via noVNC

#### Step 4: Setup Audio (2 minutes)

```bash
# Auto-detect and configure audio passthrough
./scripts/setup-audio.sh $CTID

# Test audio (optional)
./scripts/setup-audio.sh --test-only $CTID
```

#### Step 5: Setup Clipboard Sharing (2 minutes)

```bash
# Enable bidirectional clipboard
./scripts/setup-clipboard.sh $CTID

# Verify it's working
./scripts/setup-clipboard.sh --verify $CTID
```

#### Step 6: Optimize Performance (5 minutes)

```bash
# Analyze current configuration
./scripts/tune-lxc.sh --analyze-only $CTID

# Apply all optimizations
./scripts/tune-lxc.sh $CTID
```

**Optimizations applied**:
- CPU scheduling for Android workloads
- Memory management tuning
- I/O priority configuration
- Android-specific cgroup settings

#### Step 7: Verify & Test (3 minutes)

```bash
# Run comprehensive health check
pct enter $CTID
cd /root

# Check all services are running
systemctl status waydroid-vnc
systemctl status waydroid-api

# Verify GPU access
ls -la /dev/dri/

# Check Waydroid status
waydroid status

# Exit container
exit
```

### Access Your Complete Setup

**VNC Access** (Secure with TLS):
```bash
# Get container IP
pct exec $CTID -- hostname -I

# VNC with TLS (TigerVNC)
vncviewer -SecurityTypes VeNCrypt,TLSVnc <container-ip>:5900

# Web access (noVNC)
http://<container-ip>/
```

**API Access** (for Home Assistant):
```bash
# Test API
curl http://<container-ip>:8080/status
curl http://<container-ip>:8080/apps
```

### Optional: Install Apps (5 minutes)

```bash
# Enter container
pct enter $CTID

# Install apps via Play Store (connect via VNC)
# OR use automated installation:

# For Home Assistant dashboard:
/root/scripts/install-apps.sh install-batch /root/config/apps-homeassistant.yaml

# For surveillance cameras:
/root/scripts/install-apps.sh install-batch /root/config/apps-security.yaml
```

**Your production setup is complete!** 🎉

---

## Common Use Cases

### Use Case 1: Home Assistant Dashboard

**Scenario**: Display your Home Assistant dashboard on an Android tablet/kiosk app

#### Step-by-Step

```bash
# 1. Connect to Android via VNC
vncviewer <container-ip>:5900

# 2. Open Play Store in Android, install:
#    - "Home Assistant Companion"
#    - OR "Fully Kiosk Browser"

# 3. Configure the app with your HA URL
# 4. Set app to auto-start (in Android Settings > Apps > [app] > Autostart)
```

#### Home Assistant Integration

```yaml
# configuration.yaml
rest_command:
  waydroid_show_dashboard:
    url: "http://<container-ip>:8080/app/launch"
    method: POST
    headers:
      Content-Type: "application/json"
    payload: '{"package": "io.homeassistant.companion.android"}'

automation:
  - alias: "Show Dashboard on Motion"
    trigger:
      - platform: state
        entity_id: binary_sensor.front_door
        to: "on"
    action:
      - service: rest_command.waydroid_show_dashboard
```

**Resources**:
- [Full Home Assistant guide](docs/HOME_ASSISTANT.md)
- [API v3.0 documentation](API_IMPROVEMENTS_v3.0.md)

---

### Use Case 2: Surveillance Camera Apps

**Scenario**: Run Android-only camera apps (TinyCam, IP Webcam, etc.) for security monitoring

#### Step-by-Step

```bash
# 1. Install camera app
pct enter <CTID>

# Option A: Via Play Store (connect via VNC)
# Search for: "tinyCam Monitor" or "IP Webcam"

# Option B: Via APK
waydroid app install /path/to/camera-app.apk

# 2. Configure camera in Android app (via VNC)

# 3. Launch camera app on startup
cat > /etc/systemd/system/waydroid-camera.service <<EOF
[Unit]
Description=Auto-launch Camera App
After=waydroid-container.service
Requires=waydroid-container.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/waydroid app launch com.alexvas.dvr
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable waydroid-camera
systemctl start waydroid-camera

# 4. Stream camera view
# Access via VNC at: <container-ip>:5900
```

#### Embed in Home Assistant

```yaml
# Lovelace card (dashboard)
type: iframe
url: "http://<novnc-url>/?host=<container-ip>&port=5900&autoconnect=true"
aspect_ratio: 16:9
title: "Security Cameras"
```

#### Find Package Name

```bash
# Inside container
waydroid app list | grep -i camera

# Or via ADB
adb connect localhost:5555
adb shell pm list packages | grep camera
```

**Resources**:
- [App installation guide](docs/APP_INSTALLATION.md)

---

### Use Case 3: Gaming Setup

**Scenario**: Play Android games with GPU acceleration and low latency

#### Requirements
- GPU passthrough (Intel/AMD)
- Fast network (LAN recommended)
- 60 FPS VNC configuration

#### Step-by-Step

```bash
# 1. Ensure GPU acceleration is enabled
pct enter <CTID>
ls -la /dev/dri/  # Should show card0, renderD128

# 2. Optimize for gaming
exit  # Back to Proxmox host
./scripts/enhance-vnc.sh --fps 60 --preset gaming <CTID>
./scripts/tune-lxc.sh <CTID>

# 3. Increase container resources (optional)
pct set <CTID> --cores 4 --memory 4096
pct reboot <CTID>

# 4. Install games via Play Store or APK
pct enter <CTID>
# Connect via VNC, open Play Store
# Install: PUBG Mobile, Asphalt 9, etc.

# 5. Configure VNC client for best performance
# TigerVNC settings:
#   - Encoding: Tight
#   - Quality: High (9)
#   - Compression: Low (1-2)
```

#### Performance Tweaks

```bash
# Inside container
pct enter <CTID>

# Increase screen resolution (if needed)
waydroid prop set persist.waydroid.width 1920
waydroid prop set persist.waydroid.height 1080
systemctl restart waydroid-container

# Enable performance mode
waydroid prop set persist.sys.ui.hw 1
waydroid prop set debug.sf.hw 1

# Monitor performance
/root/scripts/monitor-performance.sh
```

**Expected Performance** (Intel N150 example):
- FPS: 55-60 in most games
- GPU: Full hardware acceleration
- Latency: <20ms on LAN

**Resources**:
- [Performance tuning guide](docs/LXC_TUNING.md)
- [VNC optimization](docs/VNC-ENHANCEMENTS.md)

---

### Use Case 4: Development & Testing

**Scenario**: Android app development and testing environment

#### Step-by-Step

```bash
# 1. Enable ADB access
pct enter <CTID>
apt-get update && apt-get install -y adb

# Enable ADB in Waydroid
waydroid prop set persist.waydroid.adb 1
systemctl restart waydroid-container

# 2. Connect ADB (from inside container)
adb connect localhost:5555
adb devices  # Should show device

# 3. Install development tools
apt-get install -y python3 python3-pip git

# 4. Access ADB from Proxmox host (optional)
exit  # Back to host
# Forward ADB port
pct exec <CTID> -- iptables -t nat -A PREROUTING -p tcp --dport 5555 -j ACCEPT

# Connect from host
adb connect <container-ip>:5555
```

#### Testing APKs

```bash
# From your development machine
adb connect <container-ip>:5555
adb install -r myapp.apk
adb shell am start -n com.myapp/.MainActivity

# View logs
adb logcat | grep MyApp

# Screenshots
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png
```

#### Automated Testing

```bash
# Inside container - create test script
cat > /root/test-app.sh <<'EOF'
#!/bin/bash
APP_PACKAGE="com.example.myapp"
APP_ACTIVITY=".MainActivity"

# Install app
adb install -r /root/apps/myapp.apk

# Launch app
adb shell am start -n ${APP_PACKAGE}/${APP_ACTIVITY}

# Run UI tests
sleep 5
adb shell input tap 500 800  # Tap button
sleep 2
adb shell input text "Test input"
adb shell input keyevent 66  # Enter

# Take screenshot
adb shell screencap -p /sdcard/test_result.png
adb pull /sdcard/test_result.png /root/test_results/

# Get logs
adb logcat -d > /root/test_results/logcat.txt
EOF

chmod +x /root/test-app.sh
```

#### CI/CD Integration

```yaml
# .github/workflows/android-test.yml
name: Android Test on Waydroid

on: [push]

jobs:
  test:
    runs-on: self-hosted
    steps:
      - name: Install APK
        run: |
          adb connect waydroid-container:5555
          adb install -r app/build/outputs/apk/debug/app-debug.apk

      - name: Run Tests
        run: |
          adb shell am start -n com.myapp/.MainActivity
          adb shell input tap 500 800
          sleep 5

      - name: Collect Results
        run: |
          adb shell screencap -p /sdcard/result.png
          adb pull /sdcard/result.png ./test-results/
```

**Resources**:
- [ADB documentation](https://developer.android.com/studio/command-line/adb)
- [Waydroid testing guide](https://docs.waydro.id)

---

## Troubleshooting Quick Reference

### Quick Diagnostic Commands

```bash
# 1. Check container status
pct status <CTID>

# 2. Check services inside container
pct enter <CTID>
systemctl status waydroid-vnc
systemctl status waydroid-api
systemctl status waydroid-container

# 3. View logs
journalctl -u waydroid-container -f
journalctl -u waydroid-vnc -f

# 4. Check GPU access
ls -la /dev/dri/

# 5. Network connectivity
ip addr show eth0
ping -c 3 8.8.8.8
```

---

### Common Issues & Fixes

#### Issue 1: Container Won't Start

**Symptoms**: `pct start` fails with error

**Quick Fix**:
```bash
# Check kernel modules on Proxmox host
lsmod | grep binder
lsmod | grep ashmem

# If missing, load them
modprobe binder_linux ashmem_linux

# Make persistent
echo "binder_linux" >> /etc/modules-load.d/waydroid.conf
echo "ashmem_linux" >> /etc/modules-load.d/waydroid.conf

# Try starting again
pct start <CTID>
```

---

#### Issue 2: No GPU Access / Black Screen

**Symptoms**: `/dev/dri/` is empty, or VNC shows black screen

**Quick Fix**:
```bash
# On Proxmox host - check GPU devices
ls -la /dev/dri/
# Should show: card0, renderD128

# Check container config
cat /etc/pve/lxc/<CTID>.conf | grep dri

# If missing, add GPU passthrough manually
cat >> /etc/pve/lxc/<CTID>.conf <<EOF
# GPU Passthrough
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF

# Restart container
pct stop <CTID>
pct start <CTID>

# Verify inside container
pct enter <CTID>
ls -la /dev/dri/
```

---

#### Issue 3: VNC Not Accessible

**Symptoms**: Can't connect to VNC, connection refused

**Quick Fix**:
```bash
# Check if service is running
pct enter <CTID>
systemctl status waydroid-vnc

# If not running, start it
systemctl start waydroid-vnc

# Check if port is listening
netstat -tuln | grep 5900

# Check firewall (if you have one)
iptables -L -n | grep 5900

# Restart service
systemctl restart waydroid-vnc

# Check logs for errors
journalctl -u waydroid-vnc -n 50
```

---

#### Issue 4: Waydroid Session Not Running

**Symptoms**: `waydroid status` shows "STOPPED" or "FROZEN"

**Quick Fix**:
```bash
pct enter <CTID>

# Stop all Waydroid services
systemctl stop waydroid-vnc
systemctl stop waydroid-container

# Restart Waydroid
systemctl start waydroid-container
sleep 5
systemctl start waydroid-vnc

# Check status
waydroid status

# If still not working, reinitialize
waydroid session stop
systemctl restart waydroid-container
```

---

#### Issue 5: API Not Responding

**Symptoms**: API returns 500 errors or no response

**Quick Fix**:
```bash
pct enter <CTID>

# Check service
systemctl status waydroid-api

# Restart service
systemctl restart waydroid-api

# Test locally
curl http://localhost:8080/status

# Check logs
journalctl -u waydroid-api -n 50

# If Python errors, reinstall dependencies
pip3 install --force-reinstall flask requests
systemctl restart waydroid-api
```

---

#### Issue 6: No Audio

**Symptoms**: Android apps have no sound

**Quick Fix**:
```bash
# Run audio setup script
exit  # Back to Proxmox host
./scripts/setup-audio.sh <CTID>

# Test audio configuration
./scripts/setup-audio.sh --test-only <CTID>

# Inside container - check PulseAudio
pct enter <CTID>
pactl info
pactl list sinks

# If no sinks, restart PulseAudio
pulseaudio --kill
pulseaudio --start
```

---

#### Issue 7: Clipboard Not Working

**Symptoms**: Can't copy/paste between host and Android

**Quick Fix**:
```bash
# Re-run clipboard setup
./scripts/setup-clipboard.sh <CTID>

# Verify setup
./scripts/setup-clipboard.sh --verify <CTID>

# Inside container - check clipboard service
pct enter <CTID>
systemctl status waydroid-clipboard
journalctl -u waydroid-clipboard -n 20

# Restart clipboard service
systemctl restart waydroid-clipboard
```

---

#### Issue 8: Poor Performance / Lag

**Symptoms**: Slow graphics, low FPS, laggy interface

**Quick Fix**:
```bash
# 1. Verify GPU is being used
pct enter <CTID>
ls -la /dev/dri/  # Should NOT be empty

# 2. Check if using software rendering
waydroid prop get persist.waydroid.no_gpu
# If "true", disable software rendering:
waydroid prop set persist.waydroid.no_gpu false

# 3. Optimize VNC performance
exit  # Back to host
./scripts/enhance-vnc.sh --fps 60 --preset high-quality <CTID>

# 4. Optimize container
./scripts/tune-lxc.sh <CTID>

# 5. Increase resources (if needed)
pct set <CTID> --cores 4 --memory 4096
pct reboot <CTID>
```

---

#### Issue 9: Play Store Won't Install Apps

**Symptoms**: Apps fail to download from Play Store

**Quick Fix**:
```bash
pct enter <CTID>

# Check network connectivity
ping -c 3 8.8.8.8

# Check DNS
cat /etc/resolv.conf

# Fix DNS if needed
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

# Restart network
systemctl restart networking

# In Android (via VNC):
# Settings > Apps > Play Store > Clear Cache
# Settings > Apps > Play Store > Clear Data
# Reboot Android
systemctl restart waydroid-container
```

---

#### Issue 10: Container Uses Too Much Disk Space

**Symptoms**: Container grows very large

**Quick Fix**:
```bash
pct enter <CTID>

# Check disk usage
df -h
du -sh /var/lib/waydroid/

# Clear Android cache
waydroid session stop
rm -rf ~/.local/share/waydroid/data/cache/*
rm -rf /var/lib/waydroid/overlay/cache/*

# Clean APT cache
apt-get clean
apt-get autoclean

# Restart Waydroid
systemctl start waydroid-container

# On Proxmox host - increase disk if needed
pct resize <CTID> rootfs +10G
```

---

### Emergency Recovery

#### Complete Waydroid Reset

```bash
pct enter <CTID>

# Stop all services
systemctl stop waydroid-vnc
systemctl stop waydroid-container

# Backup important data (if needed)
cp -r ~/.local/share/waydroid/data/data/com.myapp /root/backup/

# Remove Waydroid data
rm -rf ~/.local/share/waydroid/
rm -rf /var/lib/waydroid/

# Reinitialize
waydroid init -s GAPPS -f

# Restart services
systemctl start waydroid-container
systemctl start waydroid-vnc
```

#### Container Complete Reset

```bash
# On Proxmox host
# Backup container first
vzdump <CTID> --dumpdir /var/lib/vz/dump/

# Stop and destroy container
pct stop <CTID>
pct destroy <CTID>

# Reinstall from scratch
cd /tmp/waydroid-proxmox
./install/install.sh
```

---

## Command Cheat Sheet

### Container Management

```bash
# Start container
pct start <CTID>

# Stop container
pct stop <CTID>

# Restart container
pct reboot <CTID>

# Enter container
pct enter <CTID>

# Execute command in container
pct exec <CTID> -- <command>

# Container status
pct status <CTID>

# Container configuration
cat /etc/pve/lxc/<CTID>.conf

# Resize disk
pct resize <CTID> rootfs +10G

# Change resources
pct set <CTID> --cores 4 --memory 4096

# Backup container
vzdump <CTID> --dumpdir /var/lib/vz/dump/

# Restore container
pct restore <CTID> /var/lib/vz/dump/vzdump-lxc-<CTID>-*.tar.zst
```

---

### Waydroid Commands

```bash
# All commands run inside container (pct enter <CTID>)

# Status
waydroid status

# Start session
waydroid session start

# Stop session
waydroid session stop

# Show Android window
waydroid show-full-ui

# Install APK
waydroid app install /path/to/app.apk

# Launch app
waydroid app launch com.package.name

# List installed apps
waydroid app list

# Send intent
waydroid app intent "android.intent.action.VIEW -d https://example.com"

# Properties
waydroid prop get <property>
waydroid prop set <property> <value>

# Useful properties:
waydroid prop set persist.waydroid.width 1920
waydroid prop set persist.waydroid.height 1080
waydroid prop set persist.waydroid.multi_windows true

# Logs
waydroid log

# Reinitialize (with GAPPS)
waydroid init -s GAPPS -f

# Reinitialize (without GAPPS)
waydroid init -f
```

---

### Service Management

```bash
# Inside container (pct enter <CTID>)

# Check all services
systemctl status waydroid-vnc
systemctl status waydroid-api
systemctl status waydroid-container

# Start services
systemctl start waydroid-vnc
systemctl start waydroid-api

# Stop services
systemctl stop waydroid-vnc
systemctl stop waydroid-api

# Restart services
systemctl restart waydroid-vnc
systemctl restart waydroid-api

# Enable on boot
systemctl enable waydroid-vnc
systemctl enable waydroid-api

# View logs
journalctl -u waydroid-vnc -f
journalctl -u waydroid-api -f
journalctl -u waydroid-container -f

# All logs
journalctl -xe
```

---

### Enhancement Scripts

```bash
# All run from Proxmox host in /root/waydroid-proxmox

# VNC Enhancement
./scripts/enhance-vnc.sh <CTID>                    # Interactive setup
./scripts/enhance-vnc.sh --enable-tls <CTID>       # Enable TLS
./scripts/enhance-vnc.sh --fps 60 <CTID>           # Set 60 FPS
./scripts/enhance-vnc.sh --install-novnc <CTID>    # Install web interface
./scripts/enhance-vnc.sh --security-only <CTID>    # Security features only

# Audio Setup
./scripts/setup-audio.sh <CTID>                    # Auto-configure
./scripts/setup-audio.sh --test-only <CTID>        # Test only
./scripts/setup-audio.sh --dry-run <CTID>          # Preview changes
./scripts/setup-audio.sh --force-pipewire <CTID>   # Force PipeWire

# Clipboard Setup
./scripts/setup-clipboard.sh <CTID>                # Setup clipboard
./scripts/setup-clipboard.sh --verify <CTID>       # Verify setup

# Performance Tuning
./scripts/tune-lxc.sh <CTID>                       # Apply all optimizations
./scripts/tune-lxc.sh --analyze-only <CTID>        # Analyze only
./scripts/tune-lxc.sh --dry-run <CTID>             # Preview changes

# App Installation
./scripts/install-apps.sh install-apk /path/to/app.apk           # Install APK
./scripts/install-apps.sh install-fdroid org.fdroid.fdroid       # Install from F-Droid
./scripts/install-apps.sh install-batch /path/to/apps.yaml       # Batch install
./scripts/install-apps.sh search-fdroid "firefox"                # Search F-Droid

# Monitoring
./scripts/monitor-performance.sh <CTID>            # Performance monitoring
./scripts/health-check.sh <CTID>                   # Health check

# Testing
./scripts/test-setup.sh <CTID>                     # Comprehensive test
```

---

### ADB Commands

```bash
# Inside container or from host (if ADB port forwarded)

# Connect to Waydroid
adb connect localhost:5555

# List devices
adb devices

# Install APK
adb install app.apk
adb install -r app.apk  # Reinstall

# Uninstall app
adb uninstall com.package.name

# List packages
adb shell pm list packages
adb shell pm list packages | grep keyword

# Launch app
adb shell am start -n com.package.name/.MainActivity

# Stop app
adb shell am force-stop com.package.name

# Simulate input
adb shell input tap 500 800           # Tap at coordinates
adb shell input swipe 300 800 300 400  # Swipe
adb shell input text "Hello"          # Type text
adb shell input keyevent 3            # Home button
adb shell input keyevent 4            # Back button

# Screenshots
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png

# Screen recording
adb shell screenrecord /sdcard/demo.mp4
adb pull /sdcard/demo.mp4

# Logs
adb logcat                            # All logs
adb logcat | grep MyApp               # Filter logs
adb logcat -c                         # Clear logs

# Files
adb push local.txt /sdcard/
adb pull /sdcard/file.txt

# Shell
adb shell
```

---

### API Commands

```bash
# All from any machine with network access

CONTAINER_IP="<your-container-ip>"

# Get status
curl http://$CONTAINER_IP:8080/status

# List apps
curl http://$CONTAINER_IP:8080/apps

# Launch app
curl -X POST http://$CONTAINER_IP:8080/app/launch \
  -H "Content-Type: application/json" \
  -d '{"package": "com.android.settings"}'

# Send intent
curl -X POST http://$CONTAINER_IP:8080/app/intent \
  -H "Content-Type: application/json" \
  -d '{"intent": "android.intent.action.VIEW -d https://example.com"}'

# Get logs
curl http://$CONTAINER_IP:8080/logs

# Get properties
curl http://$CONTAINER_IP:8080/properties

# Set property
curl -X POST http://$CONTAINER_IP:8080/properties/set \
  -H "Content-Type: application/json" \
  -d '{"property": "persist.waydroid.width", "value": "1920"}'

# Take screenshot
curl http://$CONTAINER_IP:8080/screenshot

# Metrics (Prometheus)
curl http://$CONTAINER_IP:8080/metrics
```

---

### VNC Commands

```bash
# Connect with VNC client
vncviewer <container-ip>:5900

# With TLS encryption
vncviewer -SecurityTypes VeNCrypt,TLSVnc <container-ip>:5900

# SSH tunnel (most secure)
ssh -L 5900:localhost:5900 root@<container-ip>
vncviewer localhost:5900

# Web browser (if noVNC installed)
http://<container-ip>/

# Inside container - VNC tuning
pct enter <CTID>

# Show current VNC settings
wayvnc-tune.sh show

# Change FPS
wayvnc-tune.sh fps 30
wayvnc-tune.sh fps 60

# Apply preset
wayvnc-tune.sh preset high-quality
wayvnc-tune.sh preset balanced
wayvnc-tune.sh preset low-bandwidth

# View VNC password
cat /root/.config/wayvnc/password

# Check VNC connections
tail -f /var/log/wayvnc/connections.log
netstat -tn | grep :5900
```

---

### Diagnostics & Monitoring

```bash
# System Info
pct enter <CTID>
uname -a
cat /etc/os-release

# Resource Usage
top
htop
free -h
df -h

# GPU Info
ls -la /dev/dri/
vainfo                    # VA-API info
glxinfo | grep -i opengl  # OpenGL info

# Network
ip addr
ip route
ping -c 3 8.8.8.8
netstat -tuln

# Processes
ps aux | grep waydroid
ps aux | grep wayvnc
systemctl list-units --type=service --state=running

# Logs
dmesg | tail -50
journalctl -xe
journalctl --since "10 minutes ago"

# Performance Monitoring
./scripts/monitor-performance.sh <CTID>

# Health Check
./scripts/health-check.sh <CTID>
```

---

### Useful One-Liners

```bash
# Get container IP
pct exec <CTID> -- hostname -I | awk '{print $1}'

# Check if Waydroid is running
pct exec <CTID> -- waydroid status | grep -q "RUNNING" && echo "Running" || echo "Stopped"

# List all Android apps with package names
pct exec <CTID> -- waydroid app list

# Launch app remotely
pct exec <CTID> -- waydroid app launch com.android.settings

# Restart all Waydroid services
pct exec <CTID> -- bash -c "systemctl restart waydroid-container && sleep 5 && systemctl restart waydroid-vnc waydroid-api"

# Get VNC password
pct exec <CTID> -- cat /root/.config/wayvnc/password

# Check GPU availability
pct exec <CTID> -- ls -la /dev/dri/ | grep -q "card0" && echo "GPU available" || echo "No GPU"

# View active VNC connections
pct exec <CTID> -- netstat -tn | grep :5900

# Clear Android app data
pct exec <CTID> -- waydroid shell pm clear com.package.name

# Take screenshot via API
curl -s http://<container-ip>:8080/screenshot | jq -r '.screenshot' | base64 -d > android-screen.png

# Monitor resource usage
pct exec <CTID> -- sh -c 'while true; do clear; echo "=== CPU ==="; top -bn1 | head -5; echo "=== Memory ==="; free -h; echo "=== Disk ==="; df -h /; sleep 2; done'

# Export all Android apps list
pct exec <CTID> -- waydroid app list > android-apps-$(date +%Y%m%d).txt

# Backup Waydroid data
pct exec <CTID> -- tar czf /root/waydroid-backup-$(date +%Y%m%d).tar.gz ~/.local/share/waydroid/data
```

---

## Additional Resources

### Documentation
- **[Full Installation Guide](docs/INSTALLATION.md)** - Detailed installation instructions
- **[Configuration Options](docs/CONFIGURATION.md)** - Customize your setup
- **[Home Assistant Integration](docs/HOME_ASSISTANT.md)** - Complete HA guide
- **[API v3.0 Documentation](API_IMPROVEMENTS_v3.0.md)** - Advanced API features
- **[LXC Tuning Guide](docs/LXC_TUNING.md)** - Performance optimization
- **[VNC Enhancements](docs/VNC-ENHANCEMENTS.md)** - Security and performance
- **[Clipboard Sharing](docs/CLIPBOARD-SHARING.md)** - Clipboard integration
- **[App Installation](docs/APP_INSTALLATION.md)** - App management
- **[Developer Handoff](HANDOFF.md)** - Project architecture and development

### External Resources
- **[Waydroid Official Docs](https://docs.waydro.id)** - Waydroid documentation
- **[Proxmox Documentation](https://pve.proxmox.com/wiki/Main_Page)** - Proxmox VE guide
- **[Android Debug Bridge](https://developer.android.com/studio/command-line/adb)** - ADB reference
- **[Home Assistant](https://www.home-assistant.io/)** - Home automation platform

### Community & Support
- **[GitHub Issues](https://github.com/MvRoo/waydroid-proxmox/issues)** - Bug reports and feature requests
- **[GitHub Discussions](https://github.com/MvRoo/waydroid-proxmox/discussions)** - Community support
- **[Waydroid Community](https://github.com/waydroid/waydroid/discussions)** - Waydroid discussions

---

## Quick Tips

### Performance
- Use GPU passthrough (Intel/AMD) for best performance
- Set VNC to 60 FPS for smooth experience: `./scripts/enhance-vnc.sh --fps 60 <CTID>`
- Run `tune-lxc.sh` after installation for optimized performance
- Use wired network (LAN) for lowest latency VNC

### Security
- Always enable TLS for VNC: `--enable-tls`
- Use strong passwords (24+ characters)
- Keep containers on private network or behind firewall
- Review logs regularly: `/var/log/wayvnc.log`, `/var/log/waydroid-api.log`

### Stability
- Allocate at least 2GB RAM (4GB+ recommended)
- Give container 2+ CPU cores for better responsiveness
- Monitor disk usage - Android can grow large
- Regular backups: `vzdump <CTID>`

### Troubleshooting
- Always check logs first: `journalctl -xe`
- Restart services before rebooting: `systemctl restart waydroid-vnc`
- Check GPU access: `ls -la /dev/dri/`
- Test API locally: `curl localhost:8080/status`

---

## Next Steps

After completing your setup:

1. **Configure Android** - Via VNC, set up Android settings, Google account, etc.
2. **Install Apps** - Use Play Store or automated app installation
3. **Integrate with Home Assistant** - Set up REST commands and automations
4. **Optimize Performance** - Run tuning scripts and adjust settings
5. **Set Up Monitoring** - Enable health checks and performance monitoring
6. **Create Backups** - Regular container backups for safety

**Need Help?** Check [Troubleshooting](#troubleshooting-quick-reference) or open an [issue on GitHub](https://github.com/MvRoo/waydroid-proxmox/issues).

---

**Made with ❤️ by the Waydroid Proxmox community**

*Last updated: 2025-01-12*
