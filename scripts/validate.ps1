# Validation script for Sprite Pipeline plugin
# Checks for common issues before release

param(
    [switch]$Strict = $false
)

$ErrorActionPreference = "Stop"
$issuesFound = 0
$warningsFound = 0

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Sprite Pipeline Plugin Validator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

function Test-FileExists {
    param([string]$Path, [string]$Description)

    if (Test-Path $Path) {
        Write-Host "✅ $Description" -ForegroundColor Green
        return $true
    } else {
        Write-Host "❌ $Description - NOT FOUND" -ForegroundColor Red
        $script:issuesFound++
        return $false
    }
}

function Test-NoDebugPrints {
    Write-Host "Checking for debug print() statements..." -ForegroundColor Gray

    $gdFiles = Get-ChildItem -Path "addons/sprite_pipeline" -Filter "*.gd" -Recurse
    $foundPrints = @()

    foreach ($file in $gdFiles) {
        $content = Get-Content $file.FullName -Raw
        if ($content -match '^\s*print\(' -and $content -notmatch 'print_debug\(') {
            $foundPrints += $file.FullName
        }
    }

    if ($foundPrints.Count -eq 0) {
        Write-Host "✅ No debug print() statements found" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Found $($foundPrints.Count) files with print() statements:" -ForegroundColor Yellow
        $script:warningsFound++
        foreach ($file in $foundPrints) {
            Write-Host "   - $file" -ForegroundColor Yellow
        }
    }
}

function Test-VersionConsistency {
    Write-Host "Checking version consistency..." -ForegroundColor Gray

    # Extract version from plugin.cfg
    $pluginCfg = Get-Content "addons/sprite_pipeline/plugin.cfg" -Raw
    if ($pluginCfg -match 'version="([^"]+)"') {
        $pluginVersion = $Matches[1]
        Write-Host "   plugin.cfg version: $pluginVersion" -ForegroundColor Gray
    } else {
        Write-Host "❌ Could not extract version from plugin.cfg" -ForegroundColor Red
        $script:issuesFound++
        return
    }

    # Check pool_client.gd
    $poolClient = Get-Content "addons/sprite_pipeline/api/pool_client.gd" -Raw
    if ($poolClient -match 'const PLUGIN_VERSION := "([^"]+)"') {
        $codeVersion = $Matches[1]
        if ($codeVersion -eq $pluginVersion) {
            Write-Host "✅ Version consistent across files ($pluginVersion)" -ForegroundColor Green
        } else {
            Write-Host "❌ Version mismatch: plugin.cfg=$pluginVersion, code=$codeVersion" -ForegroundColor Red
            $script:issuesFound++
        }
    }
}

function Test-NoAPIKeys {
    Write-Host "Checking for hardcoded API keys..." -ForegroundColor Gray

    $gdFiles = Get-ChildItem -Path "addons/sprite_pipeline" -Filter "*.gd" -Recurse
    $suspiciousPatterns = @(
        'sk-[a-zA-Z0-9]{20,}',
        'Bearer [a-zA-Z0-9\-_]+\.[a-zA-Z0-9\-_]+',
        'api[_-]?key\s*=\s*["\'][^"\']{20,}["\']'
    )

    $foundKeys = @()

    foreach ($file in $gdFiles) {
        $content = Get-Content $file.FullName -Raw
        foreach ($pattern in $suspiciousPatterns) {
            if ($content -match $pattern) {
                $foundKeys += @{File = $file.FullName; Pattern = $pattern}
            }
        }
    }

    if ($foundKeys.Count -eq 0) {
        Write-Host "✅ No hardcoded API keys found" -ForegroundColor Green
    } else {
        Write-Host "❌ Found potential API keys in $($foundKeys.Count) locations!" -ForegroundColor Red
        $script:issuesFound += $foundKeys.Count
        foreach ($finding in $foundKeys) {
            Write-Host "   - $($finding.File)" -ForegroundColor Red
        }
    }
}

function Test-FileSize {
    Write-Host "Checking file sizes..." -ForegroundColor Gray

    $largeFiles = Get-ChildItem -Path "addons/sprite_pipeline" -Recurse -File |
        Where-Object { $_.Length -gt 1MB } |
        Select-Object FullName, @{Name="SizeMB";Expression={[math]::Round($_.Length/1MB, 2)}}

    if ($largeFiles.Count -eq 0) {
        Write-Host "✅ No files larger than 1MB" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Found $($largeFiles.Count) large files:" -ForegroundColor Yellow
        $script:warningsFound++
        foreach ($file in $largeFiles) {
            Write-Host "   - $($file.FullName) ($($file.SizeMB) MB)" -ForegroundColor Yellow
        }
    }
}

# Run all checks
Write-Host "Running validation checks..." -ForegroundColor Cyan
Write-Host ""

Test-FileExists "addons/sprite_pipeline/plugin.cfg" "plugin.cfg exists"
Test-FileExists "addons/sprite_pipeline/README.md" "README.md exists"
Test-FileExists "addons/sprite_pipeline/LICENSE" "LICENSE exists"
Test-FileExists "addons/sprite_pipeline/CHANGELOG.md" "CHANGELOG.md exists"
Test-FileExists "addons/sprite_pipeline/.gdignore" ".gdignore exists"

Write-Host ""
Test-VersionConsistency
Write-Host ""
Test-NoDebugPrints
Write-Host ""
Test-NoAPIKeys
Write-Host ""
Test-FileSize

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($issuesFound -eq 0 -and $warningsFound -eq 0) {
    Write-Host "✅ All checks passed!" -ForegroundColor Green
    exit 0
} elseif ($issuesFound -eq 0) {
    Write-Host "⚠️  $warningsFound warnings found" -ForegroundColor Yellow
    if ($Strict) {
        Write-Host "❌ Strict mode: Failing due to warnings" -ForegroundColor Red
        exit 1
    }
    exit 0
} else {
    Write-Host "❌ $issuesFound issues found, $warningsFound warnings" -ForegroundColor Red
    exit 1
}
