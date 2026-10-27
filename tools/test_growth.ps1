param([switch]$Native)
$ErrorActionPreference = 'Stop'
$growthProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$growthReportRoot = Join-Path (Split-Path -Parent $growthProjectRoot) '.research\school-0.981\growth-2026-10-27'
New-Item -ItemType Directory -Force -Path $growthReportRoot | Out-Null
function Invoke-GrowthCheck([string]$GrowthScript,[string]$GrowthLog,[string]$GrowthMarker,[string[]]$GrowthExtra=@()) {
    $growthArguments = @('--headless','--script',$GrowthScript,'--quit-after','240')+$GrowthExtra
    $growthOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $growthArguments 2>&1
    $growthExit = $LASTEXITCODE
    $growthOutput | Set-Content -LiteralPath (Join-Path $growthReportRoot $GrowthLog) -Encoding utf8
    $growthOutput | Where-Object { "$_" -match "$GrowthMarker|SCRIPT ERROR:|FAIL:" } | Write-Output
    $growthText = $growthOutput -join "`n"
    if ($growthExit -ne 0 -or $growthText -match 'SCRIPT ERROR:|FAIL:|String formatting error:' -or $growthText -notmatch "$GrowthMarker .*(`"failed`":0|`"ok`":true)") { throw "Growth check failed: $GrowthLog" }
}
Invoke-GrowthCheck 'res://tests/gameplay/growth.gd' 'rules.log' 'GROWTH_RESULT'
$growthFixture = Join-Path $growthReportRoot 'snapshot.json'
foreach ($growthMode in @('write','read')) { Invoke-GrowthCheck 'res://tests/gameplay/growth_snapshot.gd' "snapshot-$growthMode.log" 'GROWTH_SNAPSHOT_RESULT' @('--',"--$growthMode=$growthFixture") }
if ($Native) {
    $growthNativeArguments = @('--rendering-method','gl_compatibility','--windowed','--resolution','1366x768','--script','res://tests/gameplay/capture_growth.gd','--quit-after','600')
    $growthNativeOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $growthNativeArguments 2>&1
    $growthNativeExit = $LASTEXITCODE
    $growthNativeOutput | Set-Content -LiteralPath (Join-Path $growthReportRoot 'native.log') -Encoding utf8
    $growthNativeOutput | Where-Object { "$_" -match 'GROWTH_NATIVE_RESULT|SCRIPT ERROR:|FAIL:' } | Write-Output
    $growthNativeText = $growthNativeOutput -join "`n"
    if ($growthNativeExit -ne 0 -or $growthNativeText -match 'SCRIPT ERROR:|FAIL:|String formatting error:' -or $growthNativeText -notmatch 'GROWTH_NATIVE_RESULT .*"failed":0') { throw 'Native growth verification failed.' }
}
