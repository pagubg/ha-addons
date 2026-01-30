#!/bin/bash
# SCP Backup addon main entry point

set -e

source /usr/local/bin/utils.sh
source /usr/local/bin/backup.sh
source /usr/local/bin/transfer.sh
source /usr/local/bin/scheduler.sh

# Load configuration from /data/options.json
bashio::log.info "Loading configuration..."

SSH_HOST=$(bashio::config 'ssh_host')
SSH_PORT=$(bashio::config 'ssh_port')
SSH_USER=$(bashio::config 'ssh_user')
SSH_PRIVATE_KEY=$(bashio::config 'ssh_private_key')
REMOTE_PATH=$(bashio::config 'remote_path')
TRANSFER_MODE=$(bashio::config 'transfer_mode')
SCHEDULE_CRON=$(bashio::config 'schedule_cron // empty')
CREATE_BACKUP=$(bashio::config 'create_backup_before_transfer')
BACKUP_TYPE=$(bashio::config 'backup_type // "full"')
TRANSFER_TIMEOUT=$(bashio::config 'transfer_timeout')
VERIFY_TRANSFER=$(bashio::config 'verify_transfer')
KEEP_LOCAL_BACKUP=$(bashio::config 'keep_local_backup')
DELETE_AFTER_DAYS=$(bashio::config 'delete_after_days // 0')
LOG_LEVEL=$(bashio::config 'log_level // "info"')

# Validate required configuration
if [[ -z "$SSH_HOST" || -z "$SSH_USER" || -z "$SSH_PRIVATE_KEY" ]]; then
    log_fatal "Missing required configuration: ssh_host, ssh_user, ssh_private_key"
    exit 1
fi

# Setup SSH
bashio::log.info "Setting up SSH configuration..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Write private key
echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa

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

log_info "SSH configuration complete"

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
