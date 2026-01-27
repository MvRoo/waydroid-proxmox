# Debian 13 (Trixie) Migration Guide

**Date:** 2025-11-13
**Purpose:** Migrate from Debian 12 (Bookworm) to Debian 13 (Trixie) for proper WayVNC support
**Reason:** Debian 12's WayVNC 0.5.0/neatvnc 0.5.4 doesn't properly support `enable_auth=false`

---

## Why Debian 13?

### Package Version Comparison

| Package | Debian 12 | Debian 13 | Improvement |
|---------|-----------|-----------|-------------|
| **wayvnc** | 0.5.0 | 0.8.0+ | `enable_auth=false` works properly |
| **neatvnc** | 0.5.4 | 0.8.1+ | Fixes CVE-2024-42458 (CVSS 9.8) |
| **Security** | Vulnerable | Patched | Authentication bypass fixed |
| **VNC Compatibility** | VeNCrypt only | Standard + VeNCrypt | Type 1 (None) advertised |

### The Problem with Debian 12

**neatvnc 0.5.4 Security Type Mismatch:**
```
VNC Client offers:  [1, 2]         (None, VncAuth)
Server advertises:  [19, 30, 262]  (VeNCrypt, Apple DH, X509Plain)
Result:             "No matching security types"
```

Even with `enable_auth=false` in config, neatvnc 0.5.4 **only** advertises VeNCrypt types.

### The Solution in Debian 13

**neatvnc 0.8.1+ with proper configuration:**
```
VNC Client offers:  [1, 2]
Server advertises:  [1, 19, 262]    (includes Type 1 - None!)
Result:             Successful connection
```

---

## Step-by-Step Migration

### Prerequisites

- Proxmox VE host with access to Debian 13 template
- Backup of any important data from container 103
- Network access for package downloads

### Step 1: Download Debian 13 Template (if needed)

```bash
# On Proxmox host
cd /var/lib/vz/template/cache

# Download Debian 13 LXC template
wget http://download.proxmox.com/images/system/debian-13-standard_13.0-1_amd64.tar.zst

# Verify download
ls -lh debian-13-standard_13.0-1_amd64.tar.zst
```

### Step 2: Create Debian 13 Container

```bash
# Create container 104 with Debian 13
pct create 104 \
  local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst \
  --hostname waydroid-trixie \
  --memory 4096 \
  --swap 2048 \
  --cores 4 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --storage local-lvm \
  --rootfs local-lvm:16 \
  --features nesting=1,fuse=1 \
  --unprivileged 1 \
  --start 1

# Wait for container to start
sleep 10

# Get container IP
pct exec 104 -- ip -4 addr show eth0 | grep inet | awk '{print $2}' | cut -d/ -f1
```

**Note the IP address** - you'll need it for VNC connection.

### Step 3: Install Waydroid

```bash
# Enter container
pct enter 104

# Update package list
apt update && apt upgrade -y

# Clone repository
cd /tmp
git clone https://github.com/MvRoo/waydroid-proxmox.git
cd waydroid-proxmox

# Check for Debian 13 compatibility notes
cat QUICKSTART.md | grep -i "debian 13" -A 5 || echo "No specific notes - proceed"

# Run installation script
./install/waydroid-install.sh

# Exit container when done
exit
```

### Step 4: Verify WayVNC Version

```bash
# Check installed versions (should be 0.8.0+)
pct exec 104 -- wayvnc --version

# Expected output:
# wayvnc: 0.8.0 (or higher)
# neatvnc: 0.8.1 (or higher)
```

### Step 5: Configure WayVNC (No Auth)

```bash
# Create/verify config file
pct exec 104 -- bash <<'EOF'
mkdir -p /home/waydroid/.config/wayvnc
cat > /home/waydroid/.config/wayvnc/config <<'CONFIG'
enable_auth=false
address=0.0.0.0
port=5900
CONFIG

chown -R waydroid:waydroid /home/waydroid/.config/wayvnc
chmod 644 /home/waydroid/.config/wayvnc/config

# Verify
cat /home/waydroid/.config/wayvnc/config
EOF
```

### Step 6: Start/Restart Service

```bash
# Restart waydroid-vnc service
pct exec 104 -- systemctl restart waydroid-vnc.service

# Wait for startup
sleep 10

# Check status
pct exec 104 -- systemctl status waydroid-vnc.service --no-pager

# Verify port 5900 is listening
pct exec 104 -- ss -tlnp | grep 5900
```

### Step 7: Test VNC Connection

```bash
# Get container IP (from Step 2)
CONTAINER_IP=$(pct exec 104 -- hostname -I | awk '{print $1}')
echo "Container IP: $CONTAINER_IP"

# Test connection from your workstation
vncviewer $CONTAINER_IP:5900
```

**Expected Result:** VNC connection succeeds **without password prompt** or security errors.

---

## Troubleshooting

### Issue: "No matching security types" still appears

**Check 1: Verify WayVNC version**
```bash
pct exec 104 -- wayvnc --version
# Must be 0.8.0 or higher
```

