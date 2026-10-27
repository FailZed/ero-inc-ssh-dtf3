"""Deterministic proportion frames, skin palettes and complementary body parts.

Derived variants are explicitly not additional AI source drawings. They retain
the native canvas and shared foot baseline. Input data stays unmodified.
"""
from pathlib import Path
import argparse,json,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageChops
from scipy.interpolate import PchipInterpolator
from scipy.ndimage import map_coordinates

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(im,p):
    p.parent.mkdir(parents=True,exist_ok=True);a=np.array(im);a[a[:,:,3]==0,:3]=0;Image.fromarray(a).save(p)
    return {'path':str(p.resolve()),'sha256':sha(p)}

def split_parts(im,neck,center):
    a=np.asarray(im);fg=a[:,:,3]>16;h,w=fg.shape
    def spans(row):
        x=np.flatnonzero(row)
        return [s for s in np.split(x,np.where(np.diff(x)>1)[0]+1) if len(s)>=3] if len(x) else []
    ss=spans(fg[530]);body=next((s for s in ss if s[0]<=center<=s[-1]),None)
    masks=[np.zeros((h,w),bool),np.zeros((h,w),bool)]
    if body is not None:
        left=max((s[-1] for s in ss if s[-1]<body[0]),default=body[0]-12)+3
        right=min((s[0] for s in ss if s[0]>body[-1]),default=body[-1]+12)-3
        for y in range(neck,min(870,h)):
            if y<500:masks[0][y,:int(left)]=True;masks[1][y,int(right)+1:]=True
            else:
                ss=spans(fg[y]);ss.sort(key=lambda s:0 if s[0]<=center<=s[-1] else min(abs(s[0]-center),abs(s[-1]-center)))
                if not ss:continue
                core=ss[:1] if y<735 or ss[0][0]<=center<=ss[0][-1] else ss[:2]
                lo=min(s[0] for s in core);hi=max(s[-1] for s in core)
                l=[s for s in ss if s[-1]<lo];r=[s for s in ss if s[0]>hi]
                if l:masks[0][y,:int((max(s[-1] for s in l)+lo)/2)+1]=True
                if r:masks[1][y,int((min(s[0] for s in r)+hi)/2):]=True
    owner=np.zeros((h,w),np.uint8);owner[:neck]=1;owner[masks[0]]=2;owner[masks[1]]=3
    if center>430:
        # The canonical woman's right arm touches the torso/hip. Connected
        # components alone cannot distinguish it from the body. Trace its
        # painted inner contour as a width measured from the outer silhouette.
        masks=[np.zeros((h,w),bool),np.zeros((h,w),bool)]
        ykeys=[343,370,430,500,530,570,600,650,700,740,770,800,815,825]
        lt=[31,35,44,40,40,44,48,37,28,30,39,39,20,0]
        rt=[25,27,31,27,25,31,30,23,18,17,24,27,12,0]
        for y in range(neck,min(825,h)):
            xs=np.flatnonzero(fg[y])
            if not len(xs):continue
            left=xs[0]+np.interp(y,ykeys,lt);right=xs[-1]-np.interp(y,ykeys,rt)
            masks[0][y,:int(left)]=True;masks[1][y,int(right)+1:]=True
        owner[neck:]=0;owner[masks[0]]=2;owner[masks[1]]=3
    outputs={}
    for k,label in enumerate(['core','head','arm_left','arm_right']):
        part=a.copy();part[:,:,3]*=(owner==k);part[part[:,:,3]==0,:3]=0;outputs[label]=Image.fromarray(part)
    joined=Image.new('RGBA',im.size)
    for part in outputs.values():joined.alpha_composite(part)
    # Disjoint ownership prevents double alpha at part boundaries.
    assert np.array_equal(np.asarray(joined)[a[:,:,3]>0],a[a[:,:,3]>0])
    return outputs

def frame(im,name,neck=332):
    if name=='normal':return im.copy(),neck
    end=1395
    if name=='compact':source=[0,neck,end,1471];dest=[68,neck+68,end,1471]
    elif name=='tall':source=[0,neck,end,1471];dest=[-52,neck-52,end,1471]
    else:source=[0,neck,705,1010,end,1471];dest=[0,neck,650,990,end,1471]
    iy=PchipInterpolator(dest,source)(np.arange(im.height));yy=np.broadcast_to(iy[:,None],(im.height,im.width));xx=np.broadcast_to(np.arange(im.width),(im.height,im.width))
    a=np.asarray(im,dtype=float)/255;a[:,:,:3]*=a[:,:,3:]
    out=np.stack([map_coordinates(a[:,:,k],[yy,xx],order=1,mode='constant',cval=0) for k in range(4)],axis=2);out=np.clip(out,0,1);out[:,:,:3]/=np.maximum(out[:,:,3:],1/255)
    return Image.fromarray(np.clip(np.rint(out*255),0,255).astype('uint8')),int(dest[1])

