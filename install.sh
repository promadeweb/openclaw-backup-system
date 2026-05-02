#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# OpenClaw Backup System Installer
#
# This script installs the OpenClaw backup script
# onto a Linux system.  It prompts you for the
# location where the backup script should be
# installed and the location where backups should
# be stored.  If you press ENTER without typing a
# value, the installer will use sensible defaults.
#
# The installer is idempotent.  You can run it
# multiple times on the same system without
# damaging an existing installation.  It will
# overwrite the installed backup script and
# configuration files with the latest version
# shipped in this repository.
#
# You must run this installer with root privileges
# (e.g. via sudo) because it writes to system
# directories such as /usr/local/bin, /etc/cron.d,
# and /etc/logrotate.d.
# ==================================================

DEFAULT_SCRIPT_DIR="/usr/local/bin"
DEFAULT_BACKUP_DIR="/var/backups/openclaw"
LOG_DIR="/var/log/openclaw-backups"
LOGROTATE_CONF="/etc/logrotate.d/openclaw-backup"
CRON_FILE="/etc/cron.d/openclaw-backup"
SCRIPT_NAME="backup-openclaw.sh"

echo "OpenClaw Backup System Installer"
echo "---------------------------------"

read -p "Install the backup script into which directory? [${DEFAULT_SCRIPT_DIR}]: " script_dir
script_dir="${script_dir:-$DEFAULT_SCRIPT_DIR}"

read -p "Where should backups be stored? [${DEFAULT_BACKUP_DIR}]: " backup_dir
backup_dir="${backup_dir:-$DEFAULT_BACKUP_DIR}"

echo "\nSummary of installation settings:"
echo "  Script installation directory: $script_dir"
echo "  Backup directory:             $backup_dir"
echo "  Log directory:                $LOG_DIR"

# Create directories
mkdir -p "$script_dir"
mkdir -p "$backup_dir"
mkdir -p "$LOG_DIR"

# Set ownership and permissions.  These ensure
# only root can modify the backup script and
# backups, but cron will still be able to execute
# the script and write logs.
chown root:root "$script_dir" "$backup_dir" "$LOG_DIR"
chmod 700 "$script_dir"
chmod 700 "$backup_dir"
chmod 750 "$LOG_DIR"

# Copy the backup script into the chosen directory
install_script_path="$script_dir/$SCRIPT_NAME"
cp -f "$(dirname "$0")/$SCRIPT_NAME" "$install_script_path"
chown root:root "$install_script_path"
chmod 700 "$install_script_path"

# Replace the BACKUP_BASE_DIR definition inside the
# installed script with the chosen backup directory.
# This substitution only modifies the installed
# copy.  The original in this repository remains
# unchanged.
sed -i "s|^BACKUP_BASE_DIR=.*|BACKUP_BASE_DIR=\"$backup_dir\"|" "$install_script_path"

# Ensure the log directory exists and set
# appropriate permissions.  The backup script will
# create the log file automatically.
mkdir -p "$LOG_DIR"
touch "$LOG_DIR/openclaw-backup.log"
chown root:root "$LOG_DIR/openclaw-backup.log"
chmod 640 "$LOG_DIR/openclaw-backup.log"

# Install the logrotate configuration.  If an
# existing file is present, it will be overwritten.
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

# Install a cron job for root to run the backup
# script daily at 05:30.  If the cron file already
# exists, it will be overwritten.
cat > "$CRON_FILE" <<EOF
30 5 * * * root $install_script_path
EOF
chown root:root "$CRON_FILE"
chmod 644 "$CRON_FILE"

# Ensure the 'zip' utility is available.  If not,
# attempt to install it using the system package
# manager.  This step may fail on systems without
# apt-get; if so, instruct the user to install
# zip manually.
if ! command -v zip >/dev/null 2>&1; then
  echo "'zip' utility is not installed.  Attempting to install..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq zip
  else
    echo "Please install 'zip' manually using your package manager."
  fi
fi

echo "\nInstallation complete."
echo "--------------------------------------------------"
echo "The backup script has been installed at:"
echo "  $install_script_path"
echo "Backups will be written to:"
echo "  $backup_dir"
echo "Logs will be written to:"
echo "  $LOG_DIR/openclaw-backup.log"
echo "A cron job has been created in $CRON_FILE to run the backup"
echo "daily at 05:30.  You can adjust the schedule by editing that file."
