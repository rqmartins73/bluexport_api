# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (future changes go here)

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

- **1.10.x**: Image import from COS and repository improvements
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

[Unreleased]: https://github.com/rqmartins73/bluexport_api/compare/v1.10.0...HEAD
[1.10.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.2.0...v1.9.0
[1.2.0]: https://github.com/rqmartins73/bluexport_api/compare/v1.0.0...v1.2.0
[1.0.0]: https://github.com/rqmartins73/bluexport_api/releases/tag/v1.0.0