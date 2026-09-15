# Sprite Pipeline — Godot Plugin

[![Status](https://img.shields.io/badge/status-archived-lightgrey)](#status)
[![Version](https://img.shields.io/badge/version-1.1.0-blue)](https://github.com/fabs133/sprite-pipeline-plugin/releases)
[![Godot](https://img.shields.io/badge/godot-4.2%2B-blue)](https://godotengine.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](addons/sprite_pipeline/LICENSE)

## Status

**Archived.** This plugin shipped at v1.0.0 in February 2026. Version 1.1.0
(September 2026) ports Pool mode to protocol 2.0.0 of sprite-pipeline-backend and
moves BYOK to OpenAI's gpt-image models. The hosted Pool service of 1.0.0 is no
longer running. The code is published as an engineering reference. **Issues and
PRs are not monitored.** No support is provided.

## Overview

A Godot 4.x editor plugin that generates sprites from text prompts using OpenAI's
image models. Runs inside the Godot Editor — no external pipeline tools. Output
sprites land directly in your project, cut into frames at the size you choose.

Two operation modes are implemented:

- **BYOK (Bring Your Own Key)** — the plugin calls OpenAI directly with an API key
  you provide. Requests never go through any third-party server.
- **Pool (shared credits)** — the plugin sends the queue to a
  sprite-pipeline-backend server with protocol 2.0.0 or later and downloads the
  results. The original hosted service has been retired; see
  [Pool Mode](addons/sprite_pipeline/README.md#pool-mode) in the addon README.

## Installation

1. Clone this repository, or download a release zip from
   [Releases](https://github.com/fabs133/sprite-pipeline-plugin/releases).
2. Copy the `addons/sprite_pipeline/` folder into your Godot project's `addons/`
   directory.
3. In Godot: **Project → Project Settings → Plugins** → enable "Sprite Pipeline".
4. The "Sprite Pipeline" dock appears in the upper-right dock area of the editor.

For BYOK setup, plugin usage, configuration, and troubleshooting, see the addon
README at [addons/sprite_pipeline/README.md](addons/sprite_pipeline/README.md).

## Repository Layout

```
sprite-pipeline-plugin/
├── addons/sprite_pipeline/    Plugin source (drop into your project)
│   ├── api/                   OpenAI and Pool API clients
│   ├── ui/                    Editor dock and dialogs
│   ├── cache/                 Local LRU sprite cache
│   ├── remediation/           Self-healing actions for common errors
│   ├── prompting.gd           Prompt construction (same text as the backend)
│   ├── postprocess.gd         Frame slicing, downscaling and grid check
│   ├── manifest_paths.gd      Manifest path resolution under the output directory
│   ├── plugin.gd              EditorPlugin entry point
│   ├── version.gd             Plugin and protocol versions
│   ├── plugin.cfg             Godot plugin manifest
│   ├── README.md              Addon-internal documentation
│   ├── CHANGELOG.md           Release history
│   └── LICENSE                MIT license
├── scripts/                   Build, validation and test scripts (PowerShell + Bash)
├── tests/                     Headless GDScript tests
├── project.godot              Dev project that runs the tests
├── .github/workflows/         CI for validate / build-dev / build-prod
└── asset.cfg                  Godot Asset Library metadata
```

## Related Repositories

This plugin is the client half of a larger system. The other repositories:

- **sprite-pipeline-backend** — FastAPI backend providing Pool mode (auth, credits,
  Stripe billing, OpenAI proxying). Pool mode in 1.1.0 speaks its protocol 2.0.0.
  Repo URL: TBD.
- **sprite-pipeline-web** — Astro/React marketing and dashboard frontend for the
  hosted SaaS. Repo URL: TBD.

## Building from Source

Release zips are attached to
[GitHub Releases](https://github.com/fabs133/sprite-pipeline-plugin/releases). To
build locally (output goes to `dist/`, which is gitignored):

```bash
# Linux / macOS
./scripts/build.sh prod 1.1.0

# Windows
.\scripts\build.ps1 -Mode prod -Version 1.1.0
```

`build.ps1` checks the finished ZIP with `scripts/verify-zip.ps1` and fails if an entry
name contains `\`, `addons/sprite_pipeline/plugin.cfg` is missing or an entry starts
with `tests/`.

Validation:

```bash
.\scripts\validate.ps1 -Strict
```

Tests (Godot 4.5+; set `GODOT` to the executable if `godot` is not on PATH):

```bash
# Linux / macOS
./scripts/test.sh

# Windows
.\scripts\test.ps1
```

To release a new version, update `PLUGIN` in `addons/sprite_pipeline/version.gd`, the
version in `addons/sprite_pipeline/plugin.cfg` and `asset.cfg` (the validation script
fails if they differ), and the CHANGELOG. Pushing a `vX.Y.Z` tag runs
the Build Production Release workflow, which builds the zip and publishes a GitHub
release with `SHA256SUMS`.

## License

MIT — see [addons/sprite_pipeline/LICENSE](addons/sprite_pipeline/LICENSE).

## Credits

Built by [fabs133](https://github.com/fabs133) on top of the
[Godot Engine](https://godotengine.org/) and the [OpenAI](https://openai.com/)
image generation API.
