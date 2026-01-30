# SCP Backup Addon - Documentation

Complete guide to installing, configuring, and troubleshooting the SCP Backup addon.

## Table of Contents

1. [SSH Setup](#ssh-setup)
2. [Configuration Reference](#configuration-reference)
3. [Usage Modes](#usage-modes)
4. [Example Configurations](#example-configurations)
5. [Troubleshooting](#troubleshooting)
6. [Security Recommendations](#security-recommendations)

## SSH Setup

### Generate SSH Key Pair

If you don't have an SSH key pair, generate one:

#### On Linux/macOS:
```bash
# Generate ed25519 key (recommended, modern and secure)
ssh-keygen -t ed25519 -f ~/.ssh/ha_backup -C "home-assistant-backup"

# Or use RSA (compatible with older systems)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/ha_backup -C "home-assistant-backup"
```

When prompted for passphrase, press Enter to skip (addon doesn't support passphrases).

#### On Windows (Git Bash, WSL, or PuTTY):
Follow the same steps as above in WSL/Git Bash, or use PuTTY key generator.

### Prepare Remote Server

1. Create a dedicated backup user (recommended):
   ```bash
   sudo useradd -m -s /bin/bash ha-backup
   ```

2. Setup authorized_keys:
   ```bash
   # As the backup user or with sudo
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   cat >> ~/.ssh/authorized_keys << 'EOF'
   [paste your public key here]
   EOF
   chmod 600 ~/.ssh/authorized_keys
   ```

3. Create backup directory:
   ```bash
   sudo mkdir -p /backup
   sudo chown ha-backup:ha-backup /backup
   chmod 755 /backup
   ```

4. Test connection:
   ```bash
   ssh -i ~/.ssh/ha_backup ha-backup@your-server "ls -la /backup"
   ```

### Add Key to Addon

1. Read your private key:
   ```bash
   cat ~/.ssh/ha_backup
   ```

2. Copy the entire output (including BEGIN and END lines)

3. In Home Assistant addon config, paste into `ssh_private_key` field

## Configuration Reference

### Required Settings

- **ssh_host** (string): Remote server hostname or IP address
  - Example: `backup.example.com` or `192.168.1.100`

- **ssh_user** (string): SSH username on remote server
  - Example: `ha-backup` or `backupuser`

- **ssh_private_key** (password): Complete SSH private key
  - Paste entire key including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines

### Basic Settings

- **ssh_port** (int, default: 22): SSH port on remote server
  - Range: 1-65535

- **remote_path** (string, default: `/backup`): Directory path on remote server
  - Must exist and be writable by SSH user
  - Example: `/mnt/backups/homeassistant`

- **transfer_timeout** (int, default: 300): Timeout in seconds for SCP operations
  - Range: 30-3600 seconds
  - Increase for slow connections or large files

### Transfer Mode

- **transfer_mode** (choice): How often to transfer backups
  - `manual`: Transfer when addon starts (runs once and stops)
  - `scheduled`: Transfer on a fixed schedule using cron

### Schedule Configuration (if transfer_mode is "scheduled")

- **schedule_cron** (string): Cron expression for scheduling
  - Format: `minute hour day month weekday`
  - Examples:
    - `0 2 * * *` - Daily at 2:00 AM
    - `0 3 * * 0` - Weekly on Sunday at 3:00 AM
    - `0 */6 * * *` - Every 6 hours
    - `30 1 * * *` - Daily at 1:30 AM

### Backup Creation

- **create_backup_before_transfer** (bool, default: false): Create new backup before transfer
  - If enabled, a fresh backup is created each time the addon runs
  - If disabled, transfers existing backups

- **backup_type** (choice, default: `full`): Type of backup to create
  - `full`: Complete Home Assistant backup (includes all data)
  - `partial`: Addon and config backups only (excludes media)

### Local Backup Retention

- **keep_local_backup** (bool, default: true): Keep or delete local backup after successful transfer
  - `true`: Keep backups locally (useful for redundancy)
  - `false`: Delete backup after confirmed transfer to remote

- **delete_after_days** (int, default: 0): Auto-delete old backups
  - `0`: Disabled (no automatic deletion)
  - `1-365`: Delete backups older than this many days
  - Only deletes if transfer was verified or keep_local_backup is true

### Transfer Options

- **verify_transfer** (bool, default: true): Verify backup arrived correctly
  - Compares local and remote file sizes
  - Keeps local backup if verification fails
  - Recommended: leave enabled

- **backup_name_prefix** (string, default: `hassio`): Prefix for created backups
  - Only used if `create_backup_before_transfer` is enabled
  - Example: `homeassistant`, `ha-backup`

### Logging

- **log_level** (choice, default: `info`): Verbosity of addon logs
  - `trace`: Most detailed (debug information)
  - `debug`: Detailed debug information
  - `info`: General informational messages
  - `notice`: Important notices
  - `warning`: Warnings and errors
  - `error`: Errors only
  - `fatal`: Only fatal errors

## Usage Modes

### Manual Mode

Addon transfers backups once when started, then stops.

**Configuration:**
```yaml
transfer_mode: "manual"
create_backup_before_transfer: false
```

**Workflow:**
1. Start addon → transfers existing backups → stops
2. Manually trigger from Home Assistant UI

**Use Case:** Ad-hoc backups, triggered when needed.

### Manual Mode with Backup Creation

Creates a fresh backup before transfer.

**Configuration:**
```yaml
transfer_mode: "manual"
create_backup_before_transfer: true
backup_type: "full"
```

**Workflow:**
1. Start addon → creates new backup → transfers → stops

**Use Case:** Ensure latest backup is transferred.

### Scheduled Mode

Addon runs continuously and transfers backups on a schedule.

**Configuration:**
```yaml
transfer_mode: "scheduled"
schedule_cron: "0 2 * * *"  # Daily at 2 AM
create_backup_before_transfer: true
```

**Workflow:**
1. Start addon → waits for scheduled time
2. At 2:00 AM daily → creates backup → transfers
3. Addon continues running, waits for next schedule

**Use Case:** Automatic daily/weekly backups to remote server.

## Example Configurations

### Example 1: Daily Auto-Backup to NAS

Daily backup to a NAS at 3 AM, keep local copy for one week.

```yaml
ssh_host: "192.168.1.100"
ssh_port: 22
ssh_user: "ha-backup"
ssh_private_key: "[paste your private key here]"
remote_path: "/mnt/backups/homeassistant"
transfer_mode: "scheduled"
schedule_cron: "0 3 * * *"
create_backup_before_transfer: true
backup_type: "full"
keep_local_backup: true
delete_after_days: 7
transfer_timeout: 300
verify_transfer: true
log_level: "info"
```

### Example 2: On-Demand Backup with Automatic Cleanup

Manual transfer with automatic cleanup after successful transfer.

```yaml
ssh_host: "backup.example.com"
ssh_port: 22
ssh_user: "homeassistant"
ssh_private_key: "[paste your private key here]"
remote_path: "/home/homeassistant/backups"
transfer_mode: "manual"
create_backup_before_transfer: true
backup_type: "full"
keep_local_backup: false
verify_transfer: true
transfer_timeout: 300
log_level: "debug"
```

### Example 3: Weekly Scheduled Backup

Transfer existing backups once per week, keep all local backups.

```yaml
ssh_host: "storage.company.local"
ssh_port: 2222
ssh_user: "backup-bot"
ssh_private_key: "[paste your private key here]"
remote_path: "/backups/ha-instance"
transfer_mode: "scheduled"
schedule_cron: "0 4 * * 0"
create_backup_before_transfer: false
keep_local_backup: true
delete_after_days: 0
transfer_timeout: 600
verify_transfer: true
log_level: "info"
```

### Example 4: Continuous Monitoring with Quick Cleanup

Transfer every 6 hours, delete local backups after successful transfer.

```yaml
ssh_host: "backup.local"
ssh_port: 22
ssh_user: "ha"
ssh_private_key: "[paste your private key here]"
remote_path: "/backup/homeassistant"
transfer_mode: "scheduled"
schedule_cron: "0 */6 * * *"
create_backup_before_transfer: true
backup_type: "full"
keep_local_backup: false
delete_after_days: 0
transfer_timeout: 300
verify_transfer: true
log_level: "notice"
```

## Troubleshooting

### SSH Connection Fails

**Error:** `SSH connection failed to user@host`

**Solutions:**
1. Verify SSH host and port are correct
2. Test manually:
   ```bash
   ssh -i ~/.ssh/ha_backup user@host "echo test"
   ```
3. Check firewall allows port 22 (or configured port)
4. Verify public key is in remote `~/.ssh/authorized_keys`
5. Increase `transfer_timeout` if network is slow

### Private Key Format Error

**Error:** `Failed to setup SSH` or key permission errors

**Solutions:**
1. Ensure private key is in PEM format (not putty format)
2. Check key includes `-----BEGIN PRIVATE KEY-----` header
3. Verify no extra whitespace at beginning/end
4. Check key isn't encrypted (addon doesn't support passphrases)
5. Generate new key without passphrase: `ssh-keygen -t ed25519 -N "" -f key`

### Transfer Fails with "File not found"

**Error:** `Backup file not found: /backup/{slug}.tar`

**Solutions:**
1. If `create_backup_before_transfer: false`, ensure backups exist in Home Assistant
2. Check Home Assistant has created backups (Settings → System → Backups)
3. If addon deletes backups after transfer, verify transfer completed successfully
4. Check transfer verification didn't fail (size mismatch)

### Remote Directory Not Found

**Error:** `Failed to create remote directory`

**Solutions:**
1. Verify SSH user has write permissions to parent directory
2. Test manually:
   ```bash
   ssh -i ~/.ssh/ha_backup user@host "mkdir -p /backup"
   ```
3. Ensure remote server has sufficient disk space
4. Check SSH user isn't in restricted shell

### Transfer Verification Fails

**Error:** `Verification failed: size mismatch`

**Solutions:**
1. Check remote server has enough disk space
2. Verify no other processes are modifying the file
3. Disable compression if network is very unreliable: modify main.sh
4. Increase `transfer_timeout`
5. Check network stability

### Cron Schedule Not Working

**Error:** Scheduled transfer doesn't run at expected time

**Solutions:**
1. Verify cron expression syntax (5 fields, separated by spaces)
2. Test cron format online: https://crontab.guru
3. Check addon logs for cron errors
4. Verify addon is running (not stopped)
5. Common mistake: Day of week vs day of month (use `*` for unused field)

### Addon Stops Unexpectedly

**Error:** Addon crashes or exits with no errors

**Solutions:**
1. Increase `log_level` to `debug` or `trace`
2. Check addon logs for error messages
3. Verify all required configuration is set
4. Test SSH connection manually
5. Check Home Assistant system logs

### Permission Denied on Remote

**Error:** `Permission denied` when creating directory or transferring

**Solutions:**
1. Verify SSH user owns/can write to remote_path
2. Check remote directory permissions: `ls -la /path`
3. Try explicit user/directory: `ssh user@host "mkdir -p /backup && ls -la /backup"`
4. Create directory manually on remote server
5. Run addon with more verbose logging

## Security Recommendations

### SSH Key Best Practices

1. **Use Ed25519 Keys**: Modern, smaller, more secure than RSA
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/ha_backup
   ```

2. **Dedicated SSH User**: Create backup-specific user account
   ```bash
   sudo useradd -m -s /bin/bash ha-backup
   ```

3. **Restrict Permissions**: Minimize remote user privileges
   - Create restricted shell (e.g., `rbash`)
   - Limit to specific directory
   - Consider restricting SCP command in `authorized_keys`

4. **Key Rotation**: Rotate keys periodically
   - Generate new key pair
   - Update remote `authorized_keys`
   - Update addon configuration

5. **Secure Storage**: Protect private key
   - Don't share or expose in logs
   - Home Assistant encrypts addon config
   - Keep local backups secure

### Network Security

1. **Use Non-Standard Port**: Use port other than 22
   ```yaml
   ssh_port: 2222
   ```

2. **Firewall Rules**: Restrict SSH access
   - Allow only from Home Assistant server IP
   - Use IP allowlists on remote server

3. **VPN/Private Network**: Use private network when possible
   - SSH over VPN is more secure
   - Private LAN is preferred over internet

### Remote Server Security

1. **SSH Configuration**: Harden SSH on remote server
   - Disable password auth: `PasswordAuthentication no`
   - Disable root login: `PermitRootLogin no`
   - Use key-only auth (recommended)

2. **Backup Directory**: Restrict access
   - Create dedicated backup user
   - Backup directory owned by that user
   - Restrict to 700 (only owner can access)

3. **Monitoring**: Log and monitor backups
   - Enable SSH logging
   - Monitor disk space
   - Set up alerts for transfer failures

### General Security

1. **Keep Addon Updated**: Check for security updates
2. **Use HTTPS**: If managing Home Assistant remotely
3. **Firewall**: Keep firewall enabled
4. **Backups**: Encrypt backups at rest on remote server
5. **Testing**: Regularly test backup restoration

## Support

For issues or feature requests:
- Check logs with increased log_level (debug/trace)
- Test SSH connection manually
- Verify configuration matches examples
- Check GitHub issues: https://github.com/pagubg/ha-addons/issues
