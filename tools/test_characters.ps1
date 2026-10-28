param(
    [switch]$Isolated = $true, [switch]$Pack, [switch]$Visible, [switch]$Native,
    [string]$Godot = '',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$RunId = [Guid]::NewGuid().ToString('N')
)
& (Join-Path $PSScriptRoot 'test.ps1') -Suite 'characters' -Isolated:$Isolated -Pack:$Pack -Visible:$Visible -Native:$Native -Godot $Godot -RunId $RunId
exit $LASTEXITCODE
