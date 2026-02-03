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

# Initialize tracking file for addon-created backups
mkdir -p /data
[[ ! -f /data/addon_created_backups.txt ]] && touch /data/addon_created_backups.txt

# Debug: Show configuration
log_debug "Configuration loaded:"
log_debug "  Transfer mode: $TRANSFER_MODE"
log_debug "  Create backup before transfer: $CREATE_BACKUP"
log_debug "  Backup type: $BACKUP_TYPE"
log_debug "  Keep local backup: $KEEP_LOCAL_BACKUP"
log_debug "  Verify transfer: $VERIFY_TRANSFER"

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
LINE_COUNT=$(echo "$SSH_KEY_RAW" | wc -l)
if [[ $LINE_COUNT -eq 1 ]]; then
    log_info "Detected single-line key format, reformatting..."

    # Extract base64 content using simple sed (BusyBox compatible)
    # Remove everything before and including the BEGIN line
    BASE64_CONTENT=$(echo "$SSH_KEY_RAW" | sed 's/.*-----BEGIN OPENSSH PRIVATE KEY-----//' | sed 's/-----END OPENSSH PRIVATE KEY-----.*//')

    # Trim whitespace
    BASE64_CONTENT=$(echo "$BASE64_CONTENT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Write properly formatted key
    cat > /root/.ssh/id_rsa << 'KEYEOF'
-----BEGIN OPENSSH PRIVATE KEY-----
KEYEOF
    echo "$BASE64_CONTENT" >> /root/.ssh/id_rsa
    cat >> /root/.ssh/id_rsa << 'KEYEOF'
-----END OPENSSH PRIVATE KEY-----
KEYEOF
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

    # Execute transfer and capture summary
    transfer_output=$(transfer_all_backups "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$REMOTE_PATH" \
                                           "$TRANSFER_TIMEOUT" "$VERIFY_TRANSFER" "$KEEP_LOCAL_BACKUP" "$DELETE_AFTER_DAYS" 2>&1)
    transfer_result=$?

    if [[ $transfer_result -ne 0 ]]; then
        log_error "Backup transfer failed"
        exit 1
    fi

    # Extract transfer summary
    transfer_success_count=$(echo "$transfer_output" | grep "^__SUCCESS_COUNT=" | cut -d'=' -f2)
    transfer_fail_count=$(echo "$transfer_output" | grep "^__FAIL_COUNT=" | cut -d'=' -f2)

    # Cleanup old backups if configured and capture summary
    cleanup_output=""
    cleanup_deleted_count=0
    if [[ "$DELETE_AFTER_DAYS" -gt 0 ]]; then
        cleanup_output=$(cleanup_local_backups "$DELETE_AFTER_DAYS" "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$REMOTE_PATH" "$TRANSFER_TIMEOUT" 2>&1)
        cleanup_deleted_count=$(echo "$cleanup_output" | grep "^__DELETED_COUNT=" | cut -d'=' -f2)
    fi

    # Print summary
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "BACKUP TRANSFER SUMMARY - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════════════════════════"
    echo "Transfer Mode: MANUAL"
    echo "Remote Server: ${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}"
    echo ""
    echo "Transfer Results:"
    echo "  Successful: ${transfer_success_count:-0}"
    echo "  Failed: ${transfer_fail_count:-0}"
    echo ""

    if [[ -n "$cleanup_deleted_count" && "$cleanup_deleted_count" -gt 0 ]]; then
        echo "Cleanup Results (Retention: $DELETE_AFTER_DAYS days):"
        echo "  Deleted: $cleanup_deleted_count backup(s)"
        echo ""
    fi

    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    log_info "Manual backup transfer completed successfully"
    exit 0
fi