PALETTES={'porcelain':(255,237,225),'pale':(249,226,207),'warm':(246,215,184),'peach':(243,203,178),'olive':(210,185,148),'tan':(196,151,113),'brown':(145,102,78),'deep':(94,66,53)}
def palette(im,target,sex):
    a=np.array(im);rgb=a[:,:,:3].astype(float);neck=332 if sex=='male' else 343
    body=rgb[neck:];alpha=a[neck:,:,3]>250
    good=alpha&(body[:,:,0]>205)&(body[:,:,1]>165)&(body[:,:,2]>135)
    keys=np.rint(body[good]/4).astype(int);u,counts=np.unique(keys,axis=0,return_counts=True);source=u[counts.argmax()]*4
    # Body/face skin colors are selected from the canonical cel palette.
    region=np.zeros(a.shape[:2],bool);region[neck:]=True
    face=Image.new('L',im.size);d=ImageDraw.Draw(face)
    d.polygon([(315,203),(351,178),(457,179),(486,223),(459,305),(409,331),(348,304)] if sex=='male' else [(367,216),(390,183),(475,176),(524,207),(519,272),(465,330),(414,312)],fill=255)
    region|=np.asarray(face)>0
    selected=(a[:,:,3]>0)
    strength=np.clip((rgb[:,:,0]-140)/50,0,1)*selected
    # All pixels below the neck are skin in these canonical unclothed sources.
    # Above it, warm pale colors select face, ears and neck while retaining hair.
    warm=(rgb[:neck,:,0]>rgb[:neck,:,1]+5)&(rgb[:neck,:,1]>rgb[:neck,:,2]+4)
    face_mask=Image.new('L',im.size);fd=ImageDraw.Draw(face_mask)
    if sex=='male':
        fd.polygon([(318,217),(336,197),(365,182),(405,198),(444,188),(466,220),(477,246),(454,281),(415,308),(369,295),(337,267)],fill=255)
        fd.polygon([(376,285),(445,285),(470,332),(346,332)],fill=255)
    else:
        fd.polygon([(376,236),(389,219),(415,214),(448,235),(482,224),(508,242),(510,263),(488,293),(457,321),(420,306),(395,279)],fill=255)
        fd.polygon([(422,292),(483,292),(521,343),(384,343)],fill=255)
    fm=np.asarray(face_mask)[:neck]>0
    pale=(rgb[:neck,:,0]>185)&(rgb[:neck,:,1]>170)&(rgb[:neck,:,2]>145)&((rgb[:neck,:,0]-rgb[:neck,:,1])>2)&((rgb[:neck,:,1]-rgb[:neck,:,2])>1)
    shadow=fm&(rgb[:neck,:,0]>170)&(rgb[:neck,:,1]>115)&(rgb[:neck,:,2]>95)&((rgb[:neck,:,0]-rgb[:neck,:,1])>12)&((rgb[:neck,:,1]-rgb[:neck,:,2])>=6)
    strength[:neck]*=(pale|shadow)
    # Multiplicative palette mapping carries cel-shadow contrast to darker skin.
    mapped=np.asarray(target)*(np.maximum(rgb,1)/source)**1.15
    changed=np.clip(rgb*(1-strength[:,:,None])+mapped*strength[:,:,None],0,255)
    a[:,:,:3]=np.rint(changed).astype('uint8');return Image.fromarray(a)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--target',type=Path,required=True);p.add_argument('--palettes-only',action='store_true');a=p.parse_args();a.target.mkdir(parents=True,exist_ok=True)
    records=[];bases=read(a.index)['items']
    for item in bases:
        if a.palettes_only:break
        ident=item['id'];sex=item['sex'];source=Path(item['files']['full']['path']);im=Image.open(source).convert('RGBA');neck=item['neck_y']
        # All native bases have exact complementary core/head/arm layers.
        folder=a.target/'foundations'/ident;files={'full':save(im,folder/'full.png')}
        for label,part in split_parts(im,neck,407 if sex=='male' else 448).items():files[label]=save(part,folder/(label+'.png'))
        records.append({'id':ident,'category':'foundation','sex':sex,'kind':'local_rendered_reference_edit','source':str(source),'source_sha256':sha(source),'files':files,'canvas':[832,1472],'neck_y':neck,'baseline_y':1395,'parts_reassemble_exactly':True,'run':item['run']})
        if sex=='male':
            for name in ['normal','compact','tall','long_leg']:
                out,newneck=frame(im,name,neck);file=save(out,a.target/'frames'/(ident+'_'+name+'.png'))
                records.append({'id':ident+'_'+name,'category':'male_foundations','sex':sex,'kind':'identity_frame' if name=='normal' else 'proportion_derivative','base':ident,'frame':name,'neck_y':newneck,'baseline_y':1395,'files':{'full':file}})
    for sex,ident in [('female','female_average'),('male','male_toned')]:
        source=next(i for i in bases if i['id']==ident);im=Image.open(source['files']['full']['path']).convert('RGBA')
        for name,color in PALETTES.items():
            file=save(palette(im,color,sex),a.target/'palettes'/(sex+'_'+name+'.png'))
            records.append({'id':sex+'_'+name,'category':'skin_palette','sex':sex,'kind':'material_recolor','base':ident,'palette':name,'target_base_color':color,'files':{'full':file}})
    manifest={'scope':'Derived native body-pack assets; no runtime integration','canvas':[832,1472],'source_index':str(a.index),'items':records,'palettes':PALETTES,'counts':{'rendered_foundations':len(bases),'male_frame_states':32,'additional_male_proportion_derivatives':24,'skin_palettes':8,'palette_previews':16}}
    (a.target/'derived-index.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8');print(json.dumps(manifest['counts']))
if __name__=='__main__':main()
