#!/bin/bash

# --- Configuration ---
DB_NAME=""
DB_USER=""
DB_PASS=""
RETENTION_MONTHS=6
FUTURE_MONTHS_BUFFER=3

# List of all tables to manage
TABLES=(
    "history" "history_uint" "history_str" "history_text" "history_log" "history_bin"
    "trends" "trends_uint"
)

# --- Safety & Sanity Check Configuration ---
# Set to "true" to run in dry-run mode (default). Set to "false" only when executing.
DRY_RUN=true
# Location for logs and state files
LOG_FILE="/var/log/zabbix_partition_maintenance.log"
STATE_FILE="/var/lib/zabbix-partition-script/last_run.timestamp"
# Maximum allowed time difference in seconds with NTP server (e.g., 3600 = 1 hour)
MAX_TIME_SKEW_SECONDS=3600
# Maximum number of partitions to drop in a single run per table.
MAX_DELETES_PER_RUN=3
# --- End Configuration ---

# --- Check for --execute flag ---
if [ "$1" == "--execute" ]; then
    DRY_RUN=false
fi

# --- Functions ---
# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# Function to execute SQL
execute_sql() {
    # In dry-run mode, we don't execute DROP or REORGANIZE statements
    if $DRY_RUN && [[ "$1" =~ ^(ALTER) ]]; then
        log_message "[DRY RUN] Would execute: $1"
        return
    fi
    # The -N -s flags are for silent output, useful for queries returning single values
    mysql -u"$DB_USER" -p"$DB_PASS" -D"$DB_NAME" -N -s -e "$1"
}

# --- Initial Setup ---
log_message "--- Starting Zabbix Partition Maintenance ---"
if $DRY_RUN; then
    log_message "INFO: Running in DRY-RUN mode. No changes will be made. Use --execute to apply changes."
else
    log_message "WARNING: Running in EXECUTE mode. Changes will be applied to the database."
fi

# Ensure state file directory exists
mkdir -p "$(dirname "$STATE_FILE")"

# --- SANITY CHECKS ---
CURRENT_TIMESTAMP=$(date +%s)

# 1. State File Check (Time Travel Prevention)
if [ -f "$STATE_FILE" ]; then
    LAST_RUN_TIMESTAMP=$(cat "$STATE_FILE")
    if [ "$CURRENT_TIMESTAMP" -lt "$LAST_RUN_TIMESTAMP" ]; then
        log_message "CRITICAL ABORT: System time ($CURRENT_TIMESTAMP) is EARLIER than the last successful run ($LAST_RUN_TIMESTAMP). Clock may have been set back."
        exit 1
    fi
fi

# 2. External NTP Time Check (requires 'ntpdate' package: sudo apt install ntpdate)
NTP_TIMESTAMP_OUTPUT=$(ntpdate pool.ntp.org 2>&1 | head -1 | awk '{print $2}')
NTP_TIMESTAMP=$(date -d "$NTP_TIMESTAMP_OUTPUT" +%s 2>/dev/null)

if [ -z "$NTP_TIMESTAMP" ]; then
    log_message "WARNING: Could not get a valid timestamp from NTP server. Skipping this check."
else
    TIME_DIFFERENCE=$(( CURRENT_TIMESTAMP - NTP_TIMESTAMP ))
    TIME_DIFFERENCE=${TIME_DIFFERENCE#-} # Absolute value
    log_message "INFO: System time skew is $TIME_DIFFERENCE seconds."
    if [ "$TIME_DIFFERENCE" -gt "$MAX_TIME_SKEW_SECONDS" ]; then
        log_message "CRITICAL ABORT: System time skew is greater than the allowed $MAX_TIME_SKEW_SECONDS seconds. Aborting."
        exit 1
    fi
fi

log_message "INFO: All sanity checks passed."

# --- 1. Add future partitions ---
log_message "Checking for future partitions to add..."
for i in $(seq 1 $FUTURE_MONTHS_BUFFER); do
    TARGET_DATE=$(date -d "+$i month" +"%Y-%m-01")
    PARTITION_NAME="p$(date -d "$TARGET_DATE" +"%Y%m")"
    PARTITION_BOUNDARY_DATE=$(date -d "$TARGET_DATE + 1 month" +"%Y-%m-01")
    PARTITION_BOUNDARY_TS=$(date -d "$PARTITION_BOUNDARY_DATE" +%s)

    for table in "${TABLES[@]}"; do
        # Check if partition already exists
        EXISTS=$(execute_sql "SELECT COUNT(*) FROM information_schema.partitions WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_NAME = '$table' AND PARTITION_NAME = '$PARTITION_NAME';")
        
        if [ "$EXISTS" -eq 0 ]; then
            log_message "Adding partition $PARTITION_NAME to table $table..."
            SQL="ALTER TABLE $table REORGANIZE PARTITION p_max INTO (PARTITION $PARTITION_NAME VALUES LESS THAN ($PARTITION_BOUNDARY_TS), PARTITION p_max VALUES LESS THAN (MAXVALUE));"
            execute_sql "$SQL"
        fi
    done
done

# --- 2. Drop old partitions ---
log_message "Checking for old partitions to drop..."
RETENTION_DATE=$(date -d "-$RETENTION_MONTHS month" +"%Y-%m-01")
RETENTION_TS=$(date -d "$RETENTION_DATE" +%s)
log_message "INFO: Retention policy is to drop partitions older than $RETENTION_DATE (Timestamp: $RETENTION_TS)."

for table in "${TABLES[@]}"; do
    # Find partitions to drop
    PARTITIONS_TO_DROP=$(execute_sql "SELECT PARTITION_NAME FROM information_schema.partitions WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_NAME = '$table' AND PARTITION_DESCRIPTION < '$RETENTION_TS' AND PARTITION_NAME REGEXP '^p[0-9]{6}$';")
    
    # 3. Velocity Check
    NUM_TO_DELETE=$(echo "$PARTITIONS_TO_DROP" | grep -c .)
    if [ "$NUM_TO_DELETE" -gt "$MAX_DELETES_PER_RUN" ]; then
        log_message "CRITICAL ABORT: Script wants to delete $NUM_TO_DELETE partitions from table '$table', which exceeds the limit of $MAX_DELETES_PER_RUN."
        log_message "Partitions identified for deletion: $PARTITIONS_TO_DROP"
        exit 1
    fi

    if [ -n "$PARTITIONS_TO_DROP" ]; then
        for p in $PARTITIONS_TO_DROP; do
            log_message "Dropping partition $p from table $table..."
            SQL="ALTER TABLE $table DROP PARTITION $p;"
            execute_sql "$SQL"
        done
    else
        log_message "INFO: No partitions to drop for table $table."
    fi
done

# --- Finalization ---
# Update state file only on a successful execute run
if ! $DRY_RUN; then
    log_message "INFO: Updating state file with current timestamp."
    echo "$CURRENT_TIMESTAMP" > "$STATE_FILE"
fi

log_message "--- Partition Maintenance Finished ---"
