# Changelog

All notable changes to the Sprite Pipeline plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-09-14

### Added
- Pool mode works against sprite-pipeline-backend servers with protocol 2.0.0 or later: device login, quota, job submission with live progress, downloads and cancel.
- BYOK generates with OpenAI's gpt-image models: `gpt-image-2` (default), `gpt-image-1.5`, `gpt-image-1-mini` or any other model name, at `low`, `medium` (default) or `high` quality, always with a transparent background.
- Queue entries with `frame_w`/`frame_h` are cut into frames and scaled down to that size in both modes. Each sprite gets a compact sheet, one file per frame (`<name>/frame_<row>_<column>.png`) and the original 1024×1024 sheet (`<name>_raw.png`).
- BYOK builds the same prompt and post-processes the sheet the same way as the backend.
- `run_manifest.json` version 2 in both modes: paths relative to the output directory, frame and raw sheet paths, SHA-256 and a grid check per sprite.
- The dock shows the stage and percentage while generating, counts grid warnings in the results, and rescans the FileSystem dock after each generation.
- New settings: `[byok] image_model`, `[byok] image_quality`, `[pool] download_raw` (the **Download raw sheets** checkbox).
- `rows` queue field: rows of frames on the generated grid.
- Headless GDScript tests: `scripts/test.ps1` and `scripts/test.sh`.

### Changed
- Pool downloads are checked against the SHA-256 the server reports. Files that fail the check or the download are skipped and listed under `download_errors` in `run_manifest.json`, and such a result is not cached.
- Job polling retries a lost connection or a server error three times in a row before it gives up.
- The Pool cache stores files under their paths relative to the output directory (cache format v2), so frames with the same name no longer overwrite each other. An older cache is rebuilt automatically.
- The queue field for what to draw is `prompt`. `description` still works and is now also sent in Pool mode.
- In BYOK mode, entries without `frame_w`/`frame_h` keep the generated 1024×1024 sheet; frame sizes no longer only steer the prompt.
- The plugin and protocol versions live in `version.gd`; the protocol version sent to servers is 2.0.0.

### Removed
- DALL-E 3 in BYOK mode; OpenAI no longer offers it in the API.

### Fixed
- Pool login used the wrong device-login endpoints, took a pending authorization for a finished login, and misread the token lifetime, so every token looked expired.
- The quota display read its reset date from a field the server does not send.
- Error codes and messages in the server's error responses were lost; queue validation errors now show each problem.
- Logging in to Pool mode no longer disconnects the quota and generation handlers, so quota and results reach the dock after login.
- Pool tokens are restored when the editor restarts instead of being erased.
- The device-login verification link reads `verification_url` (falling back to `verification_uri`).
- Logging in with an empty or rejected server URL shows a clear message instead of "Failed to start request: 31".
- Saved settings pointing at the retired `sprites.pi-agents.dev` service are cleared on load.
- The remediation actions failed to compile.

### Security
- Asset paths returned by a Pool server are confined to the output directory. Previously a `../` path could overwrite project files, including editor scripts.
- Server URL validation parses the host: `http://localhost.example.com` is rejected, and plain HTTP is allowed only for localhost, loopback and private-network addresses.
- BYOK rejects `category` and `file_name` values that would write outside the output directory.

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
- Batch quota operations

---

## Version History

- **1.1.0** (2026-09-14): Pool mode on protocol 2.0.0, BYOK on gpt-image models, frame slicing
- **1.0.0** (2026-02-12): Initial public release
- **0.1.0** (2026-01-30): Internal beta release
