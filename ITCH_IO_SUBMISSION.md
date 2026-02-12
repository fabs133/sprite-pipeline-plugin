# itch.io Submission Guide

## Prerequisites

- [ ] itch.io account created (fabs133)
- [ ] Butler CLI installed: `C:\Users\fbrmp\.itch\apps\butler\butler.exe`
- [ ] Production ZIP built: `dist/sprite-pipeline-v1.0.0.zip`

## Create itch.io Project

1. **Go to itch.io Dashboard**
   - Visit: https://itch.io/game/new
   - Login as fabs133

2. **Project Setup**

   **Basic Info:**
   - **Title**: `Sprite Pipeline - Godot Plugin`
   - **Project URL**: `sprite-pipeline-godot` → https://fabs133.itch.io/sprite-pipeline-godot
   - **Short Description**: `AI-powered sprite generation for Godot 4.2+`
   - **Classification**: `Tools`
   - **Kind of Project**: `Tool`

   **Pricing:**
   - **Pricing**: `Paid` or `$0 or Donate`
   - **Suggested Price**: `$0.00` (free) or `$4.99` (paid)
   - Note: Open source (MIT), so ethically should be free or "pay what you want"

   **Uploads:**
   - Click "Upload files"
   - Upload `dist/sprite-pipeline-v1.0.0.zip`
   - **Display Name**: `Sprite Pipeline v1.0.0 (Godot 4.2+)`
   - **Platform**: `Windows, macOS, Linux` (it's a plugin, works everywhere)

   **Details:**
   - **Genre**: `Tool`
   - **Tags**: `godot`, `plugin`, `ai`, `sprites`, `pixel-art`, `game-development`, `tool`, `editor-plugin`
   - **Release Status**: `Released`
   - **Godot Engine**: Check this box

   **Description (Full):**
   ```markdown
   # Sprite Pipeline - AI-Powered Sprite Generation

   Generate high-quality sprites directly in Godot Editor using AI.

   ## Features

   - **Two Modes**: BYOK (your OpenAI key) or Pool (shared credits)
   - **Smart Caching**: Prevents duplicate generations
   - **Batch Processing**: Generate multiple sprites from JSON
   - **Multiple Styles**: Pixel Art, Cartoon, Flat Vector, Retro 8-bit, Watercolor, Realistic
   - **Auto Import**: Sprites automatically added to your project

   ## Installation

   1. Download the ZIP file
   2. Extract to your project's `addons/` folder
   3. Enable in Project → Project Settings → Plugins

   ## Requirements

   - Godot 4.2 or later
   - For BYOK mode: OpenAI API key
   - For Pool mode: Free account at sprite-pipeline.com

   ## Documentation

   Full documentation: https://github.com/fabs133/sprite-pipeline-plugin

   ## License

   MIT License - free for personal and commercial use

   ## Support

   - GitHub Issues: https://github.com/fabs133/sprite-pipeline-plugin/issues
   - Email: support@sprite-pipeline.com
   ```

   **Cover Image:**
   - Upload a 630×500 cover image showing the plugin in action
   - Or use icon as placeholder (will need to create cover later)

   **Screenshots:**
   - Upload 3-5 screenshots showing:
     - Plugin dock interface
     - Generation in progress
     - Generated sprites
     - Cache statistics

3. **Community Settings**

   - **Enable Comments**: Yes
   - **Enable Community**: Yes
   - **Visibility**: `Public`

4. **Save as Draft** first, then preview

## Upload via Butler CLI

For automated uploads and version management:

```powershell
# Login to Butler (one-time)
C:\Users\fbrmp\.itch\apps\butler\butler.exe login

# Push initial version
C:\Users\fbrmp\.itch\apps\butler\butler.exe push dist/sprite-pipeline-v1.0.0.zip fabs133/sprite-pipeline-godot:plugin --userversion 1.0.0

# Future updates
C:\Users\fbrmp\.itch\apps\butler\butler.exe push dist/sprite-pipeline-v1.1.0.zip fabs133/sprite-pipeline-godot:plugin --userversion 1.1.0
```

## Pricing Strategy Recommendations

### Option 1: Free + Donations (Recommended)
- Price: $0 or donate
- Suggested donation: $5
- Good for open-source projects
- Builds community goodwill
- Users pay for Pool mode credits anyway

### Option 2: Paid
- Price: $4.99 - $9.99
- Unlocks plugin
- May limit adoption
- Conflicts with open-source MIT license

### Option 3: Two Versions
- Free version: Basic features (GitHub releases)
- Premium version: Extra features + support (itch.io)
- Requires maintaining two versions

**Recommended**: Option 1 (Free + Donations) since it's MIT licensed and open source

## Post-Launch

- [ ] Announce on Godot forums
- [ ] Share on Reddit (r/godot)
- [ ] Tweet/social media
- [ ] Add to README.md
- [ ] Create devlog posts for updates

## Butler Installation (if needed)

```powershell
# Download Butler
Invoke-WebRequest https://broth.itch.ovh/butler/windows-amd64/LATEST/archive/default -OutFile butler.zip

# Extract to itch apps folder
Expand-Archive butler.zip -DestinationPath C:\Users\fbrmp\.itch\apps\butler\
```

## Update Process

When releasing new versions:

1. Build new release ZIP
2. Update version in itch.io web interface OR
3. Use Butler to push update:
   ```powershell
   butler push dist/sprite-pipeline-v1.1.0.zip fabs133/sprite-pipeline-godot:plugin --userversion 1.1.0
   ```
4. Post devlog update

## Marketing Copy

**One-Liner:**
> Generate AI-powered sprites directly in Godot Editor

**Short Pitch:**
> Stop drawing sprites manually. Sprite Pipeline brings OpenAI's image generation directly into Godot 4.2+. Use your own API key or shared credits. Multiple art styles, batch processing, smart caching.

**Feature Bullets:**
- ⚡ Generate sprites in seconds
- 🎨 6 art styles (Pixel Art, Cartoon, Realistic, etc.)
- 💾 Smart caching saves money
- 📦 Batch processing from JSON
- 🔐 Two modes: BYOK or Pool credits
