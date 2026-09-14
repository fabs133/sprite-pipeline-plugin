# Sprite Pipeline — Godot Plugin

[![Status](https://img.shields.io/badge/status-archived-lightgrey)](#status)
[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://github.com/fabs133/sprite-pipeline-plugin/releases)
[![Godot](https://img.shields.io/badge/godot-4.2%2B-blue)](https://godotengine.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](addons/sprite_pipeline/LICENSE)

## Status

**Archived.** This plugin shipped at v1.0.0 in February 2026. The hosted Pool service
that backed shared-credit mode is no longer running. The code is published as an
engineering reference. **Issues and PRs are not monitored.** No support is provided.

## Overview

A Godot 4.x editor plugin that generates sprites from text prompts using OpenAI's
image generation API. Runs inside the Godot Editor — no external pipeline tools.
Output sprites land directly in your project.

Two operation modes are implemented:

- **BYOK (Bring Your Own Key)** — the supported path. The plugin calls OpenAI
  directly with an API key you provide. Requests never go through any third-party
  server.
- **Pool (shared credits)** — originally backed by a hosted credit-and-billing
  service. That service has been retired. The Pool client is still in the code, but
  its API does not match the `sprite-pipeline-backend` reference implementation
  (repository not yet published), so Pool mode does not work against that backend
  without porting the client. See
  [Pool Mode](addons/sprite_pipeline/README.md#pool-mode-self-hosted-backend) in the
  addon README.

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
│   ├── plugin.gd              EditorPlugin entry point
│   ├── plugin.cfg             Godot plugin manifest
│   ├── README.md              Addon-internal documentation
│   ├── CHANGELOG.md           Release history
│   └── LICENSE                MIT license
├── scripts/                   Build and validation scripts (PowerShell + Bash)
├── .github/workflows/         CI for validate / build-dev / build-prod
└── asset.cfg                  Godot Asset Library metadata
```

## Related Repositories

This plugin was the client half of a larger system. The other repositories:

- **sprite-pipeline-backend** — FastAPI backend providing Pool mode (auth, credits,
  Stripe billing, OpenAI proxying) for the hosted service. Its API differs from the
  plugin's Pool client, so self-hosting it for Pool mode requires porting
  `addons/sprite_pipeline/api/pool_client.gd`. Repo URL: TBD.
- **sprite-pipeline-web** — Astro/React marketing and dashboard frontend for the
  hosted SaaS. Repo URL: TBD.

## Building from Source

Release zips are attached to
[GitHub Releases](https://github.com/fabs133/sprite-pipeline-plugin/releases). To
build locally (output goes to `dist/`, which is gitignored):

```bash
# Linux / macOS
./scripts/build.sh prod 1.0.0

# Windows
.\scripts\build.ps1 -Mode prod -Version 1.0.0
```

Validation:

```bash
.\scripts\validate.ps1 -Strict
```

## License

MIT — see [addons/sprite_pipeline/LICENSE](addons/sprite_pipeline/LICENSE).

## Credits

Built by [fabs133](https://github.com/fabs133) on top of the
[Godot Engine](https://godotengine.org/) and the [OpenAI](https://openai.com/)
image generation API.
