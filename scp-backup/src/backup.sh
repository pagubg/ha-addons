#!/bin/bash
# Backup management functions

set -e

source /usr/local/bin/utils.sh

# Create a new backup via Supervisor API
create_new_backup() {
    local backup_type="${1:-full}"

    if [[ "$backup_type" != "full" && "$backup_type" != "partial" ]]; then
        log_error "Invalid backup type: $backup_type"
        return 1
    fi

    log_info "Creating new $backup_type backup..."

    local endpoint="/backups/new/${backup_type}"
    local response

    if ! response=$(call_supervisor_api "POST" "$endpoint" "{}"); then
        log_error "Failed to create backup"
        return 1
    fi

    local slug
    slug=$(echo "$response" | jq -r '.data.slug // empty')

    if [[ -z "$slug" ]]; then
        log_error "Failed to extract backup slug from response"
        log_debug "Response: $response"
        return 1
    fi

    log_info "Backup created successfully: $slug"

    # Store created backup slug for tracking
    echo "$slug" >> /data/addon_created_backups.txt

    echo "$slug"
}

# Get all backups from Supervisor API
get_all_backups() {
    log_debug "Fetching backup list..."

    local response
    if ! response=$(call_supervisor_api "GET" "/backups"); then
        log_error "Failed to fetch backup list"
        return 1
    fi

    local backups
    backups=$(echo "$response" | jq -r '.data.backups[]?.slug // empty')

    if [[ -z "$backups" ]]; then
        log_notice "No backups found"
        return 0
    fi

    echo "$backups"
}

# Get backup info
get_backup_info() {
    local slug="$1"

    if [[ -z "$slug" ]]; then
        log_error "Backup slug not provided"
        return 1
    fi

    log_debug "Fetching backup info: $slug"

    local response
    if ! response=$(call_supervisor_api "GET" "/backups/$slug/info"); then
        log_error "Failed to fetch backup info: $slug"
        return 1
    fi

    echo "$response"
}

# Delete a backup
delete_backup() {
    local slug="$1"

    if [[ -z "$slug" ]]; then
        log_error "Backup slug not provided"
        return 1
    fi

    log_info "Deleting backup: $slug"

    if ! call_supervisor_api "DELETE" "/backups/$slug" > /dev/null; then
        log_error "Failed to delete backup: $slug"
        return 1
    fi

    log_info "Backup deleted: $slug"
}

# Get addon-created backups from tracking file
get_addon_created_backups() {
    local tracking_file="/data/addon_created_backups.txt"

    if [[ ! -f "$tracking_file" ]]; then
        log_debug "No addon-created backups tracking file found"
        return 0
    fi

    cat "$tracking_file"
}

# Remove created backup from tracking file
remove_backup_from_tracking() {
    local slug="$1"
    local tracking_file="/data/addon_created_backups.txt"

    if [[ -f "$tracking_file" ]]; then
        # Remove the line containing this slug
        grep -v "^${slug}$" "$tracking_file" > "${tracking_file}.tmp" 2>/dev/null || true
        mv "${tracking_file}.tmp" "$tracking_file"
    fi
}

export -f create_new_backup get_all_backups get_backup_info
export -f delete_backup get_addon_created_backups remove_backup_from_tracking
