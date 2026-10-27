param([switch]$Native)
$ErrorActionPreference = 'Stop'
$workExpansionRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workExpansionReport = Join-Path (Split-Path -Parent $workExpansionRoot) '.research\school-0.981\work-expansion-2026-10-27'
New-Item -ItemType Directory -Force -Path $workExpansionReport | Out-Null
function Invoke-WorkExpansion([string]$WorkScript,[string]$WorkLog,[string]$WorkMarker,[string[]]$WorkExtra=@(),[switch]$Visible) {
    [string[]]$workArguments = if ($Visible) { @('--rendering-method','gl_compatibility','--windowed','--resolution','1366x768') } else { @('--headless') }
    $workLimit = if ($Visible) { '1800' } else { '240' }
    $workArguments = $workArguments+@('--script',$WorkScript,'--quit-after',$workLimit)+$WorkExtra
    $workOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $workArguments 2>&1
    $workExit = $LASTEXITCODE
    $workOutput | Set-Content -LiteralPath (Join-Path $workExpansionReport $WorkLog) -Encoding utf8
    $workText = $workOutput -join "`n"
    $workOutput | Where-Object { "$_" -match "$WorkMarker|SCRIPT ERROR:|FAIL:" } | Write-Output
    if ($workExit -ne 0 -or $workText -match 'SCRIPT ERROR:|FAIL:|String formatting error:' -or $workText -notmatch "$WorkMarker .*(`"failed`":0|`"ok`":true)") { throw "Work expansion verification failed: $WorkLog" }
}
Invoke-WorkExpansion 'res://tests/gameplay/work_expansion.gd' 'rules.log' 'WORK_EXPANSION_RESULT'
$workExpansionFixture = Join-Path $workExpansionReport 'snapshot.json'
foreach ($workExpansionMode in @('write','read')) { Invoke-WorkExpansion 'res://tests/gameplay/work_expansion_snapshot.gd' "snapshot-$workExpansionMode.log" 'WORK_EXPANSION_SNAPSHOT_RESULT' @('--',"--$workExpansionMode=$workExpansionFixture") }
if ($Native) { Invoke-WorkExpansion 'res://tests/gameplay/capture_work_expansion.gd' 'native.log' 'WORK_EXPANSION_NATIVE_RESULT' -Visible }
