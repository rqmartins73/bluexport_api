# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (future changes go here)

## [1.12.0] - 2026-08-04

### Added (`bluexport_api.sh`)
- `job_monitor`'s poll waits (queued/running/still-running/transient-retry) now show a spinner with a countdown on an interactive terminal, so a long capture/export doesn't look stuck during the 30-60s waits between status checks. Falls back to a plain `sleep` (no control characters) when output isn't a tty, so log files and IBM i batch/spool output are unaffected.

## [1.11.0] - 2026-08-04

### Fixed (`bluexport_api.sh`)
- `-a`/`-j` job monitoring loop (`job_monitor`) could abort a healthy, in-progress capture/export because the IBM Cloud IAM access token (fetched once at startup, ~3600s TTL) expired mid-poll. The resulting 401 response has no `.status.state` field, which the old code treated as "no job running" and aborted on immediately.

### Added (`bluexport_api.sh`)
- IAM token retrieval extracted into `get_iam_token()`, now called proactively every 45 minutes from inside `job_monitor` (and reactively on any HTTP 401 from `job_get`) so long-running jobs never hit an expired token
- `job_monitor` now tolerates transient `job_get` failures (network errors, non-2xx HTTP, unparsable JSON) with up to 10 retries at 30s intervals before aborting, instead of aborting on the first bad response
- `job_get` now sets connection/max-time timeouts and surfaces the HTTP status code to the caller

## [1.10.2] - 2026-05-11

### Fixed
- `-vsisrcmon`: Added detection for UNKNOWN status during monitoring. When VSI enters UNKNOWN status (e.g., during shutdown while monitoring START, or other abnormal states), monitoring now terminates with an appropriate message indicating the LPAR/VSI is not starting (START mode) or not shutting down properly (SHUTOFF mode)

## [1.10.1] - 2026-05-05

### Fixed (`bluexport_api.sh`)
- `-vsistart` error message incorrectly referenced the flag as `-startvsi`
- Config file missing message used `$bluexscrt` (not yet loaded at that point) instead of `$conf_file`, resulting in an empty variable in the output
- "Iniciating Job Monitorization" corrected to "Initiating Job Monitoring"

### Fixed (`bluexscrt_config_api.sh`)
- Tool name throughout the file was `bluexscrt_config.api` (dot notation) instead of `bluexscrt_config_api.sh`
- Copyright year range was `2025-2025`; corrected to `2025-2026`
- `usage()` and `-createconfig` wizard referred to `bluexport_conf.json`; correct name is `bluexport_api_conf.json`
- END marker for `get_base_url_for_workspace` function was mistakenly written as START

### Changed (`bluexport_api.sh`)
- Help and header comment for `-a` / `-x`: clarified that `hourly` and `daily` are only valid with `image-catalog`; documented `-ta` / `-tx` test mode inline
- Help for `-snapcr` and `-snapupd`: explained meaning of `0` placeholder for optional arguments
- Help for `-vclonedel`: clarified behaviour of `0` (keep cloned volumes) vs `delete_volumes` (also delete cloned volumes)
- Help for `-vclone`: `STORAGE_TIER` replaced with explicit `tier0|tier1|tier3|tier5k` (distinct from `-vchtier` which accepts `0|1|3|5k`)
- Help for `-bucketlsobjs` and `-bucketdelobj`: marked as interactive (guided selection)
- Help for `-restorefromarchive`: documented all `ARCHIVE_TYPE` options (Bulk | Standard | Accelerated) and default values
- Help for `-grscancelfailover`: rewritten for clarity ("resync from master to aux, reactivate master→aux replication")
- Help for `-vsistart`: "IPL VSI" expanded to "IPL/Start VSI" with inline note
- `-imgimport` parameter renamed from `HMACKEYS-JSON-FILE-PATH-NAME` to `HMAC_JSON_FILE` in help, header comment, and README
- `README.md`: added `-insvchtier` command and `TIER_TO_CHANGE_TO` values to Volume Tier section
- `README.md`: `-vclone` usage updated to show explicit tier values
- `CHANGELOG.md`: "Acelerated" typo corrected to "Accelerated" (two occurrences in help and header)

### Changed (`bluexscrt_config_api.sh`)
- `usage()`: expanded `-v` description; added `-h | --help` entry; clarified that `-createconfig` also discovers COS instances; clarified `-addlpar` `WORKSPACE_SHORT` parameter; documented that `-updlpars` also refreshes `cos_instances`
- Added `-h | --help` to the `case` dispatcher (previously fell through to `*` with exit 1)

