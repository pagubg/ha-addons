#!/bin/bash
# Scheduler setup functions

set -e

source /usr/local/bin/utils.sh

# Setup cron scheduling
setup_scheduler() {
    local schedule_cron="$1"

    if [[ -z "$schedule_cron" ]]; then
        log_error "Schedule cron expression not provided"
        return 1
    fi

    log_info "Setting up scheduled transfer: $schedule_cron"

    # Validate cron expression (basic check)
    if ! echo "$schedule_cron" | grep -qE '^(\*|([0-9]|1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9])|\*/[0-9]+|\*-[0-9]+)(,(\*|([0-9]|1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9])|\*/[0-9]+|\*-[0-9]+))* (\*|([0-9]|1[0-9]|2[0-3])|\*/[0-9]+|\*-[0-9]+)(,(\*|([0-9]|1[0-9]|2[0-3])|\*/[0-9]+|\*-[0-9]+))* (\*|([1-9]|[12][0-9]|3[01])|\*/[0-9]+|\*-[0-9]+)(,(\*|([1-9]|[12][0-9]|3[01])|\*/[0-9]+|\*-[0-9]+))* (\*|([1-9]|1[012])|\*/[0-9]+|\*-[0-9]+)(,(\*|([1-9]|1[012])|\*/[0-9]+|\*-[0-9]+))* (\*|([0-6])|\*/[0-9]+|\*-[0-9]+)(,(\*|([0-6])|\*/[0-9]+|\*-[0-9]+))*'; then
        log_warning "Cron expression validation is basic - please verify format: $schedule_cron"
    fi

    # Create wrapper script that reads config from file
    cat > /usr/local/bin/run-transfer.sh << 'EOF'
#!/bin/bash
source /usr/local/bin/utils.sh
source /usr/local/bin/backup.sh
source /usr/local/bin/transfer.sh

# Initialize tracking file
mkdir -p /data
[[ ! -f /data/addon_created_backups.txt ]] && touch /data/addon_created_backups.txt

# Load configuration from file
CONFIG_FILE="${CONFIG_FILE:-/data/options.json}"
[[ ! -f "$CONFIG_FILE" ]] && CONFIG_FILE="/tmp/options.json"

SSH_HOST=$(jq -r '.ssh_host // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
SSH_PORT=$(jq -r '.ssh_port // 22' "$CONFIG_FILE" 2>/dev/null || echo "22")
SSH_USER=$(jq -r '.ssh_user // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
REMOTE_PATH=$(jq -r '.remote_path // "/backup"' "$CONFIG_FILE" 2>/dev/null || echo "/backup")
TRANSFER_TIMEOUT=$(jq -r '.transfer_timeout // 300' "$CONFIG_FILE" 2>/dev/null || echo "300")
VERIFY_TRANSFER=$(jq -r '.verify_transfer // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
KEEP_LOCAL_BACKUP=$(jq -r '.keep_local_backup // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
DELETE_AFTER_DAYS=$(jq -r '.delete_after_days // 0' "$CONFIG_FILE" 2>/dev/null || echo "0")
BACKUP_TYPE=$(jq -r '.backup_type // "full"' "$CONFIG_FILE" 2>/dev/null || echo "full")
CREATE_BACKUP=$(jq -r '.create_backup_before_transfer // true' "$CONFIG_FILE" 2>/dev/null || echo "true")

log_info "Scheduled transfer started at $(date '+%Y-%m-%d %H:%M:%S')"

if ! test_ssh_connection "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$TRANSFER_TIMEOUT"; then
    log_error "SSH connection test failed"
    exit 1
fi

# Create new backup if configured
if [[ "$CREATE_BACKUP" == "true" ]]; then
    log_info "Creating new backup before transfer..."
    if ! new_slug=$(create_new_backup "$BACKUP_TYPE"); then
        log_error "Failed to create backup"
        exit 1
    fi
    log_info "New backup created: $new_slug"
fi

# Execute transfer
transfer_output=$(transfer_all_backups "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$REMOTE_PATH" "$TRANSFER_TIMEOUT" "$VERIFY_TRANSFER" "$KEEP_LOCAL_BACKUP" "$DELETE_AFTER_DAYS" 2>&1)
transfer_result=$?

# Extract transfer summary
transfer_success_count=$(echo "$transfer_output" | grep "^__SUCCESS_COUNT=" | cut -d'=' -f2)
transfer_fail_count=$(echo "$transfer_output" | grep "^__FAIL_COUNT=" | cut -d'=' -f2)

# Cleanup old backups if configured
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
echo "Transfer Mode: SCHEDULED"
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

if [[ $transfer_result -ne 0 ]]; then
    log_error "Scheduled transfer failed"
    exit 1
fi

log_info "Scheduled transfer completed successfully"
EOF

    chmod +x /usr/local/bin/run-transfer.sh

    # Setup crontab
    local crontab_file="/etc/crontabs/root"
    mkdir -p "$(dirname "$crontab_file")"

    echo "$schedule_cron /usr/local/bin/run-transfer.sh >> /proc/1/fd/1 2>&1" > "$crontab_file"
    chmod 600 "$crontab_file"

    log_info "Cron schedule configured: $schedule_cron"

    # Start cron daemon in foreground
    log_info "Starting cron daemon..."
    exec crond -f -l 2
}

export -f setup_scheduler
