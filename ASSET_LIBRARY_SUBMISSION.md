# Godot Asset Library Submission Guide

## Prerequisites

- [ ] GitHub repository is public: https://github.com/fabs133/sprite-pipeline-plugin
- [ ] Release v1.0.0 is published with ZIP artifact
- [ ] Icon.png (128x128) is present in repository
- [ ] LICENSE file is present (MIT)
- [ ] README.md is comprehensive

## Submission Steps

1. **Go to Godot Asset Library**
   - Visit: https://godotengine.org/asset-library/asset
   - Click "Submit Assets" (requires login)

2. **Create Godot Account** (if needed)
   - Register at: https://godotengine.org/user/register
   - Verify email

3. **Fill Submission Form**

   **Basic Information:**
   - **Title**: `Sprite Pipeline`
   - **Description**:
     ```
     AI-powered sprite generation directly in Godot Editor. Supports BYOK (your own OpenAI key) and Pool (shared credits) modes. Generate single sprites or batch process from JSON queue. Multiple art styles including Pixel Art, Cartoon, Flat Vector, Retro 8-bit, Watercolor, and Realistic. Smart local caching prevents duplicate generations and saves API costs.
     ```
   - **Category**: `2D Tools`
   - **License**: `MIT`
   - **Repository URL**: `https://github.com/fabs133/sprite-pipeline-plugin`
   - **Issues URL**: `https://github.com/fabs133/sprite-pipeline-plugin/issues`
   - **Download Provider**: `Custom` (or GitHub Releases)
   - **Download URL**: `https://github.com/fabs133/sprite-pipeline-plugin/releases/download/v1.0.0/sprite-pipeline-v1.0.0.zip`

   **IMPORTANT:** Use the GitHub Releases URL above, NOT the archive/tags URL. Godot Asset Library no longer accepts Git tags.

   **Version Information:**
   - **Version String**: `1.0.0`
   - **Godot Version**: `4.2` (minimum)

   **Icon:**
   - **Icon URL**: `https://raw.githubusercontent.com/fabs133/sprite-pipeline-plugin/master/addons/sprite_pipeline/icon.png`

   **Additional Details:**
   - **Browse URL**: `https://github.com/fabs133/sprite-pipeline-plugin/tree/v1.0.0/addons/sprite_pipeline`
   - **Support Level**: `community`

4. **Add Screenshots** (optional but recommended)
   - Take screenshots of:
     - Main plugin dock showing BYOK mode
     - Main plugin dock showing Pool mode
     - Generated sprite examples
     - Cache statistics
   - Upload to repository under `docs/screenshots/`
   - Add screenshot URLs to submission

5. **Submit for Review**
   - Click "Submit"
   - Wait for moderator approval (usually 1-3 days)
   - Check email for approval notification

## After Approval

- [ ] Update README.md with Asset Library badge
- [ ] Announce on Godot forums/Discord
- [ ] Update website with Asset Library link

## Future Updates

To update the asset on Asset Library:

1. Create new release tag (e.g., `v1.1.0`)
2. GitHub Actions automatically creates release
3. Go to Asset Library → Your Assets → Sprite Pipeline → Edit
4. Update version string and download URL
5. Submit for review

## Asset Library Review Criteria

The Godot Asset Library moderators check:
- ✅ License is clearly specified
- ✅ Repository is accessible and public
- ✅ Download link works and contains correct structure
- ✅ Plugin follows Godot plugin conventions (`addons/` folder)
- ✅ No malicious code or unauthorized data collection
- ✅ Icon meets size requirements (128x128)
- ✅ Description is clear and accurate

## Notes

- **First submission takes 1-3 days** for moderator review
- **Updates are usually faster** (hours to 1 day)
- Asset Library guidelines: https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html
