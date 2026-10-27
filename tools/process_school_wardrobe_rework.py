"""Restore repaint candidates to exact School layer canvases and original alpha.

RGB repaint and the immutable placement/alpha contract are checked separately.
This exports candidates; selection and runtime activation require visual review.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,j):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def pad_rgb(pixels):
    solid=pixels[:,:,3]>245
    if not solid.any():raise ValueError('No opaque garment pixels')
    _,coords=ndimage.distance_transform_edt(~solid,return_indices=True);fringe=pixels[:,:,3]<220;pixels[fringe,:3]=pixels[coords[0][fringe],coords[1][fringe],:3]
    return pixels

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();batch=read(a.index);jobs={j['id']:j for j in read(Path(batch['config']))['items']};records=[]
    for item in batch['items']:
        job=jobs[item['id']];meta=job['authoring'];dest=a.target/item['id'];dest.mkdir(parents=True,exist_ok=True);original_path=Path(meta['source']);original=Image.open(original_path).convert('RGBA')
        if sha(original_path)!=meta['source_sha256']:raise ValueError('Original School layer changed')
        raw=Image.open(item['source']).convert('RGB');local=Image.open(Path(meta['source_rgba']).parent/'local.png').convert('RGBA');pixels=np.array(raw.convert('RGBA'));pixels[:,:,3]=np.array(local.getchannel('A'));pixels=pad_rgb(pixels);x,y=meta['local_offset'];w,h=meta['local_size'];crop=meta['crop'];patch=Image.fromarray(pixels).crop((x,y,x+w,y+h)).convert('RGBa').resize((crop[2]-crop[0],crop[3]-crop[1]),Image.Resampling.LANCZOS).convert('RGBA');native=original.copy();native.paste(patch,tuple(crop[:2]));native.putalpha(original.getchannel('A'));finished=pad_rgb(np.array(native));normalization=None
        if meta.get('asset_family')=='hair':
            source_array=np.array(original);opaque=source_array[:,:,3]>245;before=source_array[:,:,:3]@np.array([.299,.587,.114]);after=finished[:,:,:3]@np.array([.299,.587,.114]);factor=float(np.clip(np.median(before[opaque])/max(np.median(after[opaque]),1),.85,1.2));value=np.clip(np.rint(after*factor),0,255).astype('uint8');finished[:,:,:3]=value[:,:,None];normalization={'grayscale_for_runtime_tint':True,'median_luma_factor':factor}
        finished[finished[:,:,3]==0,:3]=0;native=Image.fromarray(finished);native.save(dest/'full.png')
        alpha_exact=bool(np.array_equal(finished[:,:,3],np.array(original.getchannel('A'))));assert alpha_exact and list(native.size)==meta['canvas'];source_array=np.array(original);opaque=source_array[:,:,3]>245;delta=np.max(abs(finished[:,:,:3].astype(float)-source_array[:,:,:3]),axis=2);changed=float(np.mean(delta[opaque]>8))
        record={**item,'garment':meta['garment'],'title':meta['title'],'candidate_number':job['candidate_number'],'denoise':job['denoise'],'authoring':meta,'full':str(dest/'full.png'),'sha256':sha(dest/'full.png'),'alpha_sha256':hashlib.sha256(finished[:,:,3].tobytes()).hexdigest(),'alpha_exact':alpha_exact,'canvas_exact':list(native.size)==meta['canvas'],'opaque_rgb_changed_fraction':changed,'material_normalization':normalization,'source_kind':meta['source_kind'],'source_body_modified':False,'runtime_registered':False,'visual_review':read(dest/'record.json').get('visual_review',{'decision':'pending','issues':[]}) if (dest/'record.json').exists() else {'decision':'pending','issues':[]}};write(dest/'record.json',record);records.append(record)
        tight=native.crop(native.getchannel('A').getbbox());tight.thumbnail((650,850),Image.Resampling.LANCZOS)
        for name,color in [('dark','#101b29'),('light','#eeeeec')]:
            preview=Image.new('RGBA',(700,900),color);preview.alpha_composite(tight,((700-tight.width)//2,(900-tight.height)//2));preview.convert('RGB').save(dest/(name+'.png'))
    a.target.mkdir(parents=True,exist_ok=True);write(a.target/'index.json',{'schema':1,'source_index':str(a.index),'items':records,'drawings':len(records),'status':'native_alpha_checked_candidates_need_visual_selection','all_original_alpha_preserved':all(r['alpha_exact'] for r in records)})
    garments=list(dict.fromkeys(r['garment'] for r in records));sheet=Image.new('RGB',(1280,400*len(garments)),'#101b29');draw=ImageDraw.Draw(sheet)
    for row,ident in enumerate(garments):
        group=[r for r in records if r['garment']==ident];original=Path(group[0]['authoring']['source']);columns=[('School · source',original)]+[('LoRA · '+str(r['denoise']),Path(r['full'])) for r in group]
        for col,(label,path) in enumerate(columns):
            image=Image.open(path).convert('RGBA');image=image.crop(image.getchannel('A').getbbox());image.thumbnail((300,350),Image.Resampling.LANCZOS);base=Image.new('RGBA',(320,360),'#101b29');base.alpha_composite(image,((320-image.width)//2,(360-image.height)//2));sheet.paste(base.convert('RGB'),(col*320,row*400+35));draw.text((col*320+10,row*400+12),label,fill='white')
    sheet.save(a.target/'comparison.png');print(json.dumps({'processed':len(records),'alpha_exact':all(r['alpha_exact'] for r in records),'comparison':str(a.target/'comparison.png')},ensure_ascii=False))
if __name__=='__main__':main()
