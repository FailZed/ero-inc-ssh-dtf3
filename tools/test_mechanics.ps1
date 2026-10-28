param(
    [switch]$Isolated, [switch]$Pack, [switch]$Visible, [switch]$Native,
    [string]$Godot = '', [switch]$DialogueOnly, [switch]$RandomEventsOnly, [switch]$NpcCareersOnly,
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$RunId = [Guid]::NewGuid().ToString('N')
)
if ($RandomEventsOnly) {
    if ($DialogueOnly -or $NpcCareersOnly -or $Visible -or $Native) { throw 'Choose one headless focused suite.' }
    & (Join-Path $PSScriptRoot 'test_random_events.ps1') -Pack:$Pack
    exit $LASTEXITCODE
}
& (Join-Path $PSScriptRoot 'test.ps1') -Suite 'mechanics' -Isolated:$Isolated -Pack:$Pack -Visible:$Visible -Native:$Native -Godot $Godot -DialogueOnly:$DialogueOnly -NpcCareersOnly:$NpcCareersOnly -RunId $RunId
exit $LASTEXITCODE
