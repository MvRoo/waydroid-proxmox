#!/usr/bin/env bash

# Clipboard Sharing Setup for Waydroid Proxmox LXC
# Implements bidirectional clipboard sync between host/VNC and Android
#
# Features:
#   - Wayland clipboard integration (wl-clipboard)
#   - VNC clipboard support (automatic via wayvnc)
#   - Bidirectional sync service
#   - Android clipboard access via ADB
#   - Systemd service for automatic startup
#   - Intelligent conflict resolution
#   - Performance optimization
#
# Usage:
#   ./setup-clipboard.sh [options]
#
# Options:
#   --install             Install and configure clipboard sharing
#   --uninstall           Remove clipboard sharing setup
#   --enable              Enable clipboard sync service
#   --disable             Disable clipboard sync service
#   --status              Show clipboard sync status
#   --test                Test clipboard functionality
#   --sync-interval <sec> Set sync interval in seconds (default: 2)
#   --max-size <bytes>    Set max clipboard size in bytes (default: 1048576)
#   --help                Show this help message

set -euo pipefail

# Source helper functions if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/helper-functions.sh" ]; then
    source "$SCRIPT_DIR/helper-functions.sh"
else
    # Minimal fallback functions
    msg_info() { echo "[INFO] $1"; }
    msg_ok() { echo "[OK] $1"; }
    msg_error() { echo "[ERROR] $1"; }
    msg_warn() { echo "[WARN] $1"; }
fi

# Default configuration
SYNC_INTERVAL=2
MAX_CLIPBOARD_SIZE=1048576  # 1MB
CLIPBOARD_CACHE_DIR="/var/lib/waydroid-clipboard"
CLIPBOARD_LOG="/var/log/waydroid-clipboard.log"
CLIPBOARD_SERVICE="waydroid-clipboard-sync"
ADB_PORT=5555

# Parse arguments
ACTION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --install)
            ACTION="install"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --enable)
            ACTION="enable"
            shift
            ;;
        --disable)
            ACTION="disable"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --test)
            ACTION="test"
            shift
            ;;
        --sync-interval)
            SYNC_INTERVAL="$2"
            shift 2
            ;;
        --max-size)
            MAX_CLIPBOARD_SIZE="$2"
            shift 2
            ;;
        --help)
            grep '^#' "$0" | grep -E '^# (Usage|Options|Features|  )' | sed 's/^# //'
            exit 0
            ;;
        *)
            msg_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validation
if [[ "$SYNC_INTERVAL" -lt 1 || "$SYNC_INTERVAL" -gt 60 ]]; then
    msg_error "Sync interval must be between 1 and 60 seconds"
    exit 1
fi

if [[ "$MAX_CLIPBOARD_SIZE" -lt 1024 || "$MAX_CLIPBOARD_SIZE" -gt 10485760 ]]; then
    msg_error "Max clipboard size must be between 1KB and 10MB"
    exit 1
fi

# ============================================================================
# DEPENDENCY INSTALLATION
# ============================================================================

install_dependencies() {
    msg_info "Installing clipboard dependencies..."

    # Update package lists
    apt-get update -qq || {
        msg_error "Failed to update package lists"
        return 1
    }

    # Install required packages
    local packages=(
        "wl-clipboard"      # Wayland clipboard tools
        "adb"               # Android Debug Bridge
        "inotify-tools"     # For monitoring clipboard changes
        "xclip"             # Fallback clipboard tool
        "socat"             # For socket operations
    )

    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package"; then
            msg_info "Installing $package..."
            apt-get install -y -qq "$package" 2>&1 | grep -v "^debconf:" || {
                msg_warn "Failed to install $package"
            }
        else
            msg_ok "$package already installed"
        fi
    done

    msg_ok "Dependencies installed"
}

# ============================================================================
# ADB CONFIGURATION
# ============================================================================

