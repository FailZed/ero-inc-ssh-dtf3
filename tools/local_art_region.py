"""Render a focused local garment patch, then restore its original canvas position.

Cropping/resizing is technical preparation. DaSiWa produces the actual drawing.
Outside the original explicit edit mask all pixels remain exactly unchanged.
"""
from pathlib import Path
import argparse,hashlib,json,sys
from PIL import Image,PngImagePlugin
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_art_edit as edit
import local_character_art as art


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--image',required=True);p.add_argument('--mask',required=True)
    p.add_argument('--box',type=int,nargs=4,required=True)
    p.add_argument('--size',type=int,nargs=2,required=True)
    p.add_argument('--prompt',required=True);p.add_argument('--negative',required=True)
    p.add_argument('--name',required=True);p.add_argument('--seed',type=int,required=True)
    p.add_argument('--denoise',type=float,default=.8)
    a=p.parse_args()
    if not a.name.replace('_','').isalnum():raise ValueError('Use a simple unique job name.')
    paths=[(art.ROOT/'input'/v).resolve() for v in [a.image,a.mask]]
    if not all(v.is_relative_to((art.ROOT/'input').resolve()) and v.is_file() for v in paths):raise ValueError('Inputs must exist under local input/.')
    source=Image.open(paths[0]).convert('RGB');mask=Image.open(paths[1]).convert('L')
    if mask.size!=source.size:raise ValueError('Source and mask canvas differ.')
    x0,y0,x1,y1=a.box
    if not (0<=x0<x1<=source.width and 0<=y0<y1<=source.height):raise ValueError('Invalid crop box.')
    if any(v<256 or v>1536 or v%64 for v in a.size):raise ValueError('Render dimensions must be multiples of 64, 256..1536.')
    target=art.ROOT/'output/characters_v2/regions'/f'{a.name}.png'
    if target.exists():raise ValueError('Preserve the existing result; use another name.')
    folder=art.ROOT/'input/characters_v2/regions'/a.name
    if folder.exists():raise ValueError('Preserve existing region inputs; use another name.')
    folder.mkdir(parents=True)
    source.crop(a.box).resize(a.size,Image.Resampling.LANCZOS).save(folder/'reference.png')
    mask.crop(a.box).resize(a.size,Image.Resampling.BILINEAR).save(folder/'mask.png')
    run=edit.main(['--image',f'characters_v2/regions/{a.name}/reference.png',
        '--mask',f'characters_v2/regions/{a.name}/mask.png','--preserve-input-latent',
        '--prompt',a.prompt,'--negative',a.negative,'--seed',str(a.seed),'--denoise',str(a.denoise),
        '--steps','16','--cfg','6','--sampler','euler',
        '--prefix','characters_v2/regions/raw/'+a.name,'--lora','EroInc/candidate_400.safetensors',
        '--lora-sha256','2da68309cba8e4613d0fbf8c15fb64d60fafc5bea3b9b5a791cca8cd3f225cb9','--watch'])
    result=run['history']['outputs']['9']['images'][0]
    raw=art.ROOT/'output'/result['subfolder']/result['filename']
    patch=Image.open(raw).convert('RGB').resize((x1-x0,y1-y0),Image.Resampling.LANCZOS)
    final=source.copy();final.paste(Image.composite(patch,source.crop(a.box),mask.crop(a.box)),(x0,y0))
    outside=np.asarray(mask)==0
    if np.any(np.asarray(final)[outside]!=np.asarray(source)[outside]):raise AssertionError('Changed a pixel outside the edit mask.')
    record={'source':str(paths[0]),'source_sha256':hashlib.sha256(paths[0].read_bytes()).hexdigest(),
        'mask':str(paths[1]),'mask_sha256':hashlib.sha256(paths[1].read_bytes()).hexdigest(),
        'box':a.box,'render_size':a.size,'run':str(art.ROOT/'runs'/f"{run['prompt_id']}.json"),
        'raw':str(raw),'outside_mask_identical':True,'status':'candidate_requires_visual_review'}
    meta=PngImagePlugin.PngInfo()
    for k,v in Image.open(paths[0]).info.items():
        if isinstance(v,str):meta.add_text(k,v)
    meta.add_text('ero_inc_region_edit',json.dumps(record))
    target.parent.mkdir(parents=True,exist_ok=True);final.save(target,pnginfo=meta)
    record['target']=str(target);record['sha256']=hashlib.sha256(target.read_bytes()).hexdigest()
    art.write_json(target.with_suffix('.json'),record)
    print(json.dumps(record),flush=True)


if __name__=='__main__':main()
