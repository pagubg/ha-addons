# Changelog

All notable changes to the SCP Backup addon are documented in this file.

## [1.0.12] - 2026-02-24

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
