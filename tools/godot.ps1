param([Parameter(ValueFromRemainingArguments = $true)][string[]]$EngineArguments = @('--editor'))
$ErrorActionPreference = 'Stop'
$taskPythonArgs = @()
$taskPython = if (Get-Command py -ErrorAction SilentlyContinue) { $taskPythonArgs = @('-3'); 'py' } elseif (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } elseif (Get-Command python -ErrorAction SilentlyContinue) { 'python' } else { throw 'Install Python 3.9 or newer.' }
& $taskPython @taskPythonArgs (Join-Path $PSScriptRoot 'runtime.py') run -- @EngineArguments
exit $LASTEXITCODE
