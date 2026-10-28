param([switch]$Isolated, [switch]$Pack, [switch]$Visible, [switch]$Native, [string]$Godot = '')
& (Join-Path $PSScriptRoot 'test.ps1') -Suite 'story' -Isolated:$Isolated -Pack:$Pack -Visible:$Visible -Native:$Native -Godot $Godot
exit $LASTEXITCODE
