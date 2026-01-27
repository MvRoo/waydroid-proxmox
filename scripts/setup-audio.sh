#!/usr/bin/env bash

# Waydroid Audio Passthrough Setup Script
# Copyright (c) 2025
# License: MIT
# https://github.com/MvRoo/waydroid-proxmox
#
# This script configures audio passthrough for Waydroid running in LXC containers
# on Proxmox VE. It supports both PulseAudio and PipeWire.
#
# Usage:
#   ./setup-audio.sh [options] <ctid>
#
# Options:
#   --dry-run              Show what would be done without making changes
#   --force-pulseaudio     Force PulseAudio configuration (even if PipeWire detected)
#   --force-pipewire       Force PipeWire configuration (even if PulseAudio detected)
#   --host-only            Only configure host (skip container configuration)
#   --container-only       Only configure container (skip host configuration)
#   --test-only            Run audio tests only
#   --no-restart           Don't restart services after configuration
#   --help                 Show this help message
#
# Examples:
#   ./setup-audio.sh 100                    # Auto-detect and configure audio for CT 100
#   ./setup-audio.sh --dry-run 100          # Preview changes
#   ./setup-audio.sh --force-pipewire 100   # Force PipeWire configuration
#   ./setup-audio.sh --test-only 100        # Test existing audio setup
#
# Requirements:
#   - Proxmox VE host
#   - Running LXC container with Waydroid
#   - PulseAudio or PipeWire on host

set -euo pipefail

# Source helper functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/helper-functions.sh" ]; then
    source "$SCRIPT_DIR/helper-functions.sh"
else
    # Minimal fallback functions
    BL="\033[36m"
    RD="\033[01;31m"
    GN="\033[1;92m"
    YW="\033[1;93m"
    CL="\033[m"
    CM="${GN}✓${CL}"
    CROSS="${RD}✗${CL}"

    msg_info() { echo -e "${BL}[INFO]${CL} $1"; }
    msg_ok() { echo -e "${CM} $1"; }
    msg_error() { echo -e "${CROSS} $1"; }
    msg_warn() { echo -e "${YW}[WARN]${CL} $1"; }
fi

# ============================================================================
# CONSTANTS AND DEFAULTS
# ============================================================================

VERSION="1.0.0"
AUDIO_DEVICES=(
    "/dev/snd"
)
PULSEAUDIO_SOCKET="/run/user/1000/pulse/native"
PIPEWIRE_SOCKET="/run/user/1000/pipewire-0"

# ============================================================================
# CONFIGURATION VARIABLES
# ============================================================================

DRY_RUN=false
FORCE_AUDIO_SYSTEM=""
HOST_ONLY=false
CONTAINER_ONLY=false
TEST_ONLY=false
NO_RESTART=false
CTID=""
DETECTED_AUDIO_SYSTEM=""
HOST_USER_ID="1000"  # Default UID for audio socket owner

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

show_help() {
    grep '^#' "$0" | grep -E '^# (Usage|Options|Examples|Requirements|  )' | sed 's/^# //'
    echo ""
    echo "Version: $VERSION"
    exit 0
}

show_version() {
    echo "Waydroid Audio Setup Script v$VERSION"
    exit 0
}

# Execute command or show in dry-run mode
execute() {
    local description="$1"
    shift

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} $description"
        echo -e "${BL}  Command:${CL} $*"
        return 0
    else
        msg_info "$description"
        if "$@"; then
            msg_ok "$description completed"
            return 0
        else
            msg_error "$description failed"
            return 1
        fi
    fi
}

# Execute command in container
pct_exec() {
    local ctid="$1"
    shift

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Execute in container $ctid: $*"
        return 0
    else
        pct exec "$ctid" -- bash -c "$*"
    fi
}

# Check if running on Proxmox host
check_proxmox() {
    if ! command -v pct &> /dev/null; then
        msg_error "This script must be run on a Proxmox VE host"
        exit 1
    fi
}

# Validate container ID
validate_ctid() {
    local ctid="$1"

    if [ -z "$ctid" ]; then
        msg_error "Container ID required"
        echo "Use --help for usage information"
        exit 1
    fi

    if ! [[ "$ctid" =~ ^[0-9]+$ ]]; then
        msg_error "Invalid container ID: $ctid"
        exit 1
    fi

    if [ "$DRY_RUN" = false ] && ! pct status "$ctid" &> /dev/null; then
        msg_error "Container $ctid does not exist"
        exit 1
    fi
}

