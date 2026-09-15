# Sprite Pipeline — Godot Plugin

A Godot 4.x editor plugin that generates sprite sheets from text prompts with
OpenAI's image models, either with your own API key or through a
sprite-pipeline-backend server.

![Status](https://img.shields.io/badge/status-archived-lightgrey) ![Version](https://img.shields.io/badge/version-1.1.0-blue) ![Godot](https://img.shields.io/badge/godot-4.2%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Status

**Archived.** Shipped at v1.0.0 in February 2026. Version 1.1.0 (September 2026)
ports Pool mode to protocol 2.0.0 of sprite-pipeline-backend and moves BYOK to
OpenAI's gpt-image models. The hosted Pool service that backed shared-credit mode
in 1.0.0 is no longer running. The plugin is published as an engineering
reference. Issues and PRs are not monitored.

## Operation Modes

- **BYOK (Bring Your Own Key)** — your OpenAI API key is stored locally in
  `user://` and used to call OpenAI's Images API directly (`gpt-image-2` by
  default). No third-party server is involved. Implemented in
  [api/byok_client.gd](api/byok_client.gd).
- **Pool (shared credits)** — the queue runs as a job on a sprite-pipeline-backend
  server with protocol 2.0.0 or later. You log in with a device code and use that
  server's credits. Implemented in [api/pool_client.gd](api/pool_client.gd); see
  [Pool Mode](#pool-mode). The **Server URL** field is empty by default.

Both modes build the same prompt and process the generated sheet the same way.

## Features

- **Batch generation** — every entry in a [queue file](#queue-file) becomes one
  sprite sheet.
- **Frames** — give an entry `frame_w` and `frame_h`, and the generated sheet is
  cut into frames, each scaled down to that size and saved as a compact sheet and
  as single frame files. See [Output](#output).
- **Grid check** — sprites that spill across cell boundaries are counted as grid
  warnings in the results.
- **Automatic import** — files are written under your output directory together
  with a `run_manifest.json`, the FileSystem dock is rescanned after each run, and
  the generated PNGs are imported lossless without mipmaps.
- **SpriteFrames** — every animated sheet gets a `SpriteFrames` resource, ready
  for an `AnimatedSprite2D`.
- **Pixel-art filtering** — the dock offers to set the project's default texture
  filter to Nearest. See
  [What the Plugin Writes into Your Project](#what-the-plugin-writes-into-your-project).
- **Progress** — the dock shows the current stage and percentage.
- **Local cache (Pool mode)** — results are cached in `user://sprite_cache/`
  (500 MB by default) so identical requests are not generated twice.
- **Error reporting** — copy an error summary or export a sanitized bug report
  from the dock.

## Installation

1. Copy this `addons/sprite_pipeline/` folder into your Godot project's
   `addons/` directory. (Or download a release zip from
   [Releases](https://github.com/fabs133/sprite-pipeline-plugin/releases) and
   extract it.)
2. **Project → Project Settings → Plugins** → enable "Sprite Pipeline".
3. The "Sprite Pipeline" dock appears in the upper-right dock area of the editor.

## Quick Start (BYOK)

1. Get an API key from <https://platform.openai.com/api-keys>.
2. In the **Sprite Pipeline** dock, click **BYOK (Own Key)**.
3. Paste your key into **OpenAI API Key**.
4. Pick an **Image Model** and **Image Quality** (see [BYOK Models](#byok-models)).
5. Create a [queue file](#queue-file) at `res://sprites/sprite_queue.yaml`, or
   point **Queue File** at your own.
6. Adjust **Global Style** if needed and click **Generate Sprites**.

The key is written to `user://sprite_pipeline_settings.cfg`, outside your project
folder, and is sent only to OpenAI's API.

## BYOK Models

| Image Model | Notes |
|---|---|
| `gpt-image-2` | Default |
| `gpt-image-1.5` | |
| `gpt-image-1-mini` | Lower cost |
| Custom... | Any other Images API model name |

**Image Quality** is `low`, `medium` (default) or `high`. Higher quality costs more
per image; see OpenAI's pricing page for current prices. Every image is requested
at 1024×1024 with a transparent background. When OpenAI rate-limits a request
(HTTP 429), it is retried up to three times.

## Queue File

The queue is a flat YAML list. A line starting with `- ` begins a new sprite, and
the `key: value` lines after it belong to that sprite. Only this subset is parsed:
nested lists and maps are not supported, JSON is not accepted, and `#` comments
must be on their own line.

```yaml
- file_name: hero_walk.png
  category: characters
  prompt: knight walking animation
  frames: 4
  frame_w: 64
  frame_h: 64
  layout: row
- file_name: enemy_slime.png
  category: monsters
  prompt: green slime enemy
  frames: 2
  layout: row
```

| Field | Meaning | Default |
|---|---|---|
| `file_name` | Output file name | `sprite.png` |
| `category` | Subfolder under the output directory | `misc` |
| `prompt` | What to draw; `description` works too | `file_name` without `.png`, `_` as spaces |
| `frames` | Frames per row | `1` |
| `rows` | Rows of frames | `1` |
| `frame_w`, `frame_h` | Size of each output frame; turns on slicing | not set |
| `layout` | `row` or `grid`; recorded in the manifest | `row` |

The image is generated as an N×N grid on a 1024×1024 canvas, where N is the larger
of `frames` and `rows`; cells beyond `frames` and `rows` stay empty.

### Output

For the `hero_walk.png` entry above, which sets `frame_w` and `frame_h`:

| File | Content |
|---|---|
| `characters/hero_walk.png` | Compact sheet: `frames × frame_w` wide, `rows × frame_h` high |
| `characters/hero_walk/frame_<row>_<column>.png` | One file per frame |
| `characters/hero_walk_raw.png` | The generated 1024×1024 sheet |
| `characters/hero_walk.tres` | `SpriteFrames` for the sheet, written in the editor (see [below](#spriteframes-resources)) |

Frames are scaled down with nearest-neighbour sampling and never scaled up. An
entry without `frame_w`/`frame_h`, like `enemy_slime.png`, is saved as the
generated 1024×1024 sheet. In Pool mode the `_raw.png` file is downloaded only
when **Download raw sheets** is on.

`run_manifest.json` (version 2) lists every sprite with its paths relative to the
output directory, the SHA-256 of its sheet and `grid_violation`, plus an `errors`
list for sprites that failed.

## Pool Mode

Pool mode needs a sprite-pipeline-backend server with protocol 2.0.0 or later.

### Server URL

Enter the server's base URL in **Server URL**: your own backend (for example
`http://localhost:8000` when it runs on your machine) or the FabsLabs backend,
`https://api.fabslabssprites.com`. The URL must use `https://`; plain `http://` is
accepted only for `localhost`, `127.x.x.x` and private-network addresses (`10.x`,
`172.16.x`–`172.31.x`, `192.168.x`).

### Logging In

1. In the Sprite Pipeline dock, click **Pool (Shared)** and enter the **Server URL**.
2. Click **Login with Device Code**. The dock shows a code and a link to the
   server's verification page.
3. Open the page, request a sign-in link for your email address, open the link
   and enter the code shown in the dock.

The dock then shows your remaining units and the reset date. Tokens are saved to
`user://sprite_pipeline_settings.cfg` and restored when the editor restarts. Saved
settings that still point at the retired hosted service (`sprites.pi-agents.dev`)
are cleared on load.

### Generating

**Generate Sprites** submits the queue as a job and follows it until it finishes;
the progress bar shows the server's percentage. **Cancel** cancels the job on the
server. Each file is downloaded and checked against the SHA-256 the server
reports. Files that fail the check are skipped and listed under `download_errors`
in `run_manifest.json`. If the server can't be reached while the job runs, the
plugin retries three times before it gives up.

## What the Plugin Writes into Your Project

Besides the generated files, the plugin changes up to three things in your project
after each generation in the editor. They run after the results are shown; if one
fails, the error is in the **Output** panel and the results stay.

### Project texture filter (asks first)

Godot filters 2D textures linearly by default, which blurs pixel art when it is
scaled up. If the project's default texture filter is neither Nearest nor Nearest
Mipmap, the dock asks whether to set **Project Settings → Rendering → Textures →
Canvas Textures → Default Texture Filter** to Nearest.

- **Set to Nearest** writes `textures/canvas_textures/default_texture_filter=0`
  under `[rendering]` in `project.godot`.
- **Not now** changes nothing and asks again after the next generation.
- **Don't ask again** stops the question (`filter_prompt_dismissed`). The results
  section still shows the current filter with a **Set to Nearest...** button.

The plugin never changes the **Texture Filter** of your nodes; a node set to
Linear stays blurry.

### Import settings of generated PNGs

When Godot has imported the new files, the plugin sets three import options of
every sheet and frame PNG listed in `run_manifest.json` and reimports the files it
changed:

| Import option | Value |
|---|---|
| `compress/mode` | `0`, Lossless |
| `mipmaps/generate` | `false` |
| `detect_3d/compress_to` | `0`, Disabled: a texture used in 3D is not switched to VRAM compression |

Other options and other files are left alone. The plugin waits up to 10 seconds
for the import; files not imported by then keep their settings, with a warning in
the **Output** panel. Check the result in the **Import** dock.

### SpriteFrames resources

Every sprite with more than one frame gets a `SpriteFrames` resource next to its
sheet: `characters/hero_walk.png` gets `characters/hero_walk.tres`. Assign it to
an `AnimatedSprite2D`'s **Sprite Frames**.

- Each row of the sheet is an animation: `default` for a single row, `row_0`,
  `row_1`, … for several.
- Each frame is an `AtlasTexture` region of the sheet with **Filter Clip** on, so
  pixels of the neighbouring frames don't bleed into its edges.
- Animations play at the **FPS** set in the dock (8 by default) and loop.
- Regenerating a sprite replaces the `.tres` the plugin wrote, which it recognizes
  by its `sprite_pipeline_generated` metadata; edits you made to that resource are
  replaced too, unless you delete the metadata in the inspector. Any other existing
  `.tres` is kept unless `overwrite_spriteframes` is on, and the new resource is
  saved as `<name>.generated.tres` instead. The status line says which files were
  written, updated or saved as `.generated.tres`.

The results list the files written; click one to select it in the FileSystem dock.

### Turning it off

These settings are in the `[editor]` section of
`user://sprite_pipeline_settings.cfg`:

| Setting | Default | In the dock |
|---|---|---|
| `filter_prompt_dismissed` | `false` | **Don't ask again** in the texture filter dialog |
| `pin_import_params` | `true` | — |
| `write_spriteframes` | `true` | **Write SpriteFrames** |
| `spriteframes_fps` | `8.0` | **FPS** |
| `spriteframes_loop` | `true` | — |
| `overwrite_spriteframes` | `false` | — |

Edit the file while the editor is closed; the dock writes its own values back when
a setting changes.

## Configuration

These settings are edited in the dock and saved to
`user://sprite_pipeline_settings.cfg`. The `[editor]` settings without a control
are listed under [Turning it off](#turning-it-off).

| Setting | Purpose | Default |
|---|---|---|
| Queue File | [Queue file](#queue-file) of sprites to generate | `res://sprites/sprite_queue.yaml` |
| Output Directory | Where sprites and `run_manifest.json` are written | `res://assets/sprites` |
| Global Style | Free-text style prompt added to every sprite | `pixel art game sprite, …` |
| Image Model (BYOK) | OpenAI image model | `gpt-image-2` |
| Image Quality (BYOK) | `low`, `medium` or `high` | `medium` |
| Server URL (Pool) | Backend base URL | empty |
| Download raw sheets (Pool) | Also download each sprite's generated 1024×1024 sheet | off |
| Sprite Cache (Pool) | Cache on/off; size limit under **Settings…** (100–10,000 MB) | on, 500 MB |
| Write SpriteFrames | Save a `SpriteFrames` resource next to each animated sheet | on |
| FPS | Animation speed of those resources | 8 |

Both modes add fixed instructions about the grid layout and the transparent
background to every prompt; the wording is in [prompting.gd](prompting.gd).

## Troubleshooting

### "Invalid key format" (BYOK)

- The dock expects keys that start with `sk-` (including `sk-proj-`).
- Check that the OpenAI account has credits and access to the selected model.

### "Queue file not found" / "Failed to parse queue file or queue is empty"

- Check the **Queue File** path.
- Make sure the file uses the flat YAML format described in
  [Queue File](#queue-file).

### "Enter a valid server URL" (Pool)

**Server URL** is empty or was rejected. See the URL rules in
[Server URL](#server-url); the **Output** panel shows the exact reason.

### Login or generation fails (Pool)

- Confirm the server runs sprite-pipeline-backend with protocol 2.0.0 or later and
  is reachable.
- Click **Login with Device Code** again to get fresh tokens.

### Grid warnings

The generated image had sprites crossing cell boundaries, so frames can be cut off.
Generate the sprite again, or describe fewer or simpler poses.

### Sprites look blurry

Click **Set to Nearest...** under the results, or set **Project Settings →
Rendering → Textures → Canvas Textures → Default Texture Filter** to Nearest. A
node whose own **Texture Filter** is Linear stays blurry.

### A `.generated.tres` file appeared

The sheet already had a `.tres` that the plugin didn't write, or whose
`sprite_pipeline_generated` metadata was deleted, so the plugin kept it. Delete the
old file and rename the new one, or set `overwrite_spriteframes=true` (see
[Turning it off](#turning-it-off)).

### Cached results look wrong

In the **Sprite Cache** section, click **Clear Cache**.

### Plugin debug output

Watch the editor's **Output** panel for `[SpritePipeline]`, `[PoolClient]` and
`[AutomationServer]` messages.

## Security & Privacy

⚠️ **Never commit API keys to version control.**

### BYOK mode
- The API key is stored in `user://sprite_pipeline_settings.cfg`, outside the
  project folder.
- The key is sent only to `https://api.openai.com`.
- Queue entries whose `category` or `file_name` would write outside the output
  directory are rejected.

### Pool mode
- Device-code login: no password is entered in the editor.
- Access and refresh tokens are stored in `user://sprite_pipeline_settings.cfg`.
- The server URL must use HTTPS, except for localhost and private-network
  addresses.
- Asset paths returned by the server are confined to the output directory, and
  every file is checked against its SHA-256 before it is written.

## Automation (testing)

The plugin includes a dev-only automation server for driving the dock from test
scripts. It runs inside the editor while the plugin is enabled and listens on
`127.0.0.1:19876`. Enable it with any of:

- the environment variable `SPRITE_PIPELINE_AUTOMATION=1`
- the command-line flag `--automation` (or `--enable-automation`)
- `enable_automation=true` in the `[dev]` section of
  `user://sprite_pipeline_settings.cfg`

The protocol is raw TCP, not HTTP. Every message, in both directions, is a 4-byte
little-endian length followed by that many bytes of UTF-8 JSON:

```json
{"command": "start_generate", "args": {"queue_path": "res://sprites/sprite_queue.yaml", "output_root": "res://assets/sprites"}, "request_id": "run-1"}
```

`ping`, `get_state`, `get_events`, `clear_events`, `get_manifest` and
`get_last_error_context` return their result directly. The other commands
(`start_generate`, `cancel_generate`, `import_only`, `get_config`, `set_config`,
`run_doctor`, `get_doctor_report`, `apply_fix`, `verify_fix`) reply
`{"status": "delegated"}` immediately; poll `get_events` for their results.

Minimal Python client:

```python
import json
import socket
import struct


def recv_exact(sock, size):
    data = b""
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ConnectionError("connection closed")
        data += chunk
    return data


def send(sock, message):
    body = json.dumps(message).encode()
    sock.sendall(struct.pack("<I", len(body)) + body)
    size = struct.unpack("<I", recv_exact(sock, 4))[0]
    return json.loads(recv_exact(sock, size))


with socket.create_connection(("127.0.0.1", 19876)) as sock:
    print(send(sock, {"command": "ping"}))
    print(send(sock, {"command": "start_generate", "args": {"queue_path": "res://sprites/sprite_queue.yaml"}}))
    print(send(sock, {"command": "get_events", "args": {"since_seq": 0}}))
```

## FAQ

**Q: How much does generation cost?**
A: BYOK passes through OpenAI's per-image pricing, which depends on the model and
the quality; check OpenAI's current pricing. Pool mode uses the credits of the
server you log in to.

**Q: Can I use this commercially?**
A: The plugin is MIT-licensed. Generated images are subject to OpenAI's terms.

**Q: What Godot versions are supported?**
A: Godot 4.2 and later. Godot 3.x is not supported. The headless tests in the
repository need Godot 4.5 or later.

**Q: Can I generate animations directly?**
A: Yes. With `frame_w` and `frame_h` set, every frame is saved as its own file and
the compact sheet has equal cells. In the editor, a `SpriteFrames` resource next to
the sheet plays in an `AnimatedSprite2D` right away; see
[SpriteFrames resources](#spriteframes-resources).

**Q: Where are my API keys stored?**
A: In `user://sprite_pipeline_settings.cfg`, outside the project folder, not
tracked by version control.

**Q: Can I plug in a different image generation model?**
A: Any OpenAI Images API model: choose **Custom...** under **Image Model** and
enter its name. Other providers need changes in
[api/byok_client.gd](api/byok_client.gd).

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Built on the [Godot Engine](https://godotengine.org/) and OpenAI's image
generation API.
