param([string]$Capture)
$ErrorActionPreference = 'Stop'
$taskArguments = @('--rendering-method','gl_compatibility','--resolution','1440x900','res://scenes/characters/conversation_room.tscn')
if ($Capture) { $taskArguments += @('--',"--capture-conversation=$Capture",'--capture-exit') }
& (Join-Path $PSScriptRoot 'godot.ps1') -EngineArguments $taskArguments
exit $LASTEXITCODE
