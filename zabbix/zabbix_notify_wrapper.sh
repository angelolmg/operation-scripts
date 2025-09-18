#!/bin/bash

# ---------------------------
# Zabbix Script Notification Wrapper
# With Discord Embed, Auto-Split, and Color Coding
#
# sudo apt update
# sudo apt install jq
# sudo apt install curl
# ---------------------------

SCRIPT_PATH="$1"
shift
SCRIPT_ARGS="$@"

LOG_DIR="/var/log"
SCRIPT_NAME=$(basename "$SCRIPT_PATH" .sh)
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_raw.log"

WEBHOOK_URL=""

TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_OUT"' EXIT

# Server info
SERVER_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Run the target script and capture output and exit code
"$SCRIPT_PATH" $SCRIPT_ARGS 2>&1 | tee -a "$LOG_FILE" > "$TMP_OUT"
EXIT_CODE=${PIPESTATUS[0]}
OUTPUT=$(cat "$TMP_OUT")

# Determine embed color based on success/failure
if [ $EXIT_CODE -eq 0 ]; then
    COLOR=3066993  # green
    STATUS="SUCCESS"
else
    COLOR=15158332 # red
    STATUS="FAILURE"
fi

# Discord embed constraints
MAX_LENGTH=4000  # leave buffer below 4096 chars

# Function to send one embed chunk
send_embed() {
    local chunk="$1"
    PAYLOAD=$(jq -n \
        --arg username "Zabbix Job Notifier" \
        --arg avatar "https://raw.githubusercontent.com/angelolmg/operation-scripts/refs/heads/main/zabbix/zabbix_logo.png" \
        --arg script "$SCRIPT_NAME" \
        --arg content "$chunk" \
        --arg ip "$SERVER_IP" \
        --arg ts "$TIMESTAMP" \
        --arg status "$STATUS" \
        --argjson color "$COLOR" \
    '{
      username: $username,
      avatar_url: $avatar,
      content: "\($script): \($status)",
      embeds: [
        {
          title: "",
          description: $content,
          color: $color,
          fields: [
            {name: "Server IP", value: $ip, inline: true},
            {name: "Timestamp", value: $ts, inline: true},
            {name: "Status", value: $status, inline: true}
          ]
        }
      ]
    }')
    curl -s -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL"
}

# Split output into chunks
start=0
len=${#OUTPUT}
while [ $start -lt $len ]; do
    chunk="${OUTPUT:$start:$MAX_LENGTH}"
    send_embed "$chunk"
    start=$((start + MAX_LENGTH))
done
