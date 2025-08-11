#!/bin/bash
set -euo pipefail

echo "--- Initializing Restic Check Script ---"

# Source environment variables if the file exists
# This script expects RESTIC_ENV_FILE to be set in the environment
# The environment file includes rclone throttling settings to prevent timeouts
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
trap 'notify "Restic Check" "Restic check script finished with exit code $?" $?' EXIT

# --- Main Logic ---
echo "--- Starting Restic Repository Integrity Check at $(date) ---"

echo "Running full integrity check on repository: $RESTIC_REPOSITORY (5% data subset)..."
restic check \
	--repo "${RESTIC_REPOSITORY}" \
	--password-file "${RESTIC_PASSWORD_FILE}" \
	--verbose \
	--read-data-subset 5% || {
	echo "Error: Restic check failed." >&2
	exit 1
}

echo "--- Restic Repository Integrity Check finished successfully at $(date) ---"
