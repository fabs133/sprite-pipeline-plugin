# Changelog

All notable changes to the Sprite Pipeline plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-12

### Added
- **Initial Public Release** 🎉
- BYOK mode (Bring Your Own Key) with direct OpenAI API integration
- Pool mode with shared credit system via sprite-pipeline.com
- Device code OAuth flow for secure authentication
- Local sprite cache with LRU eviction (max 500 MB)
- Support for 6 generation styles: Pixel Art, Cartoon, Flat Vector, Retro 8-bit, Watercolor, Realistic
- Batch generation from JSON queue files
- Multi-row spritesheet support for directional animations
- Automatic sprite import into Godot projects
- Cache statistics display with manual clear option
- HTTP automation server for CI/CD integration (dev mode)
- Comprehensive error handling and user feedback
- Remediation actions for common issues (cache clear, auth reset)

### Security
- Input validation for server URLs (HTTPS enforcement)
- Path validation to prevent directory traversal
- Job ID sanitization
- Secure token storage in `user://` directory
- API keys never committed to version control

### Performance
- Smart caching prevents duplicate API calls
- Idempotency keys for safe retries
- Quota caching (5-minute TTL) to reduce API load
- Efficient binary sprite storage

### Developer Experience
- Debug output using `print_debug()` (only in debug builds)
- Detailed logging for troubleshooting
- Clear error messages with actionable remediation
- Automation-friendly HTTP API

### Documentation
- Comprehensive README with quick start guide
- Security best practices
- Troubleshooting section
- API automation documentation
- Code comments and inline documentation

### Known Limitations
- Automation server is dev-only (not recommended for production)
- No offline mode (requires internet for generation)
- OpenAI API key must be provided by user in BYOK mode
- Generated images are 1024×1024 from OpenAI (resized as needed)

### Technical Details
- **Plugin Version**: 1.0.0
- **Protocol Version**: 1
- **Minimum Godot**: 4.2
- **Supported Platforms**: Windows, Linux, macOS
- **License**: MIT

## [Unreleased]

### Security
- Asset paths returned by a Pool server are confined to the output directory. Previously a `../` path could overwrite project files, including editor scripts.
- Server URL validation parses the host: `http://localhost.example.com` is rejected, and plain HTTP is allowed only for localhost, loopback and private-network addresses.

### Fixed
- Logging in to Pool mode no longer disconnects the quota and generation handlers, so quota and results reach the dock after login.
- Pool tokens are restored when the editor restarts instead of being erased.
- The device-login verification link reads `verification_url` (falling back to `verification_uri`).
- Logging in with an empty or rejected server URL shows a clear message instead of "Failed to start request: 31".
- Saved settings pointing at the retired `sprites.pi-agents.dev` service are cleared on load.

### Planned Features
- Sprite animation preview in editor
- Custom model support (non-OpenAI)
- Bulk sprite operations (batch delete, batch reimport)
- Style presets and favorites
- Project-level style configuration
- Integration with Godot's asset importer
- Visual prompt builder
- Generation history browser
- Sprite pack bundles

### Potential Improvements
- Reduce plugin binary size
- Improve cache eviction strategy
- Add sprite thumbnail preview
- Support for transparent backgrounds
- Batch quota operations

---

## Version History

- **1.0.0** (2026-02-12): Initial public release
- **0.1.0** (2026-01-30): Internal beta release
