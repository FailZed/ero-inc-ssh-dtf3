"""Owned-reference chest-shape guides for full-body local DaSiWa edits.

Source and output are whole adult neutral figures. Guides are not finished
assets and never count as accepted drawings before local rendering and review.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image,PngImagePlugin
from scipy.ndimage import map_coordinates

ROOT=Path('E:/Ai/ComfyUI-EroInc');PROJECT=Path(__file__).resolve().parents[1]
SIZES={'xs':.85,'s':1.08,'m':.82,'l':1.0,'xl':1.22}
SHAPES={'round':(1,1,0,0),'teardrop':(.96,1.12,0,4),'compact':(.95,.88,0,-4),'wide':(1.08,.97,5,0),'lower_full':(1,1.07,0,7),'asymmetric':(1,1,0,0)}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--target',type=Path,required=True);p.add_argument('--config',type=Path,required=True)
    p.add_argument('--small-revision',action='store_true')
    a=p.parse_args()
    if a.target.exists():raise ValueError('Preserve previous guide version')
    a.target.mkdir(parents=True)
    yy,xx=np.mgrid[:1472,:832].astype(float)
    c=json.loads((PROJECT/'docs/art/characters-v2/body-reference-v1.json').read_text(encoding='utf-8'));c.update(output_prefix='characters_v2/body_chest_forms_v2',denoise=.42,preserve_input_latent=True);c['items']=[];records=[]
    # All round size anchors first, then alternative natural shape families.
    cases=[(size,shape) for shape in SHAPES for size in SIZES if not a.small_revision or size in ['xs','s']]
    for j,(size,shape) in enumerate(cases):
        source=ROOT/('output/characters_v2/cutouts/female_bust_small_v4.png' if size in ['xs','s'] else 'input/characters_v2/bases/female_average/full.png')
        original=Image.open(source).convert('RGBA');rgba=np.asarray(original,dtype=float)/255
        premul=rgba.copy();premul[:,:,:3]*=premul[:,:,3:]
        strength=({'xs':.65,'s':1.18}[size] if a.small_revision else SIZES[size]);sx,sy,separation,dy=SHAPES[shape];invx=xx.copy();invy=yy.copy()
        for side,cx in enumerate([399,510] if size in ['xs','s'] else [391,511]):
            cy=440 if size in ['xs','s'] else 456
            side_factor=(.94 if side==0 else 1.06) if shape=='asymmetric' else 1
            movex=(-separation if side==0 else separation);movey=dy+((-3 if side==0 else 3) if shape=='asymmetric' else 0)
            rx,ry=(47,52) if size in ['xs','s'] else (57,69)
            w=np.exp(-((xx-cx)/rx)**4-((yy-cy)/ry)**4)
            # Smooth localized inverse proportion mapping retains neck/arms/waist context.
            invx+=(cx+(xx-cx-movex*w)/(1+(strength*sx*side_factor-1)*w)-xx)
            invy+=(cy+(yy-cy-movey*w)/(1+(strength*sy*side_factor-1)*w)-yy)
        out=np.stack([map_coordinates(premul[:,:,k],[invy,invx],order=3,mode='constant',cval=0) for k in range(4)],axis=2);out=np.clip(out,0,1);out[:,:,:3]/=np.maximum(out[:,:,3:],1/255);out=np.clip(np.rint(out*255),0,255).astype('uint8')
        im=Image.fromarray(out);im.paste(original.crop((0,0,832,340)),(0,0));im.paste(original.crop((0,572,832,1472)),(0,572))
        name='chest_'+size+'_'+shape;folder=a.target/name;folder.mkdir()
        lineage={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'method':'Owned whole-figure local proportion guide; requires DaSiWa rendering and visual review','size':size,'shape':shape}
        meta=PngImagePlugin.PngInfo();meta.add_text('ero_inc_anatomy_guide',json.dumps(lineage));im.save(folder/'guide.png',pnginfo=meta)
        flat=Image.new('RGBA',im.size,'#eeeeec');flat.alpha_composite(im);flat.convert('RGB').save(folder/'reference.png',pnginfo=meta)
        mask=Image.open(ROOT/'input/characters_v2/bases/female_average/bust-wide-soft-mask.png');mask.save(folder/'mask.png')
        wording={'xs':'very small natural adult breasts, minimal adult chest volume','s':'small natural adult breasts','m':'medium natural adult breasts, moderate volume','l':'full natural adult breasts','xl':'larger natural adult breasts, moderate realistic weight'}[size]
        form={'round':'gently rounded natural shape','teardrop':'natural teardrop shape','compact':'compact natural shape','wide':'naturally wider set breasts','lower_full':'natural lower fullness, gently lower natural contour','asymmetric':'slight natural left right asymmetry'}[shape]
        text='masterpiece, best quality, eincanime, original mature adult woman age 30, full body neutral nude anatomical figure, '+wording+', '+form+', natural nipples, same adult brown bob and blue eyes, same relaxed standing pose, thin delicate brown contours, matte flat skin colors, light peach cel shadows, evenly lit, flat light gray background'
        rel=folder.relative_to(ROOT/'input').as_posix()
        c['items'].append({'id':name,'rig':'female_canonical','category':'breast_shape','image':rel+'/reference.png','mask':rel+'/mask.png','prompt':text,'negative':c['negative']+', enlarged nipples, breast implants, spherical implants, extreme breasts'+(', full breasts, large breasts' if size in ['xs','s'] else ''),'seed':9881000+j,'denoise':.27 if a.small_revision else .42,'preserve_input_latent':True,'size':size,'shape':shape})
        records.append(lineage)
    a.config.parent.mkdir(parents=True,exist_ok=True);a.config.write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (a.target/'guides.json').write_text(json.dumps({'items':records,'source_drawings':2,'guide_count':len(records),'accepted_drawings':0},indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'guides':len(records),'config':str(a.config)}))


if __name__=='__main__':main()
