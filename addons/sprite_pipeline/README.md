# Sprite Pipeline - Godot Plugin

AI-powered sprite generation directly in the Godot Editor using OpenAI's image generation models.

![Version](https://img.shields.io/badge/version-1.0.0-blue) ![Godot](https://img.shields.io/badge/godot-4.2%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

🎨 **Two Operation Modes:**
- **BYOK Mode** (Bring Your Own Key): Use your own OpenAI API key for direct generation
- **Pool Mode**: Use shared credits via [sprite-pipeline.com](https://sprite-pipeline.com) (no OpenAI account needed)

💾 **Smart Caching**: Local cache system prevents duplicate generations and saves API costs

📦 **Automatic Import**: Generated sprites are automatically imported into your Godot project

🎭 **Multiple Styles**: Support for Pixel Art, Cartoon, Flat Vector, Retro 8-bit, Watercolor, and Realistic styles

⚡ **Batch Generation**: Process multiple sprites at once from JSON queue files

## Installation

### Option 1: From Godot Asset Library (Recommended)

1. Open your Godot project
2. Click on the **AssetLib** tab at the top
3. Search for "**Sprite Pipeline**"
4. Click **Download** → **Install**
5. Enable the plugin: **Project → Project Settings → Plugins** → Enable "Sprite Pipeline"

### Option 2: Manual Installation

1. Download the latest release from [GitHub Releases](https://github.com/fabs133/sprite-pipeline-plugin/releases)
2. Extract the `addons/sprite_pipeline/` folder to your project's `addons/` directory
3. Enable the plugin: **Project → Project Settings → Plugins** → Enable "Sprite Pipeline"
4. Restart Godot

### Option 3: From itch.io (Full Version)

Purchase the full version with premium support from [itch.io](https://fabs133.itch.io/sprite-pipeline-godot)

## Quick Start

### BYOK Mode (Bring Your Own Key)

1. Get an OpenAI API key from https://platform.openai.com/api-keys
2. Open the **Sprite Pipeline** panel at the bottom of the Godot Editor
3. Select **"BYOK Mode"** tab
4. Paste your API key in the **"OpenAI API Key"** field
5. Click **"Generate"** to create your first sprite!

**Note**: Your API key is stored securely in `user://` and never leaves your machine except to call OpenAI directly.

### Pool Mode (Shared Credits)

1. Sign up for a free account at https://sprite-pipeline.com
2. Open the **Sprite Pipeline** panel
3. Select **"Pool Mode"** tab
4. Click **"Login with Device Code"**
5. A browser will open - authorize the plugin
6. Return to Godot and start generating with credits!

**Pricing**: Get 100 free credits on signup. 1 credit = 1 sprite generation.

## Configuration

### Output Settings

- **Output Root**: Where generated sprites are saved (default: `res://assets/sprites`)
- **Queue Path**: JSON file with batch generation requests
- **Global Style**: Default style applied to all generations (can be overridden per-sprite)

### Cache Settings

The plugin includes a local cache to avoid regenerating identical sprites:

- **Location**: `user://sprite_pipeline/cache/`
- **Max Size**: 500 MB (configurable)
- **Behavior**: Automatic LRU eviction when full

**Cache Stats** are shown in the plugin panel. Use **"Clear Cache"** button to reset.

## Usage Examples

### Single Sprite Generation

1. Open the Sprite Pipeline panel
2. Choose your mode (BYOK or Pool)
3. Enter a prompt: `"a blue slime character, pixel art style"`
4. Set frame count and layout
5. Click **Generate**
6. Sprite appears in your Output Root directory

### Batch Generation with JSON Queue

Create a `queue.json` file:

```json
{
  "queue": [
    {
      "file_name": "hero_walk",
      "category": "character",
      "prompt": "knight walking animation",
      "frames": 4,
      "layout": "row"
    },
    {
      "file_name": "enemy_slime",
      "category": "monster",
      "prompt": "green slime enemy",
      "frames": 2,
      "layout": "row"
    }
  ]
}
```

Set **Queue Path** to your JSON file and click **Generate**.

### Multi-Row Spritesheets

Generate spritesheets with multiple rows (e.g., for directional animations):

```json
{
  "file_name": "hero_directional",
  "category": "character",
  "frames": 4,
  "rows": 4,
  "layout": "grid",
  "row_descriptions": [
    {"type": "custom", "prompt": "walking down"},
    {"type": "custom", "prompt": "walking left"},
    {"type": "custom", "prompt": "walking right"},
    {"type": "custom", "prompt": "walking up"}
  ]
}
```

## Supported Styles

- **Pixel Art**: Retro 8-bit/16-bit style
- **Cartoon**: Clean, bold outlines
- **Flat Vector**: Modern, minimalist design
- **Retro 8-bit**: Classic video game aesthetic
- **Watercolor**: Artistic, painted look
- **Realistic**: Photo-realistic rendering

Set via **Global Style** dropdown or per-sprite in JSON queue.

## Troubleshooting

### "Invalid API Key" (BYOK Mode)

- Verify your key starts with `sk-` or `sk-proj-`
- Check that your OpenAI account has available credits
- Test the key at https://platform.openai.com/playground

### "Generation Failed" (Pool Mode)

- Check your internet connection
- Verify you have available credits at sprite-pipeline.com
- Try logging out and back in

### "Output directory not writable"

- Ensure the Output Root path exists
- Check that you have write permissions
- Try using `res://` paths instead of absolute paths

### Clear Cache

If generations are returning unexpected cached results:

1. Open Sprite Pipeline panel
2. Scroll to **Cache Stats** section
3. Click **Clear Cache** button
4. Try generating again

### Check Plugin Logs

Enable debug output:
1. **Editor → Editor Settings → Network → Debug → HTTP Debug**
2. Check the **Output** panel for `[SpritePipeline]` messages

## Security & Privacy

⚠️ **NEVER commit your API keys to version control**

### BYOK Mode
- API keys stored in `user://sprite_pipeline_settings.cfg` (not tracked by Git)
- Keys never leave your machine (sent directly to OpenAI)
- Add `user://` to `.gitignore` for safety

### Pool Mode
- Uses OAuth device flow (no password entry)
- Access tokens stored securely in `user://`
- All API calls use HTTPS

**Best Practice**: Add this to your `.gitignore`:
```
# Sprite Pipeline user data
user://
.godot/
*.import
```

## API & Automation

The plugin supports automation via HTTP commands for CI/CD pipelines:

```bash
# Enable automation mode
export SPRITE_PIPELINE_AUTOMATION=1

# Start Godot headless
godot --headless --enable-sprite-pipeline-automation

# Send generation command
curl http://localhost:8765/generate -X POST -d '{
  "command": "generate",
  "queue_path": "res://sprites/queue.json",
  "output_root": "res://assets/sprites"
}'
```

See [automation documentation](https://github.com/fabs133/sprite-pipeline-plugin/wiki/Automation) for details.

## FAQ

**Q: How much does it cost?**

A: BYOK mode costs whatever OpenAI charges (~$0.04-0.10 per image). Pool mode is $10 for 100 credits (100 images).

**Q: Can I use this commercially?**

A: Yes! The plugin is MIT licensed. Check OpenAI's terms for generated image usage.

**Q: What Godot versions are supported?**

A: Godot 4.2 and later. Godot 3.x is not supported.

**Q: Can I generate animations?**

A: The plugin generates spritesheets (multiple frames in one image). You'll need to slice and animate them in Godot using AnimationPlayer or AnimatedSprite.

**Q: Where are my API keys stored?**

A: In `user://sprite_pipeline_settings.cfg`. This is outside your project folder and not tracked by version control.

**Q: Can I use my own image generation model?**

A: Currently only OpenAI models are supported. Contact us if you need custom model support.

## Support

- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/fabs133/sprite-pipeline-plugin/issues)
- 📧 **Email**: support@sprite-pipeline.com
- 💬 **Discord**: [Join our community](https://discord.gg/sprite-pipeline)
- 📚 **Documentation**: [Full wiki](https://github.com/fabs133/sprite-pipeline-plugin/wiki)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Godot Engine](https://godotengine.org/)
- Powered by [OpenAI](https://openai.com/)
- Inspired by the amazing Godot community

---

**Made with ❤️ by [fabs133](https://github.com/fabs133)**

If you find this plugin useful, consider [buying me a coffee](https://ko-fi.com/fabs133) ☕
