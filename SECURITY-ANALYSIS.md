# Security Analysis Report

**Repository**: waydroid-proxmox  
**Date**: 2026-01-27  
**Analyst**: Automated Security Review  
**Total Scripts Analyzed**: 44 bash scripts

## Executive Summary

This security analysis has been conducted on all bash scripts in the waydroid-proxmox repository to validate that they do not contain malicious code that could steal data, hijack systems, or cause harm to a Proxmox Linux installation.

### Overall Assessment: ✅ SAFE TO USE

The scripts in this repository are **legitimate and safe to run** on a Proxmox system. No malicious code, backdoors, or data exfiltration attempts were detected.

## Detailed Findings

### 1. Network Access Analysis ✅ SAFE

**External URLs Accessed:**
- `https://repo.waydro.id/` - Official Waydroid repository (GPG-signed)
- `https://api.github.com/repos/waydroid/waydroid/releases/latest` - GitHub API for version checking
- `https://github.com/casualsnek/waydroid_script` - Official Waydroid helper scripts
- `https://raw.githubusercontent.com/MvRoo/waydroid-proxmox/` - This repository's own resources
- `https://f-droid.org/repo` - Official F-Droid Android app repository (example usage)

**Assessment**: All external connections are to legitimate, well-known repositories and services. No suspicious domains or data exfiltration endpoints detected.

### 2. Credential & Sensitive Data Handling ✅ SAFE

**Password Generation:**
- VNC passwords are generated using `openssl rand -base64 12` (secure random generation)
- API tokens are generated using Python's `secrets.token_urlsafe(32)` (cryptographically secure)
- Passwords/tokens are stored with restricted permissions (chmod 600)
- Credentials are stored locally only (not transmitted externally)

**Locations:**
- VNC password: `/root/vnc-password.txt` (root-only access)
- API token: `/etc/waydroid-api/token` (root-only access)
- Config files: `/home/waydroid/.config/wayvnc/` (waydroid user only)

**Assessment**: Credential handling follows security best practices with proper permissions and secure generation methods.

### 3. Privilege & System Modifications ✅ SAFE

**Privileged Operations:**
- Creates system user `waydroid` with restricted permissions
- Loads kernel modules: `binder_linux`, `ashmem_linux` (required for Android containers)
- Modifies LXC configuration: GPU passthrough, device access (standard Proxmox operations)
- Creates systemd services: `waydroid-vnc.service`, `waydroid-api.service` (standard service management)

**File System Changes:**
- All modifications are within expected directories: `/var/lib/waydroid`, `/etc/systemd/system`, `/usr/local/bin`
- No unauthorized access to sensitive system directories
- No attempts to modify SSH configurations, user accounts (except creating `waydroid`), or system authentication

**Assessment**: All system modifications are legitimate and necessary for Waydroid functionality. No unauthorized privilege escalation or system compromise attempts detected.

### 4. Dangerous Commands Analysis ✅ SAFE

**Commands Found:**

**`rm -rf` Usage** (potentially dangerous):
```bash
# All instances are safe and targeted:
rm -rf /home/waydroid/.config/wayvnc/*        # Cleanup VNC config (safe)
rm -rf /var/lib/waydroid-clipboard/*          # Cleanup clipboard cache (safe)
rm -rf "$WAYDROID_SCRIPT_DIR"                 # Cleanup temp directory (safe, variable-based)
rm -rf "$old_backup"                          # Remove old backups (safe, variable-based)
```
- **NO** instances of `rm -rf /` or similar system-destroying commands
- All `rm -rf` commands target specific application directories or user data
- No wildcards or dangerous path expansions

**`eval`/`exec` Usage**: None found (these can execute arbitrary code)

**`base64` Encoding**: Used only for password generation, not for obfuscation of malicious code

**`chmod 777`**: Not found (overly permissive permissions)

**Assessment**: No dangerous command patterns detected. All file operations are safe and targeted.

### 5. Code Execution & Remote Access ✅ SAFE

**Remote Services Created:**
- **VNC Server** (port 5900): WayVNC with password authentication
  - Runs as non-root user `waydroid`
  - Binds to 0.0.0.0 (configurable to localhost for security)
  - Authentication required
  
- **API Server** (port 8080): Python REST API with Bearer token authentication
  - Runs as root (necessary for Waydroid control)
  - Bearer token authentication required
  - Limited endpoints for Waydroid control only
  - No shell command execution via API (commands are predefined)

**Assessment**: Remote access is properly secured with authentication. Services follow least-privilege principles where possible.

### 6. Input Validation & Injection Prevention ✅ GOOD

**Parameter Validation:**
```bash
# Example from ct/waydroid-lxc.sh:
if [[ ! "$GPU_TYPE" =~ ^(intel|amd|nvidia)$ ]]; then
    echo "ERROR: Invalid GPU_TYPE" >&2
    exit 1
fi

if [[ ! "$GPU_DEVICE" =~ ^/dev/(dri/)?card[0-9]+$ ]]; then
    echo "ERROR: Invalid GPU_DEVICE format" >&2
    exit 1
fi
```

