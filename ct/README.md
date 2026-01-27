# Waydroid One-Command Installer for Proxmox LXC

The streamlined, production-ready installer for Waydroid on Proxmox VE.

## Quick Start

### Interactive Installation (Recommended)

Run this single command on your Proxmox host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/MvRoo/waydroid-proxmox/main/ct/waydroid.sh)"
```

The installer will:
1. Auto-detect the next available container ID
2. Prompt you for GPU type (Intel/AMD/NVIDIA/Software)
3. Detect your GPU hardware automatically
4. Ask about Google Apps installation
5. Create and configure the LXC container
6. Install Waydroid, VNC, and Home Assistant API
7. Start all services automatically
8. Display connection information

### Non-Interactive Installation

For automated deployments or scripts:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/MvRoo/waydroid-proxmox/main/ct/waydroid.sh)" -s -- \
  --non-interactive \
  --ctid 200 \
  --gpu intel \
  --gapps \
  --disk 20 \
  --ram 4096 \
  --cpu 4
```

## Installation Options

### Container Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `--ctid <id>` | Container ID | Auto-detect next available |
| `--hostname <name>` | Container hostname | `waydroid` |
| `--disk <size>` | Disk size in GB | `16` |
| `--cpu <cores>` | CPU cores | `2` |
| `--ram <mb>` | RAM in MB | `2048` |
| `--storage <pool>` | Storage pool | `local-lxc` |
| `--bridge <name>` | Network bridge | `vmbr0` |
| `--privileged` | Use privileged container (for GPU) | Default |
| `--unprivileged` | Use unprivileged container | Software rendering only |

### GPU Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `--gpu <type>` | GPU type: `intel`, `amd`, `nvidia`, `software` | Interactive prompt |
| `--gpu-device <dev>` | Specific GPU device (e.g., `/dev/dri/card0`) | Auto-detect |
| `--render-node <dev>` | Specific render node (e.g., `/dev/dri/renderD128`) | Auto-detect |
| `--software-rendering` | Force software rendering | Based on GPU type |

### Android Configuration

| Option | Description | Default |
|--------|-------------|---------|
| `--gapps` | Install Google Apps/Play Store | Yes |
| `--no-gapps` | Skip Google Apps | No |

### Script Behavior

| Option | Description |
|--------|-------------|
| `--non-interactive` | Run without prompts |
| `--update` | Update existing installation |
| `--verbose` | Show detailed output |
| `--skip-preflight` | Skip preflight checks (not recommended) |
| `-h, --help` | Show help message |
| `--version` | Show version |

## Usage Examples

### Intel GPU with Google Apps

```bash
bash waydroid.sh --gpu intel --gapps
```

### AMD GPU with specific container resources

```bash
bash waydroid.sh --gpu amd --ctid 200 --cpu 4 --ram 4096 --disk 32
```

### Unprivileged container (software rendering)

```bash
bash waydroid.sh --unprivileged --no-gapps
```

### Update existing Waydroid installation

From Proxmox host:
```bash
pct exec 200 -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/MvRoo/waydroid-proxmox/main/ct/waydroid.sh)" -- --update
```

Or inside the container:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/MvRoo/waydroid-proxmox/main/ct/waydroid.sh)" -- --update
```

## Environment Variables

You can also use environment variables instead of command-line arguments:

```bash
export CTID=200
export GPU_TYPE=intel
export USE_GAPPS=yes
export DISK_SIZE=32
export RAM=4096
export CORES=4
bash waydroid.sh --non-interactive
```

## Post-Installation

After installation completes, you'll see output like:

```
═══════════════════════════════════════════════════════════════════════════
  Waydroid Installation Complete!
═══════════════════════════════════════════════════════════════════════════

Container Details:
  CTID: 200
  IP Address: 192.168.1.100
  Hostname: waydroid

Access Information:
  VNC:
    Address: 192.168.1.100:5900
    Username: waydroid
    Password: <random-password>

  Home Assistant API:
    Endpoint: http://192.168.1.100:8080
    Token: <random-token>

Configuration:
  GPU: intel
  Rendering: Hardware Accelerated
  GAPPS: yes
