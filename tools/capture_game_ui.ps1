param([switch]$Interactions)
$ErrorActionPreference = 'Stop'
$taskProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
foreach ($taskReview in @(@('1920x1080','1920'),@('1366x768','1366'),@('2560x1080','ultrawide'))) {
    $taskReviewName = $(if ($Interactions) { 'compact-' } else { 'approved-scene-' }) + $taskReview[1]
    $taskCapturePath = Join-Path $taskProjectRoot ('docs/ui/captures/' + $taskReviewName)
    $taskReviewLog = Join-Path $taskProjectRoot ('docs/ui/' + $taskReviewName + '.log')
    $taskCaptureArguments = @('--rendering-method','gl_compatibility','--resolution',$taskReview[0],'res://scenes/debug/ui_review.tscn','--',('--capture=' + $taskCapturePath))
    if ($Interactions) { $taskCaptureArguments += '--interaction-only' }
    & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $taskCaptureArguments *> $taskReviewLog
    $taskReviewExit = $LASTEXITCODE
    $taskReviewText = Get-Content -LiteralPath $taskReviewLog -Raw
    $taskReviewText -split "`n" | Where-Object { $_ -match 'UI_REVIEW_RESULT|SCRIPT ERROR:|UI capture failed|Story text did not settle' } | Write-Output
    if ($taskReviewExit -ne 0 -or $taskReviewText -match 'SCRIPT ERROR:|UI capture failed|Story text did not settle' -or $taskReviewText -notmatch 'UI_REVIEW_RESULT .*"failed":0') { throw "Native UI review failed. See $taskReviewLog" }
}
