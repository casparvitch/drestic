DRestic
-------

# Complete Plan: Secure & Automated Linux Backups with Restic, rclone, and Dotfiles

This plan outlines the creation of a standalone, reusable backup system for Linux. The project will be housed in its own Git repository and will include a comprehensive README with setup and recovery instructions. It leverages Restic for efficient and encrypted backups, rclone for cloud storage integration (MEGA S4), and a wrapper script for automated, secure deployment.

## Table of Contents

1.  [Goal & Core Technologies](#1-goal--core-technologies)
2.  [Prerequisites](#2-prerequisites)
3.  [Dotfiles Repository Structure](#3-dotfiles-repository-structure)
    *   [3.1. ```configure_rclone.sh```](#31-configure_rclonesh)
    *   [3.2. ```initialize_restic_repo.sh```](#32-initialize_restic_reposh)
    *   [3.3. ```restic_backup.sh```](#33-restic_backupsh)
    *   [3.4. ```restic-backup.service```](#34-restic-backupservice)
    *   [3.5. ```restic-backup.timer```](#35-restic-backuptimer)
    *   [3.6. ```restic_check.sh``` (New)](#36-restic_checksh-new)
    *   [3.7. ```restic-check.service``` (New)](#37-restic-checkservice-new)
    *   [3.8. ```restic-check.timer``` (New)](#38-restic-checktimer-new)
4.  [The Setup Wrapper Script (```setup_backups.sh```)](#4-the-setup-wrapper-script-setup_backupssh)
5.  [Deployment Steps](#5-deployment-steps)
6.  [Secure Credential Handling Summary](#6-secure-credential-handling-summary)
7.  [Backup Logic & Management](#7-backup-logic--management)
8.  [Key Benefits](#8-key-benefits)

---

## 1. Goal & Core Technologies

The primary goal is to establish a **secure, automated, and reproducible backup system** for your Linux systems. This system will leverage:

*   **Restic**: For efficient, encrypted, and deduplicated backups.
*   **Rclone**: To connect Restic to your MEGA S4 cloud storage.
*   **GNU Stow**: To manage and symlink your backup scripts and Systemd unit files from a dotfiles repository.
*   **Wrapper Bash Script**: To automate the initial setup process, including secure credential prompting and scope selection (system vs. user).
*   **Systemd Timers**: For reliable, scheduled automation of daily backups.

## 2. Prerequisites

Before executing the setup, ensure the following are in place on your system. The setup script will verify the presence of required command-line tools.

1.  **Operating System**: Debian (or a compatible Linux distribution with Systemd).
2.  **User with ```sudo``` privileges**: Required for system-scope installation.
3.  **Git Installed**: `sudo apt install -y git`
4.  **Rclone Installed**: `sudo apt install -y rclone`
5.  **Curl Installed**: `sudo apt install -y curl` (for notifications).
6.  **Restic Installed**: It's recommended to download the latest stable binary and place it in `/usr/local/bin`.
7.  **Project Repository Cloned**: The `restic-backup-automation` repository will be cloned during deployment.
8.  **MEGA S4 Account**: Have your MEGA email and password ready.
9.  **Restic Repository Password**: Choose a strong, unique password for your Restic repository.
10. **(Optional) Gotify Server for Notifications**:
    *   A running self-hosted Gotify server instance.
    *   An "Application Token" created in the Gotify UI for sending messages.

## 3. Repository Structure

The project will be organized in a standalone Git repository with the following structure. The `setup.sh` script will be at the root, with helper scripts and systemd units in their respective directories.

```
restic-backup-automation/
├── scripts/
│   ├── configure_rclone.sh
│   ├── initialize_restic_repo.sh
│   ├── restic_backup.sh
│   └── restic_check.sh
├── systemd/
│   ├── restic-backup.service
│   ├── restic-backup.timer
│   ├── restic-check.service
│   └── restic-check.timer
├── setup.sh
└── README.md
```

### 3.1. ```configure_rclone.sh``` (in ```scripts/```)

```bash
#!/bin/bash
set -euo pipefail # Exit on error, undefined variable, or pipe failure.

# This script configures rclone for MEGA S4 non-interactively.
# It expects MEGA_EMAIL and MEGA_PASSWORD environment variables to be set.

# --- Configuration Variables ---
RCLONE_REMOTE_NAME="backup_remote"
# MEGA_EMAIL and MEGA_PASSWORD are expected to be passed as environment variables

# --- Check for required environment variables ---
if [ -z "$MEGA_EMAIL" ] || [ -z "$MEGA_PASSWORD" ]; then
  echo "Error: MEGA_EMAIL or MEGA_PASSWORD environment variable is not set."
  exit 1
fi

echo "Configuring rclone remote: ${RCLONE_REMOTE_NAME}..."

# Use rclone config create for non-interactive setup
rclone config create "${RCLONE_REMOTE_NAME}" mega \
  user "${MEGA_EMAIL}" \
  pass "${MEGA_PASSWORD}" \
  --non-interactive

if [ $? -eq 0 ]; then
  echo "Rclone remote '${RCLONE_REMOTE_NAME}' configured successfully."
  echo "Testing rclone configuration..."
  rclone ls "${RCLONE_REMOTE_NAME}":
  if [ $? -eq 0 ]; then
    echo "Rclone test successful."
  else
    echo "Rclone test failed. Please check your MEGA credentials."
    exit 1
  fi
else
  echo "Error: Failed to configure rclone remote '${RCLONE_REMOTE_NAME}'."
  exit 1
fi
```

### 3.2. ```initialize_restic_repo.sh``` (in ```scripts/```)

```bash
#!/bin/bash
set -euo pipefail # Exit on error, undefined variable, or pipe failure.

# This script initializes the Restic repository on the configured rclone remote if it does not already exist.
# It expects the RESTIC_PASSWORD_FILE environment variable to be set.

# --- Configuration Variables ---
RCLONE_REMOTE_NAME="backup_remote"
RESTIC_REPO_PATH="/restic_backups" # Path within your MEGA S4 remote
RESTIC_REPO="rclone:${RCLONE_REMOTE_NAME}:${RESTIC_REPO_PATH}"

# --- Check for required environment variable ---
if [ -z "$RESTIC_PASSWORD_FILE" ]; then
  echo "Error: RESTIC_PASSWORD_FILE environment variable is not set."
  exit 1
fi

# --- Check if repository already exists ---
echo "Checking for existing Restic repository at ${RESTIC_REPO}..."
if restic cat config --repo "${RESTIC_REPO}" --password-file "${RESTIC_PASSWORD_FILE}" &> /dev/null; then
  echo "Restic repository already exists. Skipping initialization."
  exit 0
fi

echo "No existing repository found. Initializing Restic repository..."

# Initialize the Restic repository
restic init --repo "${RESTIC_REPO}" \
  --password-file "${RESTIC_PASSWORD_FILE}"

if [ $? -eq 0 ]; then
  echo "Restic repository initialized successfully."
else
  echo "Error: Failed to initialize Restic repository."
  exit 1
fi
```

### 3.3. ```restic_backup.sh``` (in ```scripts/```)

```bash
#!/bin/bash
set -euo pipefail

# --- Scope-dependent configuration ---
if [ "$(id -u)" -eq 0 ]; then
  # System-wide (root) scope
  ENV_FILE="/root/.restic_env"
  PATHS_FILE="/etc/restic/paths"
  EXCLUDES_FILE="/etc/restic/excludes"
  RESTIC_PASSWORD_FILE="/root/.restic_password"
else
  # User scope
  mkdir -p "${HOME}/.config/restic"
  ENV_FILE="${HOME}/.config/restic/env"
  PATHS_FILE="${HOME}/.config/restic/paths"
  EXCLUDES_FILE="${HOME}/.config/restic/excludes"
  RESTIC_PASSWORD_FILE="${HOME}/.config/restic/password"
fi

# Source environment variables if the file exists
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

# --- Notification Function ---
send_notification() {
  # Only run if Gotify URL and Token are set
  if [ -z "$GOTIFY_URL" ] || [ -z "$GOTIFY_TOKEN" ]; then
    return
  fi

  local exit_code=$1
  local title=""
  local message=""
  local priority=5 # Normal priority

  if [ $exit_code -ne 0 ]; then
    title="❌ Backup FAILED on $(hostname)"
    message="Restic backup script failed with exit code $exit_code."
    priority=8 # High priority
  else
    title="✅ Backup SUCCESS on $(hostname)"
    message="Restic backup completed successfully."
  fi

  curl -sS "${GOTIFY_URL}/message?token=${GOTIFY_TOKEN}" \
    -F "title=${title}" \
    -F "message=${message}" \
    -F "priority=${priority}" > /dev/null
}

# --- Exit Trap ---
# This will call send_notification with the script's final exit code upon termination.
trap 'send_notification $?' EXIT

# --- Configuration Variables ---
RCLONE_REMOTE_NAME="backup_remote"
RESTIC_REPO_PATH="/restic_backups"
RESTIC_REPO="rclone:${RCLONE_REMOTE_NAME}:${RESTIC_REPO_PATH}"

# --- Main Backup Logic ---
echo "--- Starting Restic Backup at $(date) ---"

# Perform the Restic backup
echo "Running restic backup..."
restic backup \
  --repo "${RESTIC_REPO}" \
  --files-from "${PATHS_FILE}" \
  --exclude-file "${EXCLUDES_FILE}" \
  --password-file "${RESTIC_PASSWORD_FILE}" \
  --tag daily \
  --verbose

# Prune old snapshots
echo "Running restic forget and prune..."
restic forget \
  --repo "${RESTIC_REPO}" \
  --password-file "${RESTIC_PASSWORD_FILE}" \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --keep-yearly 6 \
  --prune \
  --verbose

echo "--- Restic Backup finished at $(date) ---"
```

scripts/restic_check.sh
