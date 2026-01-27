#!/usr/bin/env bash

# Waydroid Proxmox Complete Setup Orchestration Script
# Master script for guided setup of all enhancement features
#
# Copyright (c) 2025
# License: MIT
# https://github.com/MvRoo/waydroid-proxmox
#
# This script provides a menu-driven interface to configure and apply
# all available enhancements for Waydroid running in Proxmox LXC containers.
#
# Features:
#   - Interactive menu-driven interface
#   - Non-interactive mode for automation
#   - Prerequisite checking for each enhancement
#   - Dry-run mode to preview changes
#   - Configuration saving and loading
#   - Comprehensive error handling
#   - Progress tracking and reporting
#   - Summary report generation
#
# Usage:
#   Interactive mode:     ./setup-complete.sh
#   Non-interactive:      ./setup-complete.sh --auto --config <file>
#   Dry-run:              ./setup-complete.sh --dry-run
#   Help:                 ./setup-complete.sh --help

set -euo pipefail

# ============================================================================
# CONFIGURATION AND GLOBALS
# ============================================================================

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source helper functions
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

# Configuration paths
CONFIG_DIR="/etc/waydroid-setup"
STATE_FILE="$CONFIG_DIR/setup-state.json"
CHOICES_FILE="$CONFIG_DIR/setup-choices.conf"
REPORT_DIR="/var/log/waydroid-setup"
REPORT_FILE="$REPORT_DIR/setup-report-$(date +%Y%m%d-%H%M%S).txt"

# Create directories
mkdir -p "$CONFIG_DIR" "$REPORT_DIR"

# Operation modes
DRY_RUN=false
AUTO_MODE=false
INTERACTIVE=true
SKIP_CONFIRMATION=false

# Enhancement scripts
declare -A SCRIPTS=(
    ["lxc"]="$SCRIPT_DIR/tune-lxc.sh"
    ["vnc"]="$SCRIPT_DIR/enhance-vnc.sh"
    ["audio"]="$SCRIPT_DIR/setup-audio.sh"
    ["clipboard"]="$SCRIPT_DIR/setup-clipboard.sh"
    ["apps"]="$SCRIPT_DIR/install-apps.sh"
)

# Enhancement selections (default: all disabled)
declare -A SELECTED=(
    ["lxc"]=false
    ["vnc"]=false
    ["audio"]=false
    ["clipboard"]=false
    ["apps"]=false
)

# Enhancement options
declare -A OPTIONS=(
    ["lxc_ctid"]=""
    ["vnc_enable_tls"]=false
    ["vnc_enable_monitoring"]=false
    ["vnc_fps"]="60"
    ["audio_system"]="auto"
    ["clipboard_interval"]="2"
    ["apps_config"]=""
)

# Execution tracking
declare -A EXECUTION_STATUS=()
declare -A EXECUTION_TIME=()
declare -A EXECUTION_ERROR=()
TOTAL_START_TIME=0
TOTAL_STEPS=0
COMPLETED_STEPS=0

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Display banner
show_banner() {
    clear
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║              Waydroid Proxmox Complete Setup Wizard                       ║
║                                                                           ║
║              Guided configuration for all enhancements                    ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo ""
    echo -e "${BL}Version:${CL} $VERSION"
    echo -e "${BL}Mode:${CL} $([ "$DRY_RUN" = true ] && echo "Dry-run (preview only)" || echo "Normal")"
    echo ""
}