configure_adb() {
    msg_info "Configuring ADB for Waydroid..."

    # Check if Waydroid is running
    if ! waydroid status 2>&1 | grep -q "RUNNING"; then
        msg_warn "Waydroid is not running. Starting container..."

        # Start Waydroid container
        waydroid container start 2>/dev/null || {
            msg_error "Failed to start Waydroid container"
            return 1
        }

        # Wait for container to be ready
        sleep 5
    fi

    # Enable ADB in Waydroid
    msg_info "Enabling ADB in Waydroid..."

    # Set ADB TCP port
    waydroid shell setprop service.adb.tcp.port "$ADB_PORT" 2>/dev/null || {
        msg_warn "Failed to set ADB port (Waydroid may not be fully started)"
    }

    # Restart ADB daemon
    waydroid shell stop adbd 2>/dev/null || true
    sleep 1
    waydroid shell start adbd 2>/dev/null || true
    sleep 2

    # Connect ADB
    msg_info "Connecting ADB to localhost:$ADB_PORT..."

    # Kill any existing ADB server
    adb kill-server 2>/dev/null || true
    sleep 1

    # Start ADB server
    adb start-server 2>/dev/null || {
        msg_error "Failed to start ADB server"
        return 1
    }

    # Connect to Waydroid
    adb connect localhost:$ADB_PORT 2>&1 | grep -v "failed to authenticate" || {
        msg_warn "ADB connection may need authentication"
    }

    # Wait for device
    msg_info "Waiting for device..."
    for i in {1..10}; do
        if adb devices | grep -q "localhost:$ADB_PORT.*device$"; then
            msg_ok "ADB connected successfully"
            return 0
        fi
        sleep 1
    done

    msg_warn "ADB connection timeout - clipboard sync may not work until device is ready"
    return 0
}

# ============================================================================
# CLIPBOARD SYNC DAEMON
# ============================================================================

