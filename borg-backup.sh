#!/usr/bin/env bash
set -euo pipefail

# Load configuration
CONFIG_FILE="${1:-/etc/borg-backup.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file $CONFIG_FILE not found!" >&2
    exit 1
fi

source "$CONFIG_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Fallback default Config file $CONFIG_FILE not found!" >&2
    exit 2
fi

# Set up Borg passphrase
if [ -n "${PASSPHRASE_FILE:-}" ] && [ -f "$PASSPHRASE_FILE" ]; then
    export BORG_PASSPHRASE=$(cat "$PASSPHRASE_FILE")
elif [[ -z $ENCRYPTION ]]; then
    # No encryption
    BORG_PASSPHRASE=''
else
    # If no passphrase file, Borg will prompt (only works for interactive use)
    echo "Error: Right now you need to set up a file with the password and specify that in your conf file" >&2
    exit 3
fi

echo "Using $CONFIG_FILE for backup borg configuration"
echo "Sleeping 5 seconds before proceeding"
sleep 5
echo Ok starting

source "$CONFIG_FILE"

# Auto-detect hostname if not set
if [ -z "${HOSTNAME:-}" ]; then
    HOSTNAME=$(hostname)
fi

TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)
ARCHIVE_NAME="${HOSTNAME}_${TIMESTAMP}"

# Temporary directory for system info
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR; unset BORG_PASSPHRASE" EXIT

log() {
    echo "[$(date +%Y-%m-%d_%H:%M:%S)] $1" | tee -a "$LOG_FILE"
}

log "Starting backup for $HOSTNAME..."

# Run pre-backup hook if defined
if [ -n "${PRE_BACKUP_HOOK:-}" ]; then
    log "Running pre-backup hook..."
    eval "$PRE_BACKUP_HOOK" 2>&1 | tee -a "$LOG_FILE" || log "WARNING: Pre-backup hook failed"
fi

# Save system information
log "Gathering system information..."
pacman -Qe > "$TEMP_DIR/pacman-explicit.txt"
pacman -Qm > "$TEMP_DIR/pacman-foreign.txt"
pacman -Qn > "$TEMP_DIR/pacman-native.txt"
pacman -Q > "$TEMP_DIR/pacman-all.txt"

# AUR packages
if command -v yay &>/dev/null; then
    yay -Qm > "$TEMP_DIR/aur-packages.txt" 2>/dev/null || true
elif command -v paru &>/dev/null; then
    paru -Qm > "$TEMP_DIR/aur-packages.txt" 2>/dev/null || true
fi

# System information
lsblk -f > "$TEMP_DIR/partition-layout.txt" 2>/dev/null || true
mount > "$TEMP_DIR/mounts.txt"
ip addr > "$TEMP_DIR/network-config.txt"
systemctl list-unit-files --state=enabled > "$TEMP_DIR/enabled-services.txt"
uname -a > "$TEMP_DIR/kernel-info.txt"
hostnamectl > "$TEMP_DIR/hostnamectl.txt" 2>/dev/null || true

# Crontabs
crontab -l > "$TEMP_DIR/crontab-user.txt" 2>/dev/null || true
sudo crontab -l > "$TEMP_DIR/crontab-root.txt" 2>/dev/null || true

# Save config file itself for reference
cp "$CONFIG_FILE" "$TEMP_DIR/borg-backup.conf"

# Build exclude arguments
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    EXCLUDE_ARGS+=(--exclude "$pattern")
done

# Check if valid borg repository exists
if ! borg list "$REPO" &>/dev/null; then
    log "No valid borg repository found. Initializing..."
    
    if [ -d "$REPO" ] && [ "$(ls -A $REPO 2>/dev/null)" ]; then
        log "ERROR: $REPO exists and is not empty. Cannot initialize."
        log "Please use an empty directory or different path."
        exit 1
    fi

    log "Initializing new borg repository at $REPO with encryption: $ENCRYPTION"
    borg init --encryption="$ENCRYPTION" "$REPO"

    # Export key if using keyfile mode
    if [[ "$ENCRYPTION" == keyfile* ]]; then
        KEY_BACKUP="/root/.secrets/borg-key-${HOSTNAME}.txt"
        log "Exporting keyfile to $KEY_BACKUP"
        borg key export "$REPO" "$KEY_BACKUP"
        chmod 600 "$KEY_BACKUP"
        log "IMPORTANT: Backup $KEY_BACKUP to a safe location!"
    fi
fi

# Create backup
log "Creating backup archive: $ARCHIVE_NAME"
borg create \
    --stats \
    --progress \
    --compression "$COMPRESSION" \
    --exclude-caches \
    "${EXCLUDE_ARGS[@]}" \
    "$REPO::$ARCHIVE_NAME" \
    "${BACKUP_PATHS[@]}" \
    "${BACKUP_FILES[@]}" \
    "$TEMP_DIR" \
    2>&1 | tee -a "$LOG_FILE"

# Prune old backups
log "Pruning old backups..."
borg prune \
    --list \
    --stats \
    --prefix "${HOSTNAME}_" \
    --keep-daily="$KEEP_DAILY" \
    --keep-weekly="$KEEP_WEEKLY" \
    --keep-monthly="$KEEP_MONTHLY" \
    --keep-yearly="$KEEP_YEARLY" \
    "$REPO" \
    2>&1 | tee -a "$LOG_FILE"

# Compact repository
log "Compacting repository..."
borg compact "$REPO" 2>&1 | tee -a "$LOG_FILE"

# Verify last backup
log "Verifying backup integrity..."
borg check --last 1 "$REPO" 2>&1 | tee -a "$LOG_FILE"

# Run post-backup hook if defined
if [ -n "${POST_BACKUP_HOOK:-}" ]; then
    log "Running post-backup hook..."
    eval "$POST_BACKUP_HOOK" 2>&1 | tee -a "$LOG_FILE" || log "WARNING: Post-backup hook failed"
fi

log "Backup completed successfully for $HOSTNAME!"