# Display help
show_help() {
    cat << EOF
${GN}Waydroid Proxmox Complete Setup Wizard v${VERSION}${CL}

Usage: $0 [options]

Modes:
    (no options)           Interactive menu-driven setup
    --auto                 Automatic mode (requires --config)
    --dry-run              Preview changes without applying
    --help                 Show this help message

Options:
    --config <file>        Load configuration from file
    --save-config <file>   Save current configuration to file
    --skip-confirm         Skip confirmation prompts (use with caution)
    --ctid <id>            Container ID for LXC tuning
    --report <file>        Custom report output file

Configuration File Format:
    The configuration file should contain key=value pairs:

    # Selections
    select_lxc=true
    select_vnc=true
    select_audio=true
    select_clipboard=true
    select_apps=false

    # Options
    lxc_ctid=100
    vnc_enable_tls=true
    vnc_enable_monitoring=true
    vnc_fps=60
    audio_system=pipewire
    clipboard_interval=2
    apps_config=/path/to/apps.yaml

Examples:
    # Interactive setup
    $0

    # Dry-run to preview changes
    $0 --dry-run

    # Automated setup with config file
    $0 --auto --config /etc/waydroid-setup/my-config.conf

    # Save configuration for later use
    $0 --save-config /etc/waydroid-setup/saved-config.conf

Enhancement Details:

    1. LXC Performance Tuning
       - Optimizes container cgroup settings
       - Configures CPU, memory, and I/O limits
       - Sets up monitoring hooks
       - Hardens security capabilities
       Runs on: Proxmox host
       Requires: Container ID (CTID)

    2. VNC Security Enhancements
       - Configures password authentication
       - Optional TLS encryption
       - Rate limiting protection
       - Connection monitoring
       - Performance optimization
       Runs in: LXC container
       Requires: WayVNC installed

    3. Audio Passthrough
       - Configures PulseAudio or PipeWire
       - Sets up device passthrough
       - Configures Waydroid audio
       - Tests audio functionality
       Runs on: Host and container
       Requires: Container ID, audio system

    4. Clipboard Sharing
       - Bidirectional clipboard sync
       - VNC clipboard integration
       - Android clipboard access via ADB
       - Conflict resolution
       Runs in: LXC container
       Requires: Waydroid running

    5. App Installation
       - Install from local APKs
       - Download from URLs
       - F-Droid repository support
       - Batch installation from config
       Runs in: LXC container
       Requires: Waydroid initialized

For more information, visit:
https://github.com/MvRoo/waydroid-proxmox

EOF
}

# Check if running on Proxmox host
is_proxmox_host() {
    command -v pct &> /dev/null && command -v pveversion &> /dev/null
}

# Check if running in LXC container
is_lxc_container() {
    [ -f /proc/1/environ ] && grep -q "container=lxc" /proc/1/environ
}

# Detect environment
detect_environment() {
    if is_proxmox_host; then
        echo "host"
    elif is_lxc_container; then
        echo "container"
    else
        echo "unknown"
    fi
}

# Save current choices to file
save_choices() {
    local file="${1:-$CHOICES_FILE}"

    msg_info "Saving configuration to: $file"

    cat > "$file" << EOF
# Waydroid Proxmox Setup Configuration
# Generated: $(date)

# Enhancement selections
select_lxc=${SELECTED[lxc]}
select_vnc=${SELECTED[vnc]}
select_audio=${SELECTED[audio]}
select_clipboard=${SELECTED[clipboard]}
select_apps=${SELECTED[apps]}

# Enhancement options
lxc_ctid=${OPTIONS[lxc_ctid]}
vnc_enable_tls=${OPTIONS[vnc_enable_tls]}
vnc_enable_monitoring=${OPTIONS[vnc_enable_monitoring]}
vnc_fps=${OPTIONS[vnc_fps]}
audio_system=${OPTIONS[audio_system]}
clipboard_interval=${OPTIONS[clipboard_interval]}
apps_config=${OPTIONS[apps_config]}
EOF

    msg_ok "Configuration saved"
}

# Load choices from file
load_choices() {
    local file="$1"

    if [ ! -f "$file" ]; then
        msg_error "Configuration file not found: $file"
        return 1
    fi

    msg_info "Loading configuration from: $file"

    # Source the file and parse values
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        case "$key" in
            select_lxc) SELECTED[lxc]=$value ;;
            select_vnc) SELECTED[vnc]=$value ;;
            select_audio) SELECTED[audio]=$value ;;
            select_clipboard) SELECTED[clipboard]=$value ;;
            select_apps) SELECTED[apps]=$value ;;
            lxc_ctid) OPTIONS[lxc_ctid]=$value ;;
            vnc_enable_tls) OPTIONS[vnc_enable_tls]=$value ;;
            vnc_enable_monitoring) OPTIONS[vnc_enable_monitoring]=$value ;;
            vnc_fps) OPTIONS[vnc_fps]=$value ;;
            audio_system) OPTIONS[audio_system]=$value ;;
            clipboard_interval) OPTIONS[clipboard_interval]=$value ;;
            apps_config) OPTIONS[apps_config]=$value ;;
        esac
    done < "$file"

    msg_ok "Configuration loaded"
}