# ============================================================================
# DETECTION FUNCTIONS
# ============================================================================

detect_audio_system() {
    msg_info "Detecting host audio system..."

    local audio_system=""
    local confidence="unknown"

    # Check for PipeWire
    if systemctl --user status pipewire.service &> /dev/null 2>&1 || \
       pgrep -x pipewire &> /dev/null || \
       [ -S "$PIPEWIRE_SOCKET" ]; then
        audio_system="pipewire"
        confidence="high"
        msg_ok "Detected PipeWire (confidence: $confidence)"
    # Check for PulseAudio
    elif systemctl --user status pulseaudio.service &> /dev/null 2>&1 || \
         pgrep -x pulseaudio &> /dev/null || \
         [ -S "$PULSEAUDIO_SOCKET" ]; then
        audio_system="pulseaudio"
        confidence="high"
        msg_ok "Detected PulseAudio (confidence: $confidence)"
    # Check package installations
    elif dpkg -l | grep -q pipewire; then
        audio_system="pipewire"
        confidence="medium"
        msg_warn "Detected PipeWire (installed but not running)"
    elif dpkg -l | grep -q pulseaudio; then
        audio_system="pulseaudio"
        confidence="medium"
        msg_warn "Detected PulseAudio (installed but not running)"
    else
        msg_error "No audio system detected (PulseAudio or PipeWire required)"
        echo ""
        echo "Please install either:"
        echo "  - PipeWire: apt install pipewire pipewire-pulse wireplumber"
        echo "  - PulseAudio: apt install pulseaudio"
        exit 1
    fi

    DETECTED_AUDIO_SYSTEM="$audio_system"

    # Display system information
    echo ""
    echo -e "${BL}Audio System Information:${CL}"
    echo -e "  System: ${GN}${audio_system}${CL}"
    echo -e "  Confidence: ${GN}${confidence}${CL}"

    if [ "$audio_system" = "pipewire" ]; then
        if [ -S "$PIPEWIRE_SOCKET" ]; then
            echo -e "  Socket: ${GN}${PIPEWIRE_SOCKET}${CL} (exists)"
        else
            echo -e "  Socket: ${YW}${PIPEWIRE_SOCKET}${CL} (missing)"
        fi
    else
        if [ -S "$PULSEAUDIO_SOCKET" ]; then
            echo -e "  Socket: ${GN}${PULSEAUDIO_SOCKET}${CL} (exists)"
        else
            echo -e "  Socket: ${YW}${PULSEAUDIO_SOCKET}${CL} (missing)"
        fi
    fi
    echo ""
}

detect_host_user() {
    msg_info "Detecting host user for audio..."

    # Try to find the user running the audio system
    local audio_user=""

    if [ "$DETECTED_AUDIO_SYSTEM" = "pipewire" ]; then
        audio_user=$(ps aux | grep -E 'pipewire[^-]' | grep -v grep | awk '{print $1}' | head -1)
    else
        audio_user=$(ps aux | grep pulseaudio | grep -v grep | awk '{print $1}' | head -1)
    fi

    if [ -n "$audio_user" ]; then
        HOST_USER_ID=$(id -u "$audio_user" 2>/dev/null || echo "1000")
        msg_ok "Detected audio user: $audio_user (UID: $HOST_USER_ID)"
    else
        msg_warn "Could not detect audio user, using UID 1000"
        HOST_USER_ID="1000"
    fi
}

# ============================================================================
# HOST CONFIGURATION FUNCTIONS
# ============================================================================

