#!/bin/bash
set -euo pipefail

echo "=== DRestic User Scope Uninstall ==="
echo "WARNING: This will remove DRestic but keep your backup data in MEGA"
echo ""

# Confirmation
read -p "Continue with uninstall? [y/N] " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
	echo "Uninstall cancelled."
	exit 0
fi

echo "Stopping and disabling systemd timers..."
systemctl --user stop restic-backup.timer restic-check.timer 2>/dev/null || true
systemctl --user disable restic-backup.timer restic-check.timer 2>/dev/null || true

echo "Removing systemd service and timer files..."
rm -f ~/.config/systemd/user/restic-backup.service
rm -f ~/.config/systemd/user/restic-backup.timer
rm -f ~/.config/systemd/user/restic-check.service
rm -f ~/.config/systemd/user/restic-check.timer

echo "Reloading systemd daemon..."
systemctl --user daemon-reload

echo "Removing backup scripts..."
rm -f ~/.local/bin/restic_backup.sh
rm -f ~/.local/bin/restic_check.sh

echo ""
echo "Remove configuration files? This includes passwords and settings!"
echo "Your backup data in MEGA will remain safe."
read -p "Remove ~/.config/restic/? [y/N] " config_confirm

if [ "$config_confirm" = "y" ] || [ "$config_confirm" = "Y" ]; then
	echo "Removing configuration directory..."
	rm -rf ~/.config/restic/
	echo "Configuration removed."
else
	echo "Configuration kept at ~/.config/restic/"
fi

echo ""
echo "✓ DRestic user scope uninstall completed!"
echo "• Systemd timers stopped and disabled"
echo "• Scripts removed from ~/.local/bin/"
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
