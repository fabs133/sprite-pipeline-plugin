# Sprite Pipeline - Godot Plugin

[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://github.com/fabs133/sprite-pipeline-plugin/releases)
[![Godot](https://img.shields.io/badge/godot-4.2%2B-blue)](https://godotengine.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

AI-powered sprite generation directly in the Godot Editor using OpenAI's image generation models.

## 📦 Installation

### From Godot Asset Library
1. Open Godot → AssetLib tab
2. Search for "Sprite Pipeline"
3. Download → Install
4. Enable in Project Settings → Plugins

### From GitHub Releases
1. Download the latest `sprite-pipeline-v*.zip` from [Releases](https://github.com/fabs133/sprite-pipeline-plugin/releases)
2. Extract to your project's `addons/` folder
3. Enable in Project Settings → Plugins

### From itch.io
Purchase and download from [itch.io](https://fabs133.itch.io/sprite-pipeline-godot)

## 📖 Documentation

Full documentation is available in the plugin's README: [addons/sprite_pipeline/README.md](addons/sprite_pipeline/README.md)

### Quick Links
- [Features](addons/sprite_pipeline/README.md#features)
- [Quick Start Guide](addons/sprite_pipeline/README.md#quick-start)
- [Configuration](addons/sprite_pipeline/README.md#configuration)
- [Troubleshooting](addons/sprite_pipeline/README.md#troubleshooting)
- [Changelog](addons/sprite_pipeline/CHANGELOG.md)

## 🚀 Features

- **Two Operation Modes**: BYOK (your OpenAI key) or Pool (shared credits)
- **Smart Caching**: Prevents duplicate generations
- **Batch Processing**: Generate multiple sprites from JSON
- **Multiple Styles**: Pixel Art, Cartoon, Flat Vector, Retro 8-bit, Watercolor, Realistic
- **Auto Import**: Sprites automatically appear in your project

## 🛠️ Development

### Building from Source

```bash
# Development build
./scripts/build.sh dev 1.0.0-alpha
# or
.\scripts\build.ps1 -Mode dev -Version 1.0.0-alpha

# Production build
./scripts/build.sh prod 1.0.0
# or
.\scripts\build.ps1 -Mode prod -Version 1.0.0
```

### Validation

```bash
# Standard validation
.\scripts\validate.ps1

# Strict validation (for production)
.\scripts\validate.ps1 -Strict
```

### GitHub Actions

This repository includes automated workflows:
- **Validate**: Runs on every push/PR
- **Build Dev**: Creates pre-releases from `develop` branch
- **Build Prod**: Creates releases from version tags (e.g., `v1.0.0`)

## 📄 License

MIT License - see [LICENSE](LICENSE)

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 💬 Support

- 🐛 [GitHub Issues](https://github.com/fabs133/sprite-pipeline-plugin/issues)
- 📧 Email: support@sprite-pipeline.com
- 💬 [Discord](https://discord.gg/sprite-pipeline)

---

**Made with ❤️ by [fabs133](https://github.com/fabs133)**
