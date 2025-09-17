# Zabbix Partition Maintenance Script

Follow these steps to set up and schedule the `zabbix_partition_maintenance.sh` script.
This script helps **manage Zabbix database partitions** by:

* Automatically **adding future partitions** to history and trends tables.
* **Dropping old partitions** according to a retention policy.
* Performing **safety checks** to prevent accidental data loss:

  * Prevents “time travel” issues using a state file.
  * Checks system clock against NTP to avoid large skew.
  * Limits the number of partitions dropped per run.
* Supports **dry-run mode** to simulate changes before execution.
* Logs all actions to `/var/log/zabbix_partition_maintenance.log`.

---

## Setup Steps

### **1. Install dependencies**

```bash
sudo apt update
sudo apt install ntpdate
```

---

### **2. Update configuration variables**

Edit the script to set your database and retention settings:

```bash
DB_NAME=""
DB_USER=""
DB_PASS=""
RETENTION_MONTHS=
FUTURE_MONTHS_BUFFER=
```

---

### **3. Make the script executable**

```bash
chmod +x /path/to/script/zabbix_partition_maintenance.sh
```

---

### **4. Dry run the script**

Test manually to ensure everything works:

```bash
sudo /path/to/script/zabbix_partition_maintenance.sh
```

> By default, the script runs in **dry-run mode**, meaning no changes are applied.

---

### **5. Check logs**

Monitor the log file to review actions:

```bash
tail -f /var/log/zabbix_partition_maintenance.log
```

---

### **6. Schedule the cron job**

Edit root’s crontab:

```bash
sudo crontab -e
```

Add this line to run the script **every first Monday of the month at 03:00 AM**, capturing all output and errors:

```bash
0 3 1-7 * 1 /path/to/script/zabbix_partition_maintenance.sh >> /var/log/zabbix_partition_maintenance_raw.log 2>&1
```

---

### **7. Maintain logs**

* Check logs periodically.
* Safe to delete if they grow too large; the script will recreate them.

---

✅ **Setup complete!**
The script is now executable, logged, and scheduled to run automatically, managing Zabbix partitions safely.