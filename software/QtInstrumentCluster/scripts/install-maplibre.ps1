<#
.SYNOPSIS
    Downloads and installs MapLibre Native Qt (v3.0.0) pre-built binaries for the project.

.DESCRIPTION
    This script downloads the MapLibre Native Qt plugin from the official GitHub release,
    extracts it, and copies the relevant files into the Qt installation directory so that
    the "maplibre" QtLocation plugin becomes available.

.PARAMETER QtDir
    Path to the Qt installation directory (e.g., C:\Qt\6.9.1\mingw_64).
    Defaults to C:\Qt\6.9.1\mingw_64.

.PARAMETER Force
    Re-download and re-install even if the plugin already exists.
#>
param(
    [string]$QtDir = 'C:\Qt\6.9.1\mingw_64',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$version   = '3.0.0'
$qtBuild   = 'Qt6.7.3'
$platform  = 'Windows'
$fileName  = "maplibre-native-qt_v${version}_${qtBuild}_${platform}.tar.bz2"
$url       = "https://github.com/maplibre/maplibre-native-qt/releases/download/v${version}/${fileName}"

$tempDir   = Join-Path $env:TEMP 'maplibre-install'
$archive   = Join-Path $tempDir $fileName

# Check if already installed
$pluginCheck = Join-Path $QtDir 'plugins\geoservices\qgeoservices_maplibre.dll'
$pluginCheckAlt = Get-ChildItem -Path (Join-Path $QtDir 'plugins\geoservices') -Filter '*maplibre*' -ErrorAction SilentlyContinue
if ((-not $Force) -and ((Test-Path $pluginCheck) -or $pluginCheckAlt)) {
    Write-Host "MapLibre plugin already installed in $QtDir" -ForegroundColor Green
    Write-Host "Use -Force to re-install."
    exit 0
}

# Create temp directory
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# Download
if (-not (Test-Path $archive)) {
    Write-Host "Downloading MapLibre Native Qt v${version} for ${qtBuild} ${platform}..."
    Write-Host "URL: $url"
    Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
    Write-Host "Downloaded: $archive" -ForegroundColor Green
} else {
    Write-Host "Archive already downloaded: $archive"
}

# Extract using tar (available on Windows 10+)
$extractDir = Join-Path $tempDir "maplibre-native-qt_v${version}"
if (Test-Path $extractDir) {
    Remove-Item -Recurse -Force $extractDir
}
Write-Host "Extracting..."
tar -xjf $archive -C $tempDir
Write-Host "Extracted to: $tempDir" -ForegroundColor Green

# Find the extracted content root
$candidates = Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like 'maplibre*' -or $_.Name -like 'install*' }
$installRoot = $null
foreach ($c in $candidates) {
    if (Test-Path (Join-Path $c.FullName 'lib')) {
        $installRoot = $c.FullName
        break
    }
    $sub = Get-ChildItem -Path $c.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'lib') }
    if ($sub) {
        $installRoot = $sub[0].FullName
        break
    }
}

if (-not $installRoot) {
    # Try flat extraction
    if (Test-Path (Join-Path $tempDir 'lib')) {
        $installRoot = $tempDir
    } else {
        Write-Host "Listing extracted contents for debugging:" -ForegroundColor Yellow
        Get-ChildItem -Path $tempDir -Recurse -Depth 3 | ForEach-Object { Write-Host $_.FullName }
        throw "Could not find extracted MapLibre installation root"
    }
}

Write-Host "Install root: $installRoot"

# Copy files into Qt directory
$items = @('lib', 'include', 'plugins', 'qml', 'share')
foreach ($item in $items) {
    $src = Join-Path $installRoot $item
    if (Test-Path $src) {
        $dst = Join-Path $QtDir $item
        Write-Host "Copying $item -> $dst"
        Copy-Item -Path $src -Destination $dst -Recurse -Force
    }
}

# Verify installation
$verifyPlugin = Get-ChildItem -Path (Join-Path $QtDir 'plugins\geoservices') -Filter '*maplibre*' -ErrorAction SilentlyContinue
if ($verifyPlugin) {
    Write-Host "`nMapLibre plugin installed successfully!" -ForegroundColor Green
    Write-Host "Plugin(s): $($verifyPlugin.Name -join ', ')"
} else {
    Write-Host "`nWARNING: Plugin DLL not found in expected location." -ForegroundColor Yellow
    Write-Host "You may need to manually copy the plugin from: $installRoot"
    Write-Host "Listing geoservices folder:"
    Get-ChildItem -Path (Join-Path $QtDir 'plugins\geoservices') -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
}

Write-Host "`nDone! You can now use Plugin { name: `"maplibre`" } in QML." -ForegroundColor Cyan
