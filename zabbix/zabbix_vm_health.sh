#!/bin/bash
#
# zabbix_vm_health.sh#
# Daily health-check script for Debian VM
# Should sends results through zabbix_notify_wrapper.sh

# --- Config ---
SCRIPT_NAME="zabbix_vm_health"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"

# --- Helper Functions ---
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

# Days until next specific weekday of month (first Sat/Mon)
days_until_next() {
    local target_day=$1    # 6 = Saturday, 1 = Monday
    local today=$(date +%s)
    for i in {0..14}; do
        local check=$(date -d "+$i day" +%u)
        local dom=$(date -d "+$i day" +%d)
        if [[ "$check" -eq "$target_day" && "$dom" -le 7 ]]; then
            local ts=$(date -d "+$i day 03:00" +%s)
            echo $(( (ts - today) / 86400 )) # days remaining
            return
        fi
    done
    echo "?"
}

# --- Collect Info ---

NOW=$(date +%s)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Memory usage
MEMORY=$(LC_ALL=C free -h | awk '/Mem:/ {print $3 "/" $2 " used (" int($3*100/$2) "%)"}')

# Disk usage
DISK=$(df -h | awk '$1=="/dev/sda1" {print $3 "/" $2 " used (" $5 ")"}')

# CPU load
LOAD_AVG=$(LC_ALL=C uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
CPU_CORES=$(nproc)

# Services
check_service() {
    systemctl is-active --quiet "$1" && echo "âœ… running" || echo "âŒ down"
}
ZABBIX_SERVER=$(check_service zabbix-server)
ZABBIX_AGENT=$(check_service zabbix-agent)
APACHE=$(check_service apache2)
MARIADB=$(check_service mariadb)

# Next backup (first Saturday of next month at 03:00)
NEXT_BACKUP=$(date -d "$(date +'%Y-%m-01') +1 month" +'%Y-%m-01')
NEXT_BACKUP=$(date -d "$NEXT_BACKUP +$(( (6 - $(date -d "$NEXT_BACKUP" +%u) + 7) %7 )) days 03:00" +%s)

# Next partitioning (first Monday of next month at 03:00)
NEXT_PART=$(date -d "$(date +'%Y-%m-01') +1 month" +'%Y-%m-01')
NEXT_PART=$(date -d "$NEXT_PART +$(( (1 - $(date -d "$NEXT_PART" +%u) + 7) %7 )) days 03:00" +%s)

DAYS_BACKUP=$(( (NEXT_BACKUP - NOW) / 86400 ))
DAYS_PART=$(( (NEXT_PART - NOW) / 86400 ))

# Final report
cat <<EOF
**System Health Report**
- ðŸ’¾ Memory: $MEMORY
- ðŸ“‚ Disk (/dev/sda1): $DISK
- âš™ï¸ CPU Load: $LOAD_AVG (on $CPU_CORES cores)

**Service Status**
- Zabbix Server: $ZABBIX_SERVER
- Zabbix Agent: $ZABBIX_AGENT
- Apache2: $APACHE
- MariaDB: $MARIADB

**Scheduled Maintenance**
- Next Backup (first Sat 03:00): in $DAYS_BACKUP days
- Next Partitioning (first Mon 03:00): in $DAYS_PART days
EOF

