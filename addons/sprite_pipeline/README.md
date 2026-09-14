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
  `user://` and used to call OpenAI's image API (`dall-e-3`) directly. No
  third-party server is involved. Implemented in
  [api/byok_client.gd](api/byok_client.gd).
- **Pool (shared credits)** — was backed by a hosted credit-and-billing service
  that has been retired. Implemented in [api/pool_client.gd](api/pool_client.gd).
  The client does not match the API of the `sprite-pipeline-backend` reference
  implementation; see [Pool Mode](#pool-mode-self-hosted-backend). The
  **Server URL** field is empty by default.

## Features

- **Batch generation** — every entry in a [queue file](#queue-file) becomes one
  sprite sheet.
- **Automatic import** — sprites are written under your output directory together
  with a `run_manifest.json`; **Reimport Assets** rescans the project.
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
4. Create a [queue file](#queue-file) at `res://sprites/sprite_queue.yaml`, or
   point **Queue File** at your own.
5. Adjust **Global Style** if needed and click **Generate Sprites**.

The key is written to `user://sprite_pipeline_settings.cfg`, outside your project
folder, and is sent only to OpenAI's API.

## Queue File

The queue is a flat YAML list. A line starting with `- ` begins a new sprite, and
the `key: value` lines after it belong to that sprite. Only this subset is parsed:
nested lists and maps are not supported, JSON is not accepted, and `#` comments
must be on their own line.

```yaml
- file_name: hero_walk.png
  category: characters
  description: knight walking animation
  frames: 4
  frame_w: 64
  frame_h: 64
  layout: row
- file_name: enemy_slime.png
  category: monsters
  description: green slime enemy
  frames: 2
  layout: row
```

Fields used in BYOK mode:

| Field | Meaning | Default |
|---|---|---|
| `file_name` | Output file name | `sprite.png` |
| `category` | Subfolder under the output directory | `misc` |
| `description` | What to draw | `file_name` without extension, `_` as spaces |
| `frames` | Number of animation frames | `1` |
| `frame_w`, `frame_h` | Frame size, used as a prompt hint | `64` |
| `layout` | `row` for a horizontal strip; any other value for a vertical strip | `row` |

BYOK writes each sprite to `<output directory>/<category>/<file_name>`. DALL-E 3
returns 1024×1024, 1792×1024 or 1024×1792 images and the plugin does not resize
them, so frame sizes only steer the prompt. In Pool mode the queue entries are
sent to the backend unchanged.

## Pool Mode (self-hosted backend)

> **Compatibility:** the Pool client does not work against the
> `sprite-pipeline-backend` reference implementation without changes. The backend
> uses different device-login endpoint paths and a different `/v1/generate`
> request and response format. To use that backend, port
> [api/pool_client.gd](api/pool_client.gd) first.

To point the plugin at a backend that implements the client's protocol:

1. In the Sprite Pipeline dock, click **Pool (Shared)**.
2. Enter your backend's base URL in **Server URL**. It must use `https://`; plain
   `http://` is accepted only for `localhost`, `127.x.x.x` and private-network
   addresses (`10.x`, `172.16.x`–`172.31.x`, `192.168.x`).
3. Click **Login with Device Code**, open the verification page (the link appears
   when the backend returns one) and enter the code shown in the dock.

Tokens are saved to `user://sprite_pipeline_settings.cfg` and restored when the
editor restarts. Saved settings that still point at the retired hosted service
(`sprites.pi-agents.dev`) are cleared on load.

## Configuration

All settings are edited in the dock and saved to
`user://sprite_pipeline_settings.cfg`.

| Setting | Purpose | Default |
|---|---|---|
| Queue File | [Queue file](#queue-file) of sprites to generate | `res://sprites/sprite_queue.yaml` |
| Output Directory | Where sprites and `run_manifest.json` are written | `res://assets/sprites` |
| Global Style | Free-text style prompt added to every sprite | `pixel art game sprite, …` |
| Server URL (Pool) | Backend base URL | empty |
| Sprite Cache (Pool) | Cache on/off; size limit under **Settings…** (100–10,000 MB) | on, 500 MB |

BYOK also appends a fixed "clean pixel art, game-ready asset" line to every
prompt, so other art styles need a change in [api/byok_client.gd](api/byok_client.gd).

## Troubleshooting

### "Invalid key format" (BYOK)

- The dock expects keys that start with `sk-` (including `sk-proj-`).
- Check that the OpenAI account has credits.

### "Queue file not found" / "Failed to parse queue file or queue is empty"

- Check the **Queue File** path.
- Make sure the file uses the flat YAML format described in
  [Queue File](#queue-file).

### "Enter a valid server URL" (Pool)

**Server URL** is empty or was rejected. See the URL rules in
[Pool Mode](#pool-mode-self-hosted-backend); the **Output** panel shows the exact
reason.

### Login or generation fails (Pool)

- Confirm the backend implements the client's protocol (see the compatibility
  note in [Pool Mode](#pool-mode-self-hosted-backend)) and is reachable.
- Click **Login with Device Code** again to get fresh tokens.

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

### Pool mode
- Device-code login: no password is entered in the editor.
- Access and refresh tokens are stored in `user://sprite_pipeline_settings.cfg`.
- The server URL must use HTTPS, except for localhost and private-network
  addresses.
- Asset paths returned by the server are confined to the output directory.

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
A: BYOK is wired to OpenAI's image API only. The model name (`dall-e-3`) and the
request code are in [api/byok_client.gd](api/byok_client.gd) if you want to fork.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

Built on the [Godot Engine](https://godotengine.org/) and OpenAI's image
generation API.
