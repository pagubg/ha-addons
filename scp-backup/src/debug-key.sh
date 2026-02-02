#!/bin/bash
# Debug script to check SSH key storage in Home Assistant

CONFIG_FILE="${CONFIG_FILE:-/data/options.json}"
[[ ! -f "$CONFIG_FILE" ]] && CONFIG_FILE="/tmp/options.json"

echo "=== SSH Key from Home Assistant Config ==="
echo "Config file: $CONFIG_FILE"
echo ""

echo "1. Raw JSON value (first 100 chars):"
jq -r '.ssh_private_key' "$CONFIG_FILE" 2>/dev/null | head -c 100
echo "..."
echo ""

echo "2. Key length:"
jq -r '.ssh_private_key' "$CONFIG_FILE" 2>/dev/null | wc -c
echo ""

echo "3. Check for escaped newlines:"
jq -r '.ssh_private_key' "$CONFIG_FILE" 2>/dev/null | grep -o '\\n' | wc -l
echo "escaped newlines found"
echo ""

echo "4. First line of key:"
jq -r '.ssh_private_key' "$CONFIG_FILE" 2>/dev/null | head -1
echo ""

echo "5. Last line of key:"
jq -r '.ssh_private_key' "$CONFIG_FILE" 2>/dev/null | tail -1
echo ""

echo "=== Hex dump of stored key (first 200 bytes) ==="
jq -r '.ssh_private_key' "$CONFIG_FILE" 2>/dev/null | xxd | head -10
