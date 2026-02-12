#!/bin/bash
# Build script for Sprite Pipeline plugin
# Usage: ./scripts/build.sh [dev|prod] [version]

set -e

MODE=${1:-dev}
VERSION=${2:-$(grep 'version=' addons/sprite_pipeline/plugin.cfg | cut -d'"' -f2)}

echo "========================================"
echo "Sprite Pipeline Plugin Builder"
echo "========================================"
echo "Mode: $MODE"
echo "Version: $VERSION"
echo ""

# Create dist directory
mkdir -p dist

# Define output filename
if [ "$MODE" = "prod" ]; then
    OUTPUT="dist/sprite-pipeline-v${VERSION}.zip"
    echo "Building PRODUCTION release..."
else
    OUTPUT="dist/sprite-pipeline-v${VERSION}-dev.zip"
    echo "Building DEV release..."
fi

# Clean old builds
rm -f "$OUTPUT"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
mkdir -p "$TEMP_DIR/addons/sprite_pipeline"

# Copy plugin files
echo "Copying plugin files..."
cp -r addons/sprite_pipeline/* "$TEMP_DIR/addons/sprite_pipeline/"

# Remove dev-only files in production mode
if [ "$MODE" = "prod" ]; then
    echo "Removing dev-only files..."
    rm -rf "$TEMP_DIR/addons/sprite_pipeline/tests"
    rm -rf "$TEMP_DIR/addons/sprite_pipeline/.git"
    find "$TEMP_DIR" -name "*.pyc" -delete
    find "$TEMP_DIR" -name "__pycache__" -delete
fi

# Create ZIP
echo "Creating ZIP archive..."
cd "$TEMP_DIR"
zip -r -q "$OLDPWD/$OUTPUT" addons/

# Cleanup
cd "$OLDPWD"
rm -rf "$TEMP_DIR"

# Get file size
SIZE=$(du -h "$OUTPUT" | cut -f1)

echo ""
echo "✅ Build complete!"
echo "   Output: $OUTPUT"
echo "   Size: $SIZE"
echo ""

# Calculate SHA256
if command -v sha256sum &> /dev/null; then
    SHA=$(sha256sum "$OUTPUT" | cut -d' ' -f1)
    echo "   SHA256: $SHA"
    echo ""
fi
