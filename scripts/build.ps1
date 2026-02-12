# Build script for Sprite Pipeline plugin (PowerShell)
# Usage: .\scripts\build.ps1 [-Mode dev|prod] [-Version x.y.z]

param(
    [string]$Mode = "dev",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

# Get version from plugin.cfg if not provided
if ([string]::IsNullOrEmpty($Version)) {
    $pluginCfg = Get-Content "addons/sprite_pipeline/plugin.cfg" -Raw
    if ($pluginCfg -match 'version="([^"]+)"') {
        $Version = $Matches[1]
    } else {
        Write-Error "Could not extract version from plugin.cfg"
        exit 1
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Sprite Pipeline Plugin Builder" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor Yellow
Write-Host "Version: $Version" -ForegroundColor Yellow
Write-Host ""

# Create dist directory
New-Item -ItemType Directory -Force -Path "dist" | Out-Null

# Define output filename
if ($Mode -eq "prod") {
    $outputFile = "dist/sprite-pipeline-v$Version.zip"
    Write-Host "Building PRODUCTION release..." -ForegroundColor Green
} else {
    $outputFile = "dist/sprite-pipeline-v$Version-dev.zip"
    Write-Host "Building DEV release..." -ForegroundColor Yellow
}

# Remove old build
if (Test-Path $outputFile) {
    Remove-Item $outputFile -Force
}

# Create temporary directory
$tempDir = New-Item -ItemType Directory -Path "$env:TEMP\sprite-pipeline-$(Get-Random)" -Force
$pluginDir = New-Item -ItemType Directory -Path "$tempDir\addons\sprite_pipeline" -Force

# Copy plugin files
Write-Host "Copying plugin files..." -ForegroundColor Gray
Copy-Item -Path "addons\sprite_pipeline\*" -Destination "$pluginDir" -Recurse -Force

# Remove dev-only files in production mode
if ($Mode -eq "prod") {
    Write-Host "Removing dev-only files..." -ForegroundColor Gray

    $devPaths = @(
        "$pluginDir\tests",
        "$pluginDir\.git"
    )

    foreach ($path in $devPaths) {
        if (Test-Path $path) {
            Remove-Item $path -Recurse -Force
        }
    }

    # Remove Python bytecode
    Get-ChildItem -Path $pluginDir -Filter "*.pyc" -Recurse | Remove-Item -Force
    Get-ChildItem -Path $pluginDir -Filter "__pycache__" -Recurse | Remove-Item -Force -Recurse
}

# Create ZIP
Write-Host "Creating ZIP archive..." -ForegroundColor Gray
Compress-Archive -Path "$tempDir\addons" -DestinationPath $outputFile -Force

# Cleanup
Remove-Item $tempDir -Recurse -Force

# Get file info
$fileInfo = Get-Item $outputFile
$sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)

Write-Host ""
Write-Host "✅ Build complete!" -ForegroundColor Green
Write-Host "   Output: $outputFile" -ForegroundColor White
Write-Host "   Size: $sizeMB MB" -ForegroundColor White

# Calculate SHA256
$hash = Get-FileHash $outputFile -Algorithm SHA256
Write-Host "   SHA256: $($hash.Hash)" -ForegroundColor White
Write-Host ""