# ============================================================================
# PREREQUISITE CHECKING
# ============================================================================

# Check prerequisites for LXC tuning
check_prereq_lxc() {
    local errors=0

    if ! is_proxmox_host; then
        msg_error "LXC tuning must be run on Proxmox host"
        errors=$((errors + 1))
    fi

    if [ -z "${OPTIONS[lxc_ctid]}" ]; then
        msg_error "Container ID (CTID) required for LXC tuning"
        errors=$((errors + 1))
    elif ! pct status "${OPTIONS[lxc_ctid]}" &> /dev/null; then
        msg_error "Container ${OPTIONS[lxc_ctid]} does not exist"
        errors=$((errors + 1))
    fi

    if [ ! -f "${SCRIPTS[lxc]}" ]; then
        msg_error "LXC tuning script not found: ${SCRIPTS[lxc]}"
        errors=$((errors + 1))
    fi

    return $errors
}

# Check prerequisites for VNC enhancement
check_prereq_vnc() {
    local errors=0

    if ! is_lxc_container; then
        msg_warn "VNC enhancement should be run inside LXC container"
    fi

    if ! command -v wayvnc &> /dev/null; then
        msg_error "WayVNC is not installed"
        errors=$((errors + 1))
    fi

    if [ ! -f "${SCRIPTS[vnc]}" ]; then
        msg_error "VNC enhancement script not found: ${SCRIPTS[vnc]}"
        errors=$((errors + 1))
    fi

    return $errors
}

# Check prerequisites for audio setup
check_prereq_audio() {
    local errors=0

    if ! is_proxmox_host; then
        msg_error "Audio setup must be run on Proxmox host"
        errors=$((errors + 1))
    fi

    if [ -z "${OPTIONS[lxc_ctid]}" ]; then
        msg_error "Container ID (CTID) required for audio setup"
        errors=$((errors + 1))
    fi

    if [ ! -f "${SCRIPTS[audio]}" ]; then
        msg_error "Audio setup script not found: ${SCRIPTS[audio]}"
        errors=$((errors + 1))
    fi

    # Check for audio system on host
    if ! pgrep -x "pipewire\|pulseaudio" &> /dev/null; then
        msg_warn "No audio system detected on host (PipeWire or PulseAudio)"
    fi

    return $errors
}

# Check prerequisites for clipboard setup
check_prereq_clipboard() {
    local errors=0

    if ! is_lxc_container; then
        msg_warn "Clipboard setup should be run inside LXC container"
    fi

    if ! command -v waydroid &> /dev/null; then
        msg_error "Waydroid is not installed"
        errors=$((errors + 1))
    fi

    if [ ! -f "${SCRIPTS[clipboard]}" ]; then
        msg_error "Clipboard setup script not found: ${SCRIPTS[clipboard]}"
        errors=$((errors + 1))
    fi

    return $errors
}

# Check prerequisites for app installation
check_prereq_apps() {
    local errors=0

    if ! is_lxc_container; then
        msg_warn "App installation should be run inside LXC container"
    fi

    if ! command -v waydroid &> /dev/null; then
        msg_error "Waydroid is not installed"
        errors=$((errors + 1))
    fi

    if ! waydroid status 2>&1 | grep -q "RUNNING"; then
        msg_error "Waydroid container must be running"
        errors=$((errors + 1))
    fi

    if [ ! -f "${SCRIPTS[apps]}" ]; then
        msg_error "App installation script not found: ${SCRIPTS[apps]}"
        errors=$((errors + 1))
    fi

    if [ "${SELECTED[apps]}" = true ] && [ -n "${OPTIONS[apps_config]}" ]; then
        if [ ! -f "${OPTIONS[apps_config]}" ]; then
            msg_error "App config file not found: ${OPTIONS[apps_config]}"
            errors=$((errors + 1))
        fi
    fi

    return $errors
}

