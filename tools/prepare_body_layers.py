"""Extract registered body-only PNGs from locally generated whole-figure cutouts.

Technical processing only: alpha slicing, uniform scaling and common floor.
No painting, anatomical deformation, game or save mutations.
Run with the postprocess Python environment on E:.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, PngImagePlugin
from scipy import ndimage


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path)
    parser.add_argument('target',type=Path)
    parser.add_argument('--cut-y',type=int,default=240)
    args=parser.parse_args()
    if args.target.exists(): raise ValueError('Preserve previous variants; select a new target.')
    source=Image.open(args.source).convert('RGBA')
    alpha=np.asarray(source.getchannel('A')).copy()
    alpha[:args.cut_y]=0
    components,count=ndimage.label(alpha>=16,structure=np.ones((3,3)))
    if count:
        sizes=np.bincount(components.ravel());sizes[0]=0
        keep=ndimage.binary_dilation(components==sizes.argmax(),iterations=2)
        alpha=(alpha*keep).astype('uint8')
    source.putalpha(Image.fromarray(alpha))
    bounds=source.getchannel('A').point(lambda v:255 if v>=16 else 0).getbbox()
    if not bounds or bounds[3]<=args.cut_y+300: raise ValueError('No complete body remains.')
    neck_x=np.flatnonzero(alpha[args.cut_y]>=128)
    if len(neck_x)==0: raise ValueError('Cut must pass through the neck attachment.')
    neck_center=float((neck_x[0]+neck_x[-1])/2)
    scale=1000/(bounds[3]-args.cut_y)
    crop=source.crop((0,args.cut_y,source.width,bounds[3]))
    crop=crop.resize((round(source.width*scale),1000),Image.Resampling.LANCZOS)
    result=Image.new('RGBA',(720,1280),(0,0,0,0))
    offset_x=round((720-crop.width)/2)
    result.paste(crop,(offset_x,245))
    target_bounds=result.getchannel('A').point(lambda v:255 if v>=16 else 0).getbbox()
    if target_bounds[0]<=0 or target_bounds[2]>=720: raise ValueError('Body was clipped at a side.')
    record={'source':str(args.source.resolve()),'source_sha256':hashlib.sha256(args.source.read_bytes()).hexdigest(),
            'operation':'body alpha slice and uniform registration; no anatomical deformation',
            'source_cut_y':args.cut_y,'uniform_scale':scale,'canvas':[720,1280],
            'neck_attach':[round(offset_x+neck_center*scale,2),245],
            'feet_baseline_y':1244,'alpha_bounds':target_bounds,
            'head_included':False,'clothes_included':False,
            'status':'body layer candidate; separate heads, fitted clothing and runtime review remain'}
    meta=PngImagePlugin.PngInfo()
    original=Image.open(args.source)
    for key,value in original.info.items():
        if isinstance(value,str):meta.add_text(key,value)
    meta.add_text('ero_inc_body_layer',json.dumps(record))
    args.target.parent.mkdir(parents=True,exist_ok=True)
    result.save(args.target,pnginfo=meta)
    args.target.with_suffix('.qa.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    print(json.dumps({'target':str(args.target),'neck_attach':record['neck_attach'],'bounds':target_bounds}),flush=True)


if __name__=='__main__':main()
