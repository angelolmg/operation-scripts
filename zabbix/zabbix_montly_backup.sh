#!/bin/bash

# === Configuration ===

# --- Retention Policy ---
RETENTION_COUNT=2

# --- Database Credentials ---
DB_NAME=""
DB_USER=""
DB_PASS=""

# --- Backup Directory ---
BACKUP_DIR="/path/to/zabbix-backups"

# --- Zabbix Configuration Paths (Debian 12) ---
CONFIG_FILES_TO_BACKUP=(
    "/usr/lib/zabbix"
    "/etc/apache2"
    "/usr/share/zabbix"
    "/etc/zabbix"
)

# --- Safety & Sanity Check Configuration ---
DRY_RUN=true   # Set to "false" only when executing
LOG_FILE="/var/log/zabbix_backup.log"


# --- Check for --execute flag ---
if [ "$1" == "--execute" ]; then
    DRY_RUN=false
fi


# === Fail-safe Checks ===
if [[ "$RETENTION_COUNT" -lt 1 ]]; then
    echo "ERROR: RETENTION_COUNT must be at least 1. Current value: $RETENTION_COUNT"
    exit 1
fi

# === Functions ===

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# === Script Logic ===

set -eo pipefail

DATE_FORMAT=$(date +%F)
BACKUP_FILENAME="zabbix-backup-${DATE_FORMAT}.tar.gz"
FINAL_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log_message "--- Starting Zabbix Full Backup ---"

# Info about mode
if $DRY_RUN; then
    log_message "INFO: Running in DRY-RUN mode. No changes will be made."
else
    log_message "WARNING: Running in EXECUTE mode. Backups will be created and old ones deleted."
fi

# 1. Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# 2. Backup the MySQL Database
DB_BACKUP_FILE="${TMP_DIR}/database.sql.gz"
if $DRY_RUN; then
    log_message "[DRY RUN] Would backup MySQL database '${DB_NAME}' to ${DB_BACKUP_FILE}"
else
    log_message "Backing up MySQL database..."
    mysqldump --single-transaction --quick --max_allowed_packet=512M --compress -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" | gzip > "${DB_BACKUP_FILE}"
    log_message "Database backup successful."
fi

# 3. Create final archive
if $DRY_RUN; then
    log_message "[DRY RUN] Would create archive at ${FINAL_BACKUP_PATH} with database + configs"
else
    log_message "Creating final archive: ${FINAL_BACKUP_PATH}"
    tar --warning=no-file-changed --ignore-failed-read -czf "${FINAL_BACKUP_PATH}" \
        -C "${TMP_DIR}" "database.sql.gz" \
        "${CONFIG_FILES_TO_BACKUP[@]}"
    log_message "Archive created successfully."
fi

# 4. Enforce retention policy
log_message "Enforcing retention policy: keeping the latest ${RETENTION_COUNT} backups."

# Command to identify files *beyond* the retention count
# It lists all backups, sorts by time (newest first), then skips the first ${RETENTION_COUNT} files,
# leaving only the old ones that are candidates for deletion.
FILES_TO_DELETE=$(ls -1t "${BACKUP_DIR}"/zabbix-backup-*.tar.gz 2>/dev/null | tail -n +$((RETENTION_COUNT + 1)))

if $DRY_RUN; then
    log_message "[DRY RUN] Would delete old backups beyond ${RETENTION_COUNT} months in ${BACKUP_DIR}"

    if [ -z "$FILES_TO_DELETE" ]; then
        log_message "[DRY RUN] NO files found to delete."
    else
        log_message "[DRY RUN] The following OLD files would be deleted:"
        # Print the list of files to delete, one per line
        echo "$FILES_TO_DELETE" | while read -r file; do
            log_message "  -> Would delete: ${file}"
        done
    fi

else
    # EXECUTE mode: The actual deletion command remains the same
    if [ -z "$FILES_TO_DELETE" ]; then
        log_message "NO files found to delete."
    else
        log_message "Deleting old backups..."
        # Use xargs to pass the files to rm, ensuring it handles spaces correctly
        echo "$FILES_TO_DELETE" | xargs -r rm
    fi
    log_message "Cleanup complete."
fi

exit 0
