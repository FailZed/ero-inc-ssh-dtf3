"""Prepare proportion guides from owned EroInc art for local DaSiWa cleanup.

These are reference-derived guides, not accepted body drawings. Source pixels
are never taken from School. Records distinguish guides, generated drawings,
material variants and combinations. Run with the E: postprocess environment.
"""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, PngImagePlugin
from scipy.interpolate import PchipInterpolator
from scipy.ndimage import map_coordinates

ROOT = Path('E:/Ai/ComfyUI-EroInc')
PROJECT = Path(__file__).resolve().parents[1]
Y = [0, 320, 355, 430, 525, 600, 690, 800, 900, 1010, 1140, 1260, 1395, 1471]


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def make_guide(source, scales, center, segmented_arms=False, arm_width_scale=1):
    source_image=source.convert('RGBA') if isinstance(source,Image.Image) else Image.open(source).convert('RGBA')
    rgba = np.asarray(source_image, dtype=np.float32) / 255
    h, w = rgba.shape[:2]
    yy, xx = np.mgrid[:h, :w].astype(np.float32)
    widths = PchipInterpolator(Y, scales)(np.arange(h))
    # The outer canvas stays fixed; local widths vary smoothly with torso/leg height.
    coords_x = np.empty((h, w), dtype=np.float32)
    forward_x = np.empty((h, w), dtype=np.float32)
    for y, scale in enumerate(widths):
        radius = float(np.interp(y,[0,350,460,560,660,750,850,1000,1471],[130,140,140,95,110,132,150,165,165]))
        barrier = float(np.interp(y,[0,460,560,750,850,1471],[235,215,158,178,230,235]))
        src = np.array([0,center-barrier,center-radius,center,center+radius,center+barrier,w-1])
        dst = src.copy().astype(float)
        dst[2] = center-radius*scale; dst[4] = center+radius*scale
        if not np.all(np.diff(dst)>0): raise ValueError('Invalid width guide')
        coords_x[y] = PchipInterpolator(dst, src)(np.arange(w))
        forward_x[y] = PchipInterpolator(src, dst)(np.arange(w))
    arm_masks=[]
    seam_positions=[]
    if segmented_arms:
        # Separate the original painted arms before changing torso proportions.
        # Ordinary row-wise warping couples waist width to forearm width.
        fg=rgba[:,:,3]>.5
        def segments(row):
            xs=np.flatnonzero(row)
            if not len(xs):return []
            return [s for s in np.split(xs,np.where(np.diff(xs)>1)[0]+1) if len(s)>=3]
        parts=segments(fg[530]);body=next((s for s in parts if s[0]<=center<=s[-1]),None)
        if body is None:raise ValueError('No torso interval at the arm separation reference row')
        left=max((s[-1] for s in parts if s[-1]<body[0]),default=body[0]-16)+4
        right=min((s[0] for s in parts if s[0]>body[-1]),default=body[-1]+16)-4
        lm=np.zeros((h,w),bool);rm=lm.copy()
        for row in range(340,min(870,h)):
            if row<500:
                lm[row,:int(left)]=True;rm[row,int(right)+1:]=True
            else:
                ss=segments(fg[row])
                if not ss:continue
                ss.sort(key=lambda s:0 if s[0]<=center<=s[-1] else min(abs(s[0]-center),abs(s[-1]-center)))
                core=ss[:1] if row<735 or ss[0][0]<=center<=ss[0][-1] else ss[:2]
                lo=min(s[0] for s in core);hi=max(s[-1] for s in core)
                lparts=[s for s in ss if s[-1]<lo];rparts=[s for s in ss if s[0]>hi]
                if lparts:lm[row,:int((max(s[-1] for s in lparts)+lo)/2)+1]=True
                if rparts:rm[row,int((min(s[0] for s in rparts)+hi)/2):]=True
        arm_masks=[lm,rm];seam_positions=[left,right]
        body_rgba=rgba.copy();body_rgba[:,:,3]*=~(lm|rm)
    else:body_rgba=rgba
    premult = body_rgba.copy(); premult[:,:,:3] *= premult[:,:,3:]
    interpolation=1 if segmented_arms else 3
    result = np.stack([map_coordinates(premult[:,:,c], [yy,coords_x], order=interpolation, mode='constant', cval=0) for c in range(4)], axis=2)
    result = np.clip(result,0,1)
    result[:,:,:3] /= np.maximum(result[:,:,3:],1/255)
    if segmented_arms:
        total_alpha=result[:,:,3].copy()
        # The attachment follows the torso field; lower arms move rigidly with
        # the shoulder frame. Original hands and contours stay coherent.
        for side,(mask,seam) in enumerate(zip(arm_masks,seam_positions)):
            dx=forward_x[:,int(seam)]-seam
            extra=max(0,max(scales[5:8])-1)*40
            goal=float(np.mean(dx[355:430]))+(-extra if side==0 else extra)
            t=np.clip((np.arange(h)-490)/100,0,1);t=t*t*(3-2*t)
            dx=dx*(1-t)+goal*t
            aw=1+(arm_width_scale-1)*t
            inverse=seam+(xx-seam-dx[:,None])/aw[:,None]
            arm=rgba.copy();arm[:,:,3]*=mask;arm[:,:,:3]*=arm[:,:,3:]
            sampled=np.stack([map_coordinates(arm[:,:,k],[yy,inverse],order=1,mode='constant',cval=0) for k in range(4)],axis=2)
            sampled=np.clip(sampled,0,1);aa=sampled[:,:,3:];total_alpha+=aa[:,:,0]
            # Source-over for real overlaps; additive coverage fills complementary
            # antialiased cut edges without a transparent shoulder seam.
            oa=result[:,:,3:];new_a=aa+oa*(1-aa)
            rgb=(sampled[:,:,:3]+result[:,:,:3]*oa*(1-aa))/np.maximum(new_a,1/255)
            result=np.concatenate([rgb,new_a],axis=2)
        result[:,:,3]=np.clip(total_alpha,0,1)
    result = np.clip(np.rint(result*255),0,255).astype('uint8')
    # Reference head and feet are unchanged, with no anatomy painted by the preparation tool.
    image=Image.fromarray(result)
    original=source_image
    image.paste(original.crop((0,0,w,320)),(0,0))
    return image


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--spec',type=Path,required=True);p.add_argument('--target',type=Path,required=True)
    a=p.parse_args(); spec=json.loads(a.spec.read_text(encoding='utf-8-sig'))
    if a.target.exists(): raise ValueError('Preserve prior guides; use another version')
    a.target.mkdir(parents=True); records=[]
    for item in spec['items']:
        source=Path(item['source']); im=make_guide(source,item['widths'],item['center'],item.get('segmented_arms',False),item.get('arm_width_scale',1))
        folder=a.target/item['id'];folder.mkdir()
        meta=PngImagePlugin.PngInfo()
        record={'id':item['id'],'source':str(source),'source_sha256':digest(source),'method':'Smooth 2D proportion guide derived from owned reference; requires DaSiWa rendering and visual acceptance','width_y':Y,'width_scales':item['widths'],'segmented_arms':item.get('segmented_arms',False),'arm_width_scale':item.get('arm_width_scale',1),'not_a_finished_asset':True}
        meta.add_text('ero_inc_proportion_guide',json.dumps(record))
        im.save(folder/'guide.png',pnginfo=meta)
        flat=Image.new('RGBA',im.size,'#eeeeec');flat.alpha_composite(im);flat.convert('RGB').save(folder/'reference.png',pnginfo=meta)
        # Neutral full-body edit, retaining original adult identity and external anatomy.
        mask=Image.new('L',im.size,0);ImageDraw.Draw(mask).rectangle((125,item['neck_y']+20,710,1270),fill=255)
        mask=mask.filter(ImageFilter.GaussianBlur(12)); mask.paste(0,(0,0,832,item['neck_y']))
        if item.get('edit_region')=='abdomen':
            mask=Image.new('L',im.size,0);ImageDraw.Draw(mask).rounded_rectangle((296,474,519,646),radius=24,fill=255);mask=mask.filter(ImageFilter.GaussianBlur(10))
        else:
            # This cycle changes build, not genital anatomy; the anatomy cycle has separate masks.
            protect=Image.new('L',im.size,0);d=ImageDraw.Draw(protect)
            d.ellipse(item['protected_anatomy'],fill=255)
            from PIL import ImageChops
            mask=ImageChops.subtract(mask,ImageChops.lighter(protect,protect.filter(ImageFilter.GaussianBlur(12))))
        mask.save(folder/'edit-mask.png');record['guide_sha256']=digest(folder/'guide.png');record['mask_sha256']=digest(folder/'edit-mask.png')
        records.append(record)
    (a.target/'guides.json').write_text(json.dumps({'scope':'Original own-reference proportion guides; not production art','records':records},indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'guides':len(records),'target':str(a.target)}))


if __name__=='__main__': main()
