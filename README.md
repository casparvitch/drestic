# DRestic

## What is DRestic?

DRestic is an automated backup system (using restic & mega) for Linux that provides:

- **Set-and-forget automated backups** - Runs daily at 3 AM via systemd timers
- **Strong encryption** - Your data is private even from MEGA cloud storage
- **Deduplication** - Saves storage space and bandwidth by only storing changed data
- **Point-in-time recovery** - Restore files from any backup date
- **Free cloud storage** - Uses MEGA (15GB free, more with paid plans)
- **Simple setup** - One script configures everything

## What Gets Backed Up

**User scope** (recommended for personal machines):
```
/home/username (entire home directory)
```

**System scope** (for servers):
```
/etc
/home
/root
/var/lib/docker
/opt
```

**Excluded by default:**
```
**/.cache
**/node_modules
*.tmp
*.log
**/.git/objects
**/.npm
**/.cargo/registry
**/.local/share/Trash
**/Downloads/*.iso
**/Downloads/*.img
**/.steam
**/.wine
```

## Quick Start

1. Install dependencies:
   ```
   sudo apt install rclone curl git restic
   ```

2. Clone and setup (for user install)
   ```
   git clone https://github.com/casparvitch/drestic
   cd drestic
   chmod +x setup.sh
   ./setup.sh --scope=user
   ```

The setup script will prompt for your MEGA credentials and Restic repository password. **Store these securely** - they are required for backup recovery.

## Verify It's Working

After setup, check that everything is running:

1. **Check timer status:**
   ```
   systemctl --user status restic-backup.timer
   ```

2. **Run a backup:**
   ```
   systemctl --user start restic-backup.service
   ```

3. **Watch the backup progress:**
   ```
   journalctl --user -fu restic-backup.service
   ```

4. **Verify backup completed successfully:**
   ```
   RESTIC_PASSWORD_FILE=~/.config/restic/password restic snapshots --repo rclone:backup_remote:/restic_backups
   ```

You should see at least one snapshot listed.

## Recovery (When You Need Your Files Back)

### Quick File Recovery

**List what's available:**
```
RESTIC_PASSWORD_FILE=~/.config/restic/password restic snapshots --repo rclone:backup_remote:/restic_backups
```

**Browse backups like a folder:**
```
mkdir ~/restore
RESTIC_PASSWORD_FILE=~/.config/restic/password restic mount ~/restore --repo rclone:backup_remote:/restic_backups
# Browse files in ~/restore, then unmount:
umount ~/restore
```

**Restore specific files:**
```
RESTIC_PASSWORD_FILE=~/.config/restic/password restic restore latest --target /tmp/restore --path /home/user/Documents --repo rclone:backup_remote:/restic_backups
```

### System Recovery Commands

For system scope installations, prefix commands with `sudo` and use:
- Password file: `/root/.restic_password`
- Repository: `rclone:backup_remote:/restic_backups`

## Customization

### Backup Paths and Exclusions

Edit the backup paths and exclusions:

```
# User scope
nano ~/.config/restic/paths
nano ~/.config/restic/excludes

# System scope
sudo nano /etc/restic/paths
sudo nano /etc/restic/excludes
```

The paths file contains directories to backup (one per line). The excludes file contains patterns to skip (supports ** wildcards).

### Backup Schedule

To change backup timing, edit the systemd timer files:

```
# User scope
nano ~/.config/systemd/user/restic-backup.timer

# System scope
sudo nano /etc/systemd/system/restic-backup.timer
```

Change `OnCalendar=*-*-* 03:00:00` to your preferred time. Examples:
- `OnCalendar=*-*-* 02:30:00` (2:30 AM daily)
- `OnCalendar=*-*-* 06:00:00,18:00:00` (6 AM and 6 PM daily)
- `OnCalendar=Mon,Wed,Fri 03:00:00` (Monday, Wednesday, Friday at 3 AM)

After editing, reload systemd:
```
# User scope
systemctl --user daemon-reload
systemctl --user restart restic-backup.timer

# System scope
sudo systemctl daemon-reload
sudo systemctl restart restic-backup.timer
```

**Note for user scope:** To ensure backups run when you're not logged in, enable lingering:
```
sudo loginctl enable-linger $USER
```

## Backup Schedule

Backups run automatically:
- **Daily backups** at 3:00 AM
- **Weekly integrity checks** 
- **Automatic cleanup** of old snapshots (keeps 7 daily, 4 weekly, 6 monthly, 6 yearly)

Check status:
```
# User scope
systemctl --user status restic-backup.timer

# System scope
sudo systemctl status restic-backup.timer
```

## Advanced Topics

### Notifications

Optional Gotify push notifications can be configured during setup. Edit the environment file to change settings:

```
# User scope
nano ~/.config/restic/env

# System scope
sudo nano /root/.restic_env
```

### Troubleshooting

**Backup not running:**
Check timer status and logs:
```
systemctl --user status restic-backup.timer
journalctl --user -u restic-backup.service
```

**Cannot access repository:**
Test rclone connection:
```
rclone ls backup_remote:
```

**Missing files in backup:**
Check your paths file and verify the directories exist and are readable.

**Restore fails:**
Ensure you have the correct Restic password and MEGA credentials. Test repository access with the snapshots command above.

### Testing

Run the (local) test suite:
```
make test-local
```

This requires bats-core to be installed.

Run the (w remote) test suite:
```
make test-remote
```
