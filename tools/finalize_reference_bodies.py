"""Normalize local reference edits into RGBA body candidates, with provenance.

CPU-only background segmentation, conservative palette correction, restoration
of protected guide pixels, and complementary head/body alpha slices. Visual
acceptance is recorded separately; this tool never registers art in the game.
"""
from pathlib import Path
import argparse, collections, hashlib, json, os
ROOT=Path('E:/Ai/ComfyUI-EroInc')
for k,v in {'REMBG_HOME':ROOT/'cache/rembg','XDG_CACHE_HOME':ROOT/'cache','NUMBA_CACHE_DIR':ROOT/'cache/numba','TEMP':ROOT/'temp','TMP':ROOT/'temp','OMP_NUM_THREADS':'4'}.items():os.environ[k]=str(v)
import numpy as np
from PIL import Image,ImageDraw,PngImagePlugin
from scipy import ndimage
from rembg import new_session,remove


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))


def skin_mode(rgb,selected):
    good=selected&(rgb[:,:,0]>225)&(rgb[:,:,1]>190)&(rgb[:,:,2]>150)&(rgb[:,:,0]>rgb[:,:,1]+8)&(rgb[:,:,1]>rgb[:,:,2]+6)
    values=rgb[good].astype(float)
    if len(values)<100:return None
    keys=np.clip(values//4,0,63).astype('uint8');key=np.array(collections.Counter(map(tuple,keys)).most_common(1)[0][0])
    cluster=np.all(np.abs(keys.astype(int)-key)<=1,axis=1)
    return np.median(values[cluster],axis=0)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--spec',type=Path,required=True);p.add_argument('--target',type=Path,required=True)
    a=p.parse_args();spec=read(a.spec)
    a.target.mkdir(parents=True,exist_ok=True)
    session=None;records=[]
    for item in spec['items']:
        dest=a.target/item['id']
        if (dest/'record.json').exists():
            record=read(dest/'record.json')
            if record['source_sha256']!=sha(Path(item['source'])):raise ValueError('Source changed after processing')
            records.append(record);continue
        source=Path(item['source']);guide=Path(item['guide']);mask_path=Path(item['mask'])
        original=Image.open(guide).convert('RGBA');sample=Image.open(source).convert('RGB')
        mask=np.asarray(Image.open(mask_path).convert('L'));ref=np.asarray(original);rgb=np.asarray(sample).copy()
        if sample.size!=original.size or mask.shape!=ref.shape[:2]:raise ValueError('Canvas mismatch')
        delta=np.zeros(3)
        if item.get('match_skin',False):
            selected=(ref[:,:,3]>250)&(mask>250)
            before=skin_mode(ref[:,:,:3],selected);after=skin_mode(rgb,selected)
            if before is not None and after is not None:
                delta=before-after
                if np.max(np.abs(delta))>20:raise ValueError('Large palette drift requires visual repair, not recoloring')
        if item.get('silhouette_locked',False):
            # Interior-only anatomy edits retain the guide's exact alpha.
            result=sample.convert('RGBA');result.putalpha(original.getchannel('A'))
        else:
            if session is None:session=new_session('birefnet-general-lite',providers=['CPUExecutionProvider'])
            result=remove(sample,session=session,decontaminate=True).convert('RGBA')
            alpha=np.asarray(result.getchannel('A')).copy();components,n=ndimage.label(alpha>=16,structure=np.ones((3,3)))
            if n:
                sizes=np.bincount(components.ravel());sizes[0]=0
                keep=ndimage.binary_dilation(components==sizes.argmax(),iterations=2)
                alpha=(alpha*keep).astype('uint8');result.putalpha(Image.fromarray(alpha))
        if np.any(delta):
            # Segment the neutral original background first. Tinting the input
            # background can cause a model to retain the rectangular edit ROI.
            corrected=np.asarray(result).copy()
            corrected[:,:,:3]=np.clip(np.rint(corrected[:,:,:3].astype(float)+delta*(mask[:,:,None]/255)),0,255).astype('uint8')
            result=Image.fromarray(corrected)
        outside=Image.fromarray(np.where(mask==0,255,0).astype('uint8'))
        result.paste(original,(0,0),outside)
        neck=item['neck_y'];result.paste(original.crop((0,0,832,neck)),(0,0))
        if item.get('retouch_shoulders',False):
            # Remove the internal cutout-cap line while retaining the painted
            # outer contour. This is recorded original finishing, not a claim
            # that the raw generated result was ready.
            pix=np.array(result);inside=ndimage.distance_transform_edt(pix[:,:,3]>240)>4
            roi=Image.new('L',result.size);rd=ImageDraw.Draw(roi)
            centers=[(335,366),(538,366)] if item['sex']=='female' else [(318,365),(497,365)]
            skin=skin_mode(pix[:,:,:3],(pix[:,:,3]>250)&(np.indices(pix.shape[:2])[0]>neck))
            if skin is not None:
                for x,y in centers:rd.ellipse((x-27,y-22,x+27,y+26),fill=255)
                from PIL import ImageFilter
                weight=np.asarray(roi.filter(ImageFilter.GaussianBlur(3)),dtype=float)/255*inside*(mask>0)
                pix[:,:,:3]=np.clip(np.rint(pix[:,:,:3]*(1-weight[:,:,None])+skin*weight[:,:,None]),0,255).astype('uint8');result=Image.fromarray(pix)
        alpha=np.asarray(result.getchannel('A'));bounds=result.getchannel('A').point(lambda x:255 if x>=16 else 0).getbbox()
        if not bounds or not (bounds[0]>16 and bounds[1]>16 and bounds[2]<816 and bounds[3]<1456):raise ValueError('Clipped figure')
        head=result.copy();ha=head.getchannel('A');ImageDraw.Draw(ha).rectangle((0,neck,831,1471),fill=0);head.putalpha(ha)
        body=result.copy();ba=body.getchannel('A')
        if neck>0:ImageDraw.Draw(ba).rectangle((0,0,831,neck-1),fill=0)
        body.putalpha(ba)
        assembled=Image.new('RGBA',result.size);assembled.alpha_composite(body);assembled.alpha_composite(head)
        visible=alpha>0
        assert np.array_equal(np.asarray(assembled)[visible],np.asarray(result)[visible])
        assert np.array_equal(np.asarray(result)[mask==0],ref[mask==0])
        record={**item,'source_sha256':sha(source),'guide_sha256':sha(guide),'mask_sha256':sha(mask_path),'canvas':[832,1472],'alpha_bounds':bounds,'skin_rgb_offset':delta.tolist(),'postprocess':'CPU BiRefNet general lite or locked guide alpha; protected RGBA restore; optional small skin palette offset; complementary slices','visual_acceptance':'required_separately','runtime_registered':False,'qa':{'outside_mask_rgba_exact':True,'shared_head_exact':True,'complementary_layers_exact':True,'rgba':True}}
        meta=PngImagePlugin.PngInfo()
        for k,v in Image.open(source).info.items():
            if isinstance(v,str):meta.add_text(k,v)
        meta.add_text('ero_inc_body_postprocess',json.dumps(record))
        dest.mkdir(parents=True,exist_ok=True)
        for name,im in [('full',result),('head',head),('body',body)]:im.save(dest/(name+'.png'),pnginfo=meta)
        record['files']={n:{'path':str(dest/(n+'.png')),'sha256':sha(dest/(n+'.png'))} for n in ['full','head','body']}
        (dest/'record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');records.append(record)
        print('Processed '+item['id'],flush=True)
    (a.target/'index.json').write_text(json.dumps({'items':records,'status':'processed_candidates_require_visual_acceptance'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
