#!/usr/bin/env bash

set -euo pipefail

# Configuration
INSTALL_DIR="/opt/borg_backup"
BORG_CONF="/etc/borg-backup.conf"
MQTT_CONF="/etc/mqtt.yaml"
SYSTEMD_DIR="/etc/systemd/system"
PASSPHRASE_FILE="/etc/secrets/borg-passphrase"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Parse arguments
if [[ -z ${1:-} ]]; then
    log_error "Need to pass an argument to specify the config file."
    echo "Usage: $0 <path/to/borg-backup.conf> [path/to/mqtt.yaml]"
    echo ""
    echo "Examples from conf directory:"
    ls -1 conf/*.conf 2>/dev/null || true
    exit 1
fi

CONFIG_FILE="$1"
MQTT_CONFIG_ARG="${2:-}"

# Validate borg config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 2
fi

log_info "Installing Borg Backup with MQTT monitoring..."

# Install system dependencies
log_info "Installing system dependencies (borg, python, uv)..."
pacman -S --needed --noconfirm borg python uv

# Create install directory
log_info "Creating install directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Copy project files
log_info "Copying project files..."
cp -r borg_backup "$INSTALL_DIR/"
cp pyproject.toml "$INSTALL_DIR/"
cp uv.lock "$INSTALL_DIR/" 2>/dev/null || log_warn "No uv.lock found, will generate during sync"

# Make borg script executable
chmod +x "$INSTALL_DIR/borg_backup/borg_backup.sh"

# Create venv with uv and install dependencies
log_info "Setting up Python virtual environment..."
cd "$INSTALL_DIR"
uv venv
if [[ -f uv.lock ]]; then
    log_info "Installing dependencies from lock file..."
    uv sync --frozen
else
    log_info "Generating lock file and installing dependencies..."
    uv sync
fi
cd - > /dev/null

# Copy borg backup config
log_info "Installing borg backup config to $BORG_CONF"
cp "$CONFIG_FILE" "$BORG_CONF"
chmod 600 "$BORG_CONF"

# Handle MQTT config
if [[ -n "$MQTT_CONFIG_ARG" ]]; then
    if [[ -f "$MQTT_CONFIG_ARG" ]]; then
        log_info "Installing MQTT config from $MQTT_CONFIG_ARG"
        cp "$MQTT_CONFIG_ARG" "$MQTT_CONF"
        chmod 600 "$MQTT_CONF"
    else
        log_error "MQTT config file not found: $MQTT_CONFIG_ARG"
        exit 3
    fi
elif [[ ! -f "$MQTT_CONF" ]]; then
    log_warn "MQTT config not found at $MQTT_CONF"
    echo "Please create it using the template: mqtt.yaml.template"
    echo "Example:"
    echo "  cp mqtt.yaml.template $MQTT_CONF"
    echo "  vim $MQTT_CONF"
    echo ""
    read -p "Press Enter to continue (MQTT monitoring will be disabled until config is added)..."
else
    log_info "MQTT config already exists at $MQTT_CONF"
fi

# Copy systemd files
log_info "Installing systemd units..."
cp systemd/borg-backup.service "$SYSTEMD_DIR/"
cp systemd/borg-backup.timer "$SYSTEMD_DIR/"


# Reload systemd and enable timer
log_info "Reloading systemd daemon..."
systemctl daemon-reload

log_info "Enabling and starting borg-backup.timer..."
systemctl enable borg-backup.timer
systemctl start borg-backup.timer

# Handle passphrase
save_borg_passphrase() {
    if [[ -f "$PASSPHRASE_FILE" ]]; then
        log_info "Passphrase file already exists at $PASSPHRASE_FILE"
        read -p "Do you want to update it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    log_info "Setting up Borg repository passphrase..."
    echo "Enter Borg repository passphrase:"
    read -s passphrase
    echo

    echo "Confirm passphrase:"
    read -s passphrase_confirm
    echo

    if [[ "$passphrase" != "$passphrase_confirm" ]]; then
        log_error "Passphrases don't match!"
        return 1
    fi

    mkdir -p "$(dirname "$PASSPHRASE_FILE")"
    echo "$passphrase" > "$PASSPHRASE_FILE"
    chmod 600 "$PASSPHRASE_FILE"

    unset passphrase passphrase_confirm

    log_info "Passphrase saved to $PASSPHRASE_FILE"
    log_warn "CRITICAL: Back this passphrase up to a safe location!"
    log_warn "Without it, your encrypted backups are unrecoverable."
}

# Ask user if they want to save passphrase
echo ""
read -p "Do you want to set up the Borg repository passphrase now? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    save_borg_passphrase
else
    log_warn "Skipping passphrase setup. You can run this manually later."
fi

# Print summary
echo ""
log_info "============================================"
log_info "Installation complete!"
log_info "============================================"
echo ""
echo "Configuration files:"
echo "  - Borg config: $BORG_CONF"
echo "  - MQTT config: $MQTT_CONF"
echo "  - Passphrase:  $PASSPHRASE_FILE"
echo ""
echo "Systemd units:"
echo "  - Service: $SYSTEMD_DIR/borg-backup.service"
echo "  - Timer:   $SYSTEMD_DIR/borg-backup.timer"
echo ""
echo "Status:"
systemctl status borg-backup.timer --no-pager || true
echo ""
echo "Next steps:"
echo "  - Verify MQTT config: $MQTT_CONF"
echo "  - Check timer status: systemctl status borg-backup.timer"
echo "  - View logs:          journalctl -u borg-backup.service"
echo "  - Run backup now:     systemctl start borg-backup.service"
echo ""

