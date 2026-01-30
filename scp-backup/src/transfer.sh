#!/bin/bash
# SCP transfer functions

set -e

source /usr/local/bin/utils.sh

# Transfer a single backup via SCP
transfer_backup() {
    local slug="$1"
    local remote_host="$2"
    local remote_port="$3"
    local remote_user="$4"
    local remote_path="$5"
    local timeout="$6"
    local verify="${7:-true}"

    local local_file="/backup/${slug}.tar"

    if [[ ! -f "$local_file" ]]; then
        log_error "Backup file not found: $local_file"
        return 1
    fi

    local local_size
    local_size=$(get_file_size "$local_file")
    local size_formatted
    size_formatted=$(format_bytes "$local_size")

    log_info "Transferring backup: $slug ($size_formatted)"

    if ! scp -o Compression=yes \
             -o ConnectTimeout="$timeout" \
             -o ServerAliveInterval=60 \
             -o ServerAliveCountMax=3 \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -P "$remote_port" \
             "$local_file" \
             "${remote_user}@${remote_host}:${remote_path}/" 2>&1; then
        log_error "Failed to transfer backup: $slug"
        return 1
    fi

    log_info "Backup transferred successfully: $slug"

    if [[ "$verify" == "true" ]]; then
        if ! verify_transfer "$slug" "$remote_host" "$remote_port" "$remote_user" "$remote_path" "$timeout"; then
            log_error "Transfer verification failed for: $slug"
            return 1
        fi
    fi

    return 0
}

# Verify transfer by comparing file sizes
verify_transfer() {
    local slug="$1"
    local remote_host="$2"
    local remote_port="$3"
    local remote_user="$4"
    local remote_path="$5"
    local timeout="$6"

    local local_file="/backup/${slug}.tar"
    local remote_file="${remote_path}/${slug}.tar"

    log_debug "Verifying transfer for: $slug"

    local local_size
    local_size=$(get_file_size "$local_file")

    local remote_size
    if ! remote_size=$(get_remote_file_size "$remote_host" "$remote_port" "$remote_user" "$remote_file" "$timeout"); then
        log_error "Verification failed: could not read remote file size"
        return 1
    fi

    if [[ "$local_size" -ne "$remote_size" ]]; then
        log_error "Verification failed: size mismatch - local: $local_size, remote: $remote_size"
        return 1
    fi

    log_info "Transfer verified successfully: $slug ($(format_bytes "$local_size"))"
    return 0
}

# Transfer all available backups
transfer_all_backups() {
    local remote_host="$1"
    local remote_port="$2"
    local remote_user="$3"
    local remote_path="$4"
    local timeout="$5"
    local verify="${6:-true}"
    local keep_local="${7:-true}"
    local delete_after_days="${8:-0}"

    log_info "Starting backup transfer..."

    # Create remote directory if needed
    log_debug "Ensuring remote directory exists: $remote_path"
    if ! ssh -o ConnectTimeout="$timeout" \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -p "$remote_port" \
             "${remote_user}@${remote_host}" \
             "mkdir -p '$remote_path'" 2>/dev/null; then
        log_error "Failed to create remote directory: $remote_path"
        return 1
    fi

    local backups
    if ! backups=$(get_all_backups); then
        return 1
    fi

    if [[ -z "$backups" ]]; then
        log_notice "No backups to transfer"
        return 0
    fi

    local success_count=0
    local fail_count=0

    while IFS= read -r slug; do
        [[ -z "$slug" ]] && continue

        if transfer_backup "$slug" "$remote_host" "$remote_port" "$remote_user" "$remote_path" "$timeout" "$verify"; then
            ((success_count++))

            # Delete local backup if configured and transfer was successful and verified
            if [[ "$keep_local" != "true" && "$verify" == "true" ]]; then
                delete_backup "$slug" || log_warning "Failed to delete backup: $slug"
            fi
        else
            ((fail_count++))
            log_warning "Backup transfer failed: $slug (keeping local copy)"
        fi
    done <<< "$backups"

    log_info "Transfer complete - Success: $success_count, Failed: $fail_count"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi

    return 0
}

# Cleanup old local backups
cleanup_local_backups() {
    local delete_after_days="$1"

    if [[ "$delete_after_days" -le 0 ]]; then
        log_debug "Local backup cleanup disabled"
        return 0
    fi

    log_info "Cleaning up backups older than $delete_after_days days..."

    local backups
    if ! backups=$(get_all_backups); then
        return 1
    fi

    [[ -z "$backups" ]] && return 0

    local deleted_count=0

    while IFS= read -r slug; do
        [[ -z "$slug" ]] && continue

        local file="/backup/${slug}.tar"
        if [[ ! -f "$file" ]]; then
            continue
        fi

        local file_time
        file_time=$(stat -c%Y "$file")
        local current_time
        current_time=$(date +%s)
        local age_days=$(( (current_time - file_time) / 86400 ))

        if [[ $age_days -gt $delete_after_days ]]; then
            if delete_backup "$slug"; then
                ((deleted_count++))
            fi
        fi
    done <<< "$backups"

    log_info "Cleanup complete - Deleted: $deleted_count backups"
    return 0
}

export -f transfer_backup verify_transfer transfer_all_backups cleanup_local_backups
