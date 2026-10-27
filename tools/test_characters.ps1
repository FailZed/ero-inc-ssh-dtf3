param([switch]$Pack, [switch]$Visible)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskTestRoot = Join-Path (Split-Path -Parent $taskRoot) '.dev-setup/characters-isolated'
$taskLogs = 'E:/Ai/ComfyUI-EroInc/runtime/cubism/verification'
New-Item -ItemType Directory -Path $taskTestRoot, $taskLogs -Force | Out-Null
foreach ($taskRelative in @('scripts/characters','scripts/ui/characters','data/characters','tests/characters','scenes/characters','assets/characters/mdrg_study','addons/gd_cubism')) {
    $taskDestination = Join-Path $taskTestRoot (Split-Path -Parent $taskRelative)
    New-Item -ItemType Directory -Path $taskDestination -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $taskRoot $taskRelative) -Destination $taskDestination -Recurse -Force
}
New-Item -ItemType Directory -Path "$taskTestRoot/scripts/ui/gameplay", "$taskTestRoot/assets/textures/ui/windows-v2" -Force | Out-Null
Copy-Item -LiteralPath "$taskRoot/scripts/ui/gameplay/ui_factory.gd" -Destination "$taskTestRoot/scripts/ui/gameplay" -Force
Copy-Item -LiteralPath "$taskRoot/assets/textures/ui/windows-v2/window_surface.png" -Destination "$taskTestRoot/assets/textures/ui/windows-v2" -Force
Set-Content -LiteralPath "$taskTestRoot/project.godot" -Encoding utf8 -Value @'
config_version=5
[application]
config/name="EroInc Character Tests"
config/use_custom_user_dir=true
config/custom_user_dir_name="EroIncCharacterTests"
run/main_scene="res://scenes/characters/character_workshop.tscn"
[display]
window/size/viewport_width=1440
window/size/viewport_height=900
[rendering]
renderer/rendering_method="gl_compatibility"
'@
$taskImport = & "$PSScriptRoot/godot.ps1" --path $taskTestRoot --headless --editor --import --quit 2>&1
$taskImport | Set-Content -LiteralPath "$taskLogs/import.log" -Encoding utf8
if ($LASTEXITCODE -ne 0 -or ($taskImport -join "`n") -match 'SCRIPT ERROR:|Parse Error:') { throw "Character import failed: $taskLogs/import.log" }
$taskArguments = @('--path',$taskTestRoot,'--headless','--quit-after','600','--script','res://tests/characters/run.gd')
if ($Visible) { $taskArguments = @('--path',$taskTestRoot,'--rendering-method','gl_compatibility','--quit-after','600','--script','res://tests/characters/run.gd') }
if ($Pack) {
    Set-Content -LiteralPath "$taskTestRoot/export_presets.cfg" -Encoding utf8 -Value @'
[preset.0]
name="Character Test Pack"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.json,*.moc3"
exclude_filter=""
[preset.0.options]
custom_template/debug=""
custom_template/release=""
'@
    $taskPackPath = Join-Path (Split-Path -Parent $taskTestRoot) 'characters-test.pck'
    $taskExport = & "$PSScriptRoot/godot.ps1" --path $taskTestRoot --headless --export-pack 'Character Test Pack' $taskPackPath 2>&1
    $taskExport | Set-Content -LiteralPath "$taskLogs/export.log" -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or ($taskExport -join "`n") -match 'SCRIPT ERROR:|Parse Error:|ERROR:') { throw "Character pack export failed: $taskLogs/export.log" }
    $taskLaunchRoot = Join-Path (Split-Path -Parent $taskTestRoot) 'characters-packed'
    New-Item -ItemType Directory -Path $taskLaunchRoot -Force | Out-Null
    # A PCK stores resources; the OS loads native DLLs from the filesystem.
    $taskNativeTarget = Join-Path $taskLaunchRoot 'addons/gd_cubism/bin'
    New-Item -ItemType Directory -Path $taskNativeTarget -Force | Out-Null
    Copy-Item -LiteralPath "$taskTestRoot/addons/gd_cubism/bin/libgd_cubism.windows.debug.x86_64.dll", "$taskTestRoot/addons/gd_cubism/bin/Live2DCubismCore.dll" -Destination $taskNativeTarget -Force
    $taskArguments = @('--path',$taskLaunchRoot,'--headless','--main-pack',$taskPackPath,'--quit-after','600','--script','res://tests/characters/run.gd')
}
$taskOutput = & "$PSScriptRoot/godot.ps1" -EngineArguments $taskArguments 2>&1
$taskCode = $LASTEXITCODE
$taskMode = if ($Pack) { 'pack' } elseif ($Visible) { 'visible' } else { 'headless' }
$taskOutput | Set-Content -LiteralPath "$taskLogs/tests-$taskMode.log" -Encoding utf8
$taskOutput | ForEach-Object { Write-Output $_ }
if ($taskCode -ne 0 -or ($taskOutput -join "`n") -match 'SCRIPT ERROR:|FAIL:' -or ($taskOutput -join "`n") -notmatch 'CHARACTERS_RESULT .*"failed":0') { throw "Character checks failed: $taskLogs/tests-$taskMode.log" }
Write-Output "Character checks passed: $taskLogs/tests-$taskMode.log"
