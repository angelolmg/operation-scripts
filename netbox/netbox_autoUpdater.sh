#!/bin/bash
# netbox-check-update.sh
# Dry-run by default. Use --execute to apply changes.

set -eo pipefail

# ---------------------------
# Mode control
# ---------------------------

DRY_RUN=true
if [[ "${1:-}" == "--execute" ]]; then
    DRY_RUN=false
fi

# ---------------------------
# Configuration
# ---------------------------

NETBOX_SYMLINK="/opt/netbox"
GITHUB_API="https://api.github.com/repos/netbox-community/netbox/releases/latest"

LOG_DIR="/var/log/NetboxUpdateLog"
LOG_FILE="${LOG_DIR}/netbox_update.log"
mkdir -p "$LOG_DIR"

# ---------------------------
# Logging
# ---------------------------

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# ---------------------------
# Mode info
# ---------------------------

if $DRY_RUN; then
    log_message "INFO: Running in DRY-RUN mode. No changes will be applied."
else
    log_message "WARNING: Running in EXECUTE mode. Changes WILL be applied."
fi

# ---------------------------
# Sanity checks
# ---------------------------

if [[ ! -L "$NETBOX_SYMLINK" ]]; then
    log_message "ERROR: $NETBOX_SYMLINK is not a symbolic link."
    exit 1
fi

# ---------------------------
# Detect versions
# ---------------------------

REAL_PATH=$(readlink -f "$NETBOX_SYMLINK")
CURRENT_VERSION=$(basename "$REAL_PATH" | sed 's/^netbox-//')

LATEST_VERSION=$(curl -fsSL "$GITHUB_API" \
    | grep '"tag_name":' \
    | head -n 1 \
    | cut -d '"' -f4 \
    | sed 's/^v//')

log_message "Installed version: $CURRENT_VERSION"
log_message "Latest available version: $LATEST_VERSION"

# ---------------------------
# Compare versions
# ---------------------------

if [[ "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    log_message "NetBox is already up to date."
    exit 0
fi

log_message "New NetBox version detected."

FROM="$CURRENT_VERSION"
TO="$LATEST_VERSION"
BACKUP_DIR="/opt/netbox-backups/$(date +%F_%H-%M-%S)_to_${TO}"

# ---------------------------
# Backup
# ---------------------------

if $DRY_RUN; then
    log_message "[DRY RUN] Would create backup directory: $BACKUP_DIR"
    log_message "[DRY RUN] Would dump PostgreSQL database"
    log_message "[DRY RUN] Would backup media, scripts, reports"
else
    log_message "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    log_message "Backing up PostgreSQL database..."
    pg_dump -U netbox -h localhost -Fc netbox > "$BACKUP_DIR/netbox_${FROM}.dump"

    cp -pr "$NETBOX_SYMLINK/netbox/media"   "$BACKUP_DIR/"
    cp -pr "$NETBOX_SYMLINK/netbox/scripts" "$BACKUP_DIR/"
    cp -pr "$NETBOX_SYMLINK/netbox/reports" "$BACKUP_DIR/"
    cp -pr "$NETBOX_SYMLINK/netbox/static/netbox_topology_views" "$BACKUP_DIR/"

    log_message "Backup completed successfully."
fi

# ---------------------------
# Download & extract
# ---------------------------

ARCHIVE="/tmp/netbox-${TO}.tar.gz"
TARGET_DIR="/opt/netbox-${TO}"

if $DRY_RUN; then
    log_message "[DRY RUN] Would download NetBox v$TO"
    log_message "[DRY RUN] Would extract to $TARGET_DIR"
    log_message "[DRY RUN] Would update symlink $NETBOX_SYMLINK → $TARGET_DIR"
else
    log_message "Downloading NetBox v$TO..."
    wget -q "https://github.com/netbox-community/netbox/archive/v${TO}.tar.gz" -O "$ARCHIVE"

    tar -xzf "$ARCHIVE" -C /opt
    ln -sfn "$TARGET_DIR" "$NETBOX_SYMLINK"
fi

# ---------------------------
# Migrate configuration
# ---------------------------

if $DRY_RUN; then
    log_message "[DRY RUN] Would migrate configuration and custom files"
else
    log_message "Migrating configuration and custom files..."

    cp "/opt/netbox-${FROM}/local_requirements.txt" "$NETBOX_SYMLINK/"
    cp "/opt/netbox-${FROM}/netbox/netbox/configuration.py" "$NETBOX_SYMLINK/netbox/netbox/"
    cp "/opt/netbox-${FROM}/netbox/netbox/ldap_config.py" "$NETBOX_SYMLINK/netbox/netbox/"
    cp "/opt/netbox-${FROM}/gunicorn.py" "$NETBOX_SYMLINK/"

    cp -r "/opt/netbox-${FROM}/netbox/scripts" "$NETBOX_SYMLINK/netbox/"
    cp -r "/opt/netbox-${FROM}/netbox/reports" "$NETBOX_SYMLINK/netbox/"
    cp -r "/opt/netbox-${FROM}/local" "$NETBOX_SYMLINK/"
    cp -pr "/opt/netbox-${FROM}/netbox/media" "$NETBOX_SYMLINK/netbox/"

    rm -rf "$NETBOX_SYMLINK/netbox/static/netbox_topology_views/"
    cp -r "/opt/netbox-${FROM}/netbox/static/netbox_topology_views/" \
          "$NETBOX_SYMLINK/netbox/static/"

    chown -R netbox:netbox /opt/netbox*

    log_message "Configuration migrated successfully."
fi

# ---------------------------
# Upgrade & restart
# ---------------------------

if $DRY_RUN; then
    log_message "[DRY RUN] Would run upgrade.sh"
    log_message "[DRY RUN] Would restart NetBox services"
else
    log_message "Running NetBox upgrade.sh..."
    cd "$NETBOX_SYMLINK"
    sudo PYTHON=/usr/bin/python3.12 ./upgrade.sh

    log_message "Restarting NetBox services..."
    systemctl restart netbox netbox-rq

    chown -R netbox:netbox /opt/netbox*
    log_message "Upgrade completed successfully."
fi

exit 0

