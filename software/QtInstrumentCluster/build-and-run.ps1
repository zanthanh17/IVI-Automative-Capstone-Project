param(
    [switch]$SkipBuild,
    [int]$Jobs = 4
)

$ErrorActionPreference = 'Stop'

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $projectDir 'build'
$projectFile = Join-Path $projectDir 'QtInstrumentCluster.pro'
$exePath = Join-Path $buildDir 'release\QtInstrumentCluster.exe'

$qmake = 'C:\Qt\6.9.1\mingw_64\bin\qmake.exe'
$make = 'C:\Qt\Tools\mingw1310_64\bin\mingw32-make.exe'
$windeployqt = 'C:\Qt\6.9.1\mingw_64\bin\windeployqt.exe'

if (-not (Test-Path $qmake)) { throw "qmake not found: $qmake" }
if (-not (Test-Path $make)) { throw "mingw32-make not found: $make" }
if (-not (Test-Path $windeployqt)) { throw "windeployqt not found: $windeployqt" }

$env:PATH = "C:\Qt\6.9.1\mingw_64\bin;C:\Qt\Tools\mingw1310_64\bin;$env:PATH"

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

if (-not $SkipBuild) {
    $running = Get-Process QtInstrumentCluster -ErrorAction SilentlyContinue
    if ($running) {
        $running | Stop-Process -Force
        Start-Sleep -Milliseconds 400
    }
}

Push-Location $buildDir
try {
    if (-not $SkipBuild) {
        & $qmake $projectFile
        if ($LASTEXITCODE -ne 0) { throw "qmake failed with exit code $LASTEXITCODE" }

        & $make "-j$Jobs"
        if ($LASTEXITCODE -ne 0) { throw "make failed with exit code $LASTEXITCODE" }
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path $exePath)) {
    throw "Executable not found: $exePath"
}

# Ensure runtime plugins/QML modules (including QtLocation geoservices) are deployed.
Push-Location (Split-Path -Parent $exePath)
try {
    & $windeployqt --qmldir $projectDir --release $exePath
    if ($LASTEXITCODE -ne 0) { throw "windeployqt failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$proc = Start-Process -FilePath $exePath -WorkingDirectory $projectDir -PassThru
Start-Sleep -Seconds 2
$proc.Refresh()

if ($proc.HasExited) {
    throw "QtInstrumentCluster exited immediately (exit code: $($proc.ExitCode)). Run from your local terminal to inspect runtime issues."
}

Write-Host "Launched: $exePath (PID: $($proc.Id))"
