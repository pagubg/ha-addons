#!/bin/bash
# Utility functions for SCP Backup addon

set -e

# Logging wrappers
log_debug() {
    echo "[DEBUG] $*" >&2
}

log_info() {
    echo "[INFO] $*"
}

log_notice() {
    echo "[NOTICE] $*"
}

log_warning() {
    echo "[WARNING] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_fatal() {
    echo "[FATAL] $*" >&2
}

# Get supervisor token
get_supervisor_token() {
    # Debug: Check what's available
    log_debug "Checking for Supervisor token..."
    log_debug "Checking /run/secrets/SUPERVISOR_TOKEN: $(test -f /run/secrets/SUPERVISOR_TOKEN && echo 'EXISTS' || echo 'NOT FOUND')"
    log_debug "Checking /run/secrets directory: $(test -d /run/secrets && echo 'EXISTS' || echo 'NOT FOUND')"
    if [[ -d /run/secrets ]]; then
        log_debug "Contents of /run/secrets:"
        ls -la /run/secrets/ 2>&1 | while read line; do log_debug "  $line"; done
    fi
    log_debug "Checking SUPERVISOR_TOKEN env var: $(test -n "$SUPERVISOR_TOKEN" && echo 'SET' || echo 'NOT SET')"

    # Try file first (standard location)
    if [[ -f /run/secrets/SUPERVISOR_TOKEN ]]; then
        log_debug "Using token from /run/secrets/SUPERVISOR_TOKEN"
        cat /run/secrets/SUPERVISOR_TOKEN
        return 0
    fi

    # Try environment variable
    if [[ -n "$SUPERVISOR_TOKEN" ]]; then
        log_debug "Using token from SUPERVISOR_TOKEN environment variable"
        echo "$SUPERVISOR_TOKEN"
        return 0
    fi

    # Token not available
    log_fatal "Supervisor token not found"
    log_fatal "Checked: /run/secrets/SUPERVISOR_TOKEN (file) and \$SUPERVISOR_TOKEN (env var)"
    log_fatal "The addon configuration has hassio_api: true, but Supervisor isn't providing the token"
    log_fatal "Try: 1) Restart the addon  2) Reinstall the addon  3) Restart Home Assistant Supervisor"
    return 1
}

# Call Supervisor API
call_supervisor_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local token
    if ! token=$(get_supervisor_token); then
        log_error "Cannot call Supervisor API - token unavailable"
        return 1
    fi

    if [[ -z "$token" ]]; then
        log_error "Supervisor token is empty"
        return 1
    fi

    local url="http://supervisor${endpoint}"
    local curl_args=(
        -s
        -X "$method"
        -H "Authorization: Bearer $token"
        -H "Content-Type: application/json"
    )

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    log_debug "API call: $method $endpoint"
    if ! response=$(curl "${curl_args[@]}" "$url" 2>&1); then
        log_error "API call failed: $method $endpoint"
        log_error "Response: $response"
        return 1
    fi

    echo "$response"
}

# Get file size (local)
get_file_size() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    stat -c%s "$file"
}

# Format bytes to human-readable
format_bytes() {
    local bytes=$1
    if ((bytes < 1024)); then
        echo "${bytes}B"
    elif ((bytes < 1048576)); then
        echo "$((bytes / 1024))KB"
    elif ((bytes < 1073741824)); then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# Test SSH connection
test_ssh_connection() {
    local host="$1"
    local port="$2"
    local user="$3"
    local timeout="$4"

    log_info "Testing SSH connection to ${user}@${host}:${port}"

    if ! ssh -o ConnectTimeout="$timeout" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -p "$port" \
            "${user}@${host}" "echo 'SSH connection successful'" 2>/dev/null; then
        log_error "SSH connection failed to ${user}@${host}:${port}"
        return 1
    fi

    log_info "SSH connection successful"
    return 0
}

# Get remote file size via SSH
get_remote_file_size() {
    local host="$1"
    local port="$2"
    local user="$3"
    local file="$4"
    local timeout="$5"

    if ! size=$(ssh -o ConnectTimeout="$timeout" \
                     -o StrictHostKeyChecking=no \
                     -o UserKnownHostsFile=/dev/null \
                     -p "$port" \
                     "${user}@${host}" \
                     "stat -c%s '$file'" 2>/dev/null); then
        log_error "Failed to get remote file size: $file"
        return 1
    fi

    echo "$size"
}

export -f log_debug log_info log_notice log_warning log_error log_fatal
export -f get_supervisor_token call_supervisor_api
export -f get_file_size format_bytes
export -f test_ssh_connection get_remote_file_size
