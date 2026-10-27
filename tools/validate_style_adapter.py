"""Check actual adapter weights and render fixed-seed comparisons; no auto approval."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art


def inspect_adapter(source):
    import torch
    from safetensors import safe_open
    torch.set_num_threads(4)
    count=0;nonzero_up=0;up_count=0
    with safe_open(str(source),framework='pt',device='cpu') as weights:
        metadata=weights.metadata()
        for key in weights.keys():
            value=weights.get_tensor(key)
            if not torch.isfinite(value).all():
                raise RuntimeError(f'Non-finite adapter weights: {key}')
            count+=value.numel()
            if key.endswith('lora_up.weight'):
                up_count+=1
                nonzero_up+=int(torch.count_nonzero(value)>0)
    if nonzero_up==0:
        raise RuntimeError('All LoRA up matrices are zero; no learned adapter update.')
    return {'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'bytes':source.stat().st_size,'parameters':count,'up_modules':up_count,
            'nonzero_up_modules':nonzero_up,'all_finite':True,'metadata':metadata}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adapter',type=Path,required=True)
    parser.add_argument('--tag',default='candidate_400')
    parser.add_argument('--inspect-only',action='store_true')
    parser.add_argument('--weights',type=float,nargs='+',default=[0,0.65,0.9])
    args=parser.parse_args()
    if not re.fullmatch('[a-z0-9_-]+',args.tag):
        parser.error('Use a simple lowercase comparison tag.')
    source=args.adapter.resolve()
    if not source.is_relative_to((art.ROOT/'training/ero-anime-v1').resolve()):
        parser.error('Expected our locally trained adapter.')
    report=inspect_adapter(source)
    art.write_json(art.ROOT/'training/ero-anime-v1'/f'{args.tag}-weights.json',report)
    print({k:report[k] for k in ['bytes','parameters','up_modules','nonzero_up_modules','all_finite']},flush=True)
    if args.inspect_only:
        return
    if not art.read_json(source.parent/'training-result.json')['success']:
        raise RuntimeError('Complete the training run before GPU validation.')
    target=art.ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/loras/EroInc'/(args.tag+'.safetensors')
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()!=report['sha256']:
        raise RuntimeError('Refusing to replace a different installed adapter.')
    shutil.copy2(source,target)
    config=art.read_json(art.PROJECT/'docs/art/characters-v2/dataset-profiles.json')
    config['positive']='masterpiece, best quality, eincanime, {subject}, solo, adult {person}, age 28, {hair}, {eyes} eyes, {clothes}, {framing}, looking at viewer, calm expression, plain light gray background'
    config['negative']='{exclude}, worst quality, low quality, blurry, bad anatomy, deformed face, extra limbs, extra fingers, text, logo, watermark, signature, 3d render, photorealistic, robot, metallic skin, mask, child, teen, loli, shota, nude, erotic pose'
    config['output_prefix']='characters_v2/style_validation/'+args.tag
    probes=[
        {'id':'new_female','gender':'female','subject':'1girl, adult woman','person':'woman','hair':'shoulder-length dusty pink hair','eyes':'green','clothes':'plain cream collared blouse','framing':'waist up, front view','seed':4100871},
        {'id':'new_male','gender':'male','subject':'1boy, male focus, adult man','person':'man','hair':'short black hair','eyes':'blue-gray','clothes':'plain olive green jacket over a black t-shirt','framing':'waist up, three-quarter view','seed':8800192}]
    comparison=art.ROOT/'training/ero-anime-v1'/f'{args.tag}-comparison.json'
    existing=art.read_json(comparison) if comparison.exists() else None
    if existing and existing['sha256']!=report['sha256']:
        raise RuntimeError('Comparison tag belongs to another adapter.')
    results=existing['items'] if existing else []
    for strength in args.weights:
        config['lora']={'enabled':strength!=0,'name':str(Path('EroInc')/target.name),'sha256':report['sha256'],
                        'strength_model':strength,'strength_clip':0.0}
        for profile in probes:
            if any(i['subject']==profile['id'] and i['strength']==strength for i in results):
                continue
            current={**profile,'id':profile['id']+'_w'+str(strength).replace('.','p')}
            config['profiles']=[current]  # generate one exact profile, restore below
            run=art.generate(config,current['id'],None,True)
            image=run['history']['outputs']['9']['images'][0]
            results.append({'subject':profile['id'],'strength':strength,'run':run['prompt_id'],
                            'path':str(art.ROOT/'output'/image['subfolder']/image['filename'])})
        config['profiles']=probes
        art.write_json(art.ROOT/'training/ero-anime-v1'/f'{args.tag}-comparison.json',{
            'status':'requires_visual_review','adapter':str(source),'sha256':report['sha256'],'items':results})
    art.write_json(art.ROOT/'workflows'/f'{args.tag}-validation-profiles.json',config)


if __name__=='__main__':
    main()