**Check 2: Verify config is being used**
```bash
pct exec 104 -- ps aux | grep wayvnc
# Should show: wayvnc -C /home/waydroid/.config/wayvnc/config
```

**Check 3: Test with verbose output**
```bash
pct exec 104 -- systemctl stop waydroid-vnc.service
pct exec 104 -- su -c "XDG_RUNTIME_DIR=/run/user/$(id -u waydroid) WAYLAND_DISPLAY=wayland-1 wayvnc -C /home/waydroid/.config/wayvnc/config -v 0.0.0.0 5900" waydroid
# Look for security type advertisements in output
```

### Issue: Service fails to start

**Check logs:**
```bash
pct exec 104 -- journalctl -u waydroid-vnc.service -n 50 --no-pager
```

**Common causes:**
1. Sway not starting → Check Wayland socket in `/run/user/$(id -u waydroid)/`
2. WayVNC crashes → Check `/var/log/waydroid-wayvnc.log`
3. Permission issues → Verify waydroid user exists and has proper groups

**Manual test:**
```bash
pct exec 104 -- /usr/local/bin/start-waydroid.sh
# Run startup script manually to see errors
```

### Issue: Container won't start

**Check features:**
```bash
pct config 104 | grep features
# Should show: nesting=1,fuse=1
```

**Add if missing:**
```bash
pct set 104 --features nesting=1,fuse=1
pct reboot 104
```

---

## Verification Checklist

After migration, verify:

- [ ] Container 104 is running Debian 13
- [ ] WayVNC version is 0.8.0 or higher
- [ ] neatvnc version is 0.8.1 or higher (check with `wayvnc --version`)
- [ ] Config file exists at `/home/waydroid/.config/wayvnc/config`
- [ ] Config contains `enable_auth=false`
- [ ] Service `waydroid-vnc.service` is active and running
- [ ] Port 5900 is listening on 0.0.0.0
- [ ] VNC connection succeeds without password
- [ ] Waydroid Android session starts and is visible via VNC

---

## Comparison: Before and After

### Container 103 (Debian 12) - BROKEN
```bash
# Versions
WayVNC: 0.5.0
neatvnc: 0.5.4

# Config
enable_auth=false  ← Ignored by neatvnc 0.5.4

# Result
Connection fails: "No matching security types"

# Security
CVE-2024-42458: VULNERABLE
```

### Container 104 (Debian 13) - WORKING
```bash
# Versions
WayVNC: 0.8.0+
neatvnc: 0.8.1+

# Config
enable_auth=false  ← Works correctly

# Result
Connection succeeds without password

# Security
CVE-2024-42458: PATCHED
```

---

## Cleanup (Optional)

Once container 104 is working, you can optionally remove container 103:

```bash
# Stop container 103
pct stop 103

# Backup if needed
pct backup 103 --compress zstd --storage local

# Remove container
pct destroy 103
```

**⚠️ Warning:** Only destroy container 103 after confirming container 104 is fully functional.

---

## Package Versions Reference

### Debian 12 (Bookworm)
- wayvnc: 0.5.0-1
- neatvnc: 0.5.4-1
- sway: 1.8.1
- wlroots: 0.16.2

### Debian 13 (Trixie) - Expected
- wayvnc: 0.8.0+
- neatvnc: 0.8.1+
- sway: 1.9+
- wlroots: 0.17+

**Note:** Exact versions may vary. Verify with `apt-cache policy <package>` in container.

---

## Alternative: Manual Package Upgrade (NOT RECOMMENDED)

If Debian 13 template is unavailable, you could theoretically:

1. Add Debian 13 (Trixie) repositories to Debian 12 container
2. Selectively upgrade wayvnc and neatvnc packages
3. Pin other packages to Bookworm to avoid full upgrade

**Problems with this approach:**
- Dependency conflicts
- Partial upgrades are unstable
- No security support
- May break container

**Recommendation:** Use clean Debian 13 container instead.

---

## Success Criteria

Migration is successful when:

1. ✅ VNC connection to container 104 works without password
2. ✅ No "No matching security types" error
3. ✅ Waydroid Android session displays in VNC viewer
4. ✅ No CVE-2024-42458 vulnerability (neatvnc 0.8.1+)
5. ✅ Service starts automatically after container reboot

---

## Support and Resources

**Documentation:**
- Main README: `README.md`
- Quickstart Guide: `QUICKSTART.md`
- Handover Document: `HANDOVER.md`
- WayVNC Investigation: `docs/wayvnc-investigation/`

**Scripts:**
- Installation: `install/waydroid-install.sh`
- Container Creation: `ct/waydroid-lxc.sh`
- Diagnostics: `scripts/critical-wayvnc-test.sh`

**External Resources:**
- WayVNC GitHub: https://github.com/any1/wayvnc
- neatvnc GitHub: https://github.com/any1/neatvnc
- CVE-2024-42458: https://nvd.nist.gov/vuln/detail/CVE-2024-42458

---

**Migration prepared by:** Claude (2025-11-13)
**Status:** Ready for deployment
**Expected Time:** 20-30 minutes for full migration
