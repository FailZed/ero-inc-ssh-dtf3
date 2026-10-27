param([switch]$Test, [string]$Capture)
$ErrorActionPreference = 'Stop'
if ($Test) {
    & (Join-Path $PSScriptRoot 'test_characters.ps1')
    exit $LASTEXITCODE
}
$taskArguments = @('--rendering-method', 'gl_compatibility', '--resolution', '1440x900', 'res://scenes/characters/character_workshop.tscn')
if ($Capture) { $taskArguments += @('--', "--capture=$Capture", '--capture-exit') }
& (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $taskArguments
exit $LASTEXITCODE
