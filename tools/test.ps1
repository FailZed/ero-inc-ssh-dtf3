param(
    [Parameter(Mandatory=$true)][string]$Suite,
    [switch]$Isolated, [switch]$Pack, [switch]$Visible, [switch]$Native,
    [string]$Godot = '',
    [switch]$DialogueOnly, [switch]$NpcCareersOnly,
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$RunId = [Guid]::NewGuid().ToString('N')
)
$ErrorActionPreference = 'Stop'
$taskPythonArgs = @()
$taskPython = if (Get-Command py -ErrorAction SilentlyContinue) { $taskPythonArgs = @('-3'); 'py' } elseif (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } elseif (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { throw 'Install Python 3.9 or newer.' }
$taskArguments = @($Suite,'--run-id',$RunId)
if ($DialogueOnly) { $taskArguments += '--dialogue-only' }
if ($NpcCareersOnly) { $taskArguments += '--npc-careers-only' }
if ($Isolated) { $taskArguments += '--isolated' }
if ($Pack) { $taskArguments += '--pack' }
if ($Visible) { $taskArguments += '--visible' }
if ($Native) { $taskArguments += '--native' }
$taskPreviousGodot = $env:EROINC_GODOT
try {
    if ($Godot) { $env:EROINC_GODOT = $Godot }
    & $taskPython @taskPythonArgs (Join-Path $PSScriptRoot 'test.py') @taskArguments
    $taskExit = $LASTEXITCODE
} finally { $env:EROINC_GODOT = $taskPreviousGodot }
exit $taskExit
