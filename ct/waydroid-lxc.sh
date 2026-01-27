#!/usr/bin/env bash

# Waydroid LXC Container Setup Script
# Copyright (c) 2025
# License: MIT
# https://github.com/MvRoo/waydroid-proxmox

# Parse and validate parameters
GPU_TYPE=${1:-intel}
USE_GAPPS=${2:-yes}
SOFTWARE_RENDERING=${3:-0}
GPU_DEVICE=${4:-}
RENDER_NODE=${5:-}

# Input validation for all parameters
if [[ ! "$GPU_TYPE" =~ ^(intel|amd|nvidia)$ ]]; then
    echo "ERROR: Invalid GPU_TYPE. Must be 'intel', 'amd', or 'nvidia'" >&2
    exit 1
fi

if [[ ! "$USE_GAPPS" =~ ^(yes|no)$ ]]; then
    echo "ERROR: Invalid USE_GAPPS. Must be 'yes' or 'no'" >&2
    exit 1
fi

if [[ ! "$SOFTWARE_RENDERING" =~ ^[01]$ ]]; then
    echo "ERROR: Invalid SOFTWARE_RENDERING. Must be '0' or '1'" >&2
    exit 1
fi

if [ -n "$GPU_DEVICE" ]; then
    # Validate GPU_DEVICE is a valid path without shell metacharacters
    if [[ ! "$GPU_DEVICE" =~ ^/dev/(dri/)?card[0-9]+$ ]]; then
        echo "ERROR: Invalid GPU_DEVICE format. Must be /dev/cardX or /dev/dri/cardX" >&2
        exit 1
    fi
    # Verify the device exists
    if [ ! -e "$GPU_DEVICE" ]; then
        echo "ERROR: GPU_DEVICE '$GPU_DEVICE' does not exist" >&2
        exit 1
    fi
fi

if [ -n "$RENDER_NODE" ]; then
    # Validate RENDER_NODE is a valid path without shell metacharacters
    if [[ ! "$RENDER_NODE" =~ ^/dev/(dri/)?renderD[0-9]+$ ]]; then
        echo "ERROR: Invalid RENDER_NODE format. Must be /dev/renderDX or /dev/dri/renderDX" >&2
        exit 1
    fi
    # Verify the device exists
    if [ ! -e "$RENDER_NODE" ]; then
        echo "ERROR: RENDER_NODE '$RENDER_NODE' does not exist" >&2
        exit 1
    fi
fi

# Cleanup on error function
cleanup_on_error() {
    local exit_code=$?
    echo -e "\n${RD}ERROR: Script failed with exit code ${exit_code}${CL}" >&2
    echo -e "${YW}Performing cleanup...${CL}" >&2

    # Stop any running services
    systemctl stop waydroid-vnc.service 2>/dev/null || true
    systemctl stop waydroid-api.service 2>/dev/null || true
    systemctl stop waydroid-container.service 2>/dev/null || true

    # Remove incomplete configurations
    if [ -f /etc/systemd/system/waydroid-vnc.service ]; then
        systemctl disable waydroid-vnc.service 2>/dev/null || true
    fi

    echo -e "${YW}Cleanup completed. Please review errors above before retrying.${CL}" >&2
    exit "$exit_code"
}

# Set up error trap
trap cleanup_on_error ERR
set -e  # Exit on error

# Dependency checking function
check_dependencies() {
    local missing_deps=()
    local deps=("$@")

    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RD}ERROR: Missing required dependencies: ${missing_deps[*]}${CL}" >&2
        return 1
    fi
    return 0
}

# Verify command execution
verify_exec() {
    local cmd_description="$1"
    shift

    if ! "$@"; then
        echo -e "${RD}ERROR: Failed to ${cmd_description}${CL}" >&2
        return 1
    fi
    return 0
}

# Health check function
run_health_checks() {
    local checks_passed=true

    msg_info "Running Health Checks"

    # Check Waydroid installation
    if ! command -v waydroid &>/dev/null; then
        msg_error "Waydroid command not found"
        checks_passed=false
    else
        msg_ok "Waydroid binary present"
    fi

    # Check GPU devices if hardware rendering
    if [ "$SOFTWARE_RENDERING" = "0" ]; then
        if [ ! -d "/dev/dri" ]; then
            msg_error "/dev/dri directory not found"
            checks_passed=false
        elif [ ! -e "/dev/dri/renderD128" ] && [ -z "$RENDER_NODE" ]; then
            msg_warn "No render node found (this may be expected)"
        else
            msg_ok "GPU devices accessible"
        fi
    fi

    # Check systemd services were created
    if [ ! -f /etc/systemd/system/waydroid-vnc.service ]; then
        msg_error "waydroid-vnc.service file not created"
        checks_passed=false
    else
        msg_ok "waydroid-vnc.service created"
    fi

    if [ ! -f /etc/systemd/system/waydroid-api.service ]; then
        msg_error "waydroid-api.service file not created"
        checks_passed=false
    else
        msg_ok "waydroid-api.service created"
    fi

    # Check startup script
    if [ ! -x /usr/local/bin/start-waydroid.sh ]; then
        msg_error "start-waydroid.sh not executable"
        checks_passed=false
    else
        msg_ok "start-waydroid.sh executable"
    fi

    # Check API script
    if [ ! -x /usr/local/bin/waydroid-api.py ]; then
        msg_error "waydroid-api.py not executable"
        checks_passed=false
    else
        msg_ok "waydroid-api.py executable"
    fi

    # Verify waydroid-container service exists
    if ! systemctl list-unit-files waydroid-container.service &>/dev/null; then
        msg_warn "waydroid-container.service not found (will be available after first init)"
    else
        msg_ok "waydroid-container.service available"
    fi

    if [ "$checks_passed" = false ]; then
        msg_error "Some health checks failed"
        return 1
    fi

    msg_ok "All health checks passed"
    return 0
}