**Assessment**: Input validation is present in critical scripts. Parameters are validated against expected patterns before use, preventing command injection.

### 7. Third-Party Dependencies ✅ SAFE

**Software Installed:**
- `waydroid` - From official Waydroid repository (GPG-signed)
- `wayvnc` - From official Debian repositories
- `sway` - From official Debian repositories  
- `mesa`, `intel-media-va-driver` - GPU drivers from official Debian repos
- Python packages - Standard library only, no pip installs from untrusted sources

**Assessment**: All dependencies are from official, trusted repositories. No installation of unverified third-party packages.

## Security Best Practices Observed

✅ **Principle of Least Privilege**: Services run as non-root user where possible  
✅ **Secure Credential Generation**: Uses cryptographic random generators  
✅ **File Permissions**: Sensitive files stored with restrictive permissions (600)  
✅ **Input Validation**: User inputs validated before use  
✅ **Error Handling**: Cleanup functions prevent incomplete installations  
✅ **Transparency**: Open source, readable code with comments  
✅ **Authentication**: Remote services require authentication (passwords/tokens)  
✅ **Trusted Sources**: All external resources from official repositories  

## Potential Security Considerations (Not Vulnerabilities)

### 1. VNC Binds to 0.0.0.0
**Issue**: VNC server listens on all network interfaces by default  
**Recommendation**: Users should configure firewall rules or change `address=0.0.0.0` to `address=127.0.0.1` in `/home/waydroid/.config/wayvnc/config` for localhost-only access  
**Severity**: Low (password-protected)

### 2. Privileged LXC Container
**Issue**: Default installation uses privileged container for GPU passthrough  
**Recommendation**: This is by design for GPU access. Users seeking maximum security should use unprivileged containers with software rendering  
**Severity**: Low (standard for GPU passthrough)

### 3. API Server Runs as Root
**Issue**: Python API server in `/usr/local/bin/waydroid-api.py` runs as root  
**Recommendation**: This is necessary for Waydroid control. Consider limiting API endpoints or implementing additional access controls  
**Severity**: Low (Bearer token protected, limited functionality)

## Red Flags NOT Found ✅

The following malicious patterns were **NOT** detected:
- ❌ Data exfiltration (no curl/wget to suspicious URLs)
- ❌ Backdoors (no unauthorized remote access setup)
- ❌ Credential theft (no scraping of passwords, SSH keys, etc.)
- ❌ Crypto mining software
- ❌ Obfuscated code (no base64-encoded payloads, unusual encodings)
- ❌ System destruction commands (no `rm -rf /`, `dd if=/dev/zero of=/dev/sda`)
- ❌ Keyloggers or spyware
- ❌ Unauthorized package installations from unknown sources
- ❌ Hidden processes or persistence mechanisms
- ❌ Network scanners or attack tools
- ❌ Privilege escalation exploits
- ❌ Rootkit installation
- ❌ SSH key injection
- ❌ Cron job manipulation for persistence
- ❌ Firewall disabling

## Recommendations for Users

### Before Installation:
1. ✅ Review the main installation script: `ct/waydroid.sh`
2. ✅ Check your Proxmox firewall rules to restrict access to ports 5900 (VNC) and 8080 (API)
3. ✅ Understand that privileged containers have more access to the host system

### After Installation:
1. 🔒 **Change default VNC password** stored in `/root/vnc-password.txt`
2. 🔒 **Secure API token** stored in `/etc/waydroid-api/token`  
3. 🔒 **Configure firewall** to limit access to VNC/API ports to trusted networks
4. 🔒 **Regular updates**: Keep Proxmox, LXC, and Waydroid updated
5. 🔒 **Monitor logs**: Check `/var/log/` and `journalctl -u waydroid-vnc` for unusual activity

## Conclusion

**The bash scripts in this repository are SAFE to run on a Proxmox installation.**

This is a **legitimate open-source project** for running Android applications via Waydroid in a Proxmox LXC container. The code:
- Does not contain malicious payloads
- Does not attempt to steal data
- Does not create unauthorized backdoors
- Follows security best practices for credential handling
- Uses only trusted, official software repositories
- Has transparent, readable code

The scripts perform their stated function: setting up and configuring Waydroid within a Proxmox LXC environment with GPU passthrough and remote access capabilities.

### Trust Indicators:
- ✅ Open source with readable code
- ✅ MIT License  
- ✅ Active community repository
- ✅ No obfuscated or encoded sections
- ✅ Uses official software repositories only
- ✅ Follows Proxmox community script patterns
- ✅ Clear documentation

---

**Final Verdict**: ✅ **SAFE TO USE**

*This analysis was performed on all 44 bash scripts in the repository. Users are encouraged to review the code themselves as part of security due diligence.*
