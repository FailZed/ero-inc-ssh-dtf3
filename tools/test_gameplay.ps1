param([string]$Godot = "$env:LOCALAPPDATA\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe")
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$reportDir = Join-Path (Split-Path -Parent $projectRoot) '.research\school-0.981\phase5'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
$output = & $Godot --audio-driver Dummy --headless --path $projectRoot --script res://tests/gameplay/run.gd --quit-after 240 2>&1
$exitCode = $LASTEXITCODE
$output | Set-Content -LiteralPath (Join-Path $reportDir 'tests.log') -Encoding utf8
$output | ForEach-Object { Write-Output $_ }
$text = $output -join "`n"
if ($exitCode -ne 0 -or $text -match 'SCRIPT ERROR:|FAIL:' -or $text -notmatch 'GAMEPLAY_RESULT .*"failed":0') { throw 'Gameplay integration verification failed. See phase5/tests.log.' }
