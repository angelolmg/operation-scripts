#!/bin/bash
#
# netbox_vm_health.sh
# Daily health-check script for NetBox VM
# Intended to be executed via netbox_notify_wrapper.sh

set -eo pipefail

# --- Config ---
SCRIPT_NAME="netbox_vm_health"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
NETBOX_DIR="/opt/netbox"

# --- Helper Functions ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# --- Collect Info ---

NOW=$(date +%s)

# Memory usage
MEMORY=$(LC_ALL=C free -h | awk '/Mem:/ {print $3 "/" $2 " used (" int($3*100/$2) "%)"}')

# Disk usage
DISK=$(df -h | awk '$1=="/dev/sda1" {print $3 "/" $2 " used (" $5 ")"}')

# CPU load
LOAD_AVG=$(LC_ALL=C uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
CPU_CORES=$(nproc)

# --- Services ---
check_service() {
    systemctl is-active --quiet "$1" && echo "✅ running" || echo "❌ down"
}

NETBOX_SERVICE=$(check_service netbox)
NETBOX_RQ=$(check_service netbox-rq)
POSTGRES=$(check_service postgresql)
REDIS=$(check_service redis-server)
NGINX=$(check_service nginx)

# --- NetBox Version ---
if [[ -L "$NETBOX_DIR" ]]; then
    REAL_PATH=$(readlink -f "$NETBOX_DIR")
    NETBOX_VERSION=$(basename "$REAL_PATH" | sed 's/^netbox-//')
else
    NETBOX_VERSION="unknown (missing symlink)"
fi

# --- Scheduled Maintenance ---
# NetBox auto-updater: every Wednesday at 04:00

NEXT_UPDATE=$(date -d "next wednesday 04:00" +%s)

# If today is Wednesday and before 04:00, use today
if [[ "$(date +%u)" -eq 3 && "$(date +%H)" -lt 4 ]]; then
    NEXT_UPDATE=$(date -d "today 04:00" +%s)
fi

DAYS_UPDATE=$(( (NEXT_UPDATE - NOW) / 86400 ))

# --- Final Report ---
cat <<EOF
**NetBox System Health Report**
- 📦 NetBox Version: $NETBOX_VERSION
- 💾 Memory: $MEMORY
- 📂 Disk (/dev/sda1): $DISK
- ⚙️ CPU Load: $LOAD_AVG (on $CPU_CORES cores)

**Service Status**
- NetBox: $NETBOX_SERVICE
- NetBox RQ: $NETBOX_RQ
- PostgreSQL: $POSTGRES
- Redis: $REDIS
- Nginx: $NGINX

**Scheduled Maintenance**
- Next NetBox Auto-Update (Wednesday 04:00): in $DAYS_UPDATE days
EOF

exit 0
