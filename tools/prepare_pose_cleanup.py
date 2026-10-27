"""Remove an accidental white censor object, retaining non-graphic anatomy.

Four local finishing strengths for ONE already fully drawn adult pose. These
are repairs of a single source, never four extra pose designs.
"""
from pathlib import Path
import argparse,json
import numpy as np
from PIL import Image,ImageFilter
from scipy import ndimage
from prepare_pose_pack import ROOT,PROJECT,write,config

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);a=p.parse_args();idx=json.loads(a.index.read_text(encoding='utf-8-sig'));source=Path(next(i['source'] for i in idx['items'] if i['id']=='male_arms_folded'));raw=Image.open(source).convert('RGB');rgb=np.array(raw);yy,xx=np.mgrid[:raw.height,:raw.width]
    white=(rgb.min(2)>242)&(yy>620)&(yy<950)&(xx>330)&(xx<490)
    labels,n=ndimage.label(white);counts=np.bincount(labels.ravel());counts[0]=0
    if not n or counts.max()<100:raise ValueError('Expected removable white object not located; inspect source')
    blob=ndimage.binary_dilation(labels==counts.argmax(),iterations=5);m=Image.fromarray(blob.astype('uint8')*255).filter(ImageFilter.GaussianBlur(2))
    skin=(rgb[:,:,0]>225)&(rgb[:,:,1]>180)&(rgb[:,:,2]>145)&(rgb[:,:,0].astype(int)-rgb[:,:,1]>12)&(yy>660)&(yy<780)&(xx>325)&(xx<490)&(~blob)
    color=np.median(rgb[skin],axis=0).astype('uint8');filled=Image.composite(Image.new('RGB',raw.size,tuple(color)),raw,m)
    folder=ROOT/'input/characters_v2/pose_cleanup_male_folded_v1';folder.mkdir(parents=True,exist_ok=True);filled.save(folder/'reference.png');m.save(folder/'mask.png');items=[]
    for i,d in enumerate([.16,.22,.28,.34]):
        items.append({'id':f'male_arms_folded_repair_{i+1}','rig':'male_canonical','category':'cleanup','image':(folder/'reference.png').relative_to(ROOT/'input').as_posix(),'mask':(folder/'mask.png').relative_to(ROOT/'input').as_posix(),'prompt':'eincanime, mature adult man age 35, original anime illustration, smooth uninterrupted skin surface in the small retouch area, featureless non-graphic pelvis, preserve existing neutral standing posture and all limbs, thin brown contours, warm matte flat colors, controlled peach cel shadows','negative':'genitals, penis, testicles, sexual, erotic, graphic anatomy, censored, censor bar, mosaic, sticker, emoji, white oval, white patch, symbols, clothing, text, logo, extra limbs, distorted anatomy','seed':2026102000+i,'denoise':d,'preserve_input_latent':True})
    conf=config('pose_cleanup_male_folded_v1',items);conf.pop('controlnet');conf['preserve_input_latent']=True;conf['source_pose_index']=str(a.index);conf['source_pose_id']='male_arms_folded';target=PROJECT/'docs/art/characters-v2/pose-cleanup-male-folded-v1.json';write(target,conf);print(target)
if __name__=='__main__':main()
