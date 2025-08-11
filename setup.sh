#!/bin/bash
set -euo pipefail

# Global variables for configuration
SCOPE=""

# --- Helper Functions ---

log() {
	echo "--- $* ---"
}

error() {
	echo "Error: $*" >&2
	echo "Run '$0 --help' for usage information." >&2
	exit 1
}

check_dependencies() {
	local missing_deps=()
	for cmd in restic rclone curl; do
		if ! command -v "$cmd" &>/dev/null; then
			missing_deps+=("$cmd")
		fi
	done

	if [ ${#missing_deps[@]} -ne 0 ]; then
		error "Missing required dependencies: ${missing_deps[*]}"
	fi
}

read_password() {
	local prompt="$1"
	local password=""

	while [ -z "$password" ]; do
		read -rsp "$prompt: " password
		echo
		if [ -z "$password" ]; then
			echo "Password cannot be empty. Please try again."
		fi
	done

	echo "$password"
}

validate_email() {
	local email="$1"
	if [[ ! "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
		error "Invalid email format: $email"
	fi
}

validate_url() {
	local url="$1"
	if [[ -n "$url" ]] && [[ ! "$url" =~ ^https?:// ]]; then
		error "Invalid URL format: $url (must start with http:// or https://)"
	fi
}

# Function to configure rclone
configure_rclone() {
	local email="$1"
	local password_file="$2"

	log "Configuring rclone remote: backup_remote"

	rclone config create backup_remote mega \
		user "$email" \
		pass "$(cat "$password_file")" \
		--non-interactive ||
		error "Failed to configure rclone remote 'backup_remote'."

	log "Testing rclone configuration..."
	echo "Attempting to connect to MEGA (this may take 30-60 seconds)..."
	if timeout 120 rclone ls backup_remote: >/dev/null 2>&1; then
		echo "✓ Connection successful"
	else
		echo "✗ Connection failed"
		echo "Debugging information:"
		echo "Testing with verbose output..."
		timeout 30 rclone ls backup_remote: -v 2>&1 | head -20 || true
		error "Rclone test failed. Please check your MEGA credentials and network connection."
	fi

	log "Rclone remote 'backup_remote' configured successfully."
}

# Function to initialize restic repository
initialize_restic_repo() {
	local repo="$1"
	local password_file="$2"

	log "Checking for existing Restic repository at ${repo}"

	if restic cat config --repo "${repo}" --password-file "${password_file}" &>/dev/null; then
		log "Restic repository already exists. Skipping initialization."
		return 0
	fi

	log "No existing repository found. Initializing Restic repository..."
	restic init --repo "${repo}" \
		--password-file "${password_file}" ||
		error "Failed to initialize Restic repository."

	log "Restic repository initialized successfully."
}

# Simplified validation checks (Phase 3, Step 3.2)
check_basic_config() {
	log "Performing basic configuration checks..."
	local errors=0

	# Check password file
	if [ ! -f "$PASS_FILE" ]; then
		echo "Error: Restic password file missing: $PASS_FILE" >&2
		errors=$((errors + 1))
	elif [ ! -s "$PASS_FILE" ]; then
		echo "Error: Restic password file is empty: $PASS_FILE" >&2
		errors=$((errors + 1))
	elif [ "$(stat -c %a "$PASS_FILE")" != "600" ]; then
		echo "Warning: Restic password file permissions are not 600: $PASS_FILE" >&2
		# This is a warning, not an error that stops setup, but good to flag
	fi

	# Check paths file
	if [ ! -f "$CONFIG_DIR/paths" ]; then
		echo "Error: Backup paths file missing: $CONFIG_DIR/paths" >&2
		errors=$((errors + 1))
	elif [ ! -s "$CONFIG_DIR/paths" ]; then
		echo "Error: Backup paths file is empty: $CONFIG_DIR/paths" >&2
		errors=$((errors + 1))
	fi

	if [ $errors -gt 0 ]; then
		error "Basic configuration checks failed. Please address the issues."
	else
		log "Basic configuration checks passed."
	fi
}

# --- Main Script Logic ---

# Parse arguments
if [ $# -ne 1 ] || [[ ! "$1" =~ ^--scope=(user|system)$ ]]; then
	echo "Usage: $0 --scope=<user|system>"
	echo "  --scope: Specify installation scope (user or system)."
	exit 1
fi
SCOPE="${1#*=}"

log "Configuring for $SCOPE scope"

# Check for required dependencies
log "Checking for required dependencies..."
check_dependencies
log "All dependencies found."

# --- Simplified Path Detection Logic (Phase 2, Step 2.2) ---
INSTALL_DIR=""
SYSTEMD_DIR=""
if [ "$SCOPE" == "system" ]; then
	CONFIG_DIR="/etc/restic"
	PASS_FILE="/root/.restic_password"
	ENV_FILE="/root/.restic_env"
	SYSTEMCTL_CMD="sudo systemctl"
	INSTALL_DIR="/usr/local/bin"
	SYSTEMD_DIR="/etc/systemd/system"
else # SCOPE == "user"
	CONFIG_DIR="$HOME/.config/restic"
	PASS_FILE="$CONFIG_DIR/password"
	ENV_FILE="$CONFIG_DIR/env"
	SYSTEMCTL_CMD="systemctl --user"
	INSTALL_DIR="$HOME/.local/bin"
	SYSTEMD_DIR="$HOME/.config/systemd/user"
fi

# Create configuration directories if they don't exist
log "Creating configuration directory: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR" || error "Failed to create config directory: $CONFIG_DIR"
log "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR" || error "Failed to create install directory: $INSTALL_DIR"
log "Creating systemd directory: $SYSTEMD_DIR"
mkdir -p "$SYSTEMD_DIR" || error "Failed to create systemd directory: $SYSTEMD_DIR"

# --- Interactive Input ---
log "Gathering configuration details..."

MEGA_EMAIL=""
while [ -z "$MEGA_EMAIL" ]; do
	read -rp "Enter your MEGA email address: " MEGA_EMAIL
	if [ -n "$MEGA_EMAIL" ]; then
		validate_email "$MEGA_EMAIL"
	fi
done

# For MEGA password, we'll prompt and write to a temporary file for rclone config
# This will be cleaned up after rclone config is done.
MEGA_TEMP_PASS_FILE=$(mktemp)
MEGA_PASSWORD=$(read_password "Enter your MEGA password (will not be displayed)")
echo
# Strip any trailing newlines/carriage returns from password
MEGA_PASSWORD=$(echo -n "$MEGA_PASSWORD" | tr -d '\n\r')
echo -n "$MEGA_PASSWORD" >"$MEGA_TEMP_PASS_FILE"
unset MEGA_PASSWORD # Clear password from shell history

# For Restic password, we'll prompt and write to the designated PASS_FILE
echo "----------------------------------------------------------------------------"
echo "IMPORTANT: Your Restic password encrypts ALL backup data."
echo "If you lose this password, your backups are PERMANENTLY UNRECOVERABLE."
echo "Please choose a strong password and STORE IT SAFELY (password manager, etc.)"
echo "----------------------------------------------------------------------------"
RESTIC_PASSWORD=$(read_password "Enter your Restic repository password (will not be displayed)")
echo
# Strip any trailing newlines/carriage returns from password
RESTIC_PASSWORD=$(echo -n "$RESTIC_PASSWORD" | tr -d '\n\r')
echo -n "$RESTIC_PASSWORD" >"$PASS_FILE"
log "Setting permissions for $PASS_FILE to 600"
chmod 600 "$PASS_FILE" || error "Failed to set permissions on password file."
unset RESTIC_PASSWORD # Clear password from shell history

# Gotify details (optional)
GOTIFY_URL=""
GOTIFY_TOKEN=""
read -rp "Enter your Gotify URL (no trailing slash, e.g. https://gotify.example.com, leave blank if not used): " GOTIFY_URL
if [ -n "$GOTIFY_URL" ]; then
	validate_url "$GOTIFY_URL"
	read -rp "Enter your Gotify Application Token: " GOTIFY_TOKEN
fi

# --- Call the functions with correct paths ---
configure_rclone "$MEGA_EMAIL" "$MEGA_TEMP_PASS_FILE"
# Clean up temporary MEGA password file
rm -f "$MEGA_TEMP_PASS_FILE"

# Define the restic repository path using the CONFIG_DIR for consistency
RESTIC_REPO="rclone:backup_remote:/restic_backups" # This path is fixed as per plan

initialize_restic_repo "$RESTIC_REPO" "$PASS_FILE"

create_default_config() {
	local config_dir="$1"
	local scope="$2"

	if [ ! -f "$config_dir/paths" ]; then
		if [ "$scope" = "system" ]; then
			cat >"$config_dir/paths" <<EOF
/etc
/home
/root
/var/lib/docker
/opt
EOF
		else
			cat >"$config_dir/paths" <<EOF
$HOME
EOF
		fi
		log "Created default paths file: $config_dir/paths"
	else
		log "Paths file already exists: $config_dir/paths"
	fi

	if [ ! -f "$config_dir/excludes" ]; then
		cat >"$config_dir/excludes" <<EOF
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
EOF
		log "Created default excludes file: $config_dir/excludes"
	else
		log "Excludes file already exists: $config_dir/excludes"
	fi
}

# --- Create paths and excludes files (basic versions) ---
log "Creating basic paths and excludes files..."
create_default_config "$CONFIG_DIR" "$SCOPE"

# --- Run basic configuration checks (moved after file creation) ---
check_basic_config

# --- Create environment file for Restic and Gotify ---
log "Creating environment file: $ENV_FILE with Restic and Gotify settings"
cat >"$ENV_FILE" <<EOF
RESTIC_REPOSITORY="$RESTIC_REPO"
RESTIC_PASSWORD_FILE="$PASS_FILE"
CONFIG_DIR="$CONFIG_DIR"
GOTIFY_URL="$GOTIFY_URL"
GOTIFY_TOKEN="$GOTIFY_TOKEN"
# Rclone throttling settings to prevent timeout issues during prune operations
RCLONE_TRANSFERS=1
RCLONE_CHECKERS=1
RCLONE_TIMEOUT=7200s
RCLONE_CONTIMEOUT=600s
RCLONE_LOW_LEVEL_RETRIES=20
RCLONE_BWLIMIT=1M
EOF
log "Setting permissions for $ENV_FILE to 600"
chmod 600 "$ENV_FILE" || error "Failed to set permissions on environment file."

# --- Install scripts and systemd units ---
log "Installing Restic scripts and Systemd units..."
# Copy scripts
log "Copying restic_backup.sh to $INSTALL_DIR/"
cp restic_backup.sh "$INSTALL_DIR/restic_backup.sh" || error "Failed to copy restic_backup.sh"
log "Copying restic_check.sh to $INSTALL_DIR/"
cp restic_check.sh "$INSTALL_DIR/restic_check.sh" || error "Failed to copy restic_check.sh"
log "Making scripts executable: $INSTALL_DIR/restic_backup.sh and $INSTALL_DIR/restic_check.sh"
chmod +x "$INSTALL_DIR/restic_backup.sh" "$INSTALL_DIR/restic_check.sh"

# Prepare systemd service files
# Use sed to replace the ExecStart path and add the environment variable
log "Generating systemd service file: $SYSTEMD_DIR/restic-backup.service"
sed -e "s|ExecStart=.*|ExecStart=$INSTALL_DIR/restic_backup.sh|" \
	-e "s|# Environment variable will be set by setup.sh based on scope|Environment=\"RESTIC_ENV_FILE=$ENV_FILE\"|" \
	systemd/restic-backup.service >"$SYSTEMD_DIR/restic-backup.service"
log "Generating systemd service file: $SYSTEMD_DIR/restic-check.service"
sed -e "s|ExecStart=.*|ExecStart=$INSTALL_DIR/restic_check.sh|" \
	-e "s|# Environment variable will be set by setup.sh based on scope|Environment=\"RESTIC_ENV_FILE=$ENV_FILE\"|" \
	systemd/restic-check.service >"$SYSTEMD_DIR/restic-check.service"

# Copy systemd timer files
log "Copying systemd timer file: $SYSTEMD_DIR/restic-backup.timer"
cp systemd/restic-backup.timer "$SYSTEMD_DIR/restic-backup.timer"
log "Copying systemd timer file: $SYSTEMD_DIR/restic-check.timer"
cp systemd/restic-check.timer "$SYSTEMD_DIR/restic-check.timer"

# Reload systemd daemon, enable and start timers
log "Reloading systemd daemon..."
$SYSTEMCTL_CMD daemon-reload || error "Failed to reload systemd daemon."
log "Enabling systemd timers: restic-backup.timer and restic-check.timer"
$SYSTEMCTL_CMD enable restic-backup.timer restic-check.timer || error "Failed to enable systemd timers."
log "Starting systemd timers: restic-backup.timer and restic-check.timer"
$SYSTEMCTL_CMD start restic-backup.timer restic-check.timer || error "Failed to start systemd timers."

log "Restic scripts and Systemd units installed and enabled."

log "Setup complete!"
echo "Configuration files are located in: $CONFIG_DIR"
echo "Restic password file: $PASS_FILE"
echo "Environment file: $ENV_FILE"
echo "Paths to backup: $CONFIG_DIR/paths"
echo "Excludes: $CONFIG_DIR/excludes"
echo "Systemd timers are enabled and started. You can check their status with:"
echo "  $SYSTEMCTL_CMD status restic-backup.timer restic-check.timer"
