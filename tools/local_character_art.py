"""Reproducible local ComfyUI drafts, using core nodes and an explicitly verified model.

No cloud API, paid nodes, automatic checkpoint download or game/save mutations.
prepare: export editable workflows; generate: one selected draft; status: query it.
"""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import json
import time
import urllib.error
import urllib.request
import uuid

PROJECT = Path(__file__).resolve().parents[1]
ROOT = Path('E:/Ai/ComfyUI-EroInc')
PROFILE_PATH = PROJECT / 'docs/art/characters-v1/local-profiles.json'
SERVER = 'http://127.0.0.1:8188'


class ProductionWindowEnded(RuntimeError):
    pass


def check_production_window(now=None, minimum_remaining_seconds=0):
    window=ROOT/'batches/production-window.json'
    if not window.exists():return
    spec=read_json(window)
    if not spec.get('enabled',False):return
    stop=dt.datetime.fromisoformat(spec['stop_submit_utc'].replace('Z','+00:00'))
    current=now or dt.datetime.now(dt.timezone.utc)
    if (stop-current).total_seconds()<=minimum_remaining_seconds:
        raise ProductionWindowEnded('Authorized art window ended; preserve completed work and report remaining categories.')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def api(route, value=None):
    if route=='/prompt':check_production_window()
    data = None if value is None else json.dumps(value).encode('utf-8')
    req = urllib.request.Request(SERVER + route, data=data, headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'ComfyUI HTTP {error.code}: {error.read().decode("utf-8", errors="replace")}') from error


def selected(config, name):
    return next(p for p in config['profiles'] if p['id'] == name)


def graph(config, profile, seed=None):
    settings = config['settings']
    tags = dict(profile)
    tags['subject'] = profile.get('subject', '1boy, male focus, adult man, masculine' if profile['gender'] == 'male' else '1girl, adult woman, mature female')
    tags['exclude'] = '1girl, woman, female, breasts, feminine' if profile['gender'] == 'male' else '1boy, male, masculine'
    tags['anatomy'] = profile.get('anatomy', 'natural adult male anatomy, visible natural male genitals, flaccid penis, natural nipples' if profile['gender']=='male' else 'natural adult female anatomy, natural nipples, natural external anatomy')
    tags['anatomy_exclude'] = profile.get('anatomy_exclude', 'erection, erect penis, oversized genitals' if profile['gender']=='male' else 'penis, testicles')
    tags['character_role'] = 'visual novel male character, handsome detailed male anime face' if profile['gender']=='male' else 'visual novel character creator female base'
    tags['build_exclude'] = profile.get('negative','')
    positive = profile.get('positive',config['positive']).format(**tags)
    result = {
        '4': {'class_type': 'CheckpointLoaderSimple', 'inputs': {'ckpt_name': config['checkpoint']}},
        '5': {'class_type': 'EmptyLatentImage', 'inputs': {'width': settings['width'], 'height': settings['height'], 'batch_size': 1}},
        '6': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['4', 1], 'text': positive}},
        '7': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['4', 1], 'text': config['negative'].format(**tags)}},
        '3': {'class_type': 'KSampler', 'inputs': {
            'model': ['4', 0], 'positive': ['6', 0], 'negative': ['7', 0], 'latent_image': ['5', 0],
            'seed': profile['seed'] if seed is None else seed, 'steps': settings['steps'],
            'cfg': settings['cfg'], 'sampler_name': settings['sampler_name'], 'scheduler': settings['scheduler'], 'denoise': 1.0}},
        '8': {'class_type': 'VAEDecode', 'inputs': {'samples': ['3', 0], 'vae': ['4', 2]}},
        '9': {'class_type': 'SaveImage', 'inputs': {'images': ['8', 0], 'filename_prefix': f'{config.get("output_prefix","characters_v1")}/{profile["id"]}'}}
    }
    adapter = config.get('lora', {})
    if adapter.get('enabled', False):
        result['18'] = {'class_type':'LoraLoader', 'inputs':{
            'model':['4',0], 'clip':['4',1], 'lora_name':adapter['name'],
            'strength_model':adapter['strength_model'], 'strength_clip':adapter.get('strength_clip',0.0)}}
        result['3']['inputs']['model'] = ['18',0]
        result['6']['inputs']['clip'] = ['18',1]
        result['7']['inputs']['clip'] = ['18',1]
    reference = config.get('image_reference', {})
    if reference.get('enabled', False):
        result['13'] = {'class_type':'LoadImage', 'inputs':{'image':reference['image']}}
        result['5'] = {'class_type':'VAEEncode', 'inputs':{'pixels':['13',0], 'vae':['4',2]}}
        result['3']['inputs']['denoise'] = reference.get('male_denoise', reference['denoise']) if profile['gender']=='male' else reference['denoise']
    if config.get('controlnet', {}).get('enabled', False):
        control = config['controlnet']
        result['10'] = {'class_type':'ControlNetLoader', 'inputs':{'control_net_name':control['model']}}
        pose = control.get('male_pose',control['pose']) if profile['gender']=='male' else control['pose']
        if control.get('build_pose_directory'):
            pose = control['build_pose_directory']+'/'+profile['id']+'.png'
        result['11'] = {'class_type':'LoadImage', 'inputs':{'image':pose}}
        result['12'] = {'class_type':'ControlNetApplyAdvanced', 'inputs':{
            'positive':['6',0], 'negative':['7',0], 'control_net':['10',0], 'image':['11',0],
            'strength':control['strength'], 'start_percent':control.get('start_percent',0.0), 'end_percent':control.get('end_percent',1.0), 'vae':['4',2]}}
        result['3']['inputs']['positive'] = ['12',0]
        result['3']['inputs']['negative'] = ['12',1]
    return result


