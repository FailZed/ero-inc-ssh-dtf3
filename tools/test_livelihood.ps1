param([switch]$Native)
$ErrorActionPreference = 'Stop'
$workProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workReportRoot = Join-Path (Split-Path -Parent $workProjectRoot) '.research\school-0.981\livelihood-2026-10-27'
New-Item -ItemType Directory -Force -Path $workReportRoot | Out-Null
$workArguments = @('--headless','--script','res://tests/gameplay/livelihood.gd','--quit-after','240')
$workOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $workArguments 2>&1
$workExit = $LASTEXITCODE
$workOutput | Set-Content -LiteralPath (Join-Path $workReportRoot 'rules.log') -Encoding utf8
$workOutput | Where-Object { "$_" -match '^LIVELIHOOD_RESULT |SCRIPT ERROR:|FAIL:' } | Write-Output
if ($workExit -ne 0 -or ($workOutput -join "`n") -match 'SCRIPT ERROR:|FAIL:' -or ($workOutput -join "`n") -notmatch 'LIVELIHOOD_RESULT .*"failed":0') { throw 'Livelihood checks failed; see rules.log.' }
$workFixture = Join-Path $workReportRoot 'snapshot.json'
foreach ($workMode in @('write','read')) {
    $workSnapshotArguments = @('--headless','--script','res://tests/gameplay/livelihood_snapshot.gd','--quit-after','240','--',"--$workMode=$workFixture")
    $workSnapshotOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $workSnapshotArguments 2>&1
    $workSnapshotExit = $LASTEXITCODE
    $workSnapshotOutput | Set-Content -LiteralPath (Join-Path $workReportRoot "snapshot-$workMode.log") -Encoding utf8
    $workSnapshotOutput | Where-Object { "$_" -match '^LIVELIHOOD_SNAPSHOT_RESULT |SCRIPT ERROR:' } | Write-Output
    if ($workSnapshotExit -ne 0 -or ($workSnapshotOutput -join "`n") -match 'SCRIPT ERROR:|FAIL:' -or ($workSnapshotOutput -join "`n") -notmatch 'LIVELIHOOD_SNAPSHOT_RESULT .*"ok":true') { throw "Livelihood snapshot $workMode failed." }
}
if ($Native) {
    $workNativeArguments = @('--rendering-method','gl_compatibility','--windowed','--resolution','1366x768','--script','res://tests/gameplay/capture_livelihood.gd','--quit-after','600')
    $workNativeOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $workNativeArguments 2>&1
    $workNativeExit = $LASTEXITCODE
    $workNativeOutput | Set-Content -LiteralPath (Join-Path $workReportRoot 'native.log') -Encoding utf8
    $workNativeOutput | Where-Object { "$_" -match '^LIVELIHOOD_NATIVE_RESULT |SCRIPT ERROR:|FAIL:' } | Write-Output
    if ($workNativeExit -ne 0 -or ($workNativeOutput -join "`n") -match 'SCRIPT ERROR:|FAIL:' -or ($workNativeOutput -join "`n") -notmatch 'LIVELIHOOD_NATIVE_RESULT .*"failed":0') { throw 'Native livelihood flow failed.' }
}
