"""Whitelisted local ComfyUI extension; installed as ero_inc_gpu_budget/__init__.py."""
from pathlib import Path
import json
import logging
import sys

root=Path(__file__).resolve().parents[5]
sys.path.insert(0,str(root/'runtime/budget'))
import ero_gpu_budget as budget
import comfy.model_base
import comfy.sd

comfy.model_base.BaseModel.apply_model=budget.budgeted(comfy.model_base.BaseModel.apply_model,'generation.denoiser')
comfy.sd.VAE.encode=budget.budgeted(comfy.sd.VAE.encode,'generation.vae_encode')
comfy.sd.VAE.decode=budget.budgeted(comfy.sd.VAE.decode,'generation.vae_decode')
comfy.sd.CLIP.encode_from_tokens=budget.budgeted(comfy.sd.CLIP.encode_from_tokens,'generation.text_encoder')
priority=budget.lower_priority()
logging.info('EroInc GPU budget: %s%% scheduled duty; priorities %s',budget.settings()[0]['duty_percent'],priority)


class BudgetStatus:
    @classmethod
    def INPUT_TYPES(cls):
        return {'required':{}}
    RETURN_TYPES=('STRING',)
    FUNCTION='report'
    CATEGORY='EroInc/Diagnostics'
    def report(self):
        return (json.dumps({'settings':budget.settings()[0],'priority':priority}),)


class ConditioningBarrier:
    """Resolve a small group's encoders before sampling; return latent unchanged.

    This only orders execution. It never combines prompts, changes tensors,
    seeds, samplers, precision, VRAM limits or GPU scheduling.
    """
    @classmethod
    def INPUT_TYPES(cls):
        return {'required':{'latent':('LATENT',)},
                'optional':{'conditioning_'+str(i):('CONDITIONING',) for i in range(1,11)}}
    RETURN_TYPES=('LATENT',)
    FUNCTION='ready'
    CATEGORY='EroInc/Production'
    def ready(self,latent,**conditionings):
        return (latent,)


NODE_CLASS_MAPPINGS={'EroIncGpuBudgetStatus':BudgetStatus,'EroIncConditioningBarrier':ConditioningBarrier}
NODE_DISPLAY_NAME_MAPPINGS={'EroIncGpuBudgetStatus':'EroInc GPU budget status','EroIncConditioningBarrier':'EroInc resolve group encoders'}
