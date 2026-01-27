#!/usr/bin/env bash
# Use local build.func with our custom install script URL
source <(curl -fsSL https://raw.githubusercontent.com/MvRoo/waydroid-proxmox/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: iceteaSA
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/MvRoo/waydroid-proxmox

# App Default Values
APP="Waydroid"
var_tags="${var_tags:-android}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"

# App Output & Base Settings
header_info "$APP"
variables
color
catch_errors

# Version check (for debugging)
SCRIPT_VERSION="2.0-community"
echo -e "${GN}Script Version: ${SCRIPT_VERSION}${CL}\n"

# GPU Configuration Variables
GPU_TYPE="${GPU_TYPE:-intel}"
SOFTWARE_RENDERING="${SOFTWARE_RENDERING:-0}"
GPU_DEVICE="${GPU_DEVICE:-}"
RENDER_NODE="${RENDER_NODE:-}"
USE_GAPPS="${USE_GAPPS:-yes}"

# Detect and configure GPU
detect_gpu() {
    msg_info "Detecting GPU hardware"

    # Intel GPU detection
    if lspci 2>/dev/null | grep -qi "VGA.*Intel"; then
        GPU_TYPE="intel"
        msg_ok "Intel GPU detected"
        lspci | grep -i "VGA.*Intel"

        # Find Intel GPU devices
        if [ -d /dev/dri ]; then
            mapfile -t CARDS < <(ls /dev/dri/card* 2>/dev/null | sort || true)
            mapfile -t RENDERS < <(ls /dev/dri/renderD* 2>/dev/null | sort || true)

            if [ ${#CARDS[@]} -ge 1 ]; then
                GPU_DEVICE="${CARDS[0]}"
                msg_ok "Using card device: $GPU_DEVICE"
            fi

            if [ ${#RENDERS[@]} -ge 1 ]; then
                RENDER_NODE="${RENDERS[0]}"
                msg_ok "Using render node: $RENDER_NODE"
            fi
        fi

    # AMD GPU detection
    elif lspci 2>/dev/null | grep -qi "VGA.*\(AMD\|Radeon\)"; then
        GPU_TYPE="amd"
        msg_ok "AMD GPU detected"
        lspci | grep -Ei "VGA.*(AMD|Radeon)"

        # Find AMD GPU devices
        if [ -d /dev/dri ]; then
            mapfile -t CARDS < <(ls /dev/dri/card* 2>/dev/null | sort || true)
            mapfile -t RENDERS < <(ls /dev/dri/renderD* 2>/dev/null | sort || true)

            if [ ${#CARDS[@]} -ge 1 ]; then
                GPU_DEVICE="${CARDS[0]}"
                msg_ok "Using card device: $GPU_DEVICE"
            fi

            if [ ${#RENDERS[@]} -ge 1 ]; then
                RENDER_NODE="${RENDERS[0]}"
                msg_ok "Using render node: $RENDER_NODE"
            fi
        fi

    # NVIDIA GPU (software rendering only)
    elif lspci 2>/dev/null | grep -qi "VGA.*NVIDIA"; then
        GPU_TYPE="nvidia"
        SOFTWARE_RENDERING=1
        msg_warn "NVIDIA GPU detected - using software rendering"
        echo -e "  ${YW}Note: Hardware acceleration not available for NVIDIA with Waydroid${CL}"

    # No GPU or unknown
    else
        GPU_TYPE="software"
        SOFTWARE_RENDERING=1
        msg_warn "No compatible GPU detected - using software rendering"
    fi
}

# Interactive GAPPS selection
interactive_prompts() {
    echo ""
    echo -e "${BL}Android Configuration:${CL}"
    echo ""
    read -r -p "Install Google Apps (Play Store, Gmail, etc.)? [Y/n]: " GAPPS_CHOICE
    GAPPS_CHOICE=${GAPPS_CHOICE:-y}

    if [[ $GAPPS_CHOICE =~ ^[Nn]$ ]]; then
        USE_GAPPS="no"
    else
        USE_GAPPS="yes"
    fi
}

# Configure GPU passthrough after container creation
configure_gpu_passthrough() {
    if [ "$SOFTWARE_RENDERING" = "0" ] && [ -n "$GPU_DEVICE" ]; then
        msg_info "Configuring GPU passthrough"

        local config_file="/etc/pve/lxc/${CTID}.conf"

        # Add GPU passthrough configuration
        cat >> "$config_file" <<EOF

# GPU Passthrough for Waydroid
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 29:0 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir 0 0
lxc.mount.entry: /dev/fb0 dev/fb0 none bind,optional,create=file 0 0
EOF

        msg_ok "GPU passthrough configured"
    fi
}

# Setup host kernel modules
setup_host_modules() {
    msg_info "Loading Waydroid kernel modules"

    # Load binder and ashmem modules
    if ! lsmod | grep -q binder_linux; then
        modprobe binder_linux 2>/dev/null || msg_warn "binder_linux module not available (will try in container)"
    fi

    if ! lsmod | grep -q ashmem_linux; then
        modprobe ashmem_linux 2>/dev/null || msg_warn "ashmem_linux module not available (will try in container)"
    fi

    # Make persistent
    if [ ! -f /etc/modules-load.d/waydroid.conf ]; then
        cat > /etc/modules-load.d/waydroid.conf <<EOF
binder_linux
ashmem_linux
EOF
        msg_ok "Kernel modules configured for persistence"
    fi
}

function update_script() {
    header_info
    check_container_storage
    check_container_resources

    if [[ ! -f /usr/local/bin/start-waydroid.sh ]]; then
        msg_error "No ${APP} Installation Found!"
        exit
    fi

    RELEASE=$(curl -s https://api.github.com/repos/waydroid/waydroid/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')

    msg_info "Stopping Waydroid services"
    systemctl stop waydroid-vnc.service 2>/dev/null || true
    systemctl stop waydroid-api.service 2>/dev/null || true
    msg_ok "Services stopped"

    msg_info "Updating Waydroid"
    apt-get update &>/dev/null
    apt-get install -y waydroid &>/dev/null
    msg_ok "Updated Waydroid"

    msg_info "Starting Waydroid services"
    systemctl start waydroid-vnc.service
    systemctl start waydroid-api.service
    msg_ok "Services started"

    msg_ok "Update complete"
    exit
}

# Main execution flow - detect GPU first
detect_gpu
interactive_prompts

# Show configuration summary before starting
echo ""
echo -e "${BL}Configuration:${CL}"
echo -e "  GPU Type: ${GN}${GPU_TYPE}${CL}"
echo -e "  Rendering: ${GN}$([ "$SOFTWARE_RENDERING" = "1" ] && echo "Software" || echo "Hardware Accelerated")${CL}"
[ -n "$GPU_DEVICE" ] && echo -e "  GPU Device: ${GN}${GPU_DEVICE}${CL}"
[ -n "$RENDER_NODE" ] && echo -e "  Render Node: ${GN}${RENDER_NODE}${CL}"
echo -e "  Google Apps: ${GN}${USE_GAPPS}${CL}"
echo ""

# Let build.func handle container setup interactively
start
build_container  # Uses our custom build.func with modified install script URL
description

# Post-creation configuration
msg_info "Configuring GPU passthrough"
configure_gpu_passthrough
setup_host_modules
msg_ok "GPU configuration complete"

# Pass environment variables to container for installation
msg_info "Configuring container environment"
pct push "$CTID" /dev/stdin /tmp/waydroid-env.sh <<EOF
#!/bin/bash
export GPU_TYPE="$GPU_TYPE"
export SOFTWARE_RENDERING="$SOFTWARE_RENDERING"
export USE_GAPPS="$USE_GAPPS"
export GPU_DEVICE="$GPU_DEVICE"
export RENDER_NODE="$RENDER_NODE"
EOF
pct exec "$CTID" -- chmod +x /tmp/waydroid-env.sh
msg_ok "Environment configured"

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access Waydroid at the following URLs:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}vnc://${IP}:5900${CL} (VNC)"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL} (API)"