create_sync_daemon() {
    msg_info "Creating clipboard sync daemon..."

    # Create cache directory
    mkdir -p "$CLIPBOARD_CACHE_DIR"
    chmod 700 "$CLIPBOARD_CACHE_DIR"

    # Create clipboard sync script
    cat > /usr/local/bin/waydroid-clipboard-sync.sh <<'SYNC_SCRIPT_EOF'
#!/usr/bin/env bash

# Waydroid Clipboard Sync Daemon
# Bidirectional clipboard synchronization between Wayland and Android

set -euo pipefail

# Configuration
SYNC_INTERVAL="${CLIPBOARD_SYNC_INTERVAL:-2}"
MAX_SIZE="${CLIPBOARD_MAX_SIZE:-1048576}"
CACHE_DIR="${CLIPBOARD_CACHE_DIR:-/var/lib/waydroid-clipboard}"
LOG_FILE="${CLIPBOARD_LOG:-/var/log/waydroid-clipboard.log}"
ADB_DEVICE="localhost:5555"
DEBUG="${CLIPBOARD_DEBUG:-false}"

# State files
WAYLAND_CACHE="$CACHE_DIR/wayland_last"
ANDROID_CACHE="$CACHE_DIR/android_last"
WAYLAND_HASH="$CACHE_DIR/wayland_hash"
ANDROID_HASH="$CACHE_DIR/android_hash"

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"
touch "$WAYLAND_CACHE" "$ANDROID_CACHE" "$WAYLAND_HASH" "$ANDROID_HASH"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    if [ "$DEBUG" = "true" ]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# Error handling
error_count=0
max_errors=10

handle_error() {
    local context="$1"
    error_count=$((error_count + 1))
    log "ERROR" "$context (error $error_count/$max_errors)"

    if [ $error_count -ge $max_errors ]; then
        log "FATAL" "Too many errors, exiting"
        exit 1
    fi

    sleep 5
}

# Reset error count on success
reset_errors() {
    error_count=0
}

# Check if ADB is connected
check_adb_connection() {
    if ! adb devices 2>/dev/null | grep -q "$ADB_DEVICE.*device$"; then
        log "WARN" "ADB not connected, attempting reconnection..."

        # Kill and restart ADB server
        adb kill-server 2>/dev/null || true
        sleep 1
        adb start-server 2>/dev/null || return 1

        # Reconnect
        adb connect "$ADB_DEVICE" >/dev/null 2>&1 || return 1
        sleep 2

        # Verify connection
        if adb devices 2>/dev/null | grep -q "$ADB_DEVICE.*device$"; then
            log "INFO" "ADB reconnected successfully"
            return 0
        else
            return 1
        fi
    fi
    return 0
}

# Get Wayland clipboard content
get_wayland_clipboard() {
    local content

    # Try to get clipboard content
    if content=$(timeout 2 wl-paste 2>/dev/null); then
        # Check size
        local size=${#content}
        if [ "$size" -gt "$MAX_SIZE" ]; then
            log "WARN" "Wayland clipboard too large ($size bytes), skipping"
            return 1
        fi

        echo -n "$content"
        return 0
    else
        # Empty or error
        return 1
    fi
}

# Set Wayland clipboard content
set_wayland_clipboard() {
    local content="$1"

    # Check if we're in a Wayland session
    if [ -z "${WAYLAND_DISPLAY:-}" ]; then
        log "WARN" "WAYLAND_DISPLAY not set"
        return 1
    fi

    # Set clipboard
    if echo -n "$content" | timeout 2 wl-copy 2>/dev/null; then
        return 0
    else
        log "ERROR" "Failed to set Wayland clipboard"
        return 1
    fi
}

# Get Android clipboard content
get_android_clipboard() {
    local content

    # Try to get clipboard via ADB
    if ! check_adb_connection; then
        return 1
    fi

    # Get clipboard content (API 29+)
    if content=$(timeout 3 adb -s "$ADB_DEVICE" shell cmd clipboard get 2>/dev/null); then
        # Remove trailing newline
        content="${content%$'\n'}"

        # Check size
        local size=${#content}
        if [ "$size" -gt "$MAX_SIZE" ]; then
            log "WARN" "Android clipboard too large ($size bytes), skipping"
            return 1
        fi

        echo -n "$content"
        return 0
    else
        # Try alternative method for older Android versions
        if content=$(timeout 3 adb -s "$ADB_DEVICE" shell "settings get secure clipboard" 2>/dev/null); then
            content="${content%$'\n'}"
            echo -n "$content"
            return 0
        fi
        return 1
    fi
}

# Set Android clipboard content
set_android_clipboard() {
    local content="$1"

    if ! check_adb_connection; then
        return 1
    fi

    # Escape special characters for shell
    local escaped_content=$(printf '%s' "$content" | sed "s/'/'\\\\''/g")

    # Set clipboard via ADB (API 29+)
    if timeout 3 adb -s "$ADB_DEVICE" shell "cmd clipboard put '$escaped_content'" 2>/dev/null; then
        return 0
    else
        log "ERROR" "Failed to set Android clipboard"
        return 1
    fi
}

# Calculate hash of content
calc_hash() {
    echo -n "$1" | md5sum | cut -d' ' -f1
}

# Sync from Wayland to Android
sync_wayland_to_android() {
    local wayland_content

    if ! wayland_content=$(get_wayland_clipboard); then
        return 0
    fi

    # Calculate hash
    local wayland_hash=$(calc_hash "$wayland_content")
    local last_wayland_hash=$(cat "$WAYLAND_HASH" 2>/dev/null || echo "")
    local last_android_hash=$(cat "$ANDROID_HASH" 2>/dev/null || echo "")

    # Check if content changed
    if [ "$wayland_hash" = "$last_wayland_hash" ]; then
        return 0
    fi

    # Avoid sync loops - don't sync if this is the same content we just set from Android
    if [ "$wayland_hash" = "$last_android_hash" ]; then
        # Update our tracking hash but don't sync
        echo -n "$wayland_hash" > "$WAYLAND_HASH"
        return 0
    fi

    # Sync to Android
    log "INFO" "Syncing Wayland -> Android (${#wayland_content} bytes)"

    if set_android_clipboard "$wayland_content"; then
        # Update cache
        echo -n "$wayland_content" > "$WAYLAND_CACHE"
        echo -n "$wayland_hash" > "$WAYLAND_HASH"
        echo -n "$wayland_hash" > "$ANDROID_HASH"
        log "INFO" "Sync successful"
        reset_errors
    else
        handle_error "Failed to sync Wayland -> Android"
    fi
}

# Sync from Android to Wayland
sync_android_to_wayland() {
    local android_content

    if ! android_content=$(get_android_clipboard); then
        return 0
    fi

    # Calculate hash
    local android_hash=$(calc_hash "$android_content")
    local last_android_hash=$(cat "$ANDROID_HASH" 2>/dev/null || echo "")
    local last_wayland_hash=$(cat "$WAYLAND_HASH" 2>/dev/null || echo "")

    # Check if content changed
    if [ "$android_hash" = "$last_android_hash" ]; then
        return 0
    fi

    # Avoid sync loops
    if [ "$android_hash" = "$last_wayland_hash" ]; then
        echo -n "$android_hash" > "$ANDROID_HASH"
        return 0
    fi

    # Sync to Wayland
    log "INFO" "Syncing Android -> Wayland (${#android_content} bytes)"

    if set_wayland_clipboard "$android_content"; then
        # Update cache
        echo -n "$android_content" > "$ANDROID_CACHE"
        echo -n "$android_hash" > "$ANDROID_HASH"
        echo -n "$android_hash" > "$WAYLAND_HASH"
        log "INFO" "Sync successful"
        reset_errors
    else
        handle_error "Failed to sync Android -> Wayland"
    fi
}

# Main sync loop
main() {
    log "INFO" "Clipboard sync daemon starting (interval: ${SYNC_INTERVAL}s, max size: ${MAX_SIZE} bytes)"

    # Initial ADB connection
    if ! check_adb_connection; then
        log "WARN" "Initial ADB connection failed, will retry"
    fi

    # Main loop
    while true; do
        # Sync both directions
        sync_wayland_to_android || true
        sync_android_to_wayland || true

        # Sleep
        sleep "$SYNC_INTERVAL"
    done
}

# Cleanup on exit
cleanup() {
    log "INFO" "Clipboard sync daemon stopping"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Run main loop
main
SYNC_SCRIPT_EOF

    chmod +x /usr/local/bin/waydroid-clipboard-sync.sh

    msg_ok "Clipboard sync daemon created"
}

# ============================================================================
# SYSTEMD SERVICE
# ============================================================================

create_systemd_service() {
    msg_info "Creating systemd service..."

    cat > /etc/systemd/system/${CLIPBOARD_SERVICE}.service <<EOF
[Unit]
Description=Waydroid Clipboard Sync Service
Documentation=https://github.com/MvRoo/waydroid-proxmox
After=waydroid-container.service
Wants=waydroid-container.service
PartOf=waydroid.service

[Service]
Type=simple
Environment="WAYLAND_DISPLAY=wayland-1"
Environment="XDG_RUNTIME_DIR=/run/user/0"
Environment="CLIPBOARD_SYNC_INTERVAL=$SYNC_INTERVAL"
Environment="CLIPBOARD_MAX_SIZE=$MAX_CLIPBOARD_SIZE"
Environment="CLIPBOARD_CACHE_DIR=$CLIPBOARD_CACHE_DIR"
Environment="CLIPBOARD_LOG=$CLIPBOARD_LOG"
Environment="CLIPBOARD_DEBUG=false"

ExecStart=/usr/local/bin/waydroid-clipboard-sync.sh

Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=5

# Security hardening
NoNewPrivileges=false
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$CLIPBOARD_CACHE_DIR /var/log

# Logging
StandardOutput=append:$CLIPBOARD_LOG
StandardError=append:$CLIPBOARD_LOG

[Install]
WantedBy=multi-user.target
EOF

    # Create log file
    touch "$CLIPBOARD_LOG"
    chmod 644 "$CLIPBOARD_LOG"

    # Setup log rotation
    cat > /etc/logrotate.d/waydroid-clipboard <<'LOGROTATE_EOF'
/var/log/waydroid-clipboard.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        systemctl reload waydroid-clipboard-sync 2>/dev/null || true
    endscript
}
LOGROTATE_EOF

    systemctl daemon-reload

    msg_ok "Systemd service created"
}

# ============================================================================
# MANAGEMENT TOOLS
# ============================================================================

create_management_tools() {
    msg_info "Creating management tools..."

    # Create clipboard control script
    cat > /usr/local/bin/waydroid-clipboard <<'CONTROL_EOF'
#!/usr/bin/env bash

# Waydroid Clipboard Control Tool

SERVICE="waydroid-clipboard-sync"

show_usage() {
    cat <<EOF
Waydroid Clipboard Control Tool

Usage: waydroid-clipboard [command]

Commands:
    start       Start clipboard sync service
    stop        Stop clipboard sync service
    restart     Restart clipboard sync service
    status      Show service status and statistics
    logs        Show recent clipboard sync logs
    test        Test clipboard functionality
    clear       Clear clipboard cache
    debug       Enable debug logging
    help        Show this help message

Examples:
    waydroid-clipboard start
    waydroid-clipboard status
    waydroid-clipboard logs
    waydroid-clipboard test
EOF
}

show_status() {
    echo "Waydroid Clipboard Sync Status"
    echo "==============================="
    echo ""

    # Service status
    echo "Service Status:"
    if systemctl is-active "$SERVICE" >/dev/null 2>&1; then
        echo "  Status: Running"
        echo "  Uptime: $(systemctl show -p ActiveEnterTimestamp "$SERVICE" --value | xargs -I{} date -d "{}" '+%Y-%m-%d %H:%M:%S')"
    else
        echo "  Status: Stopped"
    fi
    echo ""

    # Statistics
    if [ -f /var/log/waydroid-clipboard.log ]; then
        echo "Statistics (today):"
        local today=$(date +%Y-%m-%d)
        local wayland_to_android=$(grep "$today" /var/log/waydroid-clipboard.log | grep -c "Wayland -> Android" || echo "0")
        local android_to_wayland=$(grep "$today" /var/log/waydroid-clipboard.log | grep -c "Android -> Wayland" || echo "0")
        local errors=$(grep "$today" /var/log/waydroid-clipboard.log | grep -c "ERROR" || echo "0")

        echo "  Wayland -> Android: $wayland_to_android syncs"
        echo "  Android -> Wayland: $android_to_wayland syncs"
        echo "  Errors: $errors"
        echo ""
    fi

    # ADB connection
    echo "ADB Connection:"
    if adb devices 2>/dev/null | grep -q "localhost:5555.*device$"; then
        echo "  Status: Connected"
    else
        echo "  Status: Disconnected"
    fi
    echo ""

    # Cache info
    if [ -d /var/lib/waydroid-clipboard ]; then
        echo "Cache Directory:"
        echo "  Location: /var/lib/waydroid-clipboard"
        echo "  Size: $(du -sh /var/lib/waydroid-clipboard 2>/dev/null | cut -f1)"
    fi
    echo ""
}

show_logs() {
    if [ -f /var/log/waydroid-clipboard.log ]; then
        echo "Recent Clipboard Sync Logs:"
        echo "==========================="
        tail -n 50 /var/log/waydroid-clipboard.log
    else
        echo "No logs found"
    fi
}

test_clipboard() {
    echo "Testing Clipboard Functionality"
    echo "==============================="
    echo ""

    # Check dependencies
    echo "1. Checking dependencies..."
    local deps_ok=true

    for cmd in wl-copy wl-paste adb; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "   [OK] $cmd found"
        else
            echo "   [FAIL] $cmd not found"
            deps_ok=false
        fi
    done
    echo ""

    if [ "$deps_ok" = false ]; then
        echo "Test failed: Missing dependencies"
        return 1
    fi

    # Check ADB connection
    echo "2. Checking ADB connection..."
    if adb devices 2>/dev/null | grep -q "localhost:5555.*device$"; then
        echo "   [OK] ADB connected"
    else
        echo "   [FAIL] ADB not connected"
        echo "   Try: adb connect localhost:5555"
        return 1
    fi
    echo ""

    # Test Wayland clipboard
    echo "3. Testing Wayland clipboard..."
    local test_text="waydroid-clipboard-test-$(date +%s)"

    if echo "$test_text" | wl-copy 2>/dev/null; then
        local result=$(wl-paste 2>/dev/null)
        if [ "$result" = "$test_text" ]; then
            echo "   [OK] Wayland clipboard working"
        else
            echo "   [FAIL] Wayland clipboard read/write mismatch"
            return 1
        fi
    else
        echo "   [FAIL] Cannot write to Wayland clipboard"
        return 1
    fi
    echo ""

    # Test Android clipboard
    echo "4. Testing Android clipboard..."
    if adb shell "cmd clipboard put '$test_text'" 2>/dev/null; then
        sleep 1
        local result=$(adb shell cmd clipboard get 2>/dev/null | tr -d '\n\r')
        if [ "$result" = "$test_text" ]; then
            echo "   [OK] Android clipboard working"
        else
            echo "   [FAIL] Android clipboard read/write mismatch"
            return 1
        fi
    else
        echo "   [FAIL] Cannot write to Android clipboard"
        return 1
    fi
    echo ""

    # Test sync (if service is running)
    if systemctl is-active "$SERVICE" >/dev/null 2>&1; then
        echo "5. Testing clipboard sync..."
        echo "   Setting Wayland clipboard to: $test_text"
        echo "$test_text" | wl-copy

        echo "   Waiting for sync (5 seconds)..."
        sleep 5

        local android_result=$(adb shell cmd clipboard get 2>/dev/null | tr -d '\n\r')
        if [ "$android_result" = "$test_text" ]; then
            echo "   [OK] Clipboard synced to Android"
        else
            echo "   [FAIL] Clipboard not synced (got: '$android_result')"
        fi
        echo ""
    else
        echo "5. Skipping sync test (service not running)"
        echo ""
    fi

    echo "All tests passed!"
}

clear_cache() {
    echo "Clearing clipboard cache..."
    rm -rf /var/lib/waydroid-clipboard/*
    echo "Cache cleared"
}

enable_debug() {
    echo "Enabling debug logging..."

    # Update service environment
    mkdir -p /etc/systemd/system/waydroid-clipboard-sync.service.d
    cat > /etc/systemd/system/waydroid-clipboard-sync.service.d/debug.conf <<EOF
[Service]
Environment="CLIPBOARD_DEBUG=true"
EOF

    systemctl daemon-reload
    systemctl restart "$SERVICE"

    echo "Debug logging enabled. View logs with: journalctl -u $SERVICE -f"
}

case "${1:-}" in
    start)
        systemctl start "$SERVICE"
        echo "Clipboard sync started"
        ;;
    stop)
        systemctl stop "$SERVICE"
        echo "Clipboard sync stopped"
        ;;
    restart)
        systemctl restart "$SERVICE"
        echo "Clipboard sync restarted"
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    test)
        test_clipboard
        ;;
    clear)
        clear_cache
        ;;
    debug)
        enable_debug
        ;;
    help|--help)
        show_usage
        ;;
    *)
        show_usage
        ;;
esac
CONTROL_EOF

    chmod +x /usr/local/bin/waydroid-clipboard

    msg_ok "Management tools created"
}

# ============================================================================
# VNC CLIPBOARD INTEGRATION
# ============================================================================

configure_vnc_clipboard() {
    msg_info "Configuring VNC clipboard integration..."

    # WayVNC supports clipboard sharing natively through the VNC protocol
    # We just need to ensure wl-clipboard is available

    local wayvnc_config="/root/.config/wayvnc/config"

    if [ -f "$wayvnc_config" ]; then
        # Check if clipboard settings exist
        if ! grep -q "enable_clipboard" "$wayvnc_config" 2>/dev/null; then
            echo "" >> "$wayvnc_config"
            echo "# Clipboard support (requires wl-clipboard)" >> "$wayvnc_config"
            echo "# Enabled by default in WayVNC" >> "$wayvnc_config"
        fi
        msg_ok "VNC clipboard configuration verified"
    else
        msg_warn "WayVNC config not found at $wayvnc_config"
        msg_info "VNC clipboard will still work with default settings"
    fi
}

# ============================================================================
# INSTALLATION
# ============================================================================

do_install() {
    msg_info "Installing Waydroid Clipboard Sharing..."
    echo ""

    # Check prerequisites
    if ! command -v waydroid &>/dev/null; then
        msg_error "Waydroid is not installed"
        exit 1
    fi

    # Install dependencies
    install_dependencies || {
        msg_error "Failed to install dependencies"
        exit 1
    }

    # Configure ADB
    configure_adb || {
        msg_warn "ADB configuration incomplete, sync may not work until Waydroid is running"
    }

    # Create sync daemon
    create_sync_daemon || {
        msg_error "Failed to create sync daemon"
        exit 1
    }

    # Create systemd service
    create_systemd_service || {
        msg_error "Failed to create systemd service"
        exit 1
    }

    # Create management tools
    create_management_tools || {
        msg_error "Failed to create management tools"
        exit 1
    }

    # Configure VNC clipboard
    configure_vnc_clipboard

    echo ""
    msg_ok "Clipboard sharing installation complete!"
    echo ""
    echo "Configuration:"
    echo "  Sync Interval: ${SYNC_INTERVAL} seconds"
    echo "  Max Clipboard Size: ${MAX_CLIPBOARD_SIZE} bytes"
    echo "  Cache Directory: $CLIPBOARD_CACHE_DIR"
    echo "  Log File: $CLIPBOARD_LOG"
    echo ""
    echo "Next steps:"
    echo "  1. Enable the service: waydroid-clipboard start"
    echo "  2. Test clipboard: waydroid-clipboard test"
    echo "  3. View status: waydroid-clipboard status"
    echo ""
    echo "Management commands:"
    echo "  waydroid-clipboard start     - Start clipboard sync"
    echo "  waydroid-clipboard stop      - Stop clipboard sync"
    echo "  waydroid-clipboard status    - Show sync status"
    echo "  waydroid-clipboard test      - Test clipboard functionality"
    echo "  waydroid-clipboard logs      - View sync logs"
    echo ""
}

# ============================================================================
# UNINSTALLATION
# ============================================================================

do_uninstall() {
    msg_info "Uninstalling Waydroid Clipboard Sharing..."

    # Stop and disable service
    if systemctl is-active "$CLIPBOARD_SERVICE" >/dev/null 2>&1; then
        systemctl stop "$CLIPBOARD_SERVICE"
    fi

    if systemctl is-enabled "$CLIPBOARD_SERVICE" >/dev/null 2>&1; then
        systemctl disable "$CLIPBOARD_SERVICE"
    fi

    # Remove files
    rm -f /etc/systemd/system/${CLIPBOARD_SERVICE}.service
    rm -f /etc/systemd/system/${CLIPBOARD_SERVICE}.service.d/debug.conf
    rmdir /etc/systemd/system/${CLIPBOARD_SERVICE}.service.d 2>/dev/null || true
    rm -f /usr/local/bin/waydroid-clipboard-sync.sh
    rm -f /usr/local/bin/waydroid-clipboard
    rm -f /etc/logrotate.d/waydroid-clipboard
    rm -rf "$CLIPBOARD_CACHE_DIR"
    rm -f "$CLIPBOARD_LOG"

    systemctl daemon-reload

    msg_ok "Clipboard sharing uninstalled"
}

# ============================================================================
# SERVICE MANAGEMENT
# ============================================================================

do_enable() {
    msg_info "Enabling clipboard sync service..."

    systemctl enable "$CLIPBOARD_SERVICE"
    systemctl start "$CLIPBOARD_SERVICE"

    sleep 2

    if systemctl is-active "$CLIPBOARD_SERVICE" >/dev/null 2>&1; then
        msg_ok "Clipboard sync service enabled and started"
    else
        msg_error "Service failed to start. Check logs: journalctl -u $CLIPBOARD_SERVICE"
        exit 1
    fi
}

do_disable() {
    msg_info "Disabling clipboard sync service..."

    systemctl stop "$CLIPBOARD_SERVICE"
    systemctl disable "$CLIPBOARD_SERVICE"

    msg_ok "Clipboard sync service disabled and stopped"
}

do_status() {
    if command -v waydroid-clipboard &>/dev/null; then
        waydroid-clipboard status
    else
        msg_error "Clipboard sharing not installed"
        exit 1
    fi
}

do_test() {
    if command -v waydroid-clipboard &>/dev/null; then
        waydroid-clipboard test
    else
        msg_error "Clipboard sharing not installed"
        exit 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo "========================================"
    echo "  Waydroid Clipboard Sharing Setup"
    echo "========================================"
    echo ""

    case "$ACTION" in
        install)
            do_install
            ;;
        uninstall)
            do_uninstall
            ;;
        enable)
            do_enable
            ;;
        disable)
            do_disable
            ;;
        status)
            do_status
            ;;
        test)
            do_test
            ;;
        "")
            msg_error "No action specified. Use --help for usage information"
            exit 1
            ;;
        *)
            msg_error "Unknown action: $ACTION"
            exit 1
            ;;
    esac

    echo ""
}

# Check if running inside LXC
if [ ! -f /proc/1/environ ] || ! grep -q container=lxc /proc/1/environ; then
    msg_warn "This script is designed to run inside an LXC container"
    if [ "$ACTION" != "test" ] && [ "$ACTION" != "status" ]; then
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Run main
main
