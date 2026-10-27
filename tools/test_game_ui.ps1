param()
$ErrorActionPreference = 'Stop'
$taskProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskLogPath = Join-Path $taskProjectRoot 'docs/ui/test-ui.log'
$taskOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments @('--headless','--script','res://tests/gameplay/run_ui.gd','--quit-after','900') 2>&1
$taskExit = $LASTEXITCODE
$taskOutput | Set-Content -LiteralPath $taskLogPath -Encoding utf8
$taskText = $taskOutput -join "`n"
$taskOutput | Where-Object { "$_" -match 'GAME_UI_RESULT|INTEGRATION_ROUTES_RESULT|FAIL:|SCRIPT ERROR:' } | ForEach-Object { Write-Output $_ }
if ($taskExit -ne 0 -or $taskText -match 'SCRIPT ERROR:|FAIL:|ERROR: The object|Parse Error:' -or $taskText -notmatch 'GAME_UI_RESULT .*"failed":0') { throw "Game UI checks failed. See $taskLogPath" }
Write-Output "Game UI checks passed. Log: $taskLogPath"
