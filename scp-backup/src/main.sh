#!/bin/bash
# SCP Backup addon main entry point

set -e

source /usr/local/bin/utils.sh
source /usr/local/bin/backup.sh
source /usr/local/bin/transfer.sh
source /usr/local/bin/scheduler.sh

# Load configuration from /data/options.json
echo "Loading configuration..."

# Use jq to read config, with defaults
CONFIG_FILE="${CONFIG_FILE:-/data/options.json}"
[[ ! -f "$CONFIG_FILE" ]] && CONFIG_FILE="/tmp/options.json"

SSH_HOST=$(jq -r '.ssh_host // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
SSH_PORT=$(jq -r '.ssh_port // 22' "$CONFIG_FILE" 2>/dev/null || echo "22")
SSH_USER=$(jq -r '.ssh_user // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
SSH_PRIVATE_KEY=$(jq -r '.ssh_private_key // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
REMOTE_PATH=$(jq -r '.remote_path // "/backup"' "$CONFIG_FILE" 2>/dev/null || echo "/backup")
TRANSFER_MODE=$(jq -r '.transfer_mode // "manual"' "$CONFIG_FILE" 2>/dev/null || echo "manual")
SCHEDULE_CRON=$(jq -r '.schedule_cron // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
CREATE_BACKUP=$(jq -r '.create_backup_before_transfer // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
BACKUP_TYPE=$(jq -r '.backup_type // "full"' "$CONFIG_FILE" 2>/dev/null || echo "full")
TRANSFER_TIMEOUT=$(jq -r '.transfer_timeout // 300' "$CONFIG_FILE" 2>/dev/null || echo "300")
VERIFY_TRANSFER=$(jq -r '.verify_transfer // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
KEEP_LOCAL_BACKUP=$(jq -r '.keep_local_backup // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
DELETE_AFTER_DAYS=$(jq -r '.delete_after_days // 0' "$CONFIG_FILE" 2>/dev/null || echo "0")

# Validate required configuration
if [[ -z "$SSH_HOST" || -z "$SSH_USER" || -z "$SSH_PRIVATE_KEY" ]]; then
    log_error "Missing required configuration: ssh_host, ssh_user, ssh_private_key"
    exit 1
fi

# Setup SSH
echo "[INFO] Setting up SSH configuration..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Read the key from JSON
SSH_KEY_RAW=$(jq -r '.ssh_private_key' "$CONFIG_FILE")

# Check if key is single-line (Home Assistant UI often strips newlines)
if [[ $(echo "$SSH_KEY_RAW" | wc -l) -eq 1 ]]; then
    log_info "Detected single-line key format, reformatting..."

    # Extract components
    BEGIN_LINE=$(echo "$SSH_KEY_RAW" | grep -o '^-----BEGIN[^-]*-----')
    END_LINE=$(echo "$SSH_KEY_RAW" | grep -o '-----END[^-]*-----$')

    # Extract base64 content (everything between BEGIN and END)
    BASE64_CONTENT=$(echo "$SSH_KEY_RAW" | sed 's/^-----BEGIN[^-]*-----\s*//' | sed 's/\s*-----END[^-]*-----$//')

    # Write properly formatted key
    cat > /root/.ssh/id_rsa << EOF
$BEGIN_LINE
$BASE64_CONTENT
$END_LINE
EOF
else
    # Key already has proper newlines
    echo "$SSH_KEY_RAW" > /root/.ssh/id_rsa
fi

chmod 600 /root/.ssh/id_rsa

# Debug output
echo "[DEBUG] Key file info:"
ls -lh /root/.ssh/id_rsa
echo "[DEBUG] First line: $(head -1 /root/.ssh/id_rsa)"
echo "[DEBUG] Last line: $(tail -1 /root/.ssh/id_rsa)"
echo "[DEBUG] Total lines: $(wc -l < /root/.ssh/id_rsa)"

# Validate key
if ! ssh-keygen -y -f /root/.ssh/id_rsa >/dev/null 2>&1; then
    log_error "SSH private key validation failed"
    log_error "The key file has been written to /root/.ssh/id_rsa"
    log_error "Please check the key format in your Home Assistant configuration"
    exit 1
fi
echo "[INFO] SSH key validated successfully"

# Create SSH config
cat > /root/.ssh/config << EOF
Host backup-server
    HostName ${SSH_HOST}
    Port ${SSH_PORT}
    User ${SSH_USER}
    IdentityFile /root/.ssh/id_rsa
    ConnectTimeout ${TRANSFER_TIMEOUT}
    ServerAliveInterval 60
    ServerAliveCountMax 3
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

chmod 600 /root/.ssh/config

echo "[INFO] SSH configuration complete"

# Handle transfer modes
if [[ "$TRANSFER_MODE" == "scheduled" ]]; then
    # Scheduled mode - setup cron and run daemon
    if [[ -z "$SCHEDULE_CRON" ]]; then
        log_fatal "Schedule mode selected but schedule_cron not provided"
        exit 1
    fi

    log_info "Running in SCHEDULED mode"
    setup_scheduler "$SCHEDULE_CRON"
else
    # Manual mode - execute transfer once and exit
    log_info "Running in MANUAL mode"

    # Test SSH connection
    if ! test_ssh_connection "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$TRANSFER_TIMEOUT"; then
        log_error "SSH connection test failed - aborting transfer"
        exit 1
    fi

    # Create new backup if requested
    if [[ "$CREATE_BACKUP" == "true" ]]; then
        log_info "Creating new backup before transfer..."
        if ! new_slug=$(create_new_backup "$BACKUP_TYPE"); then
            log_error "Failed to create backup"
            exit 1
        fi
        log_info "New backup created: $new_slug"
    fi

    # Execute transfer
    if ! transfer_all_backups "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$REMOTE_PATH" \
                               "$TRANSFER_TIMEOUT" "$VERIFY_TRANSFER" "$KEEP_LOCAL_BACKUP" "$DELETE_AFTER_DAYS"; then
        log_error "Backup transfer failed"
        exit 1
    fi

    # Cleanup old backups if configured
    if [[ "$DELETE_AFTER_DAYS" -gt 0 ]]; then
        cleanup_local_backups "$DELETE_AFTER_DAYS"
    fi

    log_info "Manual backup transfer completed successfully"
    exit 0
fi
