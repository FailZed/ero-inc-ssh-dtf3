"""Run a masked edit locally, preserving pixels outside an explicit white edit mask.

Inputs must be in the E: ComfyUI input folder. Use only owned/authorized art.
Mask generation/canvas placement is a technical preparation step, not generated art.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parent))
from local_character_art import ROOT, PROFILE_PATH, api, read_json, write_json, verify_model, poll, editable_workflow


def main(argv=None, on_submitted=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    parser.add_argument('--mask')
    parser.add_argument('--preserve-input-latent', action='store_true', help='Keep source structure while editing inside a mask')
    parser.add_argument('--prompt', required=True)
    parser.add_argument('--negative', required=True, help='Explicit exclusions for this edit; no hidden anatomy or clothing exclusions')
    parser.add_argument('--seed', type=int, default=9817301)
    parser.add_argument('--denoise', type=float, default=1.0)
    parser.add_argument('--steps', type=int, default=16)
    parser.add_argument('--cfg', type=float, default=6.0)
    parser.add_argument('--sampler', default='euler')
    parser.add_argument('--scheduler', default='normal')
    parser.add_argument('--control-pose', help='Optional original technical OpenPose image inside input/')
    parser.add_argument('--control-strength', type=float, default=1.0)
    parser.add_argument('--prefix', default='characters_v1/edits/draft')
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--lora',help='Local verified style adapter name')
    parser.add_argument('--lora-sha256')
    parser.add_argument('--lora-strength',type=float,default=0.65)
    args = parser.parse_args(argv)
    config = read_json(PROFILE_PATH)
    model = verify_model(config)
    if not api('/object_info/EroIncGpuBudgetStatus').get('EroIncGpuBudgetStatus'):
        raise RuntimeError('Start ComfyUI through the configured GPU budget launcher.')
    adapter=None
    if args.lora:
        if not args.lora_sha256:
            parser.error('--lora requires --lora-sha256')
        directory=ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/loras'
        path=(directory/args.lora).resolve()
        if not path.is_relative_to(directory.resolve()) or not path.is_file():
            raise ValueError('Adapter must exist inside the local loras directory.')
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if digest!=args.lora_sha256.lower():
            raise ValueError('Adapter checksum mismatch.')
        choices=api('/object_info/LoraLoader')['LoraLoader']['input']['required']['lora_name'][0]
        name=next((n for n in choices if n.replace('\\','/')==args.lora.replace('\\','/')),None)
        if name is None:raise ValueError('ComfyUI does not list this adapter.')
        adapter={'name':name,'sha256':digest,'strength_model':args.lora_strength,'strength_clip':0.0}
    inputs = []
    for name in (name for name in (args.image, args.mask, args.control_pose) if name):
        path = (ROOT / 'input' / name).resolve()
        if not path.is_relative_to((ROOT / 'input').resolve()) or not path.is_file():
            raise ValueError(f'Input must exist inside ComfyUI input: {path}')
        inputs.append({'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    queue = api('/queue')
    if queue['queue_running'] or queue['queue_pending']:
        raise RuntimeError('Queue is busy. Inspect it before submitting another edit.')
    graph = {
        '4': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': config['checkpoint']}},
        '10': {'class_type': 'LoadImage', 'inputs': {'image': args.image}},
        '11': {'class_type': 'LoadImage', 'inputs': {'image': args.mask}},
        '12': {'class_type': 'ImageToMask', 'inputs': {'image': ['11', 0], 'channel': 'red'}},
        '5': {'class_type': 'VAEEncodeForInpaint', 'inputs': {'pixels': ['10', 0], 'vae': ['4', 2], 'mask': ['12', 0], 'grow_mask_by': 6}},
        '6': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['4', 1], 'text': args.prompt}},
        '7': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['4', 1], 'text': args.negative}},
        '3': {'class_type': 'KSampler', 'inputs': {'model': ['4', 0], 'positive': ['6', 0], 'negative': ['7', 0], 'latent_image': ['5', 0],
              'seed': args.seed, 'steps': args.steps, 'cfg': args.cfg, 'sampler_name': args.sampler, 'scheduler': args.scheduler, 'denoise': args.denoise}},
        '8': {'class_type': 'VAEDecode', 'inputs': {'samples': ['3', 0], 'vae': ['4', 2]}},
        '13': {'class_type': 'ImageCompositeMasked', 'inputs': {'destination': ['10', 0], 'source': ['8', 0], 'x': 0, 'y': 0, 'resize_source': False, 'mask': ['12', 0]}},
        '9': {'class_type': 'SaveImage', 'inputs': {'images': ['13', 0], 'filename_prefix': args.prefix}}
    }
    if not args.mask:
        for node_id in ('11','12','13'):
            del graph[node_id]
        graph['5'] = {'class_type':'VAEEncode','inputs':{'pixels':['10',0],'vae':['4',2]}}
        graph['9']['inputs']['images'] = ['8',0]
    elif args.preserve_input_latent:
        graph['5'] = {'class_type':'VAEEncode','inputs':{'pixels':['10',0],'vae':['4',2]}}
        graph['14'] = {'class_type':'SetLatentNoiseMask','inputs':{'samples':['5',0],'mask':['12',0]}}
        graph['3']['inputs']['latent_image'] = ['14',0]
    if args.control_pose:
        graph['15'] = {'class_type':'ControlNetLoader','inputs':{'control_net_name':config['controlnet']['model']}}
        graph['16'] = {'class_type':'LoadImage','inputs':{'image':args.control_pose}}
        graph['17'] = {'class_type':'ControlNetApplyAdvanced','inputs':{
            'positive':['6',0],'negative':['7',0],'control_net':['15',0],'image':['16',0],
            'strength':args.control_strength,'start_percent':0.0,'end_percent':1.0,'vae':['4',2]}}
        graph['3']['inputs']['positive'] = ['17',0]
        graph['3']['inputs']['negative'] = ['17',1]
    if adapter:
        graph['18']={'class_type':'LoraLoader','inputs':{'model':['4',0],'clip':['4',1],
            'lora_name':adapter['name'],'strength_model':adapter['strength_model'],'strength_clip':0.0}}
        graph['3']['inputs']['model']=['18',0]
        graph['6']['inputs']['clip']=['18',1]
        graph['7']['inputs']['clip']=['18',1]
    workflow = editable_workflow(graph, args.prefix)
    workflow_name = Path(args.prefix).name
    write_json(ROOT/'user/default/workflows/EroInc_Color'/f'{workflow_name}.json',workflow)
    write_json(ROOT/'workflows'/f'{workflow_name}.api.json',graph)
    result = api('/prompt', {'prompt': graph, 'client_id': str(uuid.uuid4()), 'extra_data':{'extra_pnginfo':{'workflow':workflow}}})
    prompt_id = result['prompt_id']
    run_path = ROOT / 'runs' / f'{prompt_id}.json'
    run = {'prompt_id': prompt_id, 'created_utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'model': model,
           'generator': 'Local ComfyUI / DaSiWa ' + ('masked edit' if args.mask else 'img2img'), 'input_images': inputs,
           'prompt': graph, 'workflow': workflow, 'adapter':adapter,
           'gpu_budget':read_json(ROOT/'gpu-budget.json'), 'acceptance': 'DRAFT - not approved for runtime'}
    write_json(run_path, run)
    if on_submitted:
        on_submitted(run)
    print(f'Queued edit: {prompt_id}\nRun metadata: {run_path}', flush=True)
    if not args.watch:
        return run
    deadline = time.monotonic() + 1800
    previous_state = None
    while time.monotonic() < deadline:
        history = poll(prompt_id)
        state = history.get('status', {})
        if state.get('completed') or state.get('status_str') == 'error':
            run['history'] = history
            write_json(run_path, run)
            print(json.dumps({'status': state.get('status_str'), 'outputs': history.get('outputs', {})}, indent=2), flush=True)
            if state.get('status_str') != 'success':
                raise RuntimeError(f'Generation failed: {run_path}')
            return run
        if state.get('status_str') != previous_state:
            print(f'Edit {prompt_id}: {state.get("status_str")}', flush=True)
            previous_state = state.get('status_str')
        time.sleep(2)
    raise TimeoutError(f'Job still active: {prompt_id}')


if __name__ == '__main__':
    main()
