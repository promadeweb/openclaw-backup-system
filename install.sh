#!/usr/bin/env bash
set -euo pipefail

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

echo "OpenClaw Backup System Installer"
echo "---------------------------------"

read -r -p "Install the backup script into which directory? [${DEFAULT_SCRIPT_DIR}]: " script_dir
script_dir="${script_dir:-$DEFAULT_SCRIPT_DIR}"

read -r -p "Where should backups be stored? [${DEFAULT_BACKUP_DIR}]: " backup_dir
backup_dir="${backup_dir:-$DEFAULT_BACKUP_DIR}"

printf "\nSummary of installation settings:\n"
echo "  Script installation directory: $script_dir"
echo "  Backup directory:             $backup_dir"
echo "  Log directory:                $LOG_DIR"

# Create directories
mkdir -p "$script_dir"
mkdir -p "$backup_dir"
mkdir -p "$LOG_DIR"

# Set ownership and permissions. These ensure only
# root can modify the backup script and backups.
chown root:root "$script_dir" "$backup_dir" "$LOG_DIR"
chmod 700 "$script_dir"
chmod 700 "$backup_dir"
chmod 750 "$LOG_DIR"

# Write the backup script directly from this
# installer, so the repository does not need to be
# present on the target machine.
install_script_path="$script_dir/$SCRIPT_NAME"
cat > "$install_script_path" <<'BACKUP_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

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

# ===== Prepare directories =====
mkdir -p "$BACKUP_BASE_DIR"
mkdir -p "$LOG_DIR"

# Ensure the log file exists with reasonable permissions.
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

# ===== Logging =====
exec >> "$LOG_FILE" 2>&1

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=============================================="
log "OpenClaw Backup Script started"

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

log "Backup completed successfully: $CURRENT_BACKUP_DIR"
log "OpenClaw Backup Script finished"
BACKUP_SCRIPT

# Replace the BACKUP_BASE_DIR definition inside the installed script
# with the backup directory selected by the user.
sed -i "s|^BACKUP_BASE_DIR=.*|BACKUP_BASE_DIR=\"$backup_dir\"|" "$install_script_path"

chown root:root "$install_script_path"
chmod 700 "$install_script_path"

# Ensure the log file exists and set appropriate permissions.
touch "$LOG_DIR/openclaw-backup.log"
chown root:root "$LOG_DIR/openclaw-backup.log"
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
    create 0640 root root
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
echo "A cron job has been created in $CRON_FILE to run the backup"
echo "daily at 05:30. You can adjust the schedule by editing that file."
