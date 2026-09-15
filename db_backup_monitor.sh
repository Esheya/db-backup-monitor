#!/bin/bash
#
# db_backup_monitor.sh
# Automated MySQL/MariaDB backup with rotation, plus basic service monitoring.
#
# Author: Kingsley Esheya
# Usage:
#   1. Fill in the CONFIG section below.
#   2. chmod +x db_backup_monitor.sh
#   3. Test manually:  ./db_backup_monitor.sh
#   4. Schedule with cron, e.g. run daily at 2 AM:
#        crontab -e
#        0 2 * * * /path/to/db_backup_monitor.sh >> /var/log/db_backup_monitor.log 2>&1
#
# What it does:
#   - Dumps a MySQL database and compresses it
#   - Deletes backups older than RETENTION_DAYS
#   - Checks that Apache and MySQL services are running
#   - Checks disk space and warns if usage is above a threshold
#   - Logs everything with timestamps

set -euo pipefail

# ---------------- CONFIG ----------------
DB_NAME="your_database_name"      # Run: mysql -e "SHOW DATABASES;"  to find the real name, then update this
# DB_USER and DB_PASS are no longer stored here.
# Credentials are read securely from ~/.my.cnf instead (see setup instructions).
BACKUP_DIR="/var/backups/mysql"
RETENTION_DAYS=7
DISK_WARN_THRESHOLD=85            # percent
APACHE_SERVICE="apache2"          # use "httpd" on RHEL/CentOS
MYSQL_SERVICE="mysql"             # use "mariadb" if running MariaDB
LOG_FILE="/var/log/db_backup_monitor.log"
# -----------------------------------------

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

log() {
    echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"

# ---------- 1. Database Backup ----------
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_$(date +%Y%m%d_%H%M%S).sql.gz"

log "Starting backup of database '$DB_NAME'..."

if mysqldump "$DB_NAME" | gzip > "$BACKUP_FILE"; then
    log "Backup successful: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
else
    log "ERROR: Backup failed for database '$DB_NAME'"
fi

# ---------- 2. Rotate Old Backups ----------
log "Removing backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +$RETENTION_DAYS -exec rm -v {} \; | tee -a "$LOG_FILE"

# ---------- 3. Service Health Checks ----------
check_service() {
    local service_name="$1"
    if systemctl is-active --quiet "$service_name"; then
        log "OK: $service_name is running."
    else
        log "ALERT: $service_name is NOT running!"
    fi
}

check_service "$APACHE_SERVICE"
check_service "$MYSQL_SERVICE"

# ---------- 4. Disk Space Check ----------
DISK_USAGE=$(df "$BACKUP_DIR" | awk 'NR==2 {gsub("%","",$5); print $5}')

if [ "$DISK_USAGE" -ge "$DISK_WARN_THRESHOLD" ]; then
    log "ALERT: Disk usage is at ${DISK_USAGE}% (threshold: ${DISK_WARN_THRESHOLD}%)"
else
    log "OK: Disk usage is at ${DISK_USAGE}%"
fi

log "Backup and monitoring run complete."
echo "----------------------------------------" >> "$LOG_FILE"