# Check all prerequisites
check_all_prerequisites() {
    local total_errors=0

    echo ""
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Checking Prerequisites${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""

    # Environment check
    local env=$(detect_environment)
    msg_info "Detected environment: $env"
    echo ""

    # Check each selected enhancement
    if [ "${SELECTED[lxc]}" = true ]; then
        echo -e "${BL}Checking LXC Performance Tuning...${CL}"
        if check_prereq_lxc; then
            msg_ok "LXC tuning prerequisites satisfied"
        else
            msg_error "LXC tuning prerequisites not satisfied"
            total_errors=$((total_errors + $?))
        fi
        echo ""
    fi

    if [ "${SELECTED[vnc]}" = true ]; then
        echo -e "${BL}Checking VNC Security Enhancement...${CL}"
        if check_prereq_vnc; then
            msg_ok "VNC enhancement prerequisites satisfied"
        else
            msg_error "VNC enhancement prerequisites not satisfied"
            total_errors=$((total_errors + $?))
        fi
        echo ""
    fi

    if [ "${SELECTED[audio]}" = true ]; then
        echo -e "${BL}Checking Audio Passthrough...${CL}"
        if check_prereq_audio; then
            msg_ok "Audio setup prerequisites satisfied"
        else
            msg_error "Audio setup prerequisites not satisfied"
            total_errors=$((total_errors + $?))
        fi
        echo ""
    fi

    if [ "${SELECTED[clipboard]}" = true ]; then
        echo -e "${BL}Checking Clipboard Sharing...${CL}"
        if check_prereq_clipboard; then
            msg_ok "Clipboard setup prerequisites satisfied"
        else
            msg_error "Clipboard setup prerequisites not satisfied"
            total_errors=$((total_errors + $?))
        fi
        echo ""
    fi

    if [ "${SELECTED[apps]}" = true ]; then
        echo -e "${BL}Checking App Installation...${CL}"
        if check_prereq_apps; then
            msg_ok "App installation prerequisites satisfied"
        else
            msg_error "App installation prerequisites not satisfied"
            total_errors=$((total_errors + $?))
        fi
        echo ""
    fi

    if [ $total_errors -eq 0 ]; then
        msg_ok "All prerequisites satisfied"
        return 0
    else
        msg_error "Found $total_errors prerequisite error(s)"
        return 1
    fi
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

# Display main menu
show_main_menu() {
    while true; do
        show_banner

        echo -e "${GN}═══════════════════════════════════════════════${CL}"
        echo -e "${GN}  Main Menu${CL}"
        echo -e "${GN}═══════════════════════════════════════════════${CL}"
        echo ""
        echo "Select enhancements to apply:"
        echo ""
        echo -e "  [$([ "${SELECTED[lxc]}" = true ] && echo "${GN}✓${CL}" || echo " ")] 1. LXC Performance Tuning"
        echo -e "  [$([ "${SELECTED[vnc]}" = true ] && echo "${GN}✓${CL}" || echo " ")] 2. VNC Security Enhancement"
        echo -e "  [$([ "${SELECTED[audio]}" = true ] && echo "${GN}✓${CL}" || echo " ")] 3. Audio Passthrough"
        echo -e "  [$([ "${SELECTED[clipboard]}" = true ] && echo "${GN}✓${CL}" || echo " ")] 4. Clipboard Sharing"
        echo -e "  [$([ "${SELECTED[apps]}" = true ] && echo "${GN}✓${CL}" || echo " ")] 5. App Installation"
        echo ""
        echo -e "  ${BL}o${CL}. Configure Options"
        echo -e "  ${BL}c${CL}. Check Prerequisites"
        echo -e "  ${BL}s${CL}. Save Configuration"
        echo -e "  ${BL}l${CL}. Load Configuration"
        echo ""
        echo -e "  ${GN}r${CL}. Run Selected Enhancements"
        echo -e "  ${YW}d${CL}. Dry Run (Preview Only)"
        echo -e "  ${RD}q${CL}. Quit"
        echo ""

        read -p "Enter choice: " -n 1 choice
        echo ""

        case "$choice" in
            1) toggle_selection "lxc" ;;
            2) toggle_selection "vnc" ;;
            3) toggle_selection "audio" ;;
            4) toggle_selection "clipboard" ;;
            5) toggle_selection "apps" ;;
            o|O) show_options_menu ;;
            c|C) check_all_prerequisites; read -p "Press Enter to continue..." ;;
            s|S)
                read -p "Save configuration to [${CHOICES_FILE}]: " file
                save_choices "${file:-$CHOICES_FILE}"
                read -p "Press Enter to continue..."
                ;;
            l|L)
                read -p "Load configuration from: " file
                if [ -n "$file" ]; then
                    load_choices "$file"
                fi
                read -p "Press Enter to continue..."
                ;;
            r|R)
                if ! any_selected; then
                    msg_error "No enhancements selected"
                    read -p "Press Enter to continue..."
                    continue
                fi
                DRY_RUN=false
                break
                ;;
            d|D)
                if ! any_selected; then
                    msg_error "No enhancements selected"
                    read -p "Press Enter to continue..."
                    continue
                fi
                DRY_RUN=true
                break
                ;;
            q|Q)
                msg_info "Exiting..."
                exit 0
                ;;
            *)
                msg_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Toggle enhancement selection
