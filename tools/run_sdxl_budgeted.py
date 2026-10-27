"""SDXL training entry point with the same interactive GPU budget as generation."""
from pathlib import Path
import runpy
import sys
import json
import time

root=Path('E:/Ai/ComfyUI-EroInc')
sys.path.insert(0,str(root/'runtime/budget'))
sys.path.insert(0,str(root/'training/sd-scripts'))
import ero_gpu_budget as budget
from accelerate import Accelerator
from accelerate.state import PartialState
import torch
from library.sdxl_original_unet import SdxlUNet2DConditionModel
from diffusers import AutoencoderKL

budget.lower_priority()
reserve=budget.settings()[0].get('vram_reserve_gb',4)*1024**3
fraction=1-reserve/torch.cuda.get_device_properties(0).total_memory
if not 0.25<=fraction<=1:
    raise RuntimeError('Invalid training VRAM reserve.')
torch.cuda.set_per_process_memory_fraction(fraction,device=0)
budget.log({'event':'memory_budget','allocator_fraction':fraction,'reserved_bytes':reserve})
SdxlUNet2DConditionModel.forward=budget.budgeted(SdxlUNet2DConditionModel.forward,'training.unet_forward')
Accelerator.backward=budget.budgeted(Accelerator.backward,'training.backward')
AutoencoderKL.encode=budget.budgeted(AutoencoderKL.encode,'training.vae_encode')
# ROCm Windows has no distributed backend. Accelerate 1.14 still calls its
# teardown API for a single-device run; skip only that inapplicable teardown.
_destroy=PartialState.destroy_process_group
def destroy_if_available(self,group=None):
    if not torch.distributed.is_available():
        if self.num_processes!=1:
            raise RuntimeError('This ROCm runtime supports single-GPU training only.')
        return
    return _destroy(self,group)
PartialState.destroy_process_group=destroy_if_available
trainer=root/'training/sd-scripts/sdxl_train_network.py'
output=Path(sys.argv[sys.argv.index('--output_dir')+1])
sys.argv=[str(trainer),*sys.argv[1:]]
start=time.time()
try:
    runpy.run_path(str(trainer),run_name='__main__')
except BaseException as error:
    (output/'training-result.json').write_text(json.dumps({'success':False,'error':repr(error),'elapsed_seconds':time.time()-start}),encoding='utf-8')
    raise
else:
    (output/'training-result.json').write_text(json.dumps({'success':True,'elapsed_seconds':time.time()-start,
        'peak_gpu_allocated_bytes':torch.cuda.max_memory_allocated(),'gpu_budget':budget.settings()[0]}),encoding='utf-8')
