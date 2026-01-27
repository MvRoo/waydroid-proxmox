# Waydroid Proxmox LXC

Run Android applications on Proxmox using Waydroid in an LXC container with full GPU passthrough and remote access.

## Features

### Core Functionality
- **Multi-GPU Support**: Intel, AMD GPU passthrough or software rendering
- **Interactive Setup**: Easy installer with GPU and GAPPS selection
- **Lightweight**: Minimal resource usage with LXC containers
- **Google Play Store**: Optional GAPPS integration
- **Privilege Separation**: Runs as dedicated `waydroid` user (non-root)

### Remote Access
- **VNC Access**: Remote desktop access via WayVNC on port 5900
  - Password authentication
  - Configurable frame rates and quality

### Home Assistant & Automation
- **REST API**: Control Waydroid from Home Assistant
  - Launch apps, send intents, get status
  - Bearer token authentication
  - App installation and management

## Use Cases

- **Smart Home Automation**: Control Android-only IoT devices from Home Assistant
- **Gate/Door Control**: Automate apps that only have Android interfaces
- **Security Cameras**: Run Android camera apps with Home Assistant integration
- **Remote Android Testing**: Test Android apps on your Proxmox server
- **Legacy App Support**: Run old Android apps that need specific environments

## Quick Start

### 🚀 One-Command Installer (Recommended)

Run this single command on your Proxmox host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/iceteaSA/waydroid-proxmox/main/ct/waydroid.sh)"
```

**That's it!** The installer will:
- Auto-detect your next available container ID
- Detect your GPU hardware (Intel/AMD) automatically
- Ask about Google Apps installation
- Create and configure everything
- Start all services
- Display VNC and API credentials

**Features:**
- ✅ Single command - no git clone needed
- ✅ Auto-detects GPU and container settings
- ✅ Compatible with Proxmox community scripts
- ✅ Comprehensive error handling

See [ct/README.md](ct/README.md) for all options and advanced usage.

### After Installation

Once complete, you'll receive:
- **VNC Access**: `<container-ip>:5900` with username/password
- **API Endpoint**: `http://<container-ip>:8080` with Bearer token
- **VNC Password**: Saved to `/root/vnc-password.txt` in container
- **API Token**: Saved to `/etc/waydroid-api/token` in container

First boot takes 2-3 minutes while Android initializes.

## Requirements

### Hardware
- **CPU**: Any x86_64 CPU
- **GPU**: Intel (recommended), AMD, or software rendering
- **RAM**: 2GB+ (4GB recommended)
- **Storage**: 16GB+ free space

### Software
- Proxmox VE 7.x or 8.x
- Kernel 5.15+ with binder support
- For GPU passthrough: Privileged LXC container

## Architecture

```
┌─────────────────────────────────────────┐
│         Proxmox Host                     │
│  ┌────────────────────────────────────┐ │
│  │     Waydroid LXC Container         │ │
│  │                                    │ │
│  │  ┌──────────┐      ┌───────────┐  │ │
│  │  │  Sway    │◄────►│  WayVNC   │  │ │
│  │  │Compositor│      │  :5900    │  │ │
│  │  └────┬─────┘      └───────────┘  │ │
│  │       │                            │ │
│  │  ┌────▼─────┐      ┌───────────┐  │ │
│  │  │ Waydroid │      │    API    │  │ │
│  │  │ Android  │      │   :8080   │  │ │
│  │  │  System  │      └───────────┘  │ │
│  │  └────┬─────┘                     │ │
│  │       │                            │ │
│  │  ┌────▼─────────────────────────┐ │ │
│  │  │  GPU Passthrough (Optional)  │ │ │
│  │  │  /dev/dri/card0              │ │ │
│  │  │  /dev/dri/renderD128         │ │ │
│  │  └──────────────────────────────┘ │ │
│  │                                    │ │
│  │  All services run as 'waydroid'   │ │
│  │  user for security isolation      │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## Project Structure

```
waydroid-proxmox/
├── ct/                     # Container setup scripts
│   ├── waydroid.sh        # Main installer
│   └── README.md          # Installer documentation
├── install/                # Installation scripts
│   └── waydroid-install.sh # LXC setup script
├── misc/                   # Supporting files
│   └── build.func         # Community scripts build functions
├── json/                   # Metadata
│   └── waydroid.json      # Community scripts metadata
├── docs/                   # Documentation
│   ├── INSTALLATION.md    # Detailed installation guide
│   ├── HOME_ASSISTANT.md  # Home Assistant integration
│   ├── CONFIGURATION.md   # Configuration options
│   ├── VNC-ENHANCEMENTS.md # VNC guide
│   ├── VNC-QUICK-REFERENCE.md # VNC quick reference
│   ├── APP_INSTALLATION.md # App installation guide
│   └── TESTING.md         # Testing guide
└── README.md              # This file
```

## Documentation

### Getting Started
- **[Installation Guide](docs/INSTALLATION.md)**: Detailed step-by-step installation instructions
- **[Configuration](docs/CONFIGURATION.md)**: Customize your Waydroid setup
- **[Troubleshooting](docs/INSTALLATION.md#troubleshooting)**: Common issues and solutions

### Features & Integration
- **[VNC Access](docs/VNC-ENHANCEMENTS.md)**: Remote access configuration
- **[VNC Quick Reference](docs/VNC-QUICK-REFERENCE.md)**: Common VNC commands
- **[Home Assistant Integration](docs/HOME_ASSISTANT.md)**: Automate Android apps
- **[App Installation](docs/APP_INSTALLATION.md)**: Install Android apps
- **[Testing Guide](docs/TESTING.md)**: Verify your installation

## Home Assistant Example

Control an Android gate app from Home Assistant:

```yaml
# configuration.yaml
rest_command:
  open_gate:
    url: "http://192.168.1.100:8080/app/launch"
    method: POST
    headers:
      Authorization: "Bearer YOUR_API_TOKEN"
      Content-Type: "application/json"
    payload: '{"package": "com.example.gatecontrol"}'

