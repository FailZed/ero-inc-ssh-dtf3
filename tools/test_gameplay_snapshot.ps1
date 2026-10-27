$ErrorActionPreference = 'Stop'
$snapshotProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$snapshotReportRoot = Join-Path (Split-Path -Parent $snapshotProjectRoot) '.research\school-0.981\phase5'
New-Item -ItemType Directory -Force -Path $snapshotReportRoot | Out-Null
$snapshotFixture = Join-Path $snapshotReportRoot 'systems-snapshot.json'
foreach ($snapshotMode in @('write', 'read')) {
    $snapshotArguments = @('--headless', '--script', 'res://tests/gameplay/snapshot_process.gd', '--quit-after', '240', '--', "--$snapshotMode=$snapshotFixture")
    $snapshotOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $snapshotArguments 2>&1
    $snapshotExit = $LASTEXITCODE
    $snapshotOutput | Set-Content -LiteralPath (Join-Path $snapshotReportRoot "snapshot-$snapshotMode.log") -Encoding utf8
    $snapshotOutput | Where-Object { "$_" -match '^SNAPSHOT_PROCESS_RESULT ' } | Write-Output
    $snapshotText = $snapshotOutput -join "`n"
    if ($snapshotExit -ne 0 -or $snapshotText -match 'SCRIPT ERROR:|FAIL:' -or $snapshotText -notmatch 'SNAPSHOT_PROCESS_RESULT .*"ok":true') {
        $snapshotOutput | Write-Output
        throw "Cross-process snapshot $snapshotMode failed."
    }
}
