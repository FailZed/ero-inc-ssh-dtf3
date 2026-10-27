$ErrorActionPreference = 'Stop'
$remainingProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$remainingReportRoot = Join-Path (Split-Path -Parent $remainingProjectRoot) '.research\school-0.981\remaining-2026-10-27'
New-Item -ItemType Directory -Force -Path $remainingReportRoot | Out-Null
$remainingFixture = Join-Path $remainingReportRoot 'snapshot.json'
foreach ($remainingMode in @('write', 'read')) {
    $remainingArguments = @('--headless', '--script', 'res://tests/gameplay/remaining_snapshot.gd', '--quit-after', '240', '--', "--$remainingMode=$remainingFixture")
    $remainingOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $remainingArguments 2>&1
    $remainingExit = $LASTEXITCODE
    $remainingOutput | Set-Content -LiteralPath (Join-Path $remainingReportRoot "snapshot-$remainingMode.log") -Encoding utf8
    $remainingOutput | Where-Object { "$_" -match '^REMAINING_SNAPSHOT_RESULT ' } | Write-Output
    $remainingText = $remainingOutput -join "`n"
    if ($remainingExit -ne 0 -or $remainingText -match 'SCRIPT ERROR:|FAIL:' -or $remainingText -notmatch 'REMAINING_SNAPSHOT_RESULT .*"ok":true') {
        $remainingOutput | Write-Output
        throw "Remaining-systems cross-process $remainingMode failed."
    }
}
