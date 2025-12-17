#!/bin/bash
#
# zabbix_vm_health.sh
# Daily health-check script for Debian VM
# Sends results through zabbix_notify_wrapper.sh

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
            echo $(( (ts - today) / 86400 ))
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
DISK=$(df -h / | awk 'NR==2 {print $1 " — " $3 "/" $2 " (" $5 ")"}')

# CPU load
LOAD_AVG=$(LC_ALL=C uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | xargs)
CPU_CORES=$(nproc)

# Services
check_service() {
    systemctl is-active --quiet "$1" && echo "✅ running" || echo "❌ down"
}

ZABBIX_SERVER=$(check_service zabbix-server)
ZABBIX_AGENT=$(check_service zabbix-agent)
APACHE=$(check_service apache2)
MARIADB=$(check_service mariadb)
GRAFANA=$(check_service grafana-server)

# --- Scheduled Jobs ---

# Next partition maintenance: Friday 23:00
NEXT_PART=$(date -d "next friday 23:00" +%s)

# If today is Friday and before 23:00, use today
if [[ "$(date +%u)" -eq 5 && "$(date +%H)" -lt 23 ]]; then
    NEXT_PART=$(date -d "today 23:00" +%s)
fi

# Next backup: Saturday 01:00
NEXT_BACKUP=$(date -d "next saturday 01:00" +%s)

# If today is Saturday and before 01:00, use today
if [[ "$(date +%u)" -eq 6 && "$(date +%H)" -lt 1 ]]; then
    NEXT_BACKUP=$(date -d "today 01:00" +%s)
fi

DAYS_PART=$(( (NEXT_PART - NOW) / 86400 ))
DAYS_BACKUP=$(( (NEXT_BACKUP - NOW) / 86400 ))

# Final report
cat <<EOF
**System Health Report**
- 💾 Memory: $MEMORY
- 📂 Disk (/dev/sda1): $DISK
- ⚙️ CPU Load: $LOAD_AVG (on $CPU_CORES cores)

**Service Status**
- Zabbix Server: $ZABBIX_SERVER
- Zabbix Agent: $ZABBIX_AGENT
- Apache2: $APACHE
- MariaDB: $MARIADB
- Grafana: $GRAFANA

**Scheduled Maintenance**
- Next Backup (Sat 03:00): in $DAYS_BACKUP days
- Next Partitioning (Mon 03:00): in $DAYS_PART days
EOF
