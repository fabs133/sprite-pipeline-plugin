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

# Create ZIP. Entry names are built here with "/" separators: Compress-Archive in
# Windows PowerShell 5.1 writes "\", which unzip on Linux and macOS keeps as part of
# the file name, so the plugin would not load.
Write-Host "Creating ZIP archive..." -ForegroundColor Gray
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
# .NET resolves relative paths against the process directory, not the PowerShell location
$zipPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outputFile)
$root = $tempDir.FullName
$addonsDir = Join-Path $root "addons"
$directories = @($addonsDir) + [System.IO.Directory]::GetDirectories($addonsDir, "*", [System.IO.SearchOption]::AllDirectories) | Sort-Object
$files = [System.IO.Directory]::GetFiles($addonsDir, "*", [System.IO.SearchOption]::AllDirectories) | Sort-Object
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($directory in $directories) {
        $entryName = $directory.Substring($root.Length + 1).Replace('\', '/') + "/"
        $archive.CreateEntry($entryName) | Out-Null
    }
    foreach ($file in $files) {
        $entryName = $file.Substring($root.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file, $entryName, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $archive.Dispose()
}

# Cleanup
Remove-Item $tempDir -Recurse -Force

# Check the entry names before anything publishes the ZIP
& "$PSScriptRoot\verify-zip.ps1" -Path $outputFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed: the ZIP did not pass verify-zip.ps1" -ForegroundColor Red
    exit 1
}

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