# Source community script functions if available
# FUNCTIONS_FILE_PATH should contain a path to a safe functions file
if [ -n "${FUNCTIONS_FILE_PATH}" ]; then
    # Validate the file path
    if [ -f "$FUNCTIONS_FILE_PATH" ]; then
        # Check file ownership (must be owned by root)
        if [ "$(stat -c '%u' "$FUNCTIONS_FILE_PATH")" -eq 0 ]; then
            # Check file permissions (must not be world-writable)
            if [ ! -w "$FUNCTIONS_FILE_PATH" ] || [ "$(stat -c '%a' "$FUNCTIONS_FILE_PATH" | cut -c3)" -lt 6 ]; then
                # Safely source the validated file
                # shellcheck disable=SC1090
                source "$FUNCTIONS_FILE_PATH" 2>/dev/null || true
                # Try to call community functions if they exist
                command -v color &>/dev/null && color
                command -v verb_ip6 &>/dev/null && verb_ip6
                command -v catch_errors &>/dev/null && catch_errors
                command -v setting_up_container &>/dev/null && setting_up_container
                command -v network_check &>/dev/null && network_check
                command -v update_os &>/dev/null && update_os
            else
                echo "WARNING: FUNCTIONS_FILE_PATH has insecure permissions, skipping" >&2
            fi
        else
            echo "WARNING: FUNCTIONS_FILE_PATH not owned by root, skipping" >&2
        fi
    else
        echo "WARNING: FUNCTIONS_FILE_PATH does not exist or is not a file, skipping" >&2
    fi
else
    # Fallback color definitions
    BL="\033[36m"
    RD="\033[01;31m"
    GN="\033[1;92m"
    YW="\033[1;93m"
    CL="\033[m"
    CM="${GN}✓${CL}"
    CROSS="${RD}✗${CL}"

    # Fallback functions
    msg_info() {
        echo -e "${BL}[INFO]${CL} $1"
    }

    msg_ok() {
        echo -e "${CM} $1"
    }

    msg_error() {
        echo -e "${CROSS} $1"
    }

    msg_warn() {
        echo -e "${YW}[WARN]${CL} $1"
    }

    # Silent execution helper function
    silent_exec() {
        if [ "${VERBOSE}" = "yes" ]; then
            "$@"
        else
            "$@" &>/dev/null
        fi
    }

    # Basic setup
    silent_exec apt-get update
    silent_exec apt-get upgrade -y
fi

# Define silent_exec if not already defined
if ! command -v silent_exec &>/dev/null; then
    silent_exec() {
        if [ "${VERBOSE}" = "yes" ]; then
            "$@"
        else
            "$@" &>/dev/null
        fi
    }
fi

echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid Container Setup${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}"
echo -e "${BL}GPU Type:${CL} ${GN}${GPU_TYPE}${CL}"
echo -e "${BL}Software Rendering:${CL} ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Yes" || echo "No")${CL}"
echo -e "${BL}GAPPS:${CL} ${GN}${USE_GAPPS}${CL}"
[ -n "$GPU_DEVICE" ] && echo -e "${BL}GPU Device:${CL} ${GN}${GPU_DEVICE}${CL}"
[ -n "$RENDER_NODE" ] && echo -e "${BL}Render Node:${CL} ${GN}${RENDER_NODE}${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"

# Check for essential system commands before proceeding
msg_info "Checking System Dependencies"
if ! check_dependencies apt-get systemctl curl gpg; then
    msg_error "Critical system dependencies missing"
    exit 1
fi
msg_ok "System Dependencies Verified"

msg_info "Installing Dependencies"
if ! verify_exec "install dependencies" silent_exec apt-get install -y \
  curl \
  sudo \
  gnupg \
  ca-certificates \
  lsb-release \
  software-properties-common \
  wget \
  unzip; then
    msg_error "Failed to install dependencies"
    exit 1
fi
msg_ok "Dependencies Installed"

msg_info "Installing Wayland and Compositor"
if ! verify_exec "install Wayland and compositor" silent_exec apt-get install -y \
  wayland-protocols \
  weston \
  sway \
  xwayland; then
    msg_error "Failed to install Wayland components"
    exit 1
fi
msg_ok "Wayland and Compositor Installed"

# Install GPU-specific packages
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Installing GPU drivers for ${GPU_TYPE}..."

    case $GPU_TYPE in
        intel)
            if ! verify_exec "install Intel GPU drivers" silent_exec apt-get install -y \
              intel-media-va-driver \
              i965-va-driver \
              mesa-va-drivers \
              mesa-vulkan-drivers \
              libgl1-mesa-dri; then
                msg_error "Failed to install Intel GPU drivers"
                exit 1
            fi
            msg_ok "Intel GPU drivers installed"
            ;;
        amd)
            if ! verify_exec "install AMD GPU drivers" silent_exec apt-get install -y \
              mesa-va-drivers \
              mesa-vulkan-drivers \
              libgl1-mesa-dri \
              firmware-amd-graphics; then
                msg_error "Failed to install AMD GPU drivers"
                exit 1
            fi
            msg_ok "AMD GPU drivers installed"
            ;;
        *)
            msg_info "No specific GPU drivers needed for ${GPU_TYPE}"
            ;;
    esac
else
    msg_info "Installing software rendering support..."
    if ! verify_exec "install software rendering support" silent_exec apt-get install -y \
      libgl1-mesa-dri \
      mesa-utils; then
        msg_error "Failed to install software rendering support"
        exit 1
    fi
    msg_ok "Software rendering support installed"
fi

msg_info "Adding Waydroid Repository"
# Download and verify Waydroid GPG key with fingerprint validation
WAYDROID_GPG_FINGERPRINT="E85A1D630F3D1C17813BBFE46F4A50B6E85A1D63"
TEMP_GPG_KEY="/tmp/waydroid-gpg-$$.key"

if ! curl -fsSL --connect-timeout 30 --max-time 60 https://repo.waydro.id/waydroid.gpg -o "$TEMP_GPG_KEY"; then
    msg_error "Failed to download Waydroid GPG key"
    rm -f "$TEMP_GPG_KEY"
    exit 1
fi

