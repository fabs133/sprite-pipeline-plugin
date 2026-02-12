# Sprite Pipeline - Quick Reference

## 🔗 Important Links

- **GitHub Repository:** https://github.com/fabs133/sprite-pipeline-plugin
- **Latest Release:** https://github.com/fabs133/sprite-pipeline-plugin/releases/tag/v1.0.0
- **Backend Server:** http://192.168.178.30:8000
- **Website:** https://sprite-pipeline.com

## 📦 What Was Deployed

### Backend Security Fixes (sprite-pipeline-backend)
```bash
ssh droid@192.168.178.30
cd /home/droid/.ssh/sprite-pipeline-backend
git log --oneline | head -5
```

**Commit:** `12365d2`
- Rate limiting on magic links
- XSS sanitization
- CORS lockdown
- Admin auth enforcement
- Infisical integration

### Plugin v1.0.0 (sprite-pipeline-plugin)
**GitHub:** https://github.com/fabs133/sprite-pipeline-plugin
**Release:** v1.0.0 published with automated CI/CD

## 🚀 Next Steps (Manual Actions)

### 1. Godot Asset Library (1-3 days approval)
```
URL: https://godotengine.org/asset-library/asset
Guide: ASSET_LIBRARY_SUBMISSION.md
Download: https://github.com/fabs133/sprite-pipeline-plugin/releases/download/v1.0.0/sprite-pipeline-v1.0.0.zip
```

### 2. itch.io Upload (Immediate)
```powershell
# Butler CLI (recommended)
C:\Users\fbrmp\.itch\apps\butler\butler.exe login
C:\Users\fbrmp\.itch\apps\butler\butler.exe push dist/sprite-pipeline-v1.0.0.zip fabs133/sprite-pipeline-godot:plugin --userversion 1.0.0
```

Or use web interface:
```
URL: https://itch.io/game/new
Guide: ITCH_IO_SUBMISSION.md
Cover: docs/cover.png
```

## 🔄 Creating Updates

### Version Bump Process
1. Update version in these files:
   - `addons/sprite_pipeline/plugin.cfg`
   - `addons/sprite_pipeline/api/pool_client.gd` (PLUGIN_VERSION)
   - `addons/sprite_pipeline/CHANGELOG.md`

2. Commit and tag:
```bash
git add .
git commit -m "chore: bump version to 1.1.0"
git push origin master

git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

3. GitHub Actions automatically:
   - Runs validation
   - Builds ZIP
   - Creates release with checksums

4. Update distribution platforms:
   - Godot Asset Library: Edit asset → Update version & download URL
   - itch.io: Run `butler push` with new version

## 🛠️ Useful Commands

### Build Plugin Locally
```powershell
# Development build
.\scripts\build.ps1 -Mode dev -Version 1.1.0-alpha

# Production build
.\scripts\build.ps1 -Mode prod -Version 1.1.0
```

### Validate Plugin
```powershell
.\scripts\validate.ps1           # Standard
.\scripts\validate.ps1 -Strict   # Production-ready check
```

### Check GitHub Actions
```bash
gh run list --repo fabs133/sprite-pipeline-plugin
gh run view <run-id> --log-failed
```

### View Release
```bash
gh release view v1.0.0 --repo fabs133/sprite-pipeline-plugin
gh release list --repo fabs133/sprite-pipeline-plugin
```

## 📊 File Locations

```
C:\Users\fbrmp\Projekte\
├── sprite-pipeline-plugin/          # GitHub repo (NEW)
│   ├── addons/sprite_pipeline/      # Plugin source
│   ├── scripts/                     # Build & validation scripts
│   ├── .github/workflows/           # CI/CD
│   ├── docs/                        # Images & assets
│   └── dist/                        # Build outputs (gitignored)
│
├── sprite-pipeline-backend/         # Backend (on server)
│   └── ssh droid@192.168.178.30
│
└── pi_agents/godot_2d_game/
    └── addons/sprite_pipeline/      # Original location (deprecated)
```

## 🔐 Security Checklist

- [x] Backend rate limiting active
- [x] Input sanitization implemented
- [x] No hardcoded API keys in plugin
- [x] HTTPS enforcement for server URLs
- [x] Path validation (no directory traversal)
- [x] Secrets in Infisical
- [x] CORS restricted to production domain
- [x] Debug prints removed from releases

## 📝 Documentation Files

- `README.md` - Project overview
- `addons/sprite_pipeline/README.md` - User documentation (400+ lines)
- `CHANGELOG.md` - Version history
- `ASSET_LIBRARY_SUBMISSION.md` - Godot submission guide
- `ITCH_IO_SUBMISSION.md` - itch.io upload guide
- `DEPLOYMENT_SUMMARY.md` - Complete deployment record
- `BACKEND_RATE_LIMITING.md` - OpenAI rate limit configuration
- `QUICK_REFERENCE.md` - This file

## 🎯 Status Summary

| Task | Status | Action Required |
|------|--------|----------------|
| Backend security | ✅ Complete | None |
| OpenAI rate limiting | ✅ Implemented | None (3 retries, 1s delay) |
| Plugin v1.0.0 | ✅ Complete | None |
| GitHub repo | ✅ Live | None |
| CI/CD workflows | ✅ Operational | None |
| v1.0.0 release | ✅ Published | None |
| Documentation | ✅ Complete | None |
| Asset Library | ⏳ Submitted | Awaiting moderator approval (1-3 days) |
| itch.io | ⏳ Pending | **Upload via Butler or web** |
| Marketing | ⏳ Optional | Announce when ready |

## ⚡ Quick Actions

**Check backend health:**
```bash
curl http://192.168.178.30:8000/health
```

**Adjust OpenAI rate limits:**
```bash
ssh droid@192.168.178.30
cd /home/droid/.ssh/sprite-pipeline-backend
nano .env  # Edit SPRITE_LITELLM_MAX_RETRIES and SPRITE_LITELLM_RETRY_DELAY
docker compose restart backend
```
See `BACKEND_RATE_LIMITING.md` for details.

**Test plugin in Godot:**
```bash
cd C:\Users\fbrmp\Desktop\GodotExample\assets\Godot
.\Godot_v4.6-stable_win64.exe
# Enable plugin in test project
```

**Monitor workflows:**
```bash
gh run watch --repo fabs133/sprite-pipeline-plugin
```

## 💡 Tips

- **Always test locally** before creating a tag
- **Version tags trigger production release** automatically
- **Validation must pass** or release will fail
- **Butler is faster** than web interface for itch.io
- **Asset Library approval** takes 1-3 days typically
- **Keep CHANGELOG.md updated** for automatic release notes

## 🆘 Troubleshooting

**Workflow fails on validation:**
- Check `plugin.cfg` version matches tag
- Ensure no `print()` statements (use `print_debug()`)
- Run `.\scripts\validate.ps1 -Strict` locally

**Release creation fails (403):**
- Check workflow has `permissions: contents: write` ✅ Already fixed

**Backend not accessible:**
```bash
ssh droid@192.168.178.30
cd /home/droid/.ssh/sprite-pipeline-backend
docker compose ps
docker compose logs backend
```

---

**Last Updated:** 2026-02-12
**Version:** 1.0.0
**Status:** ✅ Ready for manual distribution submission
