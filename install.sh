#!/usr/bin/env bash
set -euo pipefail
umask 027

# ==================================================
# OpenClaw Backup System Installer
#
# This installer is self-contained. It can be copied
# or downloaded as a single .sh file and executed on
# a Linux server without cloning this repository.
#
# It installs the OpenClaw backup script, creates the
# required directories, configures logrotate, and
# creates a cron job to run the backup every day.
#
# You must run this installer with root privileges
# because it writes to system directories such as
# /usr/local/bin, /etc/cron.d, and /etc/logrotate.d.
# ==================================================

DEFAULT_SCRIPT_DIR="/usr/local/bin"
DEFAULT_BACKUP_DIR="/var/backups/openclaw"
LOG_DIR="/var/log/openclaw-backups"
LOGROTATE_CONF="/etc/logrotate.d/openclaw-backup"
CRON_FILE="/etc/cron.d/openclaw-backup"
SCRIPT_NAME="backup-openclaw.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: This installer must be run as root. Use sudo."
  exit 1
fi

if getent group sudo >/dev/null 2>&1; then
  ADMIN_GROUP="sudo"
elif getent group wheel >/dev/null 2>&1; then
  ADMIN_GROUP="wheel"
else
  ADMIN_GROUP="root"
fi

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local answer=""

  if [[ -r /dev/tty ]]; then
    read -r -p "$prompt [$default_value]: " answer < /dev/tty
  elif [[ -t 0 ]]; then
    read -r -p "$prompt [$default_value]: " answer
  fi

  echo "${answer:-$default_value}"
}

echo "OpenClaw Backup System Installer"
echo "---------------------------------"

script_dir="$(prompt_with_default "Install the backup script into which directory?" "$DEFAULT_SCRIPT_DIR")"
backup_dir="$(prompt_with_default "Where should backups be stored?" "$DEFAULT_BACKUP_DIR")"

printf "\nSummary of installation settings:\n"
echo "  Script installation directory: $script_dir"
echo "  Backup directory:             $backup_dir"
echo "  Log directory:                $LOG_DIR"
echo "  Admin group read/list access: $ADMIN_GROUP"

# Create directories
mkdir -p "$script_dir"
mkdir -p "$backup_dir"
mkdir -p "$LOG_DIR"

# Root owns the installed files. The admin group can list
# directories and read files/logs, but cannot modify them.
chown root:"$ADMIN_GROUP" "$script_dir" "$backup_dir" "$LOG_DIR"
chmod 750 "$script_dir"
chmod 750 "$backup_dir"
chmod 750 "$LOG_DIR"

# Write the backup script directly from this installer, so the
# repository does not need to be present on the target machine.
install_script_path="$script_dir/$SCRIPT_NAME"
cat > "$install_script_path" <<'BACKUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
umask 027

# ==================================================
# OpenClaw Backup Script
#
# This script creates a daily backup of the OpenClaw
# application data. It keeps the most recent backup
# uncompressed and compresses older backups into ZIP
# archives. When the number of backups exceeds the
# configured maximum, the oldest backups are removed.
# ==================================================

# Directory to back up. Adjust this if your
# .openclaw folder lives under a different user.
SOURCE_DIR="/root/.openclaw"

# Base directory where backups are stored. The
# installer replaces this value during installation.
BACKUP_BASE_DIR="/var/backups/openclaw"

# System group allowed to list backup folders and
# read backup files/logs. The installer sets this to
# sudo on Debian/Ubuntu, wheel on RHEL/Fedora, or
# root if no admin group is found.
ADMIN_GROUP="sudo"

# Directory where logs are written.
LOG_DIR="/var/log/openclaw-backups"
LOG_FILE="${LOG_DIR}/openclaw-backup.log"

# File used to prevent concurrent runs of this script.
LOCK_FILE="/tmp/openclaw-backup.lock"

# Maximum number of backups to keep.
MAX_BACKUPS=10

# Construct the name for today's backup directory.
DATE_STR="$(date +%Y.%m.%d)"
BACKUP_SUFFIX="OpenClaw"
CURRENT_BACKUP_NAME="${DATE_STR}-${BACKUP_SUFFIX}"
CURRENT_BACKUP_DIR="${BACKUP_BASE_DIR}/${CURRENT_BACKUP_NAME}"

set_admin_group_permissions() {
  local path="$1"

  if getent group "$ADMIN_GROUP" >/dev/null 2>&1; then
    chgrp -R "$ADMIN_GROUP" "$path"
    chmod -R u+rwX,g+rX,o-rwx "$path"
  else
    chmod -R u+rwX,o-rwx "$path"
  fi
}

# ===== Prepare directories =====
mkdir -p "$BACKUP_BASE_DIR"
mkdir -p "$LOG_DIR"
set_admin_group_permissions "$BACKUP_BASE_DIR"
set_admin_group_permissions "$LOG_DIR"

# Ensure the log file exists with permissions that
# allow root to write and the admin group to read.
touch "$LOG_FILE"
if getent group "$ADMIN_GROUP" >/dev/null 2>&1; then
  chgrp "$ADMIN_GROUP" "$LOG_FILE"
fi
chmod 640 "$LOG_FILE"

# ===== Logging =====
exec >> "$LOG_FILE" 2>&1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=============================================="
log "OpenClaw Backup Script started"
log "Admin group with read/list access: $ADMIN_GROUP"

# ===== Lock to prevent overlapping runs =====
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "ERROR: Another backup process is already running. Exiting."
  exit 1
fi

# ===== Validate source =====
if [[ ! -d "$SOURCE_DIR" ]]; then
  log "ERROR: Source directory does not exist: $SOURCE_DIR"
  exit 1
fi

