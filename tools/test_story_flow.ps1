param([string]$Godot = "$env:LOCALAPPDATA\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe")
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$reportDir = Join-Path (Split-Path -Parent $projectRoot) '.research\school-0.981\phase5'
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
foreach ($case in 0..4) {
    $branch = if ($case -eq 4) { 2 } else { $case }
    $flowArguments = @("--branch=$branch")
    $flowArguments += "--difficulty=$(@('easy','normal','hard','custom','custom')[$case])"
    if ($case -eq 3) { $flowArguments += '--points=10' }
    if ($case -eq 4) { $flowArguments += '--points=60' }
    if ($branch -eq 3) { $flowArguments += '--flee' }
    if ($case -eq 4) { $flowArguments += '--teacher-right' }
    $output = & $Godot --audio-driver Dummy --headless --path $projectRoot --script res://tests/gameplay/flow.gd -- @flowArguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $reportDir "flow-$case.log") -Encoding utf8
    $result = $output | Where-Object { "$_" -match '^FLOW_RESULT ' }
    $result | ForEach-Object { Write-Output $_ }
    $text = $output -join "`n"
    if ($exitCode -ne 0 -or $text -match 'SCRIPT ERROR:|FAIL:' -or $text -notmatch 'FLOW_RESULT .*"failed":0') {
        throw "Story flow case $case failed. See phase5/flow-$case.log."
    }
}
