#!/usr/bin/env bats

@test "all scripts have valid bash syntax" {
	for script in *.sh; do # Assuming main scripts are in root
		run bash -n "$script"
		[ "$status" -eq 0 ]
	done
}

@test "required commands exist" {
	for cmd in restic rclone curl git; do
		run command -v "$cmd"
		[ "$status" -eq 0 ]
	done
}

@test "systemd files have correct syntax" {
	for file in systemd/*.{service,timer}; do
		# Create a temporary file for verification to replace placeholders
		local temp_file=$(mktemp)
		sed -e 's|/path/to/be/replaced/restic_backup.sh|/usr/local/bin/restic_backup.sh|' \
			-e 's|# Environment variable will be set by setup.sh based on scope|Environment="RESTIC_ENV_FILE=/tmp/dummy_env"|' \
			"$file" >"$temp_file"

		run systemd-analyze verify "$temp_file"
		# systemd-analyze outputs to stderr, so check stderr for success/failure
		# Check status and ensure no critical errors in stderr
		local systemd_analyze_output="$(output)"
		local systemd_analyze_error="$(error)"

		# Ignore the KillMode=none warning from other systemd units if present
		systemd_analyze_error=$(echo "$systemd_analyze_error" | grep -v "Unit uses KillMode=none")

		if [ "$status" -ne 0 ] && [ -n "$systemd_analyze_error" ] && [[ "$systemd_analyze_error" != *"not available"* ]]; then
			fail "systemd-analyze failed for $file. Output: $systemd_analyze_output\nError: $systemd_analyze_error"
		fi
		rm "$temp_file"
	done
}
