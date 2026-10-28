$ErrorActionPreference = 'Stop'
$npcEmploymentRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$npcEmploymentReport = Join-Path (Split-Path -Parent $npcEmploymentRoot) '.research\school-0.981\npc-employment-2026-10-28'
New-Item -ItemType Directory -Force -Path $npcEmploymentReport | Out-Null
function Invoke-NpcEmployment([string]$NpcEmploymentScript,[string]$NpcEmploymentLog,[string]$NpcEmploymentMarker,[string[]]$NpcEmploymentExtra=@()) {
    $npcEmploymentOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments (@('--headless','--script',$NpcEmploymentScript,'--quit-after','1200')+$NpcEmploymentExtra) 2>&1
    $npcEmploymentExit = $LASTEXITCODE
    $npcEmploymentOutput | Set-Content -LiteralPath (Join-Path $npcEmploymentReport $NpcEmploymentLog) -Encoding utf8
    $npcEmploymentText = $npcEmploymentOutput -join "`n"
    $npcEmploymentOutput | Where-Object { "$_" -match "$NpcEmploymentMarker|SCRIPT ERROR:|FAIL:" } | Write-Output
    if ($npcEmploymentExit -ne 0 -or $npcEmploymentText -match 'SCRIPT ERROR:|FAIL:' -or $npcEmploymentText -notmatch "$NpcEmploymentMarker .*(`"failed`":0|`"ok`":true)") { throw "NPC employment verification failed: $NpcEmploymentLog" }
}
Invoke-NpcEmployment 'res://tests/gameplay/npc_employment.gd' 'rules.log' 'NPC_EMPLOYMENT_RESULT'
$npcEmploymentFixture = Join-Path $npcEmploymentReport 'partial-work.json'
foreach ($npcEmploymentMode in @('write','read')) { Invoke-NpcEmployment 'res://tests/gameplay/npc_employment_snapshot.gd' "snapshot-$npcEmploymentMode.log" 'NPC_EMPLOYMENT_SNAPSHOT_RESULT' @('--',"--$npcEmploymentMode=$npcEmploymentFixture") }
