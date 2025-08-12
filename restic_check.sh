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

# --- Pre-warm rclone connection ---
echo "Pre-warming rclone connection to MEGA..."
prewarm_success=false
for attempt in 1 2 3; do
    echo "Connection attempt $attempt/3..."
    if timeout 120 rclone ls backup_remote: >/dev/null 2>&1; then
        echo "✓ Connection established on attempt $attempt"
        prewarm_success=true
        break
    else
        echo "✗ Attempt $attempt failed"
        [ $attempt -lt 3 ] && sleep 30
    fi
done

if [ "$prewarm_success" = false ]; then
    echo "Warning: All pre-warm attempts failed. Check may be slower or fail."
    notify "Restic Check ($(whoami)@$(hostname))" "Pre-warm connection failed - check may have issues" 6
fi

# --- Exit Trap ---
trap 'notify "Restic Check" "Restic check script finished with exit code $?" $?' EXIT

# --- Main Logic ---
echo "--- Starting Restic Repository Integrity Check at $(date) ---"

echo "Running memory-efficient integrity check on repository: $RESTIC_REPOSITORY (1% data subset)..."
restic check \
	--repo "${RESTIC_REPOSITORY}" \
	--password-file "${RESTIC_PASSWORD_FILE}" \
	--read-data-subset 1% \
	--no-cache \
	--verbose || {
	echo "Error: Restic check failed." >&2
	notify "Restic Check ($(whoami)@$(hostname))" "Weekly integrity check failed!" 8
	exit 1
}

echo "--- Restic Repository Integrity Check finished successfully at $(date) ---"
