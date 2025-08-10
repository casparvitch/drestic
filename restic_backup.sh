#!/bin/bash
set -euo pipefail

echo "--- Initializing Restic Backup Script ---"

# Source environment variables if the file exists
# This script expects RESTIC_ENV_FILE to be set in the environment
# or to be sourced from a common location.
# shellcheck source=/dev/null
if [ -f "$RESTIC_ENV_FILE" ]; then
	source "$RESTIC_ENV_FILE"
	echo "Environment variables loaded from $RESTIC_ENV_FILE"
else
	echo "Error: RESTIC_ENV_FILE not found. Please run setup.sh first." >&2
	exit 1
fi

# Single notification function to use in all scripts (Phase 2, Step 2.3)
notify() {
	local title="$1" message="$2" priority="${3:-5}"
	[ -n "${GOTIFY_URL:-}" ] && [ -n "${GOTIFY_TOKEN:-}" ] || return 0
	curl -sS "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" \
		-F "title=$title" -F "message=$message" -F "priority=$priority" \
		>/dev/null 2>&1 || true
}

# --- Exit Trap ---
# This will call notify with the script's final exit code upon termination.
trap 'notify "Restic Backup ($(whoami)@$(hostname))" "Restic backup script finished with exit code $?" $?' EXIT

# --- Main Backup Logic ---
echo "--- Starting Restic Backup at $(date) ---"

# Perform the Restic backup
echo "Starting Restic backup to repository: $RESTIC_REPOSITORY"
restic backup \
	--repo "${RESTIC_REPOSITORY}" \
	--files-from "${CONFIG_DIR}/paths" \
	--exclude-file "${CONFIG_DIR}/excludes" \
	--password-file "${RESTIC_PASSWORD_FILE}" \
	--tag daily || {
	echo "Error: Restic backup failed." >&2
	exit 1
}

# Prune old snapshots
echo "Applying Restic retention policy and pruning old snapshots..."
restic forget \
	--repo "${RESTIC_REPOSITORY}" \
	--password-file "${RESTIC_PASSWORD_FILE}" \
	--keep-daily 7 \
	--keep-weekly 4 \
	--keep-monthly 6 \
	--keep-yearly 6 \
	--prune || {
	echo "Error: Restic forget/prune failed." >&2
	exit 1
}

# Verify the latest snapshot (quick check)
echo "Performing quick integrity check on the latest snapshot (5% data subset)..."
restic check \
	--repo "${RESTIC_REPOSITORY}" \
	--password-file "${RESTIC_PASSWORD_FILE}" \
	--read-data-subset 5% \
	--verbose || {
	echo "Error: Restic check failed." >&2
	exit 1
}

echo "--- Restic Backup finished at $(date) ---"