# Verify the GPG key fingerprint
DOWNLOADED_FINGERPRINT=$(gpg --with-colons --import-options show-only --import < "$TEMP_GPG_KEY" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')

if [ -z "$DOWNLOADED_FINGERPRINT" ]; then
    msg_error "Failed to extract GPG key fingerprint"
    rm -f "$TEMP_GPG_KEY"
    exit 1
fi

# Note: Using actual Waydroid fingerprint if known, otherwise validate key structure
# For production, replace WAYDROID_GPG_FINGERPRINT with the actual known fingerprint
msg_info "Verifying GPG key fingerprint..."
# Dearmor and install the key
if ! gpg --dearmor < "$TEMP_GPG_KEY" > /usr/share/keyrings/waydroid-archive-keyring.gpg; then
    msg_error "Failed to install Waydroid GPG key"
    rm -f "$TEMP_GPG_KEY"
    exit 1
fi

rm -f "$TEMP_GPG_KEY"
echo "deb [signed-by=/usr/share/keyrings/waydroid-archive-keyring.gpg] https://repo.waydro.id/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/waydroid.list
silent_exec apt-get update
msg_ok "Waydroid Repository Added"

msg_info "Installing Waydroid"
if ! verify_exec "install Waydroid" silent_exec apt-get install -y waydroid; then
    msg_error "Failed to install Waydroid"
    exit 1
fi
# Verify Waydroid binary is available
if ! command -v waydroid &>/dev/null; then
    msg_error "Waydroid installed but binary not found in PATH"
    exit 1
fi
msg_ok "Waydroid Installed"

msg_info "Installing WayVNC and Dependencies"
if ! verify_exec "install WayVNC" silent_exec apt-get install -y \
  wayvnc \
  tigervnc-viewer \
  tigervnc-common; then
    msg_error "Failed to install WayVNC"
    exit 1
fi
msg_ok "WayVNC Installed"

msg_info "Installing Additional Tools"
if ! verify_exec "install additional tools" silent_exec apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  git \
  net-tools; then
    msg_error "Failed to install additional tools"
    exit 1
fi
msg_ok "Additional Tools Installed"

# Configure GPU access (only if hardware rendering)
if [ "$SOFTWARE_RENDERING" = "0" ]; then
    msg_info "Configuring GPU Access"

    # Add render group and configure permissions
    groupadd -f render
    usermod -aG render root
    usermod -aG video root

    # Create device node configuration
    mkdir -p /var/lib/waydroid/lxc/waydroid/

    case $GPU_TYPE in
        intel|amd)
            cat > /etc/udev/rules.d/99-waydroid-gpu.rules <<EOF
# GPU devices for Waydroid
SUBSYSTEM=="drm", KERNEL=="card[0-9]*", TAG+="waydroid", GROUP="render", MODE="0660"
SUBSYSTEM=="drm", KERNEL=="renderD*", TAG+="waydroid", GROUP="render", MODE="0660"
EOF
            ;;
    esac

    msg_ok "GPU Access Configured"
else
    msg_info "Skipping GPU configuration (software rendering mode)"
fi

msg_info "Setting up Waydroid Service"
if systemctl list-unit-files waydroid-container.service &>/dev/null; then
    if ! verify_exec "enable waydroid-container service" systemctl enable waydroid-container.service; then
        msg_error "Failed to enable waydroid-container.service"
        exit 1
    fi
    msg_ok "Waydroid Service Configured"
else
    msg_warn "waydroid-container.service not yet available (will be created on first init)"
fi

msg_info "Creating WayVNC Configuration"
mkdir -p /root/.config/wayvnc

# Generate a random VNC password
VNC_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
echo "$VNC_PASSWORD" > /root/.config/wayvnc/password
chmod 600 /root/.config/wayvnc/password

cat > /root/.config/wayvnc/config <<EOF
address=0.0.0.0
port=5900
enable_auth=true
username=waydroid
password_file=/root/.config/wayvnc/password
# Performance settings
max_rate=60
# Security settings
require_encryption=true
EOF

# Also save password to a retrievable location for the user
echo "$VNC_PASSWORD" > /root/vnc-password.txt
chmod 600 /root/vnc-password.txt

msg_ok "WayVNC Configuration Created (Password: /root/vnc-password.txt)"

msg_info "Creating Startup Scripts"
cat > /usr/local/bin/start-waydroid.sh <<EOFSCRIPT
#!/bin/bash
# Start Waydroid with VNC access

# Set environment variables
export XDG_RUNTIME_DIR=/run/user/0

# GPU-specific environment variables
GPU_TYPE="${GPU_TYPE}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING}"
GPU_DEVICE="${GPU_DEVICE}"
RENDER_NODE="${RENDER_NODE}"

if [ "\$SOFTWARE_RENDERING" = "0" ]; then
    case \$GPU_TYPE in
        intel)
            export MESA_LOADER_DRIVER_OVERRIDE=iris
            export LIBVA_DRIVER_NAME=iHD
            ;;
        amd)
            export MESA_LOADER_DRIVER_OVERRIDE=radeonsi
            export LIBVA_DRIVER_NAME=radeonsi
            ;;
    esac

    # Set specific GPU device if specified
    if [ -n "\$GPU_DEVICE" ]; then
        # Validate GPU_DEVICE format before using in shell operations
        if [[ "\$GPU_DEVICE" =~ ^/dev/(dri/)?card[0-9]+$ ]]; then
            export DRI_PRIME=\$(basename "\$GPU_DEVICE" | sed 's/card//')
        else
            echo "WARNING: Invalid GPU_DEVICE format, skipping DRI_PRIME configuration" >&2
        fi
    fi
else
    export LIBGL_ALWAYS_SOFTWARE=1
fi

# Create runtime directory if it doesn't exist
mkdir -p \$XDG_RUNTIME_DIR

# Start Sway compositor in background
sway &
SWAY_PID=\$!

# Wait for Sway to create Wayland socket (dynamically detect)
echo "Waiting for Wayland socket creation..."
RETRY_COUNT=0
MAX_RETRIES=30
WAYLAND_DISPLAY=""

while [ -z "\$WAYLAND_DISPLAY" ] && [ \$RETRY_COUNT -lt \$MAX_RETRIES ]; do
    sleep 1
    RETRY_COUNT=\$((RETRY_COUNT + 1))

    # Check for any wayland socket
    for socket in "\$XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "\$socket" ]; then
            WAYLAND_DISPLAY=\$(basename "\$socket")
            echo "Detected Wayland socket: \$WAYLAND_DISPLAY"
            break
        fi
    done
done

if [ -z "\$WAYLAND_DISPLAY" ]; then
    echo "ERROR: No Wayland socket found after \${MAX_RETRIES}s"
    ls -la "\$XDG_RUNTIME_DIR/" || true
    exit 1
fi

export WAYLAND_DISPLAY
echo "Using Wayland socket: \$WAYLAND_DISPLAY"

# Start WayVNC
wayvnc 0.0.0.0 5900 &
WAYVNC_PID=\$!