def editable_workflow(prompt, title):
    positions = {'4': [0, 240], '5': [0, 540], '6': [380, 0], '7': [380, 350], '3': [1230, 240], '8': [1600, 240], '9': [1880, 240],
                 '10':[0,750], '11':[380,750], '12':[880,450], '13':[1600,650], '14':[880,800],
                 '15':[0,1250], '16':[380,1250], '17':[880,1150], '18':[0,930]}
    sizes = {'4': [330, 120], '5': [330, 120], '6': [450, 300], '7': [450, 300], '3': [320, 280], '8': [220, 70], '9': [400, 600],
             '10':[330,440], '11':[330,440], '12':[300,200], '13':[300,170], '14':[250,100],
             '15':[330,80], '16':[330,440], '17':[300,200], '18':[330,160]}
    class_outputs = {'CheckpointLoaderSimple':['MODEL','CLIP','VAE'], 'EmptyLatentImage':['LATENT'],
                     'CLIPTextEncode':['CONDITIONING'], 'KSampler':['LATENT'], 'VAEDecode':['IMAGE'],
                     'SaveImage':[], 'ControlNetLoader':['CONTROL_NET'], 'LoadImage':['IMAGE','MASK'],
                     'ControlNetApplyAdvanced':['CONDITIONING','CONDITIONING'], 'ImageToMask':['MASK'],
                     'VAEEncode':['LATENT'], 'VAEEncodeForInpaint':['LATENT'], 'ImageCompositeMasked':['IMAGE'], 'SetLatentNoiseMask':['LATENT'],
                     'LoraLoader':['MODEL','CLIP']}
    nodes = []
    links = []
    by_id = {}
    for order, (node_id, item) in enumerate(prompt.items()):
        inputs = item['inputs']
        widgets = [v for v in inputs.values() if not isinstance(v, list)]
        if item['class_type'] == 'KSampler':
            widgets = [inputs['seed'], 'fixed', inputs['steps'], inputs['cfg'], inputs['sampler_name'], inputs['scheduler'], inputs['denoise']]
        node = {'id': int(node_id), 'type': item['class_type'], 'pos': positions[node_id], 'size': sizes[node_id],
                'flags': {}, 'order': order, 'mode': 0, 'inputs': [],
                'outputs': [{'name': t, 'type': t, 'links': []} for t in class_outputs[item['class_type']]],
                'properties': {'Node name for S&R': item['class_type'], 'cnr_id': 'comfy-core'}, 'widgets_values': widgets}
        nodes.append(node)
        by_id[node_id] = node
    for target_id, item in prompt.items():
        for key, value in item['inputs'].items():
            if not isinstance(value, list):
                continue
            source_id, source_slot = value
            source = by_id[source_id]['outputs'][source_slot]
            target_slot = len(by_id[target_id]['inputs'])
            link_id = len(links) + 1
            source['links'].append(link_id)
            by_id[target_id]['inputs'].append({'name': key, 'type': source['type'], 'link': link_id})
            links.append([link_id, int(source_id), source_slot, int(target_id), target_slot, source['type']])
    return {'last_node_id': max(int(k) for k in prompt), 'last_link_id': len(links), 'nodes': nodes, 'links': links,
            'groups': [], 'config': {}, 'extra': {'ds': {'scale': 0.65, 'offset': [80, 80]}, 'ero_inc_title': title}, 'version': 0.4}


