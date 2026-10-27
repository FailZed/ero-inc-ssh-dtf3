param([switch]$Stop)
$ErrorActionPreference = 'Stop'
$artRoot = 'E:\Ai\ComfyUI-EroInc'
$portable = Join-Path $artRoot 'runtime\ComfyUI_windows_portable'
$python = Join-Path $portable 'python_embeded\python.exe'
$main = Join-Path $portable 'ComfyUI\main.py'
$pidFile = Join-Path $artRoot 'comfyui.pid'
if (Test-Path -LiteralPath $pidFile) {
    $artProcessId = [int](Get-Content -LiteralPath $pidFile -Raw)
    $existing = Get-CimInstance Win32_Process -Filter "ProcessId = $artProcessId"
    if ($existing -and $existing.ExecutablePath -eq $python -and $existing.CommandLine.Contains($main)) {
        if ($Stop) { Stop-Process -Id $artProcessId; Remove-Item -LiteralPath $pidFile; Write-Output 'ComfyUI stopped.'; exit }
        Write-Output "ComfyUI is already running: http://127.0.0.1:8188 (PID $artProcessId)"; exit
    }
}
if ($Stop) { Write-Output 'No matching ComfyUI process is running.'; exit }
if (!(Test-Path -LiteralPath $python)) { throw "Portable Python is missing: $python" }
foreach ($folder in @('cache','cache\huggingface','cache\torch','cache\pip','temp','input','output','logs','user','workflows')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $artRoot $folder) | Out-Null
}
$env:TEMP = Join-Path $artRoot 'temp'
$env:TMP = $env:TEMP
$env:HF_HOME = Join-Path $artRoot 'cache\huggingface'
$env:TORCH_HOME = Join-Path $artRoot 'cache\torch'
$env:PIP_CACHE_DIR = Join-Path $artRoot 'cache\pip'
$env:XDG_CACHE_HOME = Join-Path $artRoot 'cache'
$env:PYTHONIOENCODING = 'utf-8'
$env:OMP_NUM_THREADS = '4'
$env:MKL_NUM_THREADS = '4'
$gpuBudget = Get-Content -LiteralPath (Join-Path $artRoot 'gpu-budget.json') -Raw | ConvertFrom-Json
$gpuReserve = [double]$gpuBudget.vram_reserve_gb
if ($gpuReserve -lt 0 -or $gpuReserve -gt 15) { throw 'GPU reserve must be between 0 and 15 GB.' }
$argsList = @('-u', '-s', $main, '--listen', '127.0.0.1', '--port', '8188',
    '--disable-auto-launch', '--disable-all-custom-nodes', '--whitelist-custom-nodes', 'ero_inc_gpu_budget', '--offline',
    '--use-pytorch-cross-attention', '--disable-pinned-memory', '--fp16-text-enc', '--disable-async-offload', '--reserve-vram', $gpuReserve.ToString([Globalization.CultureInfo]::InvariantCulture),
    '--output-directory', (Join-Path $artRoot 'output'),
    '--input-directory', (Join-Path $artRoot 'input'),
    '--temp-directory', (Join-Path $artRoot 'temp'),
    '--user-directory', (Join-Path $artRoot 'user'))
# Inherit real log file handles instead of a short-lived PowerShell relay pipe.
# The detached child keeps logging after this launcher process has exited.
$launchSpec = Join-Path $artRoot 'launch.json'
@{executable=$python; arguments=$argsList; cwd=$portable; pid_file=$pidFile;
    stdout=(Join-Path $artRoot 'logs\comfyui.stdout.log');
    stderr=(Join-Path $artRoot 'logs\comfyui.stderr.log')} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $launchSpec -Encoding utf8
$bootstrap = @'
import json,subprocess,sys
from pathlib import Path
spec=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
with open(spec['stdout'],'ab',buffering=0) as out, open(spec['stderr'],'ab',buffering=0) as err:
    process=subprocess.Popen([spec['executable'],*spec['arguments']],cwd=spec['cwd'],stdin=subprocess.DEVNULL,stdout=out,stderr=err,
        creationflags=subprocess.DETACHED_PROCESS|subprocess.CREATE_NEW_PROCESS_GROUP|subprocess.CREATE_NO_WINDOW,close_fds=True)
Path(spec['pid_file']).write_text(str(process.pid),encoding='ascii')
print('ComfyUI starting: http://127.0.0.1:8188 (PID '+str(process.pid)+')')
'@
& $python -c $bootstrap $launchSpec
if ($LASTEXITCODE -ne 0) { throw 'ComfyUI bootstrap failed.' }
