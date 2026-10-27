$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskOutput = Join-Path (Split-Path -Parent $taskRoot) '.research\school-0.981\npc-reproduction-2026-10-27'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskFixture = Join-Path $taskOutput 'cross-process.json'
foreach ($taskMode in @('write', 'read')) {
    $taskEngineArgs = @('--headless', '--script', 'res://tests/mechanics/npc_reproduction_snapshot.gd', '--quit-after', '90', '--', "--mode=$taskMode", "--file=$taskFixture")
    $taskResult = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $taskEngineArgs 2>&1
    $taskExit = $LASTEXITCODE
    $taskResult | Set-Content -LiteralPath (Join-Path $taskOutput "snapshot-$taskMode.log") -Encoding utf8
    $taskResult | ForEach-Object { Write-Output $_ }
    $taskText = $taskResult -join "`n"
    if ($taskExit -ne 0 -or $taskText -match 'SCRIPT ERROR:|FAIL:' -or $taskText -notmatch 'NPC_REPRODUCTION_SNAPSHOT_RESULT .*"failed":0') { throw "NPC reproduction snapshot $taskMode failed" }
}