automation:
  - alias: "Open Gate"
    trigger:
      - platform: state
        entity_id: input_button.gate
    action:
      - service: rest_command.open_gate
```

## API Endpoints

### Core Endpoints
- `GET /status` - Get Waydroid status
- `GET /apps` - List installed apps
- `POST /app/launch` - Launch an app
- `POST /app/intent` - Send Android intent
- `GET /logs` - Retrieve Waydroid logs
- `GET /properties` - Get Waydroid properties
- `POST /properties/set` - Set Waydroid properties
- `GET /adb/devices` - List ADB devices

See [Home Assistant Integration](docs/HOME_ASSISTANT.md) for complete API documentation and examples.

## GPU Support

### Intel GPUs (Recommended)
- Full hardware acceleration via Mesa/Iris
- VA-API video decoding
- Best performance and compatibility
- Example: Intel i3/i5/i7 with integrated graphics

### AMD GPUs
- Hardware acceleration via Mesa/RadeonSI
- VA-API video decoding
- Good performance
- Example: AMD Ryzen with Radeon Graphics

### NVIDIA GPUs
- Limited support - use software rendering
- Basic functionality only

### Software Rendering
- No GPU required
- Works in unprivileged containers
- Limited graphics performance
- Good for headless automation

## Performance

Typical resource usage:
- **RAM**: ~1.5-2GB (Android + compositor)
- **Boot Time**: ~30-60 seconds
- **CPU**: 2 cores recommended
- **Disk**: ~8-12GB after installation

## Security

### Security Validation

This repository includes comprehensive security validation to ensure the scripts are safe to run:

**Quick Security Check:**
```bash
# Clone and validate before running
git clone https://github.com/iceteaSA/waydroid-proxmox.git
cd waydroid-proxmox
bash scripts/security-check.sh
```

**Full Security Analysis:**
See [SECURITY-ANALYSIS.md](SECURITY-ANALYSIS.md) for a complete security audit of all bash scripts, including:
- Analysis of 44+ bash scripts
- Network access validation  
- Credential handling review
- Dangerous command detection
- Code obfuscation checks
- Backdoor detection

**Security Summary:**
✅ No malicious code detected  
✅ No data exfiltration attempts  
✅ Secure credential generation  
✅ Proper file permissions  
✅ Official repositories only  
✅ Input validation present  

### Security Features
- **Privilege Separation**: All services run as `waydroid` user (non-root)
- **VNC Authentication**: Password-protected remote access
- **API Authentication**: Bearer token authentication
- **Isolated Container**: LXC isolation from host system

### Security Best Practices
1. **Change Default Credentials**: Set strong VNC passwords and API tokens
2. **Firewall Configuration**: Limit access to VNC (5900) and API (8080) ports
3. **Regular Updates**: Keep Proxmox, LXC, and Waydroid updated
4. **Network Isolation**: Use firewall rules to restrict container network access

## Troubleshooting

### Container Won't Start
```bash
# Check kernel modules on host
lsmod | grep binder

# Reload if needed
modprobe binder_linux ashmem_linux
```

### No GPU Access
```bash
# Verify GPU devices on host
ls -la /dev/dri/

# Check container config
cat /etc/pve/lxc/<ctid>.conf | grep dri
```

### VNC Not Accessible
```bash
# Check service in container
pct enter <ctid>
systemctl status waydroid-vnc
journalctl -u waydroid-vnc -n 50
```

### Waydroid Won't Start
```bash
# Check as waydroid user in container
pct enter <ctid>
su - waydroid
waydroid status
```

See [full troubleshooting guide](docs/INSTALLATION.md#troubleshooting).

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request
4. Follow existing code style
5. Update documentation for new features

## Known Limitations

- **Wayland Only**: Requires Wayland compositor (no X11)
- **x86_64 Only**: No ARM64 support currently
- **Network**: Some Android apps may have network connectivity issues
- **SafetyNet**: Banking apps with SafetyNet checks may not work

## License

MIT License - see LICENSE file for details.

## Credits

- [Waydroid](https://waydro.id/) - Android container solution
- [Proxmox Community Scripts](https://github.com/community-scripts/ProxmoxVE) - Inspiration and structure
- [WayVNC](https://github.com/any1/wayvnc) - VNC server for Wayland

## Support

- **Issues**: [GitHub Issues](https://github.com/iceteaSA/waydroid-proxmox/issues)
- **Discussions**: [GitHub Discussions](https://github.com/iceteaSA/waydroid-proxmox/discussions)
- **Waydroid Docs**: [docs.waydro.id](https://docs.waydro.id)
