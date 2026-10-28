param([switch]$Pack)
$ErrorActionPreference = 'Stop'
$eventSourceRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$eventRunId = [Guid]::NewGuid().ToString('N')
$eventTestRoot = Join-Path $eventSourceRoot ".godot/random-events-$eventRunId"
New-Item -ItemType Directory -Path $eventTestRoot -Force | Out-Null
foreach ($relative in @('scripts/mechanics','scripts/gameplay','data/mechanics','data/world')) {
    $parent = Split-Path -Parent (Join-Path $eventTestRoot $relative)
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $eventSourceRoot $relative) -Destination $parent -Recurse -Force
}
foreach ($relative in @('scripts/ui/gameplay/random_event_offer.gd','tests/gameplay/random_events_runtime.gd','tools/godot.ps1','.godot-version')) {
    $target = Join-Path $eventTestRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $eventSourceRoot $relative) -Destination $target -Force
}
@'
config_version=5
[application]
config/name="EroInc Random Events Focused Tests"
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $eventTestRoot 'project.godot') -Encoding utf8
$eventPriorAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $eventTestRoot 'userdata'
    $eventArguments = @('--headless','--path',$eventTestRoot,'--script','res://tests/gameplay/random_events_runtime.gd')
    if ($Pack) {
        @'
[preset.0]
name="Random Event Tests"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="data/**/*.json"
exclude_filter=""
[preset.0.options]
custom_template/debug=""
custom_template/release=""
'@ | Set-Content -LiteralPath (Join-Path $eventTestRoot 'export_presets.cfg') -Encoding utf8
        $eventPack = Join-Path $eventTestRoot 'random-events-tests.pck'
        $exportOutput = & (Join-Path $eventTestRoot 'tools/godot.ps1') --headless --path $eventTestRoot --export-pack 'Random Event Tests' $eventPack 2>&1
        $exportOutput | Set-Content -LiteralPath (Join-Path $eventTestRoot 'export.log') -Encoding utf8
        if ($LASTEXITCODE -ne 0 -or ($exportOutput -join "`n") -match 'SCRIPT ERROR|Parse Error|ERROR:') { throw "Random event test pack export failed: $eventTestRoot" }
        $eventLaunchRoot = Join-Path $eventTestRoot 'packed-launch'
        New-Item -ItemType Directory -Path $eventLaunchRoot -Force | Out-Null
        $eventArguments = @('--headless','--path',$eventLaunchRoot,'--main-pack',$eventPack,'--script','res://tests/gameplay/random_events_runtime.gd')
    }
    $eventOutput = & (Join-Path $eventTestRoot 'tools/godot.ps1') @eventArguments 2>&1
    $eventExit = $LASTEXITCODE
    $eventOutput | Set-Content -LiteralPath (Join-Path $eventTestRoot 'result.log') -Encoding utf8
    $eventOutput | Write-Output
    if ($eventExit -ne 0 -or ($eventOutput -join "`n") -match 'SCRIPT ERROR|Parse Error|FAIL ' -or ($eventOutput -join "`n") -notmatch 'RANDOM_EVENTS_RESULT .*"failed":0') { throw "Random event checks failed: $eventTestRoot" }
    Write-Output "RANDOM_EVENTS_LOG=$eventTestRoot/result.log"
} finally {
    $env:APPDATA = $eventPriorAppData
}
