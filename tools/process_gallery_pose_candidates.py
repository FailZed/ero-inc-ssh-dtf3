"""Chroma-key fresh full-figure pose studies, keeping fingers and original RGB.

No anatomical material filter, part warping or source head pasting. The full
drawings, cutout derivatives and visual decisions stay separate in the index.
"""
from pathlib import Path
import argparse,hashlib,json,os
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage

ART=Path('E:/Ai/ComfyUI-EroInc')
for k,v in {'REMBG_HOME':ART/'cache/rembg','XDG_CACHE_HOME':ART/'cache','NUMBA_CACHE_DIR':ART/'cache/numba','TEMP':ART/'temp','TMP':ART/'temp'}.items():os.environ[k]=str(v)

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();batch=read(a.index);config=read(Path(batch['config']));lookup={j['id']:j for j in config['items']};records=[];session=None
    for item in batch['items']:
        job=lookup[item['id']];dest=a.target/item['id'];dest.mkdir(parents=True,exist_ok=True);source=Path(item['source']);raw=Image.open(source).convert('RGB');rgb=np.array(raw,float);score=np.minimum(rgb[:,:,0],rgb[:,:,2])-rgb[:,:,1]
        border=np.r_[rgb[:12].reshape(-1,3),rgb[-12:].reshape(-1,3),rgb[:,:12].reshape(-1,3),rgb[:,-12:].reshape(-1,3)];key=np.median(border,axis=0)
        if min(key[0],key[2])-key[1]<120:
            from rembg import remove,new_session
            if session is None:session=new_session('birefnet-general-lite',providers=['CPUExecutionProvider'])
            pixels=np.array(remove(raw,session=session,decontaminate=True).convert('RGBA'));matte_method='BiRefNet foreground, no skin-only deletion; generated background was not magenta.'
        else:
            pixels=key_matte(rgb,score,key);matte_method='Magenta key with foreground RGB decontamination; no skin-only deletion.'
        pixels[pixels[:,:,3]==0,:3]=0
        full=Image.fromarray(pixels);full.save(dest/'full.png');bounds=full.getchannel('A').point(lambda v:255 if v>24 else 0).getbbox();touches=bool(bounds and (bounds[0]<8 or bounds[1]<8 or bounds[2]>raw.width-8 or bounds[3]>raw.height-8))
        for name,bgcolor in [('dark','#101b29'),('light','#eeeef0'),('magenta','#ff00ff')]:
            bg=Image.new('RGBA',raw.size,bgcolor);bg.alpha_composite(full);bg.convert('RGB').save(dest/(name+'.png'))
        previous=read(dest/'record.json') if (dest/'record.json').exists() else {}
        record={**item,'sex':job['sex'],'pose':job['pose'],'title':job['title'],'candidate_number':job['candidate_number'],'full':str(dest/'full.png'),'cutout_sha256':sha(dest/'full.png'),'raw_canvas':list(raw.size),'foreground_bounds':bounds,'touches_canvas_edge':touches,'key_rgb':key.tolist(),'matte_method':matte_method,'source_gallery':job['source_gallery'],'art_direction_reference':job['art_direction_reference'],'art_direction_reference_sha256':job['art_direction_reference_sha256'],'reference_role':job['reference_role'],'raw_is_new_drawing':True,'cutout_is_derivative':True,'runtime_registered':False,'status':'processed_pose_study_requires_visual_review','visual_review':previous.get('visual_review',{'decision':'pending','issues':[]})};write(dest/'record.json',record);records.append(record)
    a.target.mkdir(parents=True,exist_ok=True);write(a.target/'index.json',{'schema':1,'source_index':str(a.index),'items':records,'drawings':len(records),'cutout_derivatives':len(records),'runtime_registered':False})
    # Five-candidate review sheets. Native originals remain linked in records.
    for sex,pose in sorted({(r['sex'],r['pose']) for r in records}):
        group=[r for r in records if r['sex']==sex and r['pose']==pose];sheet=Image.new('RGB',(300*len(group),600),'#101b29');d=ImageDraw.Draw(sheet)
        for n,r in enumerate(group):
            im=Image.open(r['full']).convert('RGBA');im.thumbnail((290,548),Image.Resampling.LANCZOS);base=Image.new('RGBA',(300,560),'#101b29');base.alpha_composite(im,((300-im.width)//2,560-im.height));sheet.paste(base.convert('RGB'),(300*n,35));d.text((300*n+10,12),r['id'],fill='white')
        sheet.save(a.target/(sex+'-'+pose+'-review.png'))
    print(json.dumps({'processed':len(records),'target':str(a.target)},ensure_ascii=False))

def key_matte(rgb,score,key):
        # Estimate foreground core first; only the key color is removed. Skin,
        # ink, highlights and finger gaps never go through a skin-only filter.
    core=score<35;labels,count=ndimage.label(core);sizes=np.bincount(labels.ravel());sizes[0]=0;core=labels==sizes.argmax();core=ndimage.binary_erosion(core,iterations=1)
    _,near=ndimage.distance_transform_edt(~core,return_indices=True);foreground=rgb[near[0],near[1]];delta=foreground-key;alpha=np.clip(np.sum((rgb-key)*delta,axis=2)/np.maximum(np.sum(delta*delta,axis=2),1),0,1)
    alpha[score<35]=1;alpha[score>min(key[0],key[2])-key[1]-8]=0;components,n=ndimage.label(alpha>.03);counts=np.bincount(components.ravel());counts[0]=0;main=ndimage.binary_dilation(components==counts.argmax(),iterations=1);alpha*=main
    color=(rgb-key*(1-alpha[:,:,None]))/np.maximum(alpha[:,:,None],1/255);color=np.clip(color,0,255);return np.concatenate([np.rint(color),np.rint(alpha[:,:,None]*255)],2).astype('uint8')
if __name__=='__main__':main()
