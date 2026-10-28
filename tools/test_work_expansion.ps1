param([switch]$Isolated, [switch]$Pack, [switch]$Visible, [switch]$Native, [string]$Godot = '')
& (Join-Path $PSScriptRoot 'test.ps1') -Suite 'work' -Isolated:$Isolated -Pack:$Pack -Visible:$Visible -Native:$Native -Godot $Godot
exit $LASTEXITCODE
