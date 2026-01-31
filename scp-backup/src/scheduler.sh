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

log_info "Scheduled transfer started"

if ! test_ssh_connection "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$TRANSFER_TIMEOUT"; then
    log_error "SSH connection test failed"
    exit 1
fi

if ! transfer_all_backups "$SSH_HOST" "$SSH_PORT" "$SSH_USER" "$REMOTE_PATH" "$TRANSFER_TIMEOUT" "$VERIFY_TRANSFER" "$KEEP_LOCAL_BACKUP"; then
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