toggle_selection() {
    local key="$1"
    if [ "${SELECTED[$key]}" = true ]; then
        SELECTED[$key]=false
    else
        SELECTED[$key]=true
        # Prompt for required options
        prompt_required_options "$key"
    fi
}

# Check if any enhancement is selected
any_selected() {
    for key in "${!SELECTED[@]}"; do
        if [ "${SELECTED[$key]}" = true ]; then
            return 0
        fi
    done
    return 1
}

# Prompt for required options when selecting enhancement
prompt_required_options() {
    local enhancement="$1"

    case "$enhancement" in
        lxc|audio)
            if [ -z "${OPTIONS[lxc_ctid]}" ]; then
                read -p "Enter Container ID (CTID): " OPTIONS[lxc_ctid]
            fi
            ;;
        apps)
            if [ -z "${OPTIONS[apps_config]}" ]; then
                read -p "Enter app config file path (or leave empty): " OPTIONS[apps_config]
            fi
            ;;
    esac
}

# Show options configuration menu
show_options_menu() {
    while true; do
        show_banner

        echo -e "${GN}═══════════════════════════════════════════════${CL}"
        echo -e "${GN}  Configuration Options${CL}"
        echo -e "${GN}═══════════════════════════════════════════════${CL}"
        echo ""

        echo -e "${BL}LXC / Audio Options:${CL}"
        echo -e "  1. Container ID: ${YW}${OPTIONS[lxc_ctid]:-<not set>}${CL}"
        echo ""

        echo -e "${BL}VNC Options:${CL}"
        echo -e "  2. Enable TLS: ${OPTIONS[vnc_enable_tls]}"
        echo -e "  3. Enable Monitoring: ${OPTIONS[vnc_enable_monitoring]}"
        echo -e "  4. Max FPS: ${OPTIONS[vnc_fps]}"
        echo ""

        echo -e "${BL}Audio Options:${CL}"
        echo -e "  5. Audio System: ${OPTIONS[audio_system]}"
        echo ""

        echo -e "${BL}Clipboard Options:${CL}"
        echo -e "  6. Sync Interval: ${OPTIONS[clipboard_interval]} seconds"
        echo ""

        echo -e "${BL}App Installation Options:${CL}"
        echo -e "  7. Config File: ${YW}${OPTIONS[apps_config]:-<not set>}${CL}"
        echo ""

        echo -e "  ${BL}b${CL}. Back to Main Menu"
        echo ""

        read -p "Enter option to change (or b to go back): " choice
        echo ""

        case "$choice" in
            1)
                read -p "Enter Container ID: " OPTIONS[lxc_ctid]
                ;;
            2)
                OPTIONS[vnc_enable_tls]=$([ "${OPTIONS[vnc_enable_tls]}" = true ] && echo false || echo true)
                ;;
            3)
                OPTIONS[vnc_enable_monitoring]=$([ "${OPTIONS[vnc_enable_monitoring]}" = true ] && echo false || echo true)
                ;;
            4)
                read -p "Enter Max FPS (15-120): " OPTIONS[vnc_fps]
                ;;
            5)
                echo "Audio system options: auto, pulseaudio, pipewire"
                read -p "Enter audio system: " OPTIONS[audio_system]
                ;;
            6)
                read -p "Enter sync interval (1-60 seconds): " OPTIONS[clipboard_interval]
                ;;
            7)
                read -p "Enter app config file path: " OPTIONS[apps_config]
                ;;
            b|B)
                break
                ;;
            *)
                msg_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# ============================================================================
