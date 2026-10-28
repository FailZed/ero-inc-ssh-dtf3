$ErrorActionPreference = 'Stop'
$workBankProject = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workBankReport = Join-Path (Split-Path -Parent $workBankProject) '.research\school-0.981\work-banks-all-2026-10-28'
New-Item -ItemType Directory -Force -Path $workBankReport | Out-Null
function Invoke-WorkBank([string]$WorkBankScript,[string]$WorkBankLog,[string]$WorkBankMarker,[string[]]$WorkBankExtra=@()) {
    $workBankOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments (@('--headless','--script',$WorkBankScript,'--quit-after','1200')+$WorkBankExtra) 2>&1
    $workBankExit = $LASTEXITCODE
    $workBankOutput | Set-Content -LiteralPath (Join-Path $workBankReport $WorkBankLog) -Encoding utf8
    $workBankText = $workBankOutput -join "`n"
    $workBankOutput | Where-Object { "$_" -match "$WorkBankMarker|SCRIPT ERROR:|FAIL:" } | Write-Output
    if ($workBankExit -ne 0 -or $workBankText -match 'SCRIPT ERROR:|FAIL:' -or $workBankText -notmatch "$WorkBankMarker .*(`"failed`":0|`"ok`":true)") { throw "Work bank verification failed: $WorkBankLog" }
}
Invoke-WorkBank 'res://tests/gameplay/work_banks.gd' 'rules.log' 'WORK_BANKS_RESULT'
$workBankFixture = Join-Path $workBankReport 'expert-banks.json'
foreach ($workBankMode in @('write','read')) { Invoke-WorkBank 'res://tests/gameplay/work_banks_snapshot.gd' "snapshot-$workBankMode.log" 'WORK_BANKS_SNAPSHOT_RESULT' @('--',"--$workBankMode=$workBankFixture") }