# ===== Create current backup =====
log "Source directory: $SOURCE_DIR"
log "Backup directory: $CURRENT_BACKUP_DIR"

# Remove any previous backup for today, directory or zip.
if [[ -d "$CURRENT_BACKUP_DIR" ]]; then
  log "Existing backup for today found. Removing: $CURRENT_BACKUP_DIR"
  rm -rf "$CURRENT_BACKUP_DIR"
fi

if [[ -f "${CURRENT_BACKUP_DIR}.zip" ]]; then
  log "Existing zip for today found. Removing: ${CURRENT_BACKUP_DIR}.zip"
  rm -f "${CURRENT_BACKUP_DIR}.zip"
fi

# Create today's backup directory and copy data.
mkdir -p "$CURRENT_BACKUP_DIR"
log "Copying source directory..."
cp -a "$SOURCE_DIR" "$CURRENT_BACKUP_DIR/"
set_admin_group_permissions "$CURRENT_BACKUP_DIR"

# ===== Compress old backups =====
cd "$BACKUP_BASE_DIR"
log "Compressing old backups..."

# Build list of existing backups, both directories and zips, sorted by date.
mapfile -t BACKUP_NAMES < <(
  find . -maxdepth 1 \( -type d -o -type f \) | sed 's|^\./||' \
    | grep -E "^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-${BACKUP_SUFFIX}(\.zip)?$" \
    | sed 's/\.zip$//' \
    | sort -u
)

# Compress all backup directories except today's.
for name in "${BACKUP_NAMES[@]}"; do
  if [[ "$name" != "$CURRENT_BACKUP_NAME" && -d "$name" ]]; then
    log "Compressing: $name -> ${name}.zip"
    rm -f "${name}.zip"
    zip -rq "${name}.zip" "$name"
    if getent group "$ADMIN_GROUP" >/dev/null 2>&1; then
      chgrp "$ADMIN_GROUP" "${name}.zip"
    fi
    chmod 640 "${name}.zip"
    rm -rf "$name"
  fi
done

# ===== Refresh backup list =====
mapfile -t BACKUP_NAMES < <(
  find . -maxdepth 1 \( -type d -o -type f \) | sed 's|^\./||' \
    | grep -E "^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-${BACKUP_SUFFIX}(\.zip)?$" \
    | sed 's/\.zip$//' \
    | sort -u
)

# Ensure existing backup files/directories remain visible to the admin group.
for name in "${BACKUP_NAMES[@]}"; do
  if [[ -d "$name" ]]; then
    set_admin_group_permissions "$name"
  elif [[ -f "${name}.zip" ]]; then
    if getent group "$ADMIN_GROUP" >/dev/null 2>&1; then
      chgrp "$ADMIN_GROUP" "${name}.zip"
    fi
    chmod 640 "${name}.zip"
  fi
done

# ===== Rotate backups =====
TOTAL="${#BACKUP_NAMES[@]}"
log "Total backups found: $TOTAL"

if (( TOTAL > MAX_BACKUPS )); then
  TO_DELETE=$(( TOTAL - MAX_BACKUPS ))
  log "More than $MAX_BACKUPS backups found. Deleting $TO_DELETE old backup(s)."
  for ((i=0; i<TO_DELETE; i++)); do
    OLD="${BACKUP_NAMES[$i]}"
    log "Deleting old backup: $OLD"
    rm -rf "$OLD"
    rm -f "${OLD}.zip"
  done
else
  log "Backup rotation not needed."
fi

set_admin_group_permissions "$BACKUP_BASE_DIR"
set_admin_group_permissions "$LOG_DIR"

log "Backup completed successfully: $CURRENT_BACKUP_DIR"
log "OpenClaw Backup Script finished"
BACKUP_SCRIPT

# Replace installer-selected values inside the installed script.
sed -i "s|^BACKUP_BASE_DIR=.*|BACKUP_BASE_DIR=\"$backup_dir\"|" "$install_script_path"
sed -i "s|^ADMIN_GROUP=.*|ADMIN_GROUP=\"$ADMIN_GROUP\"|" "$install_script_path"

chown root:"$ADMIN_GROUP" "$install_script_path"
chmod 750 "$install_script_path"

# Ensure the log file exists and set appropriate permissions.
touch "$LOG_DIR/openclaw-backup.log"
chown root:"$ADMIN_GROUP" "$LOG_DIR/openclaw-backup.log"
chmod 640 "$LOG_DIR/openclaw-backup.log"

# Install the logrotate configuration.
cat > "$LOGROTATE_CONF" <<EOF
$LOG_DIR/openclaw-backup.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root $ADMIN_GROUP
}
EOF
chown root:root "$LOGROTATE_CONF"
chmod 644 "$LOGROTATE_CONF"

# Install a cron job for root to run the backup script daily at 05:30.
cat > "$CRON_FILE" <<EOF
30 5 * * * root $install_script_path
EOF
chown root:root "$CRON_FILE"
chmod 644 "$CRON_FILE"

# Ensure the 'zip' utility is available.
if ! command -v zip >/dev/null 2>&1; then
  echo "'zip' utility is not installed. Attempting to install..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq zip
  else
    echo "WARNING: Please install 'zip' manually using your package manager."
  fi
fi

printf "\nInstallation complete.\n"
echo "--------------------------------------------------"
echo "The backup script has been installed at:"
echo "  $install_script_path"
echo "Backups will be written to:"
echo "  $backup_dir"
echo "Logs will be written to:"
echo "  $LOG_DIR/openclaw-backup.log"
echo "Admin group with read/list access:"
echo "  $ADMIN_GROUP"
echo "A cron job has been created in $CRON_FILE to run the backup"
echo "daily at 05:30. You can adjust the schedule by editing that file."
