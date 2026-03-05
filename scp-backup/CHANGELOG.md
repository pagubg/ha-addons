# Changelog

All notable changes to the SCP Backup addon are documented in this file.

## [1.0.14] - 2026-03-05

### Fixed

- **Local backup retention now works correctly**: slugs are kept in `addon_created_backups.txt` after a successful transfer instead of being removed immediately, so `cleanup_local_backups` can find them later
- **Remote as source of truth for local cleanup**: `cleanup_local_backups` now SSH-checks that `${prefix}_${slug}.tar` exists on the remote server before deleting the local copy; backups not yet transferred are never deleted locally
- **Orphaned tracking entries cleaned up automatically**: if a slug is in the tracking file but the local file no longer exists, the entry is removed silently (housekeeping)

### Changed

- `cleanup_local_backups` signature extended with remote connection parameters (`remote_host`, `remote_port`, `remote_user`, `remote_path`, `prefix`, `timeout`)
- `transfer_all_backups` is now idempotent: before each SCP call it checks whether `${prefix}_${slug}.tar` already exists on the remote and skips re-transfer if so
- Local cleanup and remote cleanup only run when at least one transfer succeeded in the current run (`transfer_success_count > 0` guard)
- When `keep_local_backup=false`, the slug is removed from tracking immediately after the local file is deleted (both on first transfer and on already-transferred skips)

## [1.0.13] - 2026-02-24

### Added

- Remote backup retention: files on the remote server older than `delete_after_days` are now automatically deleted via SSH `find`, scoped safely to the configured prefix pattern (`${prefix}_*.tar`)
- `cleanup_remote_backups` function handles remote-side cleanup independently on every run

### Changed

- Backup files are now renamed on the remote server to `${backup_name_prefix}_${slug}.tar` (e.g. `hassio_abc123.tar`), making prefix-based cleanup safe and unambiguous
- `backup_name_prefix` option is now actively used for remote filenames (was defined in config but previously ignored)
- Transfer verification (`verify_transfer`) now uses the actual local file path and the prefixed remote path, fixing a pre-existing bug where both were hardcoded to `${slug}.tar`
- `cleanup_local_backups` simplified: no longer attempts (broken) remote deletion; remote cleanup is now handled by `cleanup_remote_backups`
- Summary log now reports local and remote deleted counts separately

### Removed

- `delete_remote_backup` function removed (superseded by `cleanup_remote_backups`)

## [1.0.0] - 2026-01-30

### Added

- Initial release of SCP Backup addon
- SSH key-based authentication for remote server access
- Manual backup transfer mode for on-demand backups
- Scheduled transfer mode with cron expression support
- Automatic backup creation before transfer (optional)
- Transfer verification with local/remote file size comparison
- Configurable local backup retention policies
- Age-based automatic backup cleanup
- Comprehensive logging with configurable verbosity
- Support for multiple architectures (aarch64, amd64, armhf, armv7, i386)
- Multi-language documentation and troubleshooting guide
- GitHub Actions CI/CD for automated builds
- Complete configuration schema with validation