# EXECUTION ENGINE
# ============================================================================

# Execute single enhancement
execute_enhancement() {
    local name="$1"
    local description="$2"
    local script="$3"
    shift 3
    local args=("$@")

    COMPLETED_STEPS=$((COMPLETED_STEPS + 1))

    echo ""
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  [$COMPLETED_STEPS/$TOTAL_STEPS] $description${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""

    if [ ! -f "$script" ]; then
        msg_error "Script not found: $script"
        EXECUTION_STATUS[$name]="failed"
        EXECUTION_ERROR[$name]="Script file not found"
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        msg_info "DRY RUN: Would execute: $script ${args[*]}"
        EXECUTION_STATUS[$name]="dry-run"
        EXECUTION_TIME[$name]="0"
        return 0
    fi

    local start_time=$(date +%s)

    # Execute the script
    if bash "$script" "${args[@]}" 2>&1 | tee -a "$REPORT_FILE"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        EXECUTION_STATUS[$name]="success"
        EXECUTION_TIME[$name]="$duration"
        msg_ok "$description completed in ${duration}s"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        EXECUTION_STATUS[$name]="failed"
        EXECUTION_TIME[$name]="$duration"
        EXECUTION_ERROR[$name]="Script execution failed"
        msg_error "$description failed after ${duration}s"
        return 1
    fi
}

# Execute all selected enhancements
execute_all_enhancements() {
    TOTAL_START_TIME=$(date +%s)

    # Count total steps
    TOTAL_STEPS=0
    for key in "${!SELECTED[@]}"; do
        if [ "${SELECTED[$key]}" = true ]; then
            TOTAL_STEPS=$((TOTAL_STEPS + 1))
        fi
    done

    if [ $TOTAL_STEPS -eq 0 ]; then
        msg_error "No enhancements selected"
        return 1
    fi

    show_banner

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YW}╔═══════════════════════════════════════════╗${CL}"
        echo -e "${YW}║           DRY-RUN MODE ENABLED            ║${CL}"
        echo -e "${YW}║     No changes will be made to system     ║${CL}"
        echo -e "${YW}╚═══════════════════════════════════════════╝${CL}"
        echo ""
    fi

    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo -e "${GN}  Starting Enhancement Execution${CL}"
    echo -e "${GN}═══════════════════════════════════════════════${CL}"
    echo ""
    echo "Total enhancements to apply: $TOTAL_STEPS"
    echo ""

    if [ "$SKIP_CONFIRMATION" != true ] && [ "$DRY_RUN" != true ]; then
        read -p "Continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            msg_info "Cancelled by user"
            return 1
        fi
    fi

    COMPLETED_STEPS=0

    # Execute in correct order
    # 1. LXC tuning (must run first, on host)
    if [ "${SELECTED[lxc]}" = true ]; then
        local args=()
        [ "$DRY_RUN" = true ] && args+=("--dry-run")
        args+=("${OPTIONS[lxc_ctid]}")

        execute_enhancement "lxc" "LXC Performance Tuning" "${SCRIPTS[lxc]}" "${args[@]}"
    fi

    # 2. Audio setup (requires host access)
    if [ "${SELECTED[audio]}" = true ]; then
        local args=()
        [ "$DRY_RUN" = true ] && args+=("--dry-run")
        if [ "${OPTIONS[audio_system]}" != "auto" ]; then
            args+=("--force-${OPTIONS[audio_system]}")
        fi
        args+=("${OPTIONS[lxc_ctid]}")

        execute_enhancement "audio" "Audio Passthrough Setup" "${SCRIPTS[audio]}" "${args[@]}"
    fi

    # 3. VNC enhancement (container-based)
    if [ "${SELECTED[vnc]}" = true ]; then
        local args=()
        [ "${OPTIONS[vnc_enable_tls]}" = true ] && args+=("--enable-tls")
        [ "${OPTIONS[vnc_enable_monitoring]}" = true ] && args+=("--enable-monitoring")
        args+=("--fps" "${OPTIONS[vnc_fps]}")

        execute_enhancement "vnc" "VNC Security Enhancement" "${SCRIPTS[vnc]}" "${args[@]}"
    fi

    # 4. Clipboard setup (container-based)
    if [ "${SELECTED[clipboard]}" = true ]; then
        local args=("--install")
        args+=("--sync-interval" "${OPTIONS[clipboard_interval]}")

        execute_enhancement "clipboard" "Clipboard Sharing Setup" "${SCRIPTS[clipboard]}" "${args[@]}"
    fi

    # 5. App installation (container-based, last)
    if [ "${SELECTED[apps]}" = true ]; then
        if [ -n "${OPTIONS[apps_config]}" ] && [ -f "${OPTIONS[apps_config]}" ]; then
            local args=("install-batch" "${OPTIONS[apps_config]}")

            execute_enhancement "apps" "App Installation" "${SCRIPTS[apps]}" "${args[@]}"
        else
            msg_warn "Skipping app installation: no config file specified"
            EXECUTION_STATUS["apps"]="skipped"
        fi
    fi

    # Generate summary
    generate_summary
}

