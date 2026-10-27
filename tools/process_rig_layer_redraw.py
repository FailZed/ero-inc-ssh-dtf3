"""Extract local rig completions with alpha, retaining protected original art.

No skin-color deletion: alpha comes from foreground segmentation and the authored
component envelope. Body central anatomy, face and lower legs stay pixel-exact.
"""
from pathlib import Path
import argparse,json,hashlib,os
ROOT=Path('E:/Ai/ComfyUI-EroInc')
for k,v in {'TEMP':ROOT/'temp','TMP':ROOT/'temp','REMBG_HOME':ROOT/'cache/rembg','NUMBA_CACHE_DIR':ROOT/'cache/numba','OMP_NUM_THREADS':'4'}.items():os.environ[k]=str(v)
import numpy as np
from PIL import Image
from scipy import ndimage
from rembg import remove,new_session

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(a,p):a=np.asarray(a).copy();a[a[:,:,3]==0,:3]=0;Image.fromarray(a).save(p)
def blend(a,b,w):
    aa=a.astype(float)/255;bb=b.astype(float)/255;t=w[:,:,None];alpha=aa[:,:,3:]*(1-t)+bb[:,:,3:]*t
    color=aa[:,:,:3]*aa[:,:,3:]*(1-t)+bb[:,:,:3]*bb[:,:,3:]*t;color/=np.maximum(alpha,1/255)
    out=np.rint(np.clip(np.concatenate([color,alpha],2)*255,0,255)).astype('uint8');out[w==0]=a[w==0];return out

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();idx=read(a.index);conf=read(Path(idx['config']));jobs={i['id']:i for i in conf['items']};session=new_session('birefnet-general-lite',providers=['CPUExecutionProvider']);records=[]
    for item in idx['items']:
        job=jobs[item['id']];meta=job['authoring'];source=Path(item['source']);dest=a.target/item['id'];dest.mkdir(parents=True,exist_ok=True)
        if (dest/'record.json').exists():
            rec=read(dest/'record.json')
            if rec['render_sha256']!=sha(source):raise ValueError('Changed processed render')
            records.append(rec);continue
        original=Image.open(meta['source']).convert('RGBA')
        if sha(Path(meta['source']))!=meta['source_sha256']:raise ValueError('Changed original body')
        guide=Image.open(meta['guide_rgba']).convert('RGBA');raw=Image.open(source).convert('RGB')
        if job['category']=='rig_hidden_body':
            bg=Image.new('RGBA',guide.size,'#eeeeec');bg.alpha_composite(guide);full=bg.convert('RGB');full.paste(raw,tuple(meta['crop'][:2]));clean=remove(full,session=session,decontaminate=True).convert('RGBA')
        else:
            local=remove(raw,session=session,decontaminate=True).convert('RGBA');ox,oy=meta['local_offset'];nw,nh=meta['local_size'];crop=meta['crop'];patch=local.crop((ox,oy,ox+nw,oy+nh));patch=patch.convert('RGBa').resize((crop[2]-crop[0],crop[3]-crop[1]),Image.Resampling.LANCZOS).convert('RGBA');clean=Image.new('RGBA',guide.size);clean.paste(patch,tuple(crop[:2]))
        generated=np.array(clean);target=np.array(Image.open(meta['target_alpha']).convert('L'))>0;envelope=ndimage.binary_dilation(target,iterations=3);generated[:,:,3]*=envelope
        mask=np.array(Image.open(meta['edit_mask']).convert('L'),float)/255;out=blend(np.array(guide),generated,mask);protected_exact=None
        if job['category']=='rig_hidden_body':
            yy,xx=np.mgrid[:guide.height,:guide.width];center=meta['protected_center'];protect=(yy<325)|(yy>=850)|((abs(xx-center['x'])<center['half_width'])&(yy>center['from_y']))
            orig=np.array(original);out[protect]=orig[protect];protected_exact=bool(np.array_equal(out[protect],orig[protect]))
        save(out,dest/'full.png');preview=Image.new('RGBA',guide.size,'#101b29');preview.alpha_composite(Image.fromarray(out));preview.convert('RGB').save(dest/'dark.png')
        rec={'id':item['id'],'rig':item['rig'],'category':job['category'],'authoring':meta,'render':str(source),'render_sha256':sha(source),'run':item['run'],'full':str(dest/'full.png'),'sha256':sha(dest/'full.png'),'protected_body_pixels_exact':protected_exact,'status':'candidate_requires_joint_and_full_pose_review','method':'Foreground alpha without material deletion; authored envelope; mask blend against owned guide; exact protected body restoration.'};write(dest/'record.json',rec);records.append(rec);print('Processed '+item['id'],flush=True)
    write(a.target/'index.json',{'schema':1,'source_index':str(a.index),'items':records,'status':'processed_candidates_not_approved'})
if __name__=='__main__':main()