def verify_model(config):
    model = ROOT / 'runtime/ComfyUI_windows_portable/ComfyUI/models/checkpoints' / config['checkpoint']
    if not model.is_file():
        raise RuntimeError(f'Checkpoint missing: {model}')
    stamp = ROOT / 'model-verification.json'
    stat = model.stat()
    signature = {'path': str(model), 'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns, 'sha256': config['checkpoint_sha256'].lower()}
    if stamp.is_file() and read_json(stamp) == signature:
        return signature
    digest = hashlib.sha256()
    with model.open('rb') as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != signature['sha256']:
        raise RuntimeError('Checkpoint SHA256 does not match the selected DaSiWa version.')
    write_json(stamp, signature)
    return signature


def prepare(config):
    for profile in config['profiles']:
        prompt = graph(config, profile)
        workflow = editable_workflow(prompt, profile['id'])
        write_json(ROOT / 'workflows' / f'{profile["id"]}.api.json', prompt)
        write_json(ROOT / 'user/default/workflows' / config.get('workflow_group','EroInc') / f'{profile["id"]}.json', workflow)
    write_json(ROOT / 'workflows/profiles.json', config)
    print(f'Prepared {len(config["profiles"])} draft workflows under {ROOT}', flush=True)


def poll(prompt_id):
    history = api('/history/' + prompt_id)
    if prompt_id in history:
        return history[prompt_id]
    queue = api('/queue')
    active = any(item[1] == prompt_id for item in queue['queue_running'])
    pending = any(item[1] == prompt_id for item in queue['queue_pending'])
    return {'status': {'status_str': 'running' if active else 'pending' if pending else 'unknown', 'completed': False}}


def generate(config, name, seed, watch):
    model = verify_model(config)
    budget = read_json(ROOT/'gpu-budget.json')
    if not api('/object_info/EroIncGpuBudgetStatus').get('EroIncGpuBudgetStatus'):
        raise RuntimeError('The requested GPU budget extension is not active; restart with start_local_art.ps1.')
    adapter = config.get('lora', {})
    adapter_source = None
    if adapter.get('enabled', False):
        choices=api('/object_info/LoraLoader')['LoraLoader']['input']['required']['lora_name'][0]
        matching=next((name for name in choices if name.replace('\\','/')==adapter['name'].replace('\\','/')),None)
        if matching is None:
            raise RuntimeError('ComfyUI does not list the selected style adapter.')
        adapter={**adapter,'name':matching}
        config={**config,'lora':adapter}
        directory = ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/loras'
        path = (directory/adapter['name']).resolve()
        if not path.is_relative_to(directory.resolve()) or not path.is_file():
            raise RuntimeError('Style adapter must exist inside the local loras directory.')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != adapter['sha256'].lower():
            raise RuntimeError('Style adapter SHA256 does not match the selected version.')
        adapter_source = {**adapter, 'path':str(path)}
    profile = selected(config, name)
    info = api('/object_info/CheckpointLoaderSimple')
    choices = info['CheckpointLoaderSimple']['input']['required']['ckpt_name'][0]
    if config['checkpoint'] not in choices:
        raise RuntimeError('ComfyUI does not list the verified checkpoint yet. Refresh or restart the server.')
    queue = api('/queue')
    if queue['queue_running'] or queue['queue_pending']:
        raise RuntimeError('ComfyUI already has queued work; inspect it before submitting another job.')
    prompt = graph(config, profile, seed)
    workflow = editable_workflow(prompt, name)
    result = api('/prompt', {'prompt': prompt, 'client_id': str(uuid.uuid4()), 'extra_data': {'extra_pnginfo': {'workflow': workflow}}})
    prompt_id = result['prompt_id']
    run_path = ROOT / 'runs' / f'{prompt_id}.json'
    control_images = []
    reference = config.get('image_reference', {})
    if reference.get('enabled', False):
        source = (ROOT/'input'/reference['image']).resolve()
        control_images.append({'path':str(source), 'sha256':hashlib.sha256(source.read_bytes()).hexdigest(), 'role':reference['role']})
    if config.get('controlnet', {}).get('enabled', False):
        pose = ROOT/'input'/prompt['11']['inputs']['image']
        control_images.append({'path':str(pose), 'sha256':hashlib.sha256(pose.read_bytes()).hexdigest(),
                               'role':'Original technical pose map; no donor image'})
    run = {'prompt_id': prompt_id, 'created_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
           'profile': profile, 'model': model, 'source': config['source'], 'license': config['license'],
           'input_images': control_images, 'controlnet': config.get('controlnet') if config.get('controlnet',{}).get('enabled') else None,
           'image_reference': reference if reference.get('enabled') else None, 'generator': 'Local ComfyUI / DaSiWa EpitaphEcstasy',
           'prompt': prompt, 'workflow': workflow, 'adapter':adapter_source, 'gpu_budget':budget,
           'acceptance': 'DRAFT - not approved for runtime'}
    write_json(run_path, run)
    print(f'Queued {name}: {prompt_id}\nRun metadata: {run_path}', flush=True)
    if not watch:
        return run
    deadline = time.monotonic() + 1800
    previous_state = None
    while time.monotonic() < deadline:
        history = poll(prompt_id)
        state = history.get('status', {})
        if state.get('completed') or state.get('status_str') == 'error':
            run['history'] = history
            write_json(run_path, run)
            print(json.dumps({'prompt_id': prompt_id, 'status': state.get('status_str'),
                              'outputs': history.get('outputs', {})}, ensure_ascii=False, indent=2), flush=True)
            if state.get('status_str') != 'success':
                raise RuntimeError('Generation failed. Inspect recorded ComfyUI history.')
            return run
        if state.get('status_str') != previous_state:
            previous_state = state.get('status_str')
            print(f'{name}: {previous_state}', flush=True)
        time.sleep(2)
    raise TimeoutError(f'Job {prompt_id} is still queued; inspect it before resubmitting.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'verify', 'generate', 'status'])
    parser.add_argument('--profile', default='male_average')
    parser.add_argument('--config',type=Path,default=PROFILE_PATH,help='Explicit project profile family; default is the body study')
    parser.add_argument('--seed', type=int)
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--pose', action='store_true', help='Enable the installed technical OpenPose control')
    parser.add_argument('--reference', action='store_true', help='Regenerate the whole approved DaSiWa study; no fixed-head or body mask')
    parser.add_argument('--prompt-id')
    args = parser.parse_args()
    config = read_json(args.config)
    if args.pose:
        config['controlnet']['enabled'] = True
    if args.reference:
        config['image_reference']['enabled'] = True
        source = (ROOT/'input'/config['image_reference']['image']).resolve()
        if not source.is_relative_to((ROOT/'input').resolve()) or not source.is_file():
            parser.error('Approved reference must exist inside ComfyUI input/')
    if args.command == 'prepare':
        prepare(config)
    elif args.command == 'verify':
        print(json.dumps(verify_model(config), indent=2))
    elif args.command == 'generate':
        generate(config, args.profile, args.seed, args.watch)
    else:
        if not args.prompt_id:
            parser.error('status requires --prompt-id')
        print(json.dumps(poll(args.prompt_id), ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
