param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$EngineArguments = @('--editor')
)
$ErrorActionPreference = 'Stop'
$taskProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskVersion = (Get-Content -LiteralPath (Join-Path $taskProjectRoot '.godot-version') -Raw).Trim()
$taskEngine = Join-Path $env:LOCALAPPDATA "Programs\Godot\$taskVersion\Godot_v$taskVersion-stable_win64_console.exe"
if (-not (Test-Path -LiteralPath $taskEngine)) { throw "Install Godot $taskVersion stable at $taskEngine" }
# User instruction: game processes must not open a Windows audio endpoint.
if ('--audio-driver' -in $EngineArguments) { throw 'Audio is disabled by this launcher; do not override the driver.' }
& $taskEngine --audio-driver Dummy --path $taskProjectRoot @EngineArguments
exit $LASTEXITCODE
