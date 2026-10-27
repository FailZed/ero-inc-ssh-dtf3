param(
    [string]$Godot = "$env:LOCALAPPDATA\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe",
    [switch]$Isolated,
    [switch]$Pack
)
$ErrorActionPreference = 'Stop'
if ($Pack -and -not $Isolated) { throw '-Pack requires -Isolated; the main project export settings are never changed.' }
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$artifactRoot = Join-Path (Split-Path -Parent $projectRoot) '.research\school-0.981'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$testRoot = $projectRoot
$userArguments = @()
if ($Isolated) {
    $testRoot = Join-Path (Split-Path -Parent $projectRoot) '.dev-setup\mechanics-isolated'
    foreach ($directory in @('scripts', 'data', 'tests', 'scenes')) {
        New-Item -ItemType Directory -Path (Join-Path $testRoot $directory) -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'scripts\mechanics') -Destination (Join-Path $testRoot 'scripts') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'data\mechanics') -Destination (Join-Path $testRoot 'data') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'tests\mechanics') -Destination (Join-Path $testRoot 'tests') -Recurse -Force
    $debugSceneTarget = Join-Path $testRoot 'scenes\debug'
    New-Item -ItemType Directory -Path $debugSceneTarget -Force | Out-Null
    foreach ($sceneFile in @('interior_lab.tscn', 'mechanics_lab.tscn', 'world_setup.tscn')) {
        Copy-Item -LiteralPath (Join-Path $projectRoot "scenes\debug\$sceneFile") -Destination $debugSceneTarget -Force
    }
    # Remove a preview copied by the older harness; it depends on main-game autoloads.
    Remove-Item -LiteralPath (Join-Path $debugSceneTarget 'gameplay_preview.tscn') -Force -ErrorAction SilentlyContinue
    $portraitTarget = Join-Path $testRoot 'assets\textures\portraits'
    New-Item -ItemType Directory -Path $portraitTarget -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'assets\textures\portraits\protagonist_layers') -Destination $portraitTarget -Recurse -Force
    Set-Content -LiteralPath (Join-Path $testRoot 'project.godot') -Encoding utf8 -Value @'
config_version=5
[application]
config/name="EroInc Mechanics Tests"
[display]
window/size/viewport_width=1366
window/size/viewport_height=900
[rendering]
renderer/rendering_method="gl_compatibility"
'@
    $userArguments = @('--', '--unit-only')
    if ($Pack) {
        Set-Content -LiteralPath (Join-Path $testRoot 'export_presets.cfg') -Encoding utf8 -Value @'
[preset.0]
name="Mechanics Test Pack"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="data/mechanics/*.json"
exclude_filter=""
export_path="../mechanics-test.pck"
[preset.0.options]
custom_template/debug=""
custom_template/release=""
'@
    }
}
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot not found: $Godot. Pass -Godot with its path." }
$mode = if ($Isolated) { 'isolated' } else { 'integration' }
if ($Pack) { $mode = 'pack' }
$logPath = Join-Path $artifactRoot "tests-$mode.log"
$preflight = & $Godot --audio-driver Dummy --headless --path $testRoot --script res://scripts/mechanics/simulation.gd --check-only 2>&1
if ($LASTEXITCODE -ne 0 -or ($preflight -join "`n") -match 'SCRIPT ERROR:|Parse Error:') {
    $preflight | Set-Content -LiteralPath $logPath -Encoding utf8
    $preflight | ForEach-Object { Write-Output $_ }
    throw "Mechanics scripts do not compile. See $logPath"
}
if ($Pack) {
    $packPath = Join-Path (Split-Path -Parent $testRoot) 'mechanics-test.pck'
    $exportOutput = & $Godot --audio-driver Dummy --headless --path $testRoot --export-pack 'Mechanics Test Pack' $packPath 2>&1
    $exportOutput | Set-Content -LiteralPath (Join-Path $artifactRoot 'export-mechanics.log') -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or ($exportOutput -join "`n") -match 'SCRIPT ERROR:|Parse Error:|ERROR:') {
        throw "Mechanics pack export failed. See $artifactRoot\export-mechanics.log"
    }
    # Launch without a loose project/catalog alongside the pack.
    $packLaunchRoot = Join-Path (Split-Path -Parent $testRoot) 'mechanics-packed'
    New-Item -ItemType Directory -Path $packLaunchRoot -Force | Out-Null
    $output = & $Godot --audio-driver Dummy --headless --quit-after 30 --path $packLaunchRoot --main-pack $packPath --script res://tests/mechanics/run.gd @userArguments 2>&1
} else {
    $output = & $Godot --audio-driver Dummy --headless --quit-after 30 --path $testRoot --script res://tests/mechanics/run.gd @userArguments 2>&1
}
$code = $LASTEXITCODE
$output | Set-Content -LiteralPath $logPath -Encoding utf8
$output | ForEach-Object { Write-Output $_ }
$textOutput = $output -join "`n"
if ($code -ne 0 -or $textOutput -match 'SCRIPT ERROR:|FAIL:' -or $textOutput -notmatch 'MECHANICS_RESULT .*"failed":0') {
    throw "Mechanics checks failed. See $logPath"
}
Write-Output "Checks passed. Log: $logPath"
