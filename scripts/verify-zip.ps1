# Check a built plugin ZIP before it is published
# Usage: .\scripts\verify-zip.ps1 -Path dist/sprite-pipeline-v1.1.0.zip
# Lists the entries and fails if an entry name contains "\" (unzip on Linux and macOS
# keeps it as part of the file name), if addons/sprite_pipeline/plugin.cfg is missing,
# or if an entry starts with tests/.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# .NET resolves relative paths against the process directory, not the PowerShell location
$zipPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    Write-Host "ZIP not found: $Path" -ForegroundColor Red
    exit 1
}

$archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $names = @($archive.Entries | ForEach-Object { $_.FullName })
} finally {
    $archive.Dispose()
}

Write-Host "Entries in ${Path}:" -ForegroundColor Gray
foreach ($name in $names) {
    Write-Host "   $name"
}

$problems = @()
foreach ($name in $names) {
    if ($name.Contains('\')) {
        $problems += "Entry name contains '\': $name"
    }
    if ($name.StartsWith("tests/") -or $name.StartsWith("tests\")) {
        $problems += "Test file in the ZIP: $name"
    }
}
if ($names -cnotcontains "addons/sprite_pipeline/plugin.cfg") {
    $problems += "addons/sprite_pipeline/plugin.cfg is missing"
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) {
        Write-Host "   $problem" -ForegroundColor Red
    }
    Write-Host "ZIP check failed: $($problems.Count) problems in $($names.Count) entries" -ForegroundColor Red
    exit 1
}
Write-Host "ZIP check passed: $($names.Count) entries" -ForegroundColor Green
exit 0
