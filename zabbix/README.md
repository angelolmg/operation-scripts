# Index

This folder contains some automation scripts for Zabbix:

1. **[Zabbix Partition Maintenance Script](#zabbix-partition-maintenance-script)**
   Automates management of Zabbix database partitions: adds future partitions, drops old ones according to retention, includes safety checks, supports dry-run mode, and logs all actions.

2. **[Zabbix Full Backup Script](#zabbix-full-backup-script)**
   Performs full backups of Zabbix servers: dumps the MySQL database, archives configuration files, enforces a retention policy, supports dry-run mode, and logs all operations.

Specs:
- Zabbix 7.4.2
- Debian 12

# Zabbix Partition Maintenance Script

`zabbix_partition_maintenance.sh` automates **Zabbix database partition management**:

* Adds future partitions to history and trends tables automatically.
* Drops old partitions according to a retention policy.
* Includes safety checks to prevent data loss:

  * Uses a state file to prevent “time travel” errors.
  * Validates system clock against NTP to avoid large skew.
  * Limits the number of partitions dropped per run.
* Supports **dry-run mode** to simulate changes.
* Logs all actions to `/var/log/zabbix_partition_maintenance.log`.

---

## Setup

### 1. Install dependencies

```bash
sudo apt update
sudo apt install ntpdate
```

### 2. Configure the script

Set database credentials and retention parameters:

```bash
DB_NAME=""
DB_USER=""
DB_PASS=""
RETENTION_MONTHS=
FUTURE_MONTHS_BUFFER=
```

### 3. Make executable

```bash
chmod +x /path/to/zabbix_partition_maintenance.sh
```

### 4. Dry-run test

```bash
sudo /path/to/zabbix_partition_maintenance.sh
```

> Default is **dry-run mode**; no changes applied.

### 5. Monitor logs

```bash
tail -f /var/log/zabbix_partition_maintenance.log
```

### 6. Schedule cron (first Monday monthly at 03:00)

```bash
sudo crontab -e
```

Add:

```cron
0 3 1-7 * 1 /path/to/zabbix_partition_maintenance.sh --execute >> /var/log/zabbix_partition_maintenance_raw.log 2>&1
```

---

# Zabbix Full Backup Script

`zabbix_full_backup.sh` performs a **full backup of a Zabbix server**, including the database and configuration files:

* Dumps the MySQL database (`mysqldump`) with routines and triggers, compresses it to `database.sql.gz`.
* Archives key directories and files (`/etc/zabbix`, `/usr/lib/zabbix`, `/usr/share/zabbix`, `/etc/apache2`) into a single `.tar.gz`.
* Implements a **retention policy**: keeps the latest N backups and deletes older archives.
* Includes **safety checks**: validates retention count, supports **dry-run mode** for testing.
* Logs all operations to `/var/log/zabbix_backup.log`.

* IMPORTANT: Setup swapfile to at least half the system's total RAM, otherwise `mysqldump` could run out of memory and the backup procedure could fail.

## Setup

### 1. Configure the script

Set database credentials and retention parameters:

```bash
DB_NAME=""
DB_USER=""
DB_PASS=""
RETENTION_COUNT=
```

### 2. Make executable

```bash
chmod +x /path/to/zabbix_montly_backup.sh
```

### 3. Dry-run test

```bash
sudo /path/to/zabbix_montly_backup.sh
```

> Default is **dry-run mode**; no changes applied.

### 4. Monitor logs

```bash
tail -f /var/log/zabbix_montly_backup.log
```

### 5. Schedule cron (first Saturday of the month at 03:00)

```bash
sudo crontab -e
```

Add:

```cron
0 3 1-7 * 1 /path/to/zabbix_montly_backup.sh --execute >> /var/log/zabbix_montly_backup_raw.log 2>&1
```