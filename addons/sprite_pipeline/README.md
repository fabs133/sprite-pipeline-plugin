# Sprite Pipeline — Godot Plugin

A Godot 4.x editor plugin that generates sprites from text prompts using OpenAI's
image generation API.

![Status](https://img.shields.io/badge/status-archived-lightgrey) ![Version](https://img.shields.io/badge/version-1.0.0-blue) ![Godot](https://img.shields.io/badge/godot-4.2%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Status

**Archived.** Shipped at v1.0.0 in February 2026. The hosted Pool service that
backed shared-credit mode is no longer running. The plugin is published as an
engineering reference. Issues and PRs are not monitored.

## Operation Modes

The plugin supports two modes. **BYOK is the supported path** for the archived
release.

- **BYOK (Bring Your Own Key)** — your OpenAI API key is stored locally in
  `user://` and used to call OpenAI directly. No third-party server is involved.
  Implemented in [api/byok_client.gd](api/byok_client.gd).
- **Pool (shared credits)** — was originally backed by a hosted credit-and-billing
  service. That service has been retired. The Pool client still works against a
  self-hosted backend; see the `sprite-pipeline-backend` reference implementation
  (URL placeholder pending publication). Implemented in
  [api/api_client.gd](api/api_client.gd). The default `pool.server_url` setting
  still points at the original hosted instance and should be overridden in the
  plugin panel.

## Features

- **Smart caching** — local LRU cache (`user://sprite_pipeline/cache/`, 500 MB
  default) prevents duplicate generations.
- **Automatic import** — generated sprites are placed under your configured
  output root and picked up by Godot's importer.
- **Multiple styles** — Pixel Art, Cartoon, Flat Vector, Retro 8-bit, Watercolor,
  Realistic. Selectable globally or per-sprite.
- **Batch generation** — process JSON queue files producing multiple sprites in
  one run.
- **Multi-row spritesheets** — for directional animations (e.g., walk-down,
  walk-left, walk-right, walk-up in a single sheet).

## Installation

1. Copy this `addons/sprite_pipeline/` folder into your Godot project's
   `addons/` directory. (Or download a release zip from
   [Releases](https://github.com/fabs133/sprite-pipeline-plugin/releases) and
   extract it.)
2. **Project → Project Settings → Plugins** → enable "Sprite Pipeline".
3. The "Sprite Pipeline" panel appears at the bottom of the editor.

## Quick Start (BYOK)

1. Get an API key from <https://platform.openai.com/api-keys>.
2. Open the **Sprite Pipeline** panel.
3. Select the **BYOK Mode** tab.
4. Paste your key into **OpenAI API Key**.
5. Enter a prompt and click **Generate**.

The key is written to `user://sprite_pipeline_settings.cfg`, outside your project
folder, and is sent only to OpenAI's API.

## Pool Mode (self-hosted backend)

Pool mode requires a backend that implements the device-code OAuth flow and
credit/billing endpoints the plugin expects. The original hosted service is
offline; a reference backend implementation is available in the
`sprite-pipeline-backend` repository (URL placeholder pending publication).

To point the plugin at your own backend:

1. Open the Sprite Pipeline panel → **Pool Mode** tab.
2. Edit the **Server URL** field to your backend's base URL.
3. Click **Login with Device Code** and complete the flow in your browser.

## Configuration

| Setting | Purpose | Default |
|---|---|---|
| Output Root | Where generated sprites are saved | `res://assets/sprites` |
| Queue Path | JSON file with batch requests | (none) |
| Global Style | Default style applied to generations | Pixel Art |
| Cache Size | LRU cache budget | 500 MB |

Cache stats are shown in the panel; **Clear Cache** resets them.

## Usage Examples

### Single sprite

1. Open the Sprite Pipeline panel.
2. Choose mode (BYOK or Pool).
3. Enter a prompt: `"a blue slime character, pixel art style"`.
4. Set frame count and layout.
5. **Generate.** The sprite is written to your Output Root.

### Batch from JSON queue

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

Set **Queue Path** to your JSON and click **Generate**.

### Multi-row spritesheet

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

Pixel Art, Cartoon, Flat Vector, Retro 8-bit, Watercolor, Realistic. Selectable
via the Global Style dropdown or per-sprite in the JSON queue.

## Troubleshooting

### "Invalid API Key" (BYOK)

- Verify the key starts with `sk-` or `sk-proj-`.
- Check that the OpenAI account has credits.
- Test the key in the [OpenAI playground](https://platform.openai.com/playground).

### "Generation Failed" (Pool)

- Confirm the backend `Server URL` in the Pool tab points at a reachable instance.
- Check your internet connection.
- Try logging out and back in.

### "Output directory not writable"

- Ensure the Output Root path exists.
- Use `res://...` paths rather than absolute paths.

### Cached results look wrong

Open the panel → **Cache Stats** → **Clear Cache**.

### Plugin debug output

**Editor → Editor Settings → Network → Debug → HTTP Debug**, then watch the
**Output** panel for `[SpritePipeline]` messages.

## Security & Privacy

⚠️ **Never commit API keys to version control.**

### BYOK mode
- API key is stored in `user://sprite_pipeline_settings.cfg`, outside the
  project folder.
- The key is sent only to `https://api.openai.com`.

### Pool mode
- OAuth device flow — no password is entered.
- Access tokens are stored in `user://`.
- All backend calls use HTTPS.

Suggested `.gitignore` additions for projects using the plugin:

```
user://
.godot/
*.import
```

## Automation (CI/CD)

The plugin includes an HTTP automation server for headless generation:

```bash
export SPRITE_PIPELINE_AUTOMATION=1
godot --headless --enable-sprite-pipeline-automation

curl http://localhost:8765/generate -X POST -d '{
  "command": "generate",
  "queue_path": "res://sprites/queue.json",
  "output_root": "res://assets/sprites"
}'
```

## FAQ

**Q: How much does generation cost?**
A: BYOK passes through OpenAI's per-image pricing (~$0.04–0.10 per image at the
time of release; check current pricing). Pool mode pricing was set by the
hosted service and no longer applies.

**Q: Can I use this commercially?**
A: The plugin is MIT-licensed. Generated images are subject to OpenAI's terms.

**Q: What Godot versions are supported?**
A: Godot 4.2 and later. Godot 3.x is not supported.

**Q: Can I generate animations directly?**
A: The plugin generates spritesheets (multiple frames in one image). Slice and
animate them in Godot using `AnimatedSprite2D` or `AnimationPlayer`.

**Q: Where are my API keys stored?**
A: In `user://sprite_pipeline_settings.cfg`, outside the project folder, not
tracked by version control.

**Q: Can I plug in a different image generation model?**
A: Only OpenAI's image API is wired up. The relevant code is concentrated in
[api/byok_client.gd](api/byok_client.gd) and [api/api_client.gd](api/api_client.gd)
if you want to fork.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Built on the [Godot Engine](https://godotengine.org/) and OpenAI's image
generation API.
