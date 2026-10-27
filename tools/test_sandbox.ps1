$ErrorActionPreference = 'Stop'
$sandboxProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$sandboxReportRoot = Join-Path (Split-Path -Parent $sandboxProjectRoot) '.research\school-0.981\sandbox-2026-10-27'
New-Item -ItemType Directory -Force -Path $sandboxReportRoot | Out-Null
$sandboxArguments = @('--headless','--script','res://tests/gameplay/run_sandbox.gd','--quit-after','240')
$sandboxOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $sandboxArguments 2>&1
$sandboxExit = $LASTEXITCODE
$sandboxOutput | Set-Content -LiteralPath (Join-Path $sandboxReportRoot 'tests.log') -Encoding utf8
$sandboxOutput | ForEach-Object { Write-Output $_ }
$sandboxText = $sandboxOutput -join "`n"
if ($sandboxExit -ne 0 -or $sandboxText -match 'SCRIPT ERROR:|FAIL:' -or $sandboxText -notmatch 'SANDBOX_RESULT .*"failed":0') { throw 'Sandbox verification failed.' }
$sandboxFlowArguments = @('--headless','--script','res://tests/gameplay/sandbox_flow.gd','--quit-after','240')
$sandboxFlowOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $sandboxFlowArguments 2>&1
$sandboxFlowExit = $LASTEXITCODE
$sandboxFlowOutput | Set-Content -LiteralPath (Join-Path $sandboxReportRoot 'flow.log') -Encoding utf8
$sandboxFlowOutput | ForEach-Object { Write-Output $_ }
$sandboxFlowText = $sandboxFlowOutput -join "`n"
if ($sandboxFlowExit -ne 0 -or $sandboxFlowText -match 'SCRIPT ERROR:|FAIL:' -or $sandboxFlowText -notmatch 'SANDBOX_FLOW_RESULT .*"failed":0') { throw 'Real sandbox flow verification failed.' }
$sandboxFixture = Join-Path $sandboxReportRoot 'snapshot.json'
foreach ($sandboxMode in @('write','read')) {
    $sandboxSnapshotArguments = @('--headless','--script','res://tests/gameplay/sandbox_snapshot.gd','--quit-after','240','--',"--$sandboxMode=$sandboxFixture")
    $sandboxSnapshotOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $sandboxSnapshotArguments 2>&1
    $sandboxSnapshotExit = $LASTEXITCODE
    $sandboxSnapshotOutput | Set-Content -LiteralPath (Join-Path $sandboxReportRoot "snapshot-$sandboxMode.log") -Encoding utf8
    $sandboxSnapshotOutput | Where-Object { "$_" -match '^SANDBOX_SNAPSHOT_RESULT ' } | Write-Output
    $sandboxSnapshotText = $sandboxSnapshotOutput -join "`n"
    if ($sandboxSnapshotExit -ne 0 -or $sandboxSnapshotText -match 'SCRIPT ERROR:|FAIL:' -or $sandboxSnapshotText -notmatch 'SANDBOX_SNAPSHOT_RESULT .*"ok":true') {
        $sandboxSnapshotOutput | Write-Output
        throw "Sandbox cross-process $sandboxMode failed."
    }
}
