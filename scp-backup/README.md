# SCP Backup Addon

Automatically backup your Home Assistant configuration to a remote server via SCP (SSH). This addon supports both manual and scheduled transfers with SSH key authentication.

## Features

- **SSH Key Authentication**: Secure key-based authentication to remote servers
- **Manual & Scheduled Modes**: Trigger backups manually or on a fixed schedule
- **Automatic Backup Creation**: Optionally create backups before transfer
- **Transfer Verification**: Verify backups arrive correctly with size comparison
- **Local Backup Retention**: Control whether to keep or delete local backups after transfer
- **Comprehensive Logging**: Detailed logs for troubleshooting
- **Multi-Architecture**: Runs on aarch64, amd64, armhf, armv7, and i386

## Installation

1. Add this repository to Home Assistant:
   - Go to Settings → Add-ons → Add-on Store
   - Click the three-dot menu and select "Repositories"
   - Add: `https://github.com/pagubg/ha-addons`

2. Find "SCP Backup" in the Add-on Store and click Install

3. See [DOCS.md](DOCS.md) for configuration instructions

## Quick Start

1. Generate or obtain an SSH private key
2. Configure the addon with:
   - SSH host and credentials
   - Remote backup directory
   - Transfer mode (manual or scheduled)
3. Start the addon
4. Check logs to verify configuration

## Documentation

See [DOCS.md](DOCS.md) for:
- SSH key setup instructions
- Complete configuration reference
- Example configurations
- Troubleshooting guide