# ============================================================================
# REPORTING
# ============================================================================

# Generate execution summary
generate_summary() {
    local total_end_time=$(date +%s)
    local total_duration=$((total_end_time - TOTAL_START_TIME))

    local summary_file="${REPORT_FILE%.txt}-summary.txt"

    {
        echo "╔═══════════════════════════════════════════════════════════════════════════╗"
        echo "║                                                                           ║"
        echo "║              Waydroid Proxmox Setup - Execution Summary                   ║"
        echo "║                                                                           ║"
        echo "╚═══════════════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Execution Date: $(date)"
        echo "Total Duration: ${total_duration}s ($(date -u -d @${total_duration} +%T 2>/dev/null || echo "${total_duration}s"))"
        echo "Mode: $([ "$DRY_RUN" = true ] && echo "Dry-run" || echo "Normal")"
        echo ""
        echo "═══════════════════════════════════════════════════════════════════════════"
        echo "  Enhancement Results"
        echo "═══════════════════════════════════════════════════════════════════════════"
        echo ""

        local success_count=0
        local failed_count=0
        local skipped_count=0

        for key in lxc vnc audio clipboard apps; do
            if [ "${SELECTED[$key]}" = true ]; then
                local status="${EXECUTION_STATUS[$key]:-not_run}"
                local time="${EXECUTION_TIME[$key]:-0}"
                local error="${EXECUTION_ERROR[$key]:-}"

                local name=""
                case "$key" in
                    lxc) name="LXC Performance Tuning" ;;
                    vnc) name="VNC Security Enhancement" ;;
                    audio) name="Audio Passthrough" ;;
                    clipboard) name="Clipboard Sharing" ;;
                    apps) name="App Installation" ;;
                esac

                printf "%-30s : " "$name"

                case "$status" in
                    success)
                        echo -e "\033[1;92mSUCCESS\033[m (${time}s)"
                        success_count=$((success_count + 1))
                        ;;
                    failed)
                        echo -e "\033[01;31mFAILED\033[m (${time}s)"
                        [ -n "$error" ] && echo "  Error: $error"
                        failed_count=$((failed_count + 1))
                        ;;
                    dry-run)
                        echo -e "\033[1;93mDRY-RUN\033[m"
                        ;;
                    skipped)
                        echo -e "\033[36mSKIPPED\033[m"
                        skipped_count=$((skipped_count + 1))
                        ;;
                    *)
                        echo -e "\033[01;31mNOT RUN\033[m"
                        ;;
                esac
            fi
        done

        echo ""
        echo "═══════════════════════════════════════════════════════════════════════════"
        echo "  Summary Statistics"
        echo "═══════════════════════════════════════════════════════════════════════════"
        echo ""
        echo "Total Enhancements: $TOTAL_STEPS"
        echo "Successful: $success_count"
        echo "Failed: $failed_count"
        echo "Skipped: $skipped_count"
        echo ""

        if [ "$DRY_RUN" != true ]; then
            echo "═══════════════════════════════════════════════════════════════════════════"
            echo "  Next Steps"
            echo "═══════════════════════════════════════════════════════════════════════════"
            echo ""

            if [ $failed_count -eq 0 ]; then
                echo "All enhancements completed successfully!"
                echo ""

                if [ "${SELECTED[lxc]}" = true ]; then
                    echo "LXC Container:"
                    echo "  - Restart container to apply changes: pct restart ${OPTIONS[lxc_ctid]}"
                    echo "  - Review config: cat /etc/pve/lxc/${OPTIONS[lxc_ctid]}.conf"
                    echo ""
                fi

                if [ "${SELECTED[vnc]}" = true ] || [ "${SELECTED[clipboard]}" = true ]; then
                    echo "Services:"
                    echo "  - Check VNC: systemctl status waydroid-vnc"
                    if [ "${SELECTED[clipboard]}" = true ]; then
                        echo "  - Check clipboard: waydroid-clipboard status"
                    fi
                    echo ""
                fi

                if [ "${SELECTED[audio]}" = true ]; then
                    echo "Audio:"
                    echo "  - Test audio: pct exec ${OPTIONS[lxc_ctid]} -- speaker-test -t wav -c 2"
                    echo ""
                fi

                if [ "${SELECTED[apps]}" = true ]; then
                    echo "Apps:"
                    echo "  - List installed: waydroid app list"
                    echo ""
                fi

                echo "Logs:"
                echo "  - Full report: $REPORT_FILE"
                echo "  - Summary: $summary_file"
            else
                echo "Some enhancements failed. Please review the errors above."
                echo ""
                echo "Troubleshooting:"
                echo "  - Check detailed logs: $REPORT_FILE"
                echo "  - Review individual script documentation"
                echo "  - Run scripts manually with --help for more options"
                echo ""
                echo "You can re-run this script to retry failed enhancements."
            fi
            echo ""
        else
            echo "═══════════════════════════════════════════════════════════════════════════"
            echo "  Dry-Run Complete"
            echo "═══════════════════════════════════════════════════════════════════════════"
            echo ""
            echo "This was a dry-run. No changes were made to the system."
            echo ""
            echo "To apply these changes, run again without --dry-run:"
            echo "  $0"
            echo ""
        fi

    } | tee "$summary_file"

    msg_info "Summary saved to: $summary_file"
    msg_info "Full log saved to: $REPORT_FILE"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                INTERACTIVE=false
                shift
                ;;
            --config)
                if [ -n "${2:-}" ]; then
                    load_choices "$2"
                    shift 2
                else
                    msg_error "--config requires a file path"
                    exit 1
                fi
                ;;
            --save-config)
                if [ -n "${2:-}" ]; then
                    save_choices "$2"
                    exit 0
                else
                    msg_error "--save-config requires a file path"
                    exit 1
                fi
                ;;
            --skip-confirm)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --ctid)
                if [ -n "${2:-}" ]; then
                    OPTIONS[lxc_ctid]="$2"
                    shift 2
                else
                    msg_error "--ctid requires a container ID"
                    exit 1
                fi
                ;;
            --report)
                if [ -n "${2:-}" ]; then
                    REPORT_FILE="$2"
                    shift 2
                else
                    msg_error "--report requires a file path"
                    exit 1
                fi
                ;;
            *)
                msg_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Initialize report file
    {
        echo "Waydroid Proxmox Setup - Execution Log"
        echo "Started: $(date)"
        echo "Mode: $([ "$DRY_RUN" = true ] && echo "Dry-run" || echo "Normal")"
        echo "========================================"
        echo ""
    } > "$REPORT_FILE"

    # Interactive mode
    if [ "$INTERACTIVE" = true ]; then
        show_main_menu
        check_all_prerequisites || {
            echo ""
            msg_error "Prerequisites check failed"
            echo ""
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                msg_info "Setup cancelled"
                exit 1
            fi
        }
    fi

    # Auto mode validation
    if [ "$AUTO_MODE" = true ]; then
        if ! any_selected; then
            msg_error "Auto mode requires at least one enhancement to be selected in config file"
            exit 1
        fi

        if ! check_all_prerequisites; then
            msg_error "Prerequisites check failed in auto mode"
            exit 1
        fi
    fi

    # Execute selected enhancements
    execute_all_enhancements

    local exit_code=0
    for key in "${!EXECUTION_STATUS[@]}"; do
        if [ "${EXECUTION_STATUS[$key]}" = "failed" ]; then
            exit_code=1
            break
        fi
    done

    exit $exit_code
}

# Run main function
main "$@"
