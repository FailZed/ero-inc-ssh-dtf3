# Minimal current-city domain smoke: no autoloads, live saves, exports, or windows.
$ErrorActionPreference = 'Stop'
$cityProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$cityHarnessRoot = Join-Path $cityProjectRoot '.godot/city-graph-smoke'
New-Item -ItemType Directory -Path $cityHarnessRoot -Force | Out-Null
foreach ($relative in @('scripts/mechanics','scripts/gameplay','data/mechanics','data/world')) {
    $parent = Split-Path -Parent (Join-Path $cityHarnessRoot $relative)
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $cityProjectRoot $relative) -Destination $parent -Recurse -Force
}
New-Item -ItemType Directory -Path (Join-Path $cityHarnessRoot 'tools') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $cityProjectRoot 'tools/godot.ps1') -Destination (Join-Path $cityHarnessRoot 'tools/godot.ps1') -Force
Copy-Item -LiteralPath (Join-Path $cityProjectRoot '.godot-version') -Destination (Join-Path $cityHarnessRoot '.godot-version') -Force
Copy-Item -LiteralPath (Join-Path $cityProjectRoot 'tests/gameplay/city_graph_runtime_smoke.gd') -Destination (Join-Path $cityHarnessRoot 'run.gd') -Force
@'
config_version=5
[application]
config/name="EroInc City Graph Smoke"
[rendering]
renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $cityHarnessRoot 'project.godot') -Encoding utf8
$cityPriorAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $cityProjectRoot '.godot/city-graph-smoke-userdata'
    $parseOutput = & (Join-Path $cityProjectRoot 'tools/godot.ps1') --headless --path $cityHarnessRoot --check-only --script res://run.gd 2>&1
    $parseOutput | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($parseOutput -match 'SCRIPT ERROR|Parse Error|Compile Error')) { throw 'City smoke did not compile.' }
    $runtimeOutput = & (Join-Path $cityProjectRoot 'tools/godot.ps1') --headless --path $cityHarnessRoot --script res://run.gd 2>&1
    $runtimeOutput | Write-Output
    $runtimeOutput | Set-Content -LiteralPath (Join-Path $cityProjectRoot '.godot/city-graph-smoke.log') -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or ($runtimeOutput -match 'SCRIPT ERROR|Parse Error|Compile Error|FAIL ') -or -not ($runtimeOutput -match 'CITY_SMOKE checks=89 failures=0')) { throw 'City smoke failed; see .godot/city-graph-smoke.log.' }
} finally {
    $env:APPDATA = $cityPriorAppData
}
