#!/usr/bin/env bash
set -euo pipefail
umask 027

# ==================================================
# OpenClaw Backup System Installer
#
# This installer downloads or copies the single
# source-of-truth backup script: backup-openclaw.sh.
# It does not duplicate the backup logic.
#
# It can be executed from a URL, from a copied file,
# or from a cloned checkout.
#
# You must run this installer with root privileges
# because it writes to system directories such as
# /usr/local/bin, /etc/cron.d, and /etc/logrotate.d.
# ==================================================

DEFAULT_SOURCE_DIR="/root/.openclaw"
DEFAULT_SCRIPT_DIR="/usr/local/bin"
DEFAULT_BACKUP_DIR="/var/backups/openclaw"
DEFAULT_BACKUP_SCRIPT_URL="https://raw.githubusercontent.com/promadeweb/openclaw-backup-system/main/backup-openclaw.sh"
LOG_DIR="/var/log/openclaw-backups"
LOGROTATE_CONF="/etc/logrotate.d/openclaw-backup"
CRON_FILE="/etc/cron.d/openclaw-backup"
SCRIPT_NAME="backup-openclaw.sh"
BACKUP_SCRIPT_URL="${BACKUP_SCRIPT_URL:-$DEFAULT_BACKUP_SCRIPT_URL}"

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

install_backup_script() {
  local destination="$1"
  local local_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$SCRIPT_NAME"

  if [[ -f "$local_script" ]]; then
    echo "Using local backup script: $local_script"
    cp -f "$local_script" "$destination"
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    echo "Downloading backup script from: $BACKUP_SCRIPT_URL"
    curl -fsSL -o "$destination" "$BACKUP_SCRIPT_URL"
    return
  fi

  echo "ERROR: Could not find local $SCRIPT_NAME and curl is not installed."
  echo "Install curl or run this installer from a checkout that includes $SCRIPT_NAME."
  exit 1
}

echo "OpenClaw Backup System Installer"
echo "---------------------------------"

source_dir="$(prompt_with_default "Which directory should be backed up?" "$DEFAULT_SOURCE_DIR")"
script_dir="$(prompt_with_default "Install the backup script into which directory?" "$DEFAULT_SCRIPT_DIR")"
backup_dir="$(prompt_with_default "Where should backups be stored?" "$DEFAULT_BACKUP_DIR")"

if [[ ! -d "$source_dir" ]]; then
  echo "WARNING: Source directory does not exist yet: $source_dir"
  echo "The installer will continue, but backups will fail until this directory exists."
fi

printf "\nSummary of installation settings:\n"
echo "  Source directory:              $source_dir"
echo "  Script installation directory: $script_dir"
echo "  Backup directory:             $backup_dir"
echo "  Log directory:                $LOG_DIR"
echo "  Admin group read/list access: $ADMIN_GROUP"
echo "  Backup script URL:            $BACKUP_SCRIPT_URL"

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

# Install the single source-of-truth backup script.
install_script_path="$script_dir/$SCRIPT_NAME"
install_backup_script "$install_script_path"

# Replace installer-selected values inside the installed script.
sed -i "s|^SOURCE_DIR=.*|SOURCE_DIR=\"$source_dir\"|" "$install_script_path"
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
echo "Source directory to back up:"
echo "  $source_dir"
echo "Backups will be written to:"
echo "  $backup_dir"
echo "Logs will be written to:"
echo "  $LOG_DIR/openclaw-backup.log"
echo "Admin group with read/list access:"
echo "  $ADMIN_GROUP"
echo "A cron job has been created in $CRON_FILE to run the backup"
echo "daily at 05:30. You can adjust the schedule by editing that file."