## [1.10.0] - 2026-04-28

### Added
- `-imgimport` flag to import images from IBM Cloud Object Storage into a PowerVS workspace image catalog using the native `/cos-images` API
- Support for explicit COS bucket region (`BUCKET_REGION`) to correctly target COS endpoints during image import
- Support for explicit imported image name using `IMGNAME_WS`
- Support for image import storage tier selection: `tier0`, `tier1`, `tier3`, `tier5k`
- Support for current-account and cross-account COS image import using `CURRACCOUNT|OTHERACCOUNT`
- HMAC JSON parsing for cross-account imports using IBM Cloud COS Service Credentials format: `.cos_hmac_keys.access_key_id` and `.cos_hmac_keys.secret_access_key`
- Validation of HMAC JSON structure with explicit error handling for invalid COS credentials
- Help text explaining how to obtain HMAC keys from IBM Cloud COS Service Credentials

- Professional repository structure with `.gitignore`, `CONTRIBUTING.md`, and `CHANGELOG.md`
- Issue and pull request templates
- `.editorconfig` for consistent code formatting
- Example configuration files in `examples/` directory
- Badges in README for license, version, and maintenance status

## [1.9.0] - 2025-03-30

### Added
- VSI operations: start, boot mode, operating mode, and task execution
- SRC monitoring for IBM i systems
- Volume attach/detach operations by common name
- Enhanced error handling and logging

### Changed
- Improved API rate limiting handling with exponential backoff
- Enhanced GRS operations with better safety checks
- Updated documentation with more examples

### Fixed
- Rate limiting issues in high-frequency operations
- Error handling in snapshot restore operations

## [1.2.0] - 2025-01-15

### Added
- `bluexscrt_config_api.sh` - Interactive configuration generator
- Support for multiple PowerVS workspaces
- Automatic workspace discovery via API
- LPAR management commands (`-addlpar`, `-dellpar`, `-updlpars`)

### Changed
- Configuration file format to JSON for better structure
- Improved secrets management

## [1.0.0] - 2024-12-01

### Added
- Initial release of bluexport_api.sh
- VSI lifecycle operations (start, stop, monitor)
- Snapshot management (create, update, delete, restore)
- Captured images management (list, delete)
- Volume clones (create, delete, list)
- Volume tier changes
- GRS (Global Replication Services) orchestration
- IBM i operational tasks support
- Cloud Object Storage (COS) integration
- Multi-workspace support
- Comprehensive logging system
- API-driven automation without IBM Cloud CLI dependency

### Features
- **Snapshots**: Full lifecycle management with multi-workspace awareness
- **Volume Clones**: Create and manage clones with tiered storage support
- **GRS Operations**: Volume group creation, onboarding, and deletion
- **VSI Operations**: Boot modes, operating modes, and IBM i tasks
- **COS Integration**: Bucket and object management
- **Monitoring**: SRC monitoring and job tracking

---

## Version History Summary

- **1.10.x**: Image import from COS, repository improvements, help and bug fixes
- **1.9.x**: VSI operations and enhanced monitoring
- **1.2.x**: Configuration management improvements
- **1.0.x**: Initial release with core functionality

---

## Migration Notes

### Upgrading to 1.10.0

No breaking changes. New features are additive.

### Upgrading to 1.9.0

No breaking changes. New features are additive.

### Upgrading to 1.2.0

**Configuration File Changes:**
- Old format: Shell variables in `bluexscrt` file
- New format: JSON structure in `bluexscrt_*.json`
- Use `bluexscrt_config_api.sh -createconfig` to generate new format

**Migration Steps:**
1. Backup existing configuration
2. Run `./bluexscrt_config_api.sh -createconfig`
3. Populate with your existing values
4. Test with non-production resources
5. Update automation scripts to use new config path

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this project.

---

## Support

For issues, questions, or contributions:
- **Issues**: https://github.com/rqmartins73/bluexport_api/issues
- **Email**: ricardo.martins@bluechip.pt
- **Documentation**: See [README.md](README.md)

---

[Unreleased]: https://github.com/rqmartins73/bluexport_api/compare/v1.10.1...HEAD
[1.10.1]: https://github.com/rqmartins73/bluexport_api/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.2.0...v1.9.0
[1.2.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/rqmartins73/bluexport_api/releases/tag/v1.0.0