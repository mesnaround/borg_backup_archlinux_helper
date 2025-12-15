#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

MOUNT_UNIT="mnt-bpshare-bpshare0-backup.mount"
AUTOMOUNT_UNIT="mnt-bpshare-bpshare0-backup.automount"
MOUNT_POINT="/mnt/bpshare/bpshare0/backup"

log_info "Setting up systemd mount units for Borg backup share..."

# Create mount point
log_info "Creating mount point: $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

# Copy mount units
log_info "Installing systemd mount units..."
cp "$MOUNT_UNIT" /etc/systemd/system/
cp "$AUTOMOUNT_UNIT" /etc/systemd/system/

# Reload systemd
log_info "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start automount (this will trigger mount on access)
log_info "Enabling automount unit..."
systemctl enable "$AUTOMOUNT_UNIT"
systemctl start "$AUTOMOUNT_UNIT"

log_info "Setup complete!"
echo ""
echo "Mount configuration:"
echo "  - Mount point: $MOUNT_POINT"
echo "  - Automount will trigger on first access"
echo "  - Idle timeout: 300 seconds (5 minutes)"
echo ""
echo "Useful commands:"
echo "  - Check status:  systemctl status $AUTOMOUNT_UNIT"
echo "  - Manual mount:  systemctl start $MOUNT_UNIT"
echo "  - Test access:   ls $MOUNT_POINT"
echo "  - View logs:     journalctl -u $MOUNT_UNIT"
echo ""