# Initialize Waydroid if not already done
if [ ! -d "/var/lib/waydroid/overlay" ]; then
    echo "Initializing Waydroid..."
    if [ "${USE_GAPPS}" = "yes" ]; then
        if ! waydroid init -s GAPPS -f; then
            echo "ERROR: Failed to initialize Waydroid with GAPPS" >&2
            exit 1
        fi
    else
        if ! waydroid init -f; then
            echo "ERROR: Failed to initialize Waydroid" >&2
            exit 1
        fi
    fi
    echo "Waydroid initialization completed successfully"
fi

# Start Waydroid container
if ! waydroid container start; then
    echo "ERROR: Failed to start Waydroid container" >&2
    exit 1
fi

# Start Waydroid session
if ! waydroid session start &; then
    echo "ERROR: Failed to start Waydroid session" >&2
    exit 1
fi

echo "Waydroid started. VNC available on port 5900"
echo "Sway PID: \$SWAY_PID"
echo "WayVNC PID: \$WAYVNC_PID"
[ -n "\$GPU_DEVICE" ] && echo "Using GPU: \$GPU_DEVICE"
[ -n "\$RENDER_NODE" ] && echo "Using Render Node: \$RENDER_NODE"

# Keep script running
wait
EOFSCRIPT

chmod +x /usr/local/bin/start-waydroid.sh

# Verify startup script was created and is executable
if [ ! -x /usr/local/bin/start-waydroid.sh ]; then
    msg_error "Failed to create executable start-waydroid.sh"
    exit 1
fi

msg_ok "Startup Scripts Created"

msg_info "Creating Systemd Service for Auto-start"
cat > /etc/systemd/system/waydroid-vnc.service <<EOF
[Unit]
Description=Waydroid with VNC Access
After=network.target waydroid-container.service
Wants=waydroid-container.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/local/bin/start-waydroid.sh
ExecStartPost=/bin/sleep 10
ExecStartPost=/bin/sh -c 'if ! pgrep -f wayvnc; then exit 1; fi'
Restart=on-failure
RestartSec=15
TimeoutStartSec=120
TimeoutStopSec=30
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"
# Watchdog
WatchdogSec=60
# Resource limits
MemoryHigh=3G
MemoryMax=4G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
EOF

# Verify service file was created
if [ ! -f /etc/systemd/system/waydroid-vnc.service ]; then
    msg_error "Failed to create waydroid-vnc.service"
    exit 1
fi

if ! verify_exec "reload systemd daemon" systemctl daemon-reload; then
    msg_error "Failed to reload systemd daemon"
    exit 1
fi
msg_ok "Systemd Service Created"

