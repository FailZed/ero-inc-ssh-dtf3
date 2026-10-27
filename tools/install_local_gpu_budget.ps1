$ErrorActionPreference = 'Stop'
$artRoot = 'E:\Ai\ComfyUI-EroInc'
$budgetDirectory = Join-Path $artRoot 'runtime\budget'
$extensionDirectory = Join-Path $artRoot 'runtime\ComfyUI_windows_portable\ComfyUI\custom_nodes\ero_inc_gpu_budget'
New-Item -ItemType Directory -Force -Path $budgetDirectory,$extensionDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ero_gpu_budget.py') -Destination $budgetDirectory
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'comfy_gpu_budget_init.py') -Destination (Join-Path $extensionDirectory '__init__.py')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start_local_art.ps1') -Destination (Join-Path $artRoot 'Start-ComfyUI.ps1')
$budgetConfig = Join-Path $artRoot 'gpu-budget.json'
if (!(Test-Path -LiteralPath $budgetConfig)) {
    @{schema=1; duty_percent=80; cpu_priority='below_normal'; gpu_priority='below_normal';
      vram_reserve_gb=4; note='Average process work duty; transient GPU peaks remain possible.'} |
      ConvertTo-Json | Set-Content -LiteralPath $budgetConfig -Encoding utf8
}
Write-Output "GPU budget installed. Current settings: $budgetConfig"