```

### Accessing Android

1. **VNC**: Connect to `<container-ip>:5900` using any VNC client
   - Username: `waydroid`
   - Password: shown in installation output (also saved to `/root/vnc-password.txt`)

2. **Wait for boot**: First boot takes 2-3 minutes while Android initializes

3. **Google Play Store** (if GAPPS installed): Sign in with your Google account

### Using the Home Assistant API

The API token is shown in the installation output and saved to `/etc/waydroid-api/token` inside the container.

#### Launch an app:
```bash
curl -X POST http://<container-ip>:8080/app/launch \
  -H "Authorization: Bearer <your-token>" \
  -H "Content-Type: application/json" \
  -d '{"package": "com.android.settings"}'
```

#### Check status:
```bash
curl http://<container-ip>:8080/status \
  -H "Authorization: Bearer <your-token>"
```

#### Health check (no auth required):
```bash
curl http://<container-ip>:8080/health
```

## Features

### What Makes This Installer Special

1. **True One-Command**: Single curl command handles everything
2. **Smart Environment Detection**: Auto-detects if running on host or in container
3. **GPU Auto-Detection**: Scans and presents available GPUs
4. **Multi-GPU Support**: Select specific GPU when multiple are available
5. **Community Script Integration**: Compatible with tteck/Proxmox scripts
6. **Update Capability**: Re-run to update existing installations
7. **Non-Interactive Mode**: Perfect for automation and scripts
8. **Comprehensive Error Handling**: Cleanup on failure, helpful error messages
9. **Preflight Checks**: Validates environment before starting
10. **Post-Install Verification**: Ensures everything is working

### vs Legacy install.sh

The new `ct/waydroid.sh` offers several advantages over `install/install.sh`:

| Feature | waydroid.sh | install.sh |
|---------|-------------|------------|
| Single command | ✅ | ❌ (requires two scripts) |
| Update mode | ✅ | ❌ |
| Non-interactive | ✅ | ⚠️ (partial) |
| Community script integration | ✅ | ❌ |
| Multi-GPU selection | ✅ | ❌ |
| Help system | ✅ | ❌ |
| Environment detection | ✅ | ⚠️ (limited) |
| Post-install summary | ✅ | ⚠️ (basic) |

## Troubleshooting

### Check container logs
```bash
pct exec <CTID> -- journalctl -xe
```

### Check service status
```bash
pct exec <CTID> -- systemctl status waydroid-vnc.service
pct exec <CTID> -- systemctl status waydroid-api.service
```

### Manual service restart
```bash
pct exec <CTID> -- systemctl restart waydroid-vnc.service
pct exec <CTID> -- systemctl restart waydroid-api.service
```

### Get VNC password
```bash
pct exec <CTID> -- cat /root/vnc-password.txt
```

### Get API token
```bash
pct exec <CTID> -- cat /etc/waydroid-api/token
```

### Enter container for debugging
```bash
pct enter <CTID>
```

## Advanced Usage

### Custom GPU device mapping

If you have multiple GPUs and want to specify exact devices:

```bash
bash waydroid.sh \
  --gpu intel \
  --gpu-device /dev/dri/card1 \
  --render-node /dev/dri/renderD129
```

### Minimal installation (no GAPPS, software rendering)

```bash
bash waydroid.sh \
  --unprivileged \
  --no-gapps \
  --ram 1024 \
  --disk 8
```

### High-performance configuration

```bash
bash waydroid.sh \
  --gpu intel \
  --gapps \
  --cpu 8 \
  --ram 8192 \
  --disk 64
```

## Integration with tteck/Proxmox Scripts

This installer is designed to work seamlessly with the [tteck Proxmox Helper Scripts](https://tteck.github.io/Proxmox/):

```bash
# Set the community functions path
export FUNCTIONS_FILE_PATH=/path/to/community/functions.sh

# Run installer - it will automatically use community functions
bash waydroid.sh
```

The installer will automatically use community functions for:
- Color output (`color`, `msg_info`, `msg_ok`, `msg_error`)
- Error handling (`catch_errors`)
- Container setup (`setting_up_container`)
- Network checks (`network_check`)
- System updates (`update_os`)

## Requirements

- Proxmox VE 7.0 or later
- Debian 12 (Bookworm) LXC template
- For GPU passthrough:
  - Intel: 6th gen (Skylake) or newer recommended
  - AMD: GCN 3.0 or newer
  - NVIDIA: Software rendering only
- Kernel modules: `binder_linux`, `ashmem_linux` (auto-loaded)

## License

MIT License - See [LICENSE](../LICENSE) file

## Contributing

Issues and pull requests welcome at: https://github.com/MvRoo/waydroid-proxmox

## Documentation

- [Main README](../README.md)
- [Developer Handoff Documentation](../HANDOFF.md)
- [API Documentation](../api/README.md)