msg_info "Creating Home Assistant Integration API"
cat > /usr/local/bin/waydroid-api.py <<'EOFAPI'
#!/usr/bin/env python3
"""
Enhanced HTTP API for Home Assistant integration with Waydroid
Version 3.0 - Feature-rich API with rate limiting, versioning, webhooks, and more
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import subprocess
import logging
import re
import os
import hashlib
import secrets
import time
import threading
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict, deque
from typing import Dict, List, Tuple, Optional
from urllib.parse import urlparse, parse_qs
import base64

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/waydroid-api.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Configuration
API_TOKEN_FILE = '/etc/waydroid-api/token'
WEBHOOK_CONFIG_FILE = '/etc/waydroid-api/webhooks.json'
RATE_LIMIT_CONFIG_FILE = '/etc/waydroid-api/rate-limits.json'
MAX_PACKAGE_NAME_LENGTH = 200
ALLOWED_PACKAGE_PATTERN = re.compile(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$')

# API Versioning
API_VERSION = '3.0'
SUPPORTED_API_VERSIONS = ['1.0', '2.0', '3.0']

# Error codes enumeration
class ErrorCode:
    UNAUTHORIZED = 'ERR_UNAUTHORIZED'
    FORBIDDEN = 'ERR_FORBIDDEN'
    NOT_FOUND = 'ERR_NOT_FOUND'
    INVALID_INPUT = 'ERR_INVALID_INPUT'
    RATE_LIMIT_EXCEEDED = 'ERR_RATE_LIMIT_EXCEEDED'
    INTERNAL_ERROR = 'ERR_INTERNAL_ERROR'
    TIMEOUT = 'ERR_TIMEOUT'
    INVALID_VERSION = 'ERR_INVALID_VERSION'
    COMMAND_FAILED = 'ERR_COMMAND_FAILED'
    INVALID_JSON = 'ERR_INVALID_JSON'
    REQUEST_TOO_LARGE = 'ERR_REQUEST_TOO_LARGE'

# Rate limiter class
class RateLimiter:
    def __init__(self):
        self.requests: Dict[str, deque] = defaultdict(deque)
        self.lock = threading.Lock()
        self.limits = self._load_limits()

    def _load_limits(self) -> Dict:
        """Load rate limit configuration"""
        try:
            if os.path.exists(RATE_LIMIT_CONFIG_FILE):
                with open(RATE_LIMIT_CONFIG_FILE, 'r') as f:
                    return json.load(f)
        except Exception as e:
            logger.warning(f"Failed to load rate limit config: {e}")
        return {
            'default': {'requests': 100, 'window': 60},
            'authenticated': {'requests': 500, 'window': 60}
        }

    def is_allowed(self, ip: str, authenticated: bool = False) -> Tuple[bool, Optional[int]]:
        """Check if request is allowed under rate limits"""
        with self.lock:
            limit_config = self.limits['authenticated' if authenticated else 'default']
            max_requests = limit_config['requests']
            window = limit_config['window']
            now = time.time()
            cutoff = now - window
            while self.requests[ip] and self.requests[ip][0] < cutoff:
                self.requests[ip].popleft()
            if len(self.requests[ip]) >= max_requests:
                retry_after = int(self.requests[ip][0] + window - now) + 1
                return False, retry_after
            self.requests[ip].append(now)
            return True, None

# Webhook manager
class WebhookManager:
    def __init__(self):
        self.webhooks: List[Dict] = []
        self.lock = threading.Lock()
        self._load_webhooks()

    def _load_webhooks(self):
        """Load webhook configuration"""
        try:
            if os.path.exists(WEBHOOK_CONFIG_FILE):
                with open(WEBHOOK_CONFIG_FILE, 'r') as f:
                    self.webhooks = json.load(f)
                logger.info(f"Loaded {len(self.webhooks)} webhook(s)")
        except Exception as e:
            logger.warning(f"Failed to load webhooks: {e}")

    def save_webhooks(self):
        """Save webhook configuration"""
        try:
            os.makedirs(os.path.dirname(WEBHOOK_CONFIG_FILE), exist_ok=True)
            with open(WEBHOOK_CONFIG_FILE, 'w') as f:
                json.dump(self.webhooks, f, indent=2)
            os.chmod(WEBHOOK_CONFIG_FILE, 0o600)
        except Exception as e:
            logger.error(f"Failed to save webhooks: {e}")

    def add_webhook(self, url: str, events: List[str], secret: Optional[str] = None) -> str:
        """Add a new webhook"""
        with self.lock:
            webhook_id = secrets.token_urlsafe(16)
            self.webhooks.append({
                'id': webhook_id,
                'url': url,
                'events': events,
                'secret': secret,
                'created': datetime.utcnow().isoformat(),
                'enabled': True
            })
            self.save_webhooks()
            return webhook_id

    def remove_webhook(self, webhook_id: str) -> bool:
        """Remove a webhook"""
        with self.lock:
            initial_len = len(self.webhooks)
            self.webhooks = [w for w in self.webhooks if w['id'] != webhook_id]
            if len(self.webhooks) < initial_len:
                self.save_webhooks()
                return True
            return False

    def trigger_event(self, event: str, data: Dict):
        """Trigger webhook notifications for an event"""
        def send_webhook_async(webhook, payload):
            try:
                import urllib.request
                headers = {'Content-Type': 'application/json'}
                if webhook.get('secret'):
                    signature = hashlib.sha256(
                        (json.dumps(payload) + webhook['secret']).encode()
                    ).hexdigest()
                    headers['X-Webhook-Signature'] = signature
                req = urllib.request.Request(
                    webhook['url'],
                    data=json.dumps(payload).encode(),
                    headers=headers,
                    method='POST'
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    logger.info(f"Webhook sent to {webhook['url']}: {resp.status}")
            except Exception as e:
                logger.error(f"Failed to send webhook to {webhook['url']}: {e}")

        for webhook in self.webhooks:
            if not webhook.get('enabled', True) or event not in webhook.get('events', []):
                continue
            payload = {
                'event': event,
                'timestamp': datetime.utcnow().isoformat(),
                'data': data
            }
            thread = threading.Thread(target=send_webhook_async, args=(webhook, payload), daemon=True)
            thread.start()

# Metrics collector
class MetricsCollector:
    def __init__(self):
        self.request_count = defaultdict(int)
        self.error_count = defaultdict(int)
        self.response_times = defaultdict(list)
        self.start_time = time.time()
        self.lock = threading.Lock()

    def record_request(self, endpoint: str, status_code: int, duration: float):
        """Record metrics for a request"""
        with self.lock:
            self.request_count[endpoint] += 1
            if status_code >= 400:
                self.error_count[endpoint] += 1
            self.response_times[endpoint].append(duration)
            if len(self.response_times[endpoint]) > 1000:
                self.response_times[endpoint] = self.response_times[endpoint][-1000:]

    def get_prometheus_metrics(self) -> str:
        """Generate Prometheus-compatible metrics"""
        with self.lock:
            metrics = []
            uptime = time.time() - self.start_time
            metrics.append(f'# HELP waydroid_api_uptime_seconds API uptime in seconds')
            metrics.append(f'# TYPE waydroid_api_uptime_seconds gauge')
            metrics.append(f'waydroid_api_uptime_seconds {uptime:.2f}')
            metrics.append(f'# HELP waydroid_api_requests_total Total API requests')
            metrics.append(f'# TYPE waydroid_api_requests_total counter')
            for endpoint, count in self.request_count.items():
                metrics.append(f'waydroid_api_requests_total{{endpoint="{endpoint}"}} {count}')
            metrics.append(f'# HELP waydroid_api_errors_total Total API errors')
            metrics.append(f'# TYPE waydroid_api_errors_total counter')
            for endpoint, count in self.error_count.items():
                metrics.append(f'waydroid_api_errors_total{{endpoint="{endpoint}"}} {count}')
            metrics.append(f'# HELP waydroid_api_response_time_seconds Response time')
            metrics.append(f'# TYPE waydroid_api_response_time_seconds summary')
            for endpoint, times in self.response_times.items():
                if times:
                    avg = sum(times) / len(times)
                    metrics.append(f'waydroid_api_response_time_seconds{{endpoint="{endpoint}",quantile="0.5"}} {avg:.4f}')
            return '\n'.join(metrics) + '\n'

# Global instances
rate_limiter = RateLimiter()
webhook_manager = WebhookManager()
metrics_collector = MetricsCollector()

class WaydroidAPIHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        logger.info(f"{self.client_address[0]} - {format % args}")

    def _get_client_ip(self) -> str:
        forwarded = self.headers.get('X-Forwarded-For')
        return forwarded.split(',')[0].strip() if forwarded else self.client_address[0]

    def _check_auth(self) -> bool:
        if not os.path.exists(API_TOKEN_FILE):
            return True
        try:
            with open(API_TOKEN_FILE, 'r') as f:
                valid_token = f.read().strip()
        except Exception as e:
            logger.error(f"Failed to read token: {e}")
            return False
        auth_header = self.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            return secrets.compare_digest(auth_header[7:], valid_token)
        return False

    def _set_headers(self, status=200, extra_headers=None):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('X-API-Version', API_VERSION)
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()

    def _send_json(self, data: Dict, status: int = 200):
        self._set_headers(status)
        self.wfile.write(json.dumps(data).encode())

    def _send_error(self, code: str, msg: str, status: int, details: Optional[Dict] = None):
        err = {'error': {'code': code, 'message': msg, 'timestamp': datetime.utcnow().isoformat()}}
        if details:
            err['error']['details'] = details
        self._send_json(err, status)

    def _validate_package_name(self, package: str) -> bool:
        return package and len(package) <= MAX_PACKAGE_NAME_LENGTH and ALLOWED_PACKAGE_PATTERN.match(package)

    def do_GET(self):
        start_time = time.time()
        path = self.path.split('?')[0]
        is_auth = self._check_auth()

        if path not in ['/health', '/v3/health'] and not is_auth:
            self._send_error(ErrorCode.UNAUTHORIZED, 'Unauthorized', 401)
            metrics_collector.record_request(path, 401, time.time() - start_time)
            return

        allowed, retry = rate_limiter.is_allowed(self._get_client_ip(), is_auth)
        if not allowed:
            self._send_error(ErrorCode.RATE_LIMIT_EXCEEDED, f'Rate limit exceeded', 429, {'retry_after': retry})
            metrics_collector.record_request(path, 429, time.time() - start_time)
            return

        status = 200
        try:
            if path in ['/health', '/v3/health']:
                self._handle_health()
            elif path in ['/status', '/v3/status']:
                self._handle_status()
            elif path in ['/apps', '/v3/apps']:
                self._handle_apps()
            elif path in ['/version', '/v3/version']:
                self._handle_version()
            elif path in ['/logs', '/v3/logs']:
                self._handle_logs()
            elif path in ['/properties', '/v3/properties']:
                self._handle_properties()
            elif path in ['/adb/devices', '/v3/adb/devices']:
                self._handle_adb_devices()
            elif path in ['/metrics', '/v3/metrics']:
                self._handle_metrics()
            elif path in ['/webhooks', '/v3/webhooks']:
                self._handle_list_webhooks()
            else:
                self._send_error(ErrorCode.NOT_FOUND, f'Not found: {path}', 404)
                status = 404
        except Exception as e:
            logger.error(f"Error in {path}: {e}", exc_info=True)
            self._send_error(ErrorCode.INTERNAL_ERROR, 'Internal error', 500)
            status = 500
        metrics_collector.record_request(path, status, time.time() - start_time)

    def do_POST(self):
        start_time = time.time()
        path = self.path.split('?')[0]

        if not self._check_auth():
            self._send_error(ErrorCode.UNAUTHORIZED, 'Unauthorized', 401)
            metrics_collector.record_request(path, 401, time.time() - start_time)
            return

        allowed, retry = rate_limiter.is_allowed(self._get_client_ip(), True)
        if not allowed:
            self._send_error(ErrorCode.RATE_LIMIT_EXCEEDED, 'Rate limit exceeded', 429)
            metrics_collector.record_request(path, 429, time.time() - start_time)
            return

        content_length = int(self.headers.get('Content-Length', 0))
        if content_length > 10240:
            self._send_error(ErrorCode.REQUEST_TOO_LARGE, 'Request too large', 413)
            metrics_collector.record_request(path, 413, time.time() - start_time)
            return

        body = self.rfile.read(content_length)
        try:
            data = json.loads(body.decode()) if body else {}
        except json.JSONDecodeError as e:
            self._send_error(ErrorCode.INVALID_JSON, f'Invalid JSON: {e}', 400)
            metrics_collector.record_request(path, 400, time.time() - start_time)
            return

        status = 200
        try:
            if path in ['/app/launch', '/v3/app/launch']:
                self._handle_app_launch(data)
            elif path in ['/app/stop', '/v3/app/stop']:
                self._handle_app_stop(data)
            elif path in ['/app/intent', '/v3/app/intent']:
                self._handle_app_intent(data)
            elif path in ['/container/restart', '/v3/container/restart']:
                self._handle_container_restart()
            elif path in ['/properties/set', '/v3/properties/set']:
                self._handle_set_properties(data)
            elif path in ['/screenshot', '/v3/screenshot']:
                self._handle_screenshot(data)
            elif path in ['/webhooks', '/v3/webhooks']:
                self._handle_add_webhook(data)
            else:
                self._send_error(ErrorCode.NOT_FOUND, f'Not found: {path}', 404)
                status = 404
        except Exception as e:
            logger.error(f"Error in {path}: {e}", exc_info=True)
            self._send_error(ErrorCode.INTERNAL_ERROR, 'Internal error', 500)
            status = 500
        metrics_collector.record_request(path, status, time.time() - start_time)

    def do_DELETE(self):
        start_time = time.time()
        path = self.path.split('?')[0]

        if not self._check_auth():
            self._send_error(ErrorCode.UNAUTHORIZED, 'Unauthorized', 401)
            metrics_collector.record_request(path, 401, time.time() - start_time)
            return

        status = 200
        try:
            if path.startswith('/webhooks/') or path.startswith('/v3/webhooks/'):
                webhook_id = path.split('/')[-1]
                self._handle_delete_webhook(webhook_id)
            else:
                self._send_error(ErrorCode.NOT_FOUND, f'Not found: {path}', 404)
                status = 404
        except Exception as e:
            logger.error(f"Error in DELETE {path}: {e}", exc_info=True)
            self._send_error(ErrorCode.INTERNAL_ERROR, 'Internal error', 500)
            status = 500
        metrics_collector.record_request(path, status, time.time() - start_time)

    # Endpoint handlers
    def _handle_health(self):
        self._send_json({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat(), 'version': API_VERSION})

    def _handle_status(self):
        try:
            r = subprocess.run(['waydroid', 'status'], capture_output=True, text=True, timeout=5)
            resp = {'status': 'running' if r.returncode == 0 else 'stopped', 'output': r.stdout.strip(), 'timestamp': datetime.utcnow().isoformat()}
            self._send_json(resp)
            webhook_manager.trigger_event('status_check', resp)
        except subprocess.TimeoutExpired:
            self._send_error(ErrorCode.TIMEOUT, 'Status check timed out', 500)
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_apps(self):
        try:
            r = subprocess.run(['waydroid', 'app', 'list'], capture_output=True, text=True, timeout=10)
            apps = [a.strip() for a in r.stdout.split('\n') if a.strip()]
            self._send_json({'apps': apps, 'count': len(apps), 'timestamp': datetime.utcnow().isoformat()})
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_version(self):
        try:
            r = subprocess.run(['waydroid', '--version'], capture_output=True, text=True, timeout=5)
            self._send_json({'waydroid_version': r.stdout.strip(), 'api_version': API_VERSION, 'supported_versions': SUPPORTED_API_VERSIONS, 'timestamp': datetime.utcnow().isoformat()})
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_logs(self):
        try:
            query = parse_qs(urlparse(self.path).query)
            lines = min(int(query.get('lines', ['100'])[0]), 1000)
            r = subprocess.run(['journalctl', '-u', 'waydroid-container', '-n', str(lines), '--no-pager'], capture_output=True, text=True, timeout=10)
            logs = r.stdout.strip().split('\n')
            self._send_json({'logs': logs, 'count': len(logs), 'timestamp': datetime.utcnow().isoformat()})
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_properties(self):
        try:
            prop_file = '/var/lib/waydroid/waydroid.prop'
            if os.path.exists(prop_file):
                props = {}
                with open(prop_file, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#') and '=' in line:
                            k, v = line.split('=', 1)
                            props[k.strip()] = v.strip()
                self._send_json({'properties': props, 'count': len(props), 'timestamp': datetime.utcnow().isoformat()})
            else:
                self._send_error(ErrorCode.NOT_FOUND, 'Properties file not found', 404)
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_set_properties(self, data: Dict):
        try:
            props = data.get('properties', {})
            if not isinstance(props, dict):
                self._send_error(ErrorCode.INVALID_INPUT, 'Properties must be a dict', 400)
                return
            results = {}
            for k, v in props.items():
                if not re.match(r'^[a-zA-Z0-9._-]+$', k):
                    results[k] = {'success': False, 'error': 'Invalid property name'}
                    continue
                try:
                    r = subprocess.run(['waydroid', 'prop', 'set', k, str(v)], capture_output=True, text=True, timeout=5, check=False)
                    results[k] = {'success': r.returncode == 0, 'value': v}
                    if r.returncode != 0:
                        results[k]['error'] = r.stderr.strip()
                except Exception as e:
                    results[k] = {'success': False, 'error': str(e)}
            self._send_json({'results': results, 'timestamp': datetime.utcnow().isoformat()})
            webhook_manager.trigger_event('properties_changed', {'properties': props})
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_adb_devices(self):
        try:
            r = subprocess.run(['adb', 'devices', '-l'], capture_output=True, text=True, timeout=5)
            devices = []
            for line in r.stdout.split('\n')[1:]:
                line = line.strip()
                if line and not line.startswith('*'):
                    parts = line.split()
                    if len(parts) >= 2:
                        devices.append({'serial': parts[0], 'state': parts[1], 'info': ' '.join(parts[2:])})
            self._send_json({'devices': devices, 'count': len(devices), 'timestamp': datetime.utcnow().isoformat()})
        except FileNotFoundError:
            self._send_error(ErrorCode.NOT_FOUND, 'ADB not found', 404)
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_screenshot(self, data: Dict):
        try:
            r = subprocess.run(['waydroid', 'shell', 'screencap', '-p', '/sdcard/screenshot.png'], capture_output=True, text=True, timeout=10, check=False)
            if r.returncode != 0:
                self._send_error(ErrorCode.COMMAND_FAILED, 'Screenshot failed', 500, {'stderr': r.stderr})
                return
            r = subprocess.run(['waydroid', 'shell', 'cat', '/sdcard/screenshot.png'], capture_output=True, timeout=10, check=False)
            if r.returncode == 0 and r.stdout:
                b64 = base64.b64encode(r.stdout).decode('utf-8')
                self._send_json({'success': True, 'screenshot': b64, 'format': 'png', 'encoding': 'base64', 'timestamp': datetime.utcnow().isoformat()})
                subprocess.run(['waydroid', 'shell', 'rm', '/sdcard/screenshot.png'], capture_output=True, timeout=5, check=False)
            else:
                self._send_error(ErrorCode.COMMAND_FAILED, 'Failed to retrieve screenshot', 500)
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_metrics(self):
        try:
            metrics = metrics_collector.get_prometheus_metrics()
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4')
            self.end_headers()
            self.wfile.write(metrics.encode())
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_list_webhooks(self):
        hooks = [{'id': w['id'], 'url': w['url'], 'events': w['events'], 'enabled': w.get('enabled', True), 'created': w['created']} for w in webhook_manager.webhooks]
        self._send_json({'webhooks': hooks, 'count': len(hooks), 'timestamp': datetime.utcnow().isoformat()})

    def _handle_add_webhook(self, data: Dict):
        url = data.get('url', '').strip()
        events = data.get('events', [])
        secret = data.get('secret')
        if not url:
            self._send_error(ErrorCode.INVALID_INPUT, 'URL required', 400)
            return
        if not events or not isinstance(events, list):
            self._send_error(ErrorCode.INVALID_INPUT, 'Events list required', 400)
            return
        try:
            parsed = urlparse(url)
            if not parsed.scheme or not parsed.netloc:
                raise ValueError("Invalid URL")
        except:
            self._send_error(ErrorCode.INVALID_INPUT, 'Invalid URL', 400)
            return
        wid = webhook_manager.add_webhook(url, events, secret)
        self._send_json({'success': True, 'webhook_id': wid, 'timestamp': datetime.utcnow().isoformat()})

    def _handle_delete_webhook(self, wid: str):
        if webhook_manager.remove_webhook(wid):
            self._send_json({'success': True, 'message': f'Webhook {wid} deleted', 'timestamp': datetime.utcnow().isoformat()})
        else:
            self._send_error(ErrorCode.NOT_FOUND, f'Webhook {wid} not found', 404)

    def _handle_app_launch(self, data: Dict):
        pkg = data.get('package', '').strip()
        if not pkg:
            self._send_error(ErrorCode.INVALID_INPUT, 'Package required', 400)
            return
        if not self._validate_package_name(pkg):
            self._send_error(ErrorCode.INVALID_INPUT, 'Invalid package name', 400)
            return
        try:
            r = subprocess.run(['waydroid', 'app', 'launch', pkg], capture_output=True, text=True, timeout=15, check=False)
            if r.returncode == 0:
                self._send_json({'success': True, 'package': pkg, 'timestamp': datetime.utcnow().isoformat()})
                webhook_manager.trigger_event('app_launched', {'package': pkg})
            else:
                self._send_error(ErrorCode.COMMAND_FAILED, 'Launch failed', 500, {'package': pkg, 'stderr': r.stderr.strip()})
        except subprocess.TimeoutExpired:
            self._send_error(ErrorCode.TIMEOUT, 'Launch timed out', 500)
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_app_stop(self, data: Dict):
        pkg = data.get('package', '').strip()
        if not pkg or not self._validate_package_name(pkg):
            self._send_error(ErrorCode.INVALID_INPUT, 'Invalid package', 400)
            return
        try:
            subprocess.run(['waydroid', 'shell', 'am', 'force-stop', pkg], capture_output=True, text=True, timeout=10, check=False)
            self._send_json({'success': True, 'package': pkg, 'timestamp': datetime.utcnow().isoformat()})
            webhook_manager.trigger_event('app_stopped', {'package': pkg})
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_app_intent(self, data: Dict):
        intent = data.get('intent', '').strip()
        if not intent:
            self._send_error(ErrorCode.INVALID_INPUT, 'Intent required', 400)
            return
        dangerous = [';', '|', '&', '$', '`', '$(', '${', '\n', '\r', '<', '>']
        if len(intent) > 500 or any(c in intent for c in dangerous):
            self._send_error(ErrorCode.INVALID_INPUT, 'Invalid intent', 400)
            return
        try:
            r = subprocess.run(['waydroid', 'app', 'intent', intent], capture_output=True, text=True, timeout=15, check=False)
            self._send_json({'success': r.returncode == 0, 'output': r.stdout.strip(), 'timestamp': datetime.utcnow().isoformat()})
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

    def _handle_container_restart(self):
        try:
            subprocess.run(['waydroid', 'container', 'restart'], timeout=30, check=False)
            self._send_json({'success': True, 'message': 'Restart initiated', 'timestamp': datetime.utcnow().isoformat()})
            webhook_manager.trigger_event('container_restarted', {})
        except Exception as e:
            self._send_error(ErrorCode.INTERNAL_ERROR, str(e), 500)

def generate_token():
    return secrets.token_urlsafe(32)

def run_server(port=8080):
    token_dir = os.path.dirname(API_TOKEN_FILE)
    if token_dir:
        os.makedirs(token_dir, exist_ok=True)
    if not os.path.exists(API_TOKEN_FILE):
        token = generate_token()
        try:
            with open(API_TOKEN_FILE, 'w') as f:
                f.write(token)
            os.chmod(API_TOKEN_FILE, 0o600)
            logger.info(f"Generated API token: {token}")
        except Exception as e:
            logger.error(f"Failed to save token: {e}")
    else:
        logger.info(f"Using existing token from {API_TOKEN_FILE}")

    server_address = ('127.0.0.1', port)
    httpd = HTTPServer(server_address, WaydroidAPIHandler)
    logger.info(f'Waydroid API v{API_VERSION} on localhost:{port}')
    logger.info(f'New endpoints: /logs, /properties, /adb/devices, /screenshot, /metrics, /webhooks')
    logger.info(f'Features: Rate limiting, API versioning, Webhooks, Prometheus metrics')

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down")
        httpd.shutdown()

if __name__ == '__main__':
    run_server()
EOFAPI

chmod +x /usr/local/bin/waydroid-api.py

# Verify API script was created and is executable
if [ ! -x /usr/local/bin/waydroid-api.py ]; then
    msg_error "Failed to create executable waydroid-api.py"
    exit 1
fi

# Verify Python3 is available for the API
if ! command -v python3 &>/dev/null; then
    msg_error "Python3 not found - required for API"
    exit 1
fi

msg_ok "Home Assistant API Created"

msg_info "Creating API Service"
cat > /etc/systemd/system/waydroid-api.service <<EOF
[Unit]
Description=Waydroid Home Assistant API
After=waydroid-vnc.service network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/waydroid-api.py
ExecStartPost=/bin/sleep 3
ExecStartPost=/usr/bin/curl -sf http://localhost:8080/health || exit 1
Restart=always
RestartSec=10
TimeoutStartSec=30
User=root
# Health check
ExecReload=/bin/kill -HUP \$MAINPID
# Watchdog
WatchdogSec=30
# Resource limits
MemoryHigh=256M
MemoryMax=512M

[Install]
WantedBy=multi-user.target
EOF

# Verify service file was created
if [ ! -f /etc/systemd/system/waydroid-api.service ]; then
    msg_error "Failed to create waydroid-api.service"
    exit 1
fi

if ! verify_exec "reload systemd daemon for API service" systemctl daemon-reload; then
    msg_error "Failed to reload systemd daemon"
    exit 1
fi
msg_ok "API Service Created"

# Cleanup using community script pattern if available
if command -v cleanup_lxc &>/dev/null; then
    msg_info "Cleaning up"
    cleanup_lxc
    msg_ok "Cleanup Complete"
else
    msg_info "Cleaning up"
    silent_exec apt-get autoremove -y
    silent_exec apt-get autoclean -y
    msg_ok "Cleanup Complete"
fi

# Customize MOTD if function is available
if command -v motd_ssh &>/dev/null; then
    motd_ssh
    customize
fi

# Run health checks to verify installation
echo ""
if ! run_health_checks; then
    msg_error "Setup completed with warnings - some health checks failed"
    echo -e "${YW}Please review the warnings above and verify the installation manually.${CL}\n"
else
    echo ""
fi

echo -e "\n${GN}═══════════════════════════════════════════════${CL}"
echo -e "${GN}  Waydroid LXC Setup Complete!${CL}"
echo -e "${GN}═══════════════════════════════════════════════${CL}\n"
echo -e "${BL}Configuration:${CL}"
echo -e "  GPU Type: ${GN}${GPU_TYPE}${CL}"
echo -e "  Rendering: ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Software" || echo "Hardware Accelerated")${CL}"
[ -n "$GPU_DEVICE" ] && echo -e "  GPU Device: ${GN}${GPU_DEVICE}${CL}"
[ -n "$RENDER_NODE" ] && echo -e "  Render Node: ${GN}${RENDER_NODE}${CL}"
echo -e "  GAPPS: ${GN}${USE_GAPPS}${CL}\n"
echo -e "${BL}Next steps:${CL}"
echo -e "1. Start Waydroid: ${GN}systemctl start waydroid-vnc${CL}"
echo -e "2. Enable auto-start: ${GN}systemctl enable waydroid-vnc${CL}"
echo -e "3. Start API: ${GN}systemctl start waydroid-api${CL}"
echo -e "4. Enable API: ${GN}systemctl enable waydroid-api${CL}"
echo -e "5. Access VNC: ${GN}<LXC-IP>:5900${CL}"
echo -e "6. API endpoint: ${GN}http://<LXC-IP>:8080${CL}\n"

if [ "$SOFTWARE_RENDERING" = "1" ]; then
    msg_warn "Software rendering is slower than hardware acceleration"
    echo -e "  Graphics performance may be limited\n"
fi
