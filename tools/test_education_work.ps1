param([switch]$Native)
$ErrorActionPreference = 'Stop'
$educationProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$educationReport = Join-Path (Split-Path -Parent $educationProjectRoot) '.research\school-0.981\education-2026-10-28'
New-Item -ItemType Directory -Force -Path $educationReport | Out-Null
function Invoke-EducationCheck([string]$EducationScript,[string]$EducationLog,[string]$EducationMarker,[string[]]$EducationExtra=@(),[switch]$Visible) {
    [string[]]$educationArguments = if ($Visible) { @('--rendering-method','gl_compatibility','--windowed','--resolution','1366x900') } else { @('--headless') }
    $educationArguments += @('--script',$EducationScript,'--quit-after','1800')+$EducationExtra
    $educationOutput = & (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $educationArguments 2>&1
    $educationExit = $LASTEXITCODE
    $educationOutput | Set-Content -LiteralPath (Join-Path $educationReport $EducationLog) -Encoding utf8
    $educationText = $educationOutput -join "`n"
    $educationOutput | Where-Object { "$_" -match "$EducationMarker|SCRIPT ERROR:|FAIL:" } | Write-Output
    if ($educationExit -ne 0 -or $educationText -match 'SCRIPT ERROR:|FAIL:|String formatting error:' -or $educationText -notmatch "$EducationMarker .*(`"failed`":0|`"ok`":true)") { throw "Education verification failed: $EducationLog" }
}
Invoke-EducationCheck 'res://tests/gameplay/education_work.gd' 'rules.log' 'EDUCATION_WORK_RESULT'
foreach ($educationStatus in @('student','nonstudent')) {
    $educationFixture = Join-Path $educationReport "snapshot-$educationStatus.json"
    foreach ($educationMode in @('write','read')) {
        $educationExtra = @('--',"--$educationMode=$educationFixture")
        if ($educationStatus -eq 'nonstudent') { $educationExtra += '--nonstudent' }
        Invoke-EducationCheck 'res://tests/gameplay/sandbox_snapshot.gd' "snapshot-$educationStatus-$educationMode.log" 'SANDBOX_SNAPSHOT_RESULT' $educationExtra
    }
}
if ($Native) { Invoke-EducationCheck 'res://tests/gameplay/capture_education_work.gd' 'native.log' 'EDUCATION_NATIVE_RESULT' -Visible }
