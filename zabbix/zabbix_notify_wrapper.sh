#!/bin/bash

# -------------------------------------------------
# Generic Script Notification Wrapper
# - Executes any script
# - Logs output
# - Sends Discord webhook with embeds
# - Auto-splits long output
# - Color-coded by exit status
#
# Dependencies:
#   sudo apt install -y jq curl
# -------------------------------------------------

TARGET_SCRIPT="$1"
shift
TARGET_ARGS="$@"

# ---------------------------
# Configuration
# ---------------------------

WEBHOOK_URL=""  # Discord webhook URL
LOG_DIR="/var/log"

NOTIFIER_NAME="Zabbix Job Notifier"
NOTIFIER_AVATAR="https://raw.githubusercontent.com/angelolmg/operation-scripts/refs/heads/main/zabbix/zabbix_logo.jpg"

MAX_EMBED_LENGTH=4000

# ---------------------------
# Derived variables
# ---------------------------

SCRIPT_NAME=$(basename "$TARGET_SCRIPT" .sh)
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"

HOSTNAME=$(hostname)
HOST_IP=$(hostname -I | awk '{print $1}')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_OUT"' EXIT

# ---------------------------
# Execute script
# ---------------------------

"$TARGET_SCRIPT" $TARGET_ARGS 2>&1 | tee -a "$LOG_FILE" > "$TMP_OUT"
EXIT_CODE=${PIPESTATUS[0]}
OUTPUT=$(cat "$TMP_OUT")

# ---------------------------
# Status & color
# ---------------------------

if [ "$EXIT_CODE" -eq 0 ]; then
    STATUS="SUCCESS"
    COLOR=3066993      # green
else
    STATUS="FAILURE"
    COLOR=15158332     # red
fi

# ---------------------------
# Send Discord embed
# ---------------------------

send_embed() {
    local chunk="$1"

    PAYLOAD=$(jq -n \
        --arg username "$NOTIFIER_NAME" \
        --arg avatar "$NOTIFIER_AVATAR" \
        --arg script "$SCRIPT_NAME" \
        --arg status "$STATUS" \
        --arg content "$chunk" \
        --arg host "$HOSTNAME" \
        --arg ip "$HOST_IP" \
        --arg ts "$TIMESTAMP" \
        --argjson color "$COLOR" \
    '{
      username: $username,
      avatar_url: $avatar,
      content: "\($script) — \($status)",
      embeds: [
        {
          description: $content,
          color: $color,
          fields: [
            {name: "Host", value: $host, inline: true},
            {name: "IP", value: $ip, inline: true},
            {name: "Timestamp", value: $ts, inline: true},
            {name: "Status", value: $status, inline: true}
          ]
        }
      ]
    }')

    curl -s -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK_URL" >/dev/null
}

# ---------------------------
# Chunk output and send
# ---------------------------

start=0
length=${#OUTPUT}

while [ $start -lt $length ]; do
    chunk="${OUTPUT:$start:$MAX_EMBED_LENGTH}"
    send_embed "$chunk"
    start=$((start + MAX_EMBED_LENGTH))
done

exit "$EXIT_CODE"