configure_host_audio() {
    local ctid="$1"
    local audio_system="${2:-$DETECTED_AUDIO_SYSTEM}"

    echo ""
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Configuring Host Audio System${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""

    # Verify audio devices exist
    check_audio_devices

    # Configure LXC for audio passthrough
    configure_lxc_audio "$ctid" "$audio_system"

    # Configure host audio service for network access
    configure_host_audio_service "$audio_system"

    msg_ok "Host audio configuration complete"
}

check_audio_devices() {
    msg_info "Checking audio devices on host..."

    local all_exist=true

    for device in "${AUDIO_DEVICES[@]}"; do
        if [ -e "$device" ]; then
            msg_ok "Found: $device"
        else
            msg_error "Missing: $device"
            all_exist=false
        fi
    done

    if [ "$all_exist" = false ]; then
        msg_warn "Some audio devices are missing"
        msg_info "Ensure ALSA/sound drivers are loaded on the host"
    fi

    # Check for sound cards
    if ls /dev/snd/pcm* &> /dev/null; then
        local card_count=$(ls -1 /dev/snd/pcm* 2>/dev/null | wc -l)
        msg_ok "Found $card_count PCM device(s)"
    else
        msg_warn "No PCM devices found - audio may not work"
    fi
}

configure_lxc_audio() {
    local ctid="$1"
    local audio_system="$2"
    local lxc_config="/etc/pve/lxc/${ctid}.conf"

    msg_info "Configuring LXC container $ctid for audio..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would configure: $lxc_config"
        echo -e "${BL}  Changes:${CL}"
        echo "    - Add /dev/snd device passthrough"
        echo "    - Add audio socket bind mount"
        echo "    - Configure device cgroup access"
        return 0
    fi

    # Backup configuration
    cp "$lxc_config" "${lxc_config}.backup.audio.$(date +%Y%m%d-%H%M%S)"

    # Remove existing audio configuration
    sed -i '/# Audio passthrough/d' "$lxc_config"
    sed -i '/lxc.mount.entry.*snd/d' "$lxc_config"
    sed -i '/lxc.mount.entry.*pulse/d' "$lxc_config"
    sed -i '/lxc.mount.entry.*pipewire/d' "$lxc_config"
    sed -i '/lxc.cgroup2.devices.allow.*116/d' "$lxc_config"

    # Add audio configuration header
    echo "" >> "$lxc_config"
    echo "# Audio passthrough - configured by setup-audio.sh" >> "$lxc_config"
    echo "# Generated: $(date)" >> "$lxc_config"

    # Add /dev/snd device passthrough
    echo "lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir 0 0" >> "$lxc_config"

    # Add device cgroup permissions for sound devices
    # 116 is the major number for ALSA sound devices
    echo "lxc.cgroup2.devices.allow: c 116:* rwm" >> "$lxc_config"

    # Add audio socket bind mount based on detected system
    if [ "$audio_system" = "pipewire" ]; then
        local host_socket="/run/user/${HOST_USER_ID}/pipewire-0"
        echo "lxc.mount.entry: ${host_socket} run/user/0/pipewire-0 none bind,optional,create=file 0 0" >> "$lxc_config"
        msg_ok "Configured PipeWire socket passthrough"
    else
        local host_socket="/run/user/${HOST_USER_ID}/pulse/native"
        echo "lxc.mount.entry: ${host_socket} run/user/0/pulse/native none bind,optional,create=file 0 0" >> "$lxc_config"
        msg_ok "Configured PulseAudio socket passthrough"
    fi

    msg_ok "LXC configuration updated"
    msg_info "Configuration backed up to: ${lxc_config}.backup.audio.$(date +%Y%m%d)"
}

configure_host_audio_service() {
    local audio_system="$1"

    msg_info "Configuring host audio service for container access..."

    if [ "$audio_system" = "pipewire" ]; then
        configure_pipewire_host
    else
        configure_pulseaudio_host
    fi
}

configure_pipewire_host() {
    msg_info "Configuring PipeWire for container access..."

    # Check if PipeWire is running
    if ! pgrep -x pipewire &> /dev/null; then
        msg_warn "PipeWire is not running"
        msg_info "Start with: systemctl --user start pipewire.service"
    fi

    # Ensure socket has correct permissions
    local socket="/run/user/${HOST_USER_ID}/pipewire-0"
    if [ -S "$socket" ]; then
        execute "Setting PipeWire socket permissions" \
            chmod 666 "$socket" 2>/dev/null || true
        msg_ok "PipeWire socket permissions configured"
    else
        msg_warn "PipeWire socket not found at $socket"
    fi

    msg_ok "PipeWire host configuration complete"
}

configure_pulseaudio_host() {
    msg_info "Configuring PulseAudio for container access..."

    local pa_config_dir="/home/$(id -un $HOST_USER_ID)/.config/pulse"
    local pa_config="$pa_config_dir/default.pa"

    # Create config directory if needed
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$pa_config_dir"
    fi

    # Check if we need to configure network access
    if [ -f "$pa_config" ] && grep -q "module-native-protocol-unix" "$pa_config"; then
        msg_ok "PulseAudio already configured for socket access"
    else
        if [ "$DRY_RUN" = false ]; then
            # Create minimal config if it doesn't exist
            if [ ! -f "$pa_config" ]; then
                cat > "$pa_config" <<EOF
# PulseAudio configuration for LXC container access
# Generated by setup-audio.sh

.include /etc/pulse/default.pa

# Enable socket access for containers
load-module module-native-protocol-unix auth-anonymous=1
EOF
                msg_ok "Created PulseAudio configuration"
            fi
        else
            echo -e "${YW}[DRY-RUN]${CL} Would create/modify: $pa_config"
        fi
    fi

    # Ensure socket has correct permissions
    local socket="/run/user/${HOST_USER_ID}/pulse/native"
    if [ -S "$socket" ] && [ "$DRY_RUN" = false ]; then
        chmod 666 "$socket" 2>/dev/null || true
        msg_ok "PulseAudio socket permissions configured"
    fi

    # Check if PulseAudio is running
    if ! pgrep -x pulseaudio &> /dev/null; then
        msg_warn "PulseAudio is not running"
        msg_info "Start with: systemctl --user start pulseaudio.service"
    fi

    msg_ok "PulseAudio host configuration complete"
}

# ============================================================================
# CONTAINER CONFIGURATION FUNCTIONS
# ============================================================================

configure_container_audio() {
    local ctid="$1"
    local audio_system="${2:-$DETECTED_AUDIO_SYSTEM}"

    echo ""
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Configuring Container Audio System${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""

    # Check if container is running
    if [ "$DRY_RUN" = false ]; then
        local status=$(pct status "$ctid" | awk '{print $2}')
        if [ "$status" != "running" ]; then
            msg_warn "Container $ctid is not running"
            msg_info "Starting container..."
            pct start "$ctid"
            sleep 5
        fi
    fi

    # Install audio packages in container
    install_container_audio_packages "$ctid" "$audio_system"

    # Configure container audio client
    configure_container_audio_client "$ctid" "$audio_system"

    # Configure Waydroid for audio
    configure_waydroid_audio "$ctid"

    # Set up audio permissions
    configure_container_audio_permissions "$ctid"

    msg_ok "Container audio configuration complete"
}

install_container_audio_packages() {
    local ctid="$1"
    local audio_system="$2"

    msg_info "Installing audio packages in container..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would install audio packages in container $ctid"
        if [ "$audio_system" = "pipewire" ]; then
            echo "  - pipewire"
            echo "  - pipewire-pulse"
            echo "  - wireplumber"
        else
            echo "  - pulseaudio"
            echo "  - pulseaudio-utils"
        fi
        echo "  - alsa-utils"
        return 0
    fi

    # Update package lists
    pct_exec "$ctid" "apt-get update -qq"

    # Install based on audio system
    if [ "$audio_system" = "pipewire" ]; then
        pct_exec "$ctid" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq pipewire pipewire-pulse wireplumber alsa-utils"
        msg_ok "Installed PipeWire packages"
    else
        pct_exec "$ctid" "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq pulseaudio pulseaudio-utils alsa-utils"
        msg_ok "Installed PulseAudio packages"
    fi
}

configure_container_audio_client() {
    local ctid="$1"
    local audio_system="$2"

    msg_info "Configuring audio client in container..."

    if [ "$audio_system" = "pipewire" ]; then
        configure_container_pipewire "$ctid"
    else
        configure_container_pulseaudio "$ctid"
    fi
}

configure_container_pipewire() {
    local ctid="$1"

    msg_info "Configuring PipeWire in container..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would configure PipeWire client in container"
        return 0
    fi

    # Create runtime directory
    pct_exec "$ctid" "mkdir -p /run/user/0"

    # Set environment variables for PipeWire
    pct_exec "$ctid" "cat >> /etc/environment <<EOF
PIPEWIRE_RUNTIME_DIR=/run/user/0
XDG_RUNTIME_DIR=/run/user/0
EOF"

    # Create systemd user service override for root
    pct_exec "$ctid" "mkdir -p /root/.config/systemd/user"

    msg_ok "PipeWire client configured in container"
}

configure_container_pulseaudio() {
    local ctid="$1"

    msg_info "Configuring PulseAudio in container..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would configure PulseAudio client in container"
        return 0
    fi

    # Create PulseAudio client configuration
    pct_exec "$ctid" "mkdir -p /root/.config/pulse"
    pct_exec "$ctid" "cat > /root/.config/pulse/client.conf <<EOF
# PulseAudio client configuration for LXC
# Generated by setup-audio.sh
default-server = unix:/run/user/0/pulse/native
autospawn = no
daemon-binary = /bin/true
enable-shm = false
EOF"

    # Set environment variables
    pct_exec "$ctid" "cat >> /etc/environment <<EOF
PULSE_SERVER=unix:/run/user/0/pulse/native
PULSE_RUNTIME_PATH=/run/user/0/pulse
EOF"

    msg_ok "PulseAudio client configured in container"
}

configure_waydroid_audio() {
    local ctid="$1"

    msg_info "Configuring Waydroid for audio..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would configure Waydroid audio properties"
        return 0
    fi

    # Check if Waydroid is installed
    if ! pct_exec "$ctid" "command -v waydroid &> /dev/null"; then
        msg_warn "Waydroid not found in container - skipping Waydroid configuration"
        return 0
    fi

    # Configure Waydroid properties for audio
    pct_exec "$ctid" "cat > /tmp/configure-waydroid-audio.sh <<'EOFSCRIPT'
#!/bin/bash
# Wait for Waydroid to be initialized
if [ ! -d /var/lib/waydroid ]; then
    echo \"Waydroid not initialized yet - audio will be configured on first run\"
    exit 0
fi

# Set audio properties
waydroid prop set persist.waydroid.audio true 2>/dev/null || true
waydroid prop set ro.audio.ignore_effects true 2>/dev/null || true

echo \"Waydroid audio properties configured\"
EOFSCRIPT"

    pct_exec "$ctid" "chmod +x /tmp/configure-waydroid-audio.sh"
    pct_exec "$ctid" "/tmp/configure-waydroid-audio.sh"
    pct_exec "$ctid" "rm /tmp/configure-waydroid-audio.sh"

    msg_ok "Waydroid audio configuration complete"
}

configure_container_audio_permissions() {
    local ctid="$1"

    msg_info "Configuring audio device permissions in container..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would configure audio permissions in container"
        return 0
    fi

    # Add root to audio group
    pct_exec "$ctid" "usermod -aG audio root 2>/dev/null || true"

    # Create udev rule for audio devices
    pct_exec "$ctid" "cat > /etc/udev/rules.d/99-audio.rules <<EOF
# Audio device permissions for LXC
SUBSYSTEM==\"sound\", MODE=\"0666\"
KERNEL==\"controlC[0-9]*\", MODE=\"0666\"
KERNEL==\"pcmC[0-9]*D[0-9]*[cp]\", MODE=\"0666\"
KERNEL==\"timer\", MODE=\"0666\"
EOF"

    # Reload udev rules
    pct_exec "$ctid" "udevadm control --reload-rules 2>/dev/null || true"
    pct_exec "$ctid" "udevadm trigger 2>/dev/null || true"

    msg_ok "Audio permissions configured"
}

# ============================================================================
# TESTING FUNCTIONS
# ============================================================================

test_audio_setup() {
    local ctid="$1"
    local audio_system="${2:-$DETECTED_AUDIO_SYSTEM}"

    echo ""
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Testing Audio Configuration${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""

    local tests_passed=0
    local tests_failed=0

    # Test 1: Check audio devices in container
    msg_info "Test 1: Checking audio devices..."
    if pct_exec "$ctid" "test -d /dev/snd" &> /dev/null; then
        msg_ok "/dev/snd directory exists in container"
        tests_passed=$((tests_passed + 1))
    else
        msg_error "/dev/snd directory not found in container"
        tests_failed=$((tests_failed + 1))
    fi

    # Test 2: Check for PCM devices
    msg_info "Test 2: Checking PCM devices..."
    if pct_exec "$ctid" "ls /dev/snd/pcm* &> /dev/null" &> /dev/null; then
        local device_count=$(pct exec "$ctid" -- bash -c "ls -1 /dev/snd/pcm* 2>/dev/null | wc -l" 2>/dev/null || echo "0")
        msg_ok "Found $device_count PCM device(s) in container"
        tests_passed=$((tests_passed + 1))
    else
        msg_warn "No PCM devices found in container"
        tests_failed=$((tests_failed + 1))
    fi

    # Test 3: Check audio socket
    msg_info "Test 3: Checking audio socket..."
    if [ "$audio_system" = "pipewire" ]; then
        if pct_exec "$ctid" "test -S /run/user/0/pipewire-0" &> /dev/null; then
            msg_ok "PipeWire socket exists in container"
            tests_passed=$((tests_passed + 1))
        else
            msg_error "PipeWire socket not found in container"
            tests_failed=$((tests_failed + 1))
        fi
    else
        if pct_exec "$ctid" "test -S /run/user/0/pulse/native" &> /dev/null; then
            msg_ok "PulseAudio socket exists in container"
            tests_passed=$((tests_passed + 1))
        else
            msg_error "PulseAudio socket not found in container"
            tests_failed=$((tests_failed + 1))
        fi
    fi

    # Test 4: Check ALSA
    msg_info "Test 4: Testing ALSA..."
    if pct exec "$ctid" -- bash -c "aplay -l &> /dev/null" &> /dev/null; then
        msg_ok "ALSA can detect audio devices"
        tests_passed=$((tests_passed + 1))

        # Show available devices
        echo -e "${BL}Available audio devices:${CL}"
        pct exec "$ctid" -- bash -c "aplay -l 2>&1 | grep -E '^card|^  '" || true
    else
        msg_warn "ALSA could not detect audio devices"
        tests_failed=$((tests_failed + 1))
    fi

    # Test 5: Check audio client tools
    msg_info "Test 5: Checking audio client tools..."
    if [ "$audio_system" = "pipewire" ]; then
        if pct_exec "$ctid" "command -v pw-cli &> /dev/null" &> /dev/null; then
            msg_ok "PipeWire client tools available"
            tests_passed=$((tests_passed + 1))
        else
            msg_warn "PipeWire client tools not found"
            tests_failed=$((tests_failed + 1))
        fi
    else
        if pct_exec "$ctid" "command -v pactl &> /dev/null" &> /dev/null; then
            msg_ok "PulseAudio client tools available"
            tests_passed=$((tests_passed + 1))

            # Try to get server info
            if pct exec "$ctid" -- bash -c "pactl info &> /dev/null"; then
                msg_ok "Can connect to PulseAudio server"
                tests_passed=$((tests_passed + 1))
            else
                msg_warn "Cannot connect to PulseAudio server"
                tests_failed=$((tests_failed + 1))
            fi
        else
            msg_warn "PulseAudio client tools not found"
            tests_failed=$((tests_failed + 1))
        fi
    fi

    # Test 6: Check audio group membership
    msg_info "Test 6: Checking audio group membership..."
    if pct exec "$ctid" -- bash -c "groups root | grep -q audio" &> /dev/null; then
        msg_ok "root user is member of audio group"
        tests_passed=$((tests_passed + 1))
    else
        msg_warn "root user is not in audio group"
        tests_failed=$((tests_failed + 1))
    fi

    # Summary
    echo ""
    echo -e "${BL}═══ Test Summary ═══${CL}"
    echo -e "Passed: ${GN}${tests_passed}${CL}"
    echo -e "Failed: ${RD}${tests_failed}${CL}"
    echo ""

    if [ $tests_failed -eq 0 ]; then
        msg_ok "All audio tests passed!"
        echo ""
        echo -e "${GN}Audio is properly configured.${CL}"
        echo "You can test audio playback with:"
        echo -e "  ${BL}pct exec $ctid -- speaker-test -t wav -c 2${CL}"
        return 0
    else
        msg_warn "Some audio tests failed"
        echo ""
        echo "See troubleshooting section below for help."
        return 1
    fi
}

# ============================================================================
# RESTART FUNCTIONS
# ============================================================================

restart_container() {
    local ctid="$1"

    msg_info "Restarting container $ctid to apply changes..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would restart container $ctid"
        return 0
    fi

    pct stop "$ctid"
    sleep 2
    pct start "$ctid"
    sleep 5

    msg_ok "Container restarted"
}

restart_waydroid_services() {
    local ctid="$1"

    msg_info "Restarting Waydroid services in container..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}[DRY-RUN]${CL} Would restart Waydroid services"
        return 0
    fi

    # Restart Waydroid services if they exist
    pct_exec "$ctid" "systemctl restart waydroid-container.service 2>/dev/null || true"
    pct_exec "$ctid" "systemctl restart waydroid-vnc.service 2>/dev/null || true"

    msg_ok "Waydroid services restarted"
}

# ============================================================================
# TROUBLESHOOTING FUNCTIONS
# ============================================================================

show_troubleshooting() {
    cat <<'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                          TROUBLESHOOTING GUIDE                            ║
╚═══════════════════════════════════════════════════════════════════════════╝

COMMON ISSUES AND SOLUTIONS
───────────────────────────────────────────────────────────────────────────

1. No audio in Waydroid apps
   ──────────────────────────
   Problem: Android apps have no sound

   Solutions:
   • Restart the container: pct restart <ctid>
   • Check audio socket permissions on host
   • Verify audio system is running on host
   • Check Waydroid properties:
     pct exec <ctid> -- waydroid prop get persist.waydroid.audio

   • Manually set Waydroid audio property:
     pct exec <ctid> -- waydroid prop set persist.waydroid.audio true

2. /dev/snd not accessible
   ────────────────────────
   Problem: Audio devices not available in container

   Solutions:
   • Check LXC configuration: cat /etc/pve/lxc/<ctid>.conf
   • Ensure cgroup permissions are set
   • Verify devices exist on host: ls -la /dev/snd/
   • Restart container to remount devices

3. PulseAudio/PipeWire connection failed
   ────────────────────────────────────
   Problem: Cannot connect to audio server

   Solutions:
   • Verify socket exists on host:
     - PipeWire: ls -la /run/user/1000/pipewire-0
     - PulseAudio: ls -la /run/user/1000/pulse/native

   • Check socket permissions (should be 666):
     - PipeWire: chmod 666 /run/user/1000/pipewire-0
     - PulseAudio: chmod 666 /run/user/1000/pulse/native

   • Verify bind mount in container:
     pct exec <ctid> -- ls -la /run/user/0/

4. Permission denied errors
   ────────────────────────
   Problem: Cannot access audio devices

   Solutions:
   • Add root to audio group in container:
     pct exec <ctid> -- usermod -aG audio root

   • Check device permissions:
     pct exec <ctid> -- ls -la /dev/snd/

   • Verify udev rules are loaded

5. Audio system not detected
   ──────────────────────────
   Problem: Script cannot detect PulseAudio or PipeWire

   Solutions:
   • Install audio system on host:
     - PipeWire: apt install pipewire pipewire-pulse wireplumber
     - PulseAudio: apt install pulseaudio

   • Start audio service:
     - PipeWire: systemctl --user start pipewire
     - PulseAudio: systemctl --user start pulseaudio

   • Force specific audio system:
     ./setup-audio.sh --force-pipewire <ctid>
     ./setup-audio.sh --force-pulseaudio <ctid>

DIAGNOSTIC COMMANDS
───────────────────────────────────────────────────────────────────────────

Test audio in container:
  pct exec <ctid> -- aplay -l
  pct exec <ctid> -- speaker-test -t wav -c 2

Check PulseAudio:
  pct exec <ctid> -- pactl info
  pct exec <ctid> -- pactl list sinks

Check PipeWire:
  pct exec <ctid> -- pw-cli info all

Check Waydroid audio:
  pct exec <ctid> -- waydroid prop get persist.waydroid.audio
  pct exec <ctid> -- waydroid shell getprop | grep audio

View container logs:
  pct exec <ctid> -- journalctl -u waydroid-container -n 50

MANUAL CONFIGURATION
───────────────────────────────────────────────────────────────────────────

If automatic setup fails, you can manually configure:

1. Add to /etc/pve/lxc/<ctid>.conf:

   lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir
   lxc.cgroup2.devices.allow: c 116:* rwm

   For PipeWire:
   lxc.mount.entry: /run/user/1000/pipewire-0 run/user/0/pipewire-0 none bind,optional,create=file

   For PulseAudio:
   lxc.mount.entry: /run/user/1000/pulse/native run/user/0/pulse/native none bind,optional,create=file

2. In container, create /root/.config/pulse/client.conf (PulseAudio):

   default-server = unix:/run/user/0/pulse/native
   autospawn = no
   enable-shm = false

3. Set environment variables in container /etc/environment:

   For PipeWire:
   PIPEWIRE_RUNTIME_DIR=/run/user/0

   For PulseAudio:
   PULSE_SERVER=unix:/run/user/0/pulse/native

ADDITIONAL RESOURCES
───────────────────────────────────────────────────────────────────────────

• Waydroid Audio Guide: https://docs.waydro.id/faq/audio
• PipeWire Documentation: https://pipewire.org/
• PulseAudio LXC Guide: https://wiki.archlinux.org/title/PulseAudio
• Proxmox LXC Documentation: https://pve.proxmox.com/wiki/Linux_Container

Need more help? Open an issue at:
https://github.com/MvRoo/waydroid-proxmox/issues

EOF
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Waydroid Audio Passthrough Setup${CL}"
    echo -e "${GN}  Version $VERSION${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""

    # Display dry-run notice if applicable
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}╔═══════════════════════════════════════════╗${CL}"
        echo -e "${YW}║           DRY-RUN MODE ENABLED            ║${CL}"
        echo -e "${YW}║     No changes will be made to system     ║${CL}"
        echo -e "${YW}╚═══════════════════════════════════════════╝${CL}"
        echo ""
    fi

    # Validate environment
    if [ "$CONTAINER_ONLY" = false ]; then
        check_proxmox
    fi

    validate_ctid "$CTID"

    # Detect audio system unless forced
    if [ -z "$FORCE_AUDIO_SYSTEM" ]; then
        detect_audio_system
        detect_host_user
    else
        DETECTED_AUDIO_SYSTEM="$FORCE_AUDIO_SYSTEM"
        msg_info "Forced audio system: $DETECTED_AUDIO_SYSTEM"
        detect_host_user
    fi

    # Execute based on mode
    if [ "$TEST_ONLY" = true ]; then
        test_audio_setup "$CTID" "$DETECTED_AUDIO_SYSTEM"
        exit $?
    fi

    # Configure host
    if [ "$CONTAINER_ONLY" = false ]; then
        configure_host_audio "$CTID" "$DETECTED_AUDIO_SYSTEM"
    fi

    # Configure container
    if [ "$HOST_ONLY" = false ]; then
        configure_container_audio "$CTID" "$DETECTED_AUDIO_SYSTEM"
    fi

    # Restart services unless disabled
    if [ "$NO_RESTART" = false ] && [ "$DRY_RUN" = false ]; then
        echo ""
        msg_info "Restarting services to apply changes..."
        restart_container "$CTID"
        sleep 3
        restart_waydroid_services "$CTID"
    fi

    # Run tests
    echo ""
    test_audio_setup "$CTID" "$DETECTED_AUDIO_SYSTEM"

    # Final summary
    echo ""
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Audio Setup Complete!${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""
    echo -e "${BL}Configuration Summary:${CL}"
    echo -e "  Container ID: ${GN}${CTID}${CL}"
    echo -e "  Audio System: ${GN}${DETECTED_AUDIO_SYSTEM}${CL}"
    echo -e "  Mode: ${GN}$([ "$DRY_RUN" = true ] && echo "Dry-run" || echo "Applied")${CL}"
    echo ""
    echo -e "${BL}Next Steps:${CL}"
    echo "  1. Test audio with: speaker-test -t wav -c 2"
    echo "  2. Launch a Waydroid app with audio (e.g., YouTube)"
    echo "  3. If issues occur, run: $0 --test-only $CTID"
    echo ""

    if [ "$DRY_RUN" = false ]; then
        msg_ok "Audio passthrough is ready to use!"
    else
        msg_info "Run without --dry-run to apply these changes"
    fi

    # Show troubleshooting guide
    show_troubleshooting
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force-pulseaudio)
            FORCE_AUDIO_SYSTEM="pulseaudio"
            shift
            ;;
        --force-pipewire)
            FORCE_AUDIO_SYSTEM="pipewire"
            shift
            ;;
        --host-only)
            HOST_ONLY=true
            shift
            ;;
        --container-only)
            CONTAINER_ONLY=true
            shift
            ;;
        --test-only)
            TEST_ONLY=true
            shift
            ;;
        --no-restart)
            NO_RESTART=true
            shift
            ;;
        --version)
            show_version
            ;;
        --help|-h)
            show_help
            ;;
        -*)
            msg_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            if [ -z "$CTID" ]; then
                CTID="$1"
            else
                msg_error "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate conflicting options
if [ "$HOST_ONLY" = true ] && [ "$CONTAINER_ONLY" = true ]; then
    msg_error "Cannot use --host-only and --container-only together"
    exit 1
fi

if [ -n "$FORCE_AUDIO_SYSTEM" ]; then
    if [ "$FORCE_AUDIO_SYSTEM" != "pulseaudio" ] && [ "$FORCE_AUDIO_SYSTEM" != "pipewire" ]; then
        msg_error "Invalid audio system forced"
        exit 1
    fi
fi

# Run main function
main

exit 0
