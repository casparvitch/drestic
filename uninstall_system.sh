#!/bin/bash
set -euo pipefail

echo "=== DRestic System Scope Uninstall ==="
echo "WARNING: This will remove DRestic system installation"
echo ""

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
	echo "Error: System scope uninstall requires root privileges."
	echo "Please run: sudo $0"
	exit 1
fi

# Confirmation
read -p "Continue with system uninstall? [y/N] " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
	echo "Uninstall cancelled."
	exit 0
fi

echo "Stopping and disabling systemd timers..."
systemctl stop restic-backup.timer restic-check.timer 2>/dev/null || true
systemctl disable restic-backup.timer restic-check.timer 2>/dev/null || true

echo "Removing systemd service and timer files..."
rm -f /etc/systemd/system/restic-backup.service
rm -f /etc/systemd/system/restic-backup.timer
rm -f /etc/systemd/system/restic-check.service
rm -f /etc/systemd/system/restic-check.timer

echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Removing backup scripts..."
rm -f /usr/local/bin/restic_backup.sh
rm -f /usr/local/bin/restic_check.sh

echo ""
echo "Remove configuration files? This includes passwords and settings!"
echo "Your backup data in MEGA will remain safe."
read -p "Remove /etc/restic/ and /root/.restic_*? [y/N] " config_confirm

if [ "$config_confirm" = "y" ] || [ "$config_confirm" = "Y" ]; then
	echo "Removing configuration files..."
	rm -rf /etc/restic/
	rm -f /root/.restic_*
	echo "Configuration removed."
else
	echo "Configuration kept at /etc/restic/ and /root/.restic_*"
fi

echo ""
echo "✓ DRestic system scope uninstall completed!"
echo "• Systemd timers stopped and disabled"
echo "• Scripts removed from /usr/local/bin/"
echo "• Systemd files removed"
if [ "$config_confirm" = "y" ] || [ "$config_confirm" = "Y" ]; then
	echo "• Configuration removed"
else
	echo "• Configuration preserved"
fi
echo "• Backup data remains safe in MEGA"
echo ""
echo "To remove backup data from MEGA, use:"
echo "  rclone purge backup_remote:/restic_backups"
echo "  rclone config delete backup_remote"
