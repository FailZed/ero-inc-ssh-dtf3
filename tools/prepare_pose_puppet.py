"""Owned, non-graphic adult puppet guides for local pose finishing.

Guides are explicitly not finished illustrations. The two existing neutral
identities supply contour, palette, hands and feet; no donor art is used.
"""
from pathlib import Path
import argparse, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
from scipy import ndimage
from prepare_pose_pack import ROOT,PROJECT,SIZE,STYLE,NEGATIVE,subject,config,write,draw_control
from pose_pack_catalogue import specifications
from compose_body_pack import nipple_centers

PACK=PROJECT/'assets/art_source/characters_v2/body_pack_v1'

def normalize(im):
    a=np.array(im);a[a[:,:,3]==0,:3]=0;return Image.fromarray(a)

def neutral_core(sex):
    im=Image.open(PACK/f'rig/{sex}/core.png').convert('RGBA');a=np.array(im)
    skin=(255,235,216) if sex=='female' else (249,223,202)
    # Explicit smooth figure-study treatment, no intimate details transferred.
    m=Image.new('L',SIZE);d=ImageDraw.Draw(m)
    if sex=='female':
        for x,y in nipple_centers(im):d.ellipse((x-22,y-22,x+22,y+22),fill=255)
        d.ellipse((385,677,546,807),fill=255)
    else:
        for x,y in [(338,450),(476,450)]:d.ellipse((x-15,y-15,x+15,y+15),fill=255)
        d.ellipse((352,663,466,808),fill=255)
    mm=np.asarray(m.filter(ImageFilter.GaussianBlur(3)),float)/255*(a[:,:,3]/255)
    a[:,:,:3]=np.rint(a[:,:,:3]*(1-mm[:,:,None])+np.array(skin)*mm[:,:,None]).astype('uint8')
    if sex=='male':
        a[756:834,383:435,3]=0
        im=Image.fromarray(a);p=ImageDraw.Draw(im)
        p.polygon([(360,700),(460,700),(451,741),(427,756),(408,762),(387,754),(368,739)],fill=skin)
    else:im=Image.fromarray(a)
    return normalize(im)

def source_joints(sex):
    # Anchors are measured on the original registered rig, image-space sides.
    if sex=='female':
        return {'arms':[((335,366),(333,540),(301,794)),((538,366),(554,540),(596,794))],
                'legs':[((392,800),(370,1090),(378,1350)),((521,800),(526,1090),(523,1350))], 'neck':343,'hip':800,'center':448}
    return {'arms':[((318,366),(290,520),(278,775)),((497,366),(525,520),(550,775))],
            'legs':[((355,790),(343,1085),(340,1350)),((465,790),(479,1085),(483,1350))], 'neck':332,'hip':790,'center':407}

def bone(im,a,b,c,d):
    a=np.array(a,float);b=np.array(b,float);c=np.array(c,float);d=np.array(d,float)
    v=b-a;w=d-c;s=np.linalg.norm(w)/np.linalg.norm(v)
    theta=math.atan2(w[1],w[0])-math.atan2(v[1],v[0]);co=math.cos(theta)/s;si=math.sin(theta)/s
    mat=np.array([[co,si],[-si,co]]);t=a-mat@c
    return im.transform(SIZE,Image.Transform.AFFINE,(*mat[0],t[0],*mat[1],t[1]),Image.Resampling.BICUBIC)

def clipped(im,box):
    m=Image.new('L',SIZE);ImageDraw.Draw(m).rectangle(box,fill=255);o=im.copy();o.putalpha(ImageChops.multiply(o.getchannel('A'),m));return o

def guide(sex,spec):
    core=neutral_core(sex);j=source_joints(sex);pts=spec['points'];category=spec['category']
    arm_images=[];leg_images=[];neck=j['neck']
    head=clipped(core,(0,0,831,neck-1))
    if category=='full_pose':
        # Torso and pelvis remain a volume; legs are projected around true joints.
        torso=clipped(core,(0,neck,831,j['hip']+25));ty=pts[1][1];scale=(sum(pts[k][1] for k in [8,11])/2-ty)/(j['hip']-neck)
        head=head.transform(SIZE,Image.Transform.AFFINE,(1,0,0,0,1,neck-ty),Image.Resampling.BICUBIC)
        torso=torso.transform(SIZE,Image.Transform.AFFINE,(1,0,j['center']-416,0,1/scale,neck-ty/scale),Image.Resampling.BICUBIC)
        core=torso;neck=round(ty)
    elif category=='legs':
        core=clipped(core,(0,0,831,j['hip']+25))
    if category in ['legs','full_pose']:
        original=neutral_core(sex)
        for side,ids in enumerate([(8,9,10),(11,12,13)]):
            hip,knee,ankle=j['legs'][side];center=j['center'];part=clipped(original,(0 if side==0 else center,j['hip']-5,center if side==0 else 831,1471))
            upper=clipped(part,(0,0,831,knee[1]+15));lower=clipped(part,(0,knee[1]-15,831,1471))
            leg=bone(lower,knee,ankle,pts[ids[1]],pts[ids[2]])
            leg.alpha_composite(bone(upper,hip,knee,pts[ids[0]],pts[ids[1]]));leg_images.append(leg)
    for side,ids in enumerate([(2,3,4),(5,6,7)]):
        src=Image.open(PACK/f'rig/{sex}/rest/arm-{"left" if side==0 else "right"}.png').convert('RGBA');sh,el,wr=j['arms'][side]
        if category in ['head','legs']:
            arm=src
        else:
            upper=clipped(src,(0,0,831,el[1]+14));lower=clipped(src,(0,el[1]-14,831,1471))
            arm=bone(upper,sh,el,pts[ids[0]],pts[ids[1]])
            arm.alpha_composite(bone(lower,el,wr,pts[ids[1]],pts[ids[2]]))
        arm_images.append(arm)
    out=Image.new('RGBA',SIZE)
    for leg in leg_images:out.alpha_composite(leg)
    # Ordinary gestures behind the torso, folded/hip/thoughtful gestures in front.
    front=category=='arms' and spec['state'] in ['folded','hip_left','hip_right','thinking']
    if not front:
        for arm in arm_images:out.alpha_composite(arm)
    out.alpha_composite(core)
    if front:
        for arm in arm_images:out.alpha_composite(arm)
    if category=='full_pose':out.alpha_composite(head)
    # Entire figure is a reference-preserving finishing target, not free generation.
    mask=out.getchannel('A').filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(3))
    if category=='head':
        mask=Image.new('L',SIZE);ImageDraw.Draw(mask).rectangle((230,55,625,neck+20),fill=255);mask=mask.filter(ImageFilter.GaussianBlur(5))
    else:
        prot=head.getchannel('A').filter(ImageFilter.MaxFilter(9));mask=ImageChops.subtract(mask,prot)
    if category=='arms':
        # Keep legs and feet pixel-exact for local arm modules.
        ImageDraw.Draw(mask).rectangle((0,960,831,1471),fill=0)
    return normalize(out),mask,neck,arm_images,leg_images

def main():
    raise SystemExit('Abandoned guide experiment: the user requested complete figure redraws. Use prepare_pose_redraw.py; do not generate new warped limb guides.')
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--pilot',action='store_true');p.add_argument('--all',action='store_true');p.add_argument('--version',default='v3');a=p.parse_args()
    specs=specifications()
    if a.pilot:specs=[i for i in specs if (i['category'],i['state']) in [('arms','folded'),('full_pose','seated_front')]]
    elif not a.all:p.error('Choose --pilot or --all')
    prefix='pose_puppet_'+('pilot_' if a.pilot else 'all_')+a.version;folder=ROOT/'input/characters_v2'/prefix;items=[]
    if folder.exists():raise ValueError('Preserve guide versions; use another --version')
    for spec in specs:
        for sex in ['female','male']:
            ident=sex+'_'+spec['category']+'_'+spec['state'];dest=folder/ident;dest.mkdir(parents=True)
            im,mask,neck,arms,legs=guide(sex,spec);im.save(dest/'guide.png');mask.save(dest/'mask.png')
            bg=Image.new('RGBA',SIZE,'#eeeeec');bg.alpha_composite(im);bg.convert('RGB').save(dest/'reference.png');draw_control(spec['points'],dest/'control.png')
            for i,part in enumerate(arms):part.save(dest/f'arm-{i}.png')
            for i,part in enumerate(legs):part.save(dest/f'leg-{i}.png')
            meta={**spec,'sex':sex,'neck_y':neck,'technical_guide_only':True,'intimate_details':'not transferred; smooth non-graphic figure-study treatment'};write(dest/'joints.json',meta)
            rel=dest.relative_to(ROOT/'input').as_posix()
            items.append({'id':ident,'rig':sex+'_canonical','sex':sex,'category':spec['category'],'state':spec['state'],'title':spec['title'],'image':rel+'/reference.png','mask':rel+'/mask.png','control':rel+'/control.png','prompt':STYLE+', '+subject(sex)+', '+spec['action']+', nude adult nonsexual anatomical art reference, bare shoulders and limbs, smooth simplified pelvis','seed':2026101950+len(items),'head_neck_y':neck,'denoise':.32 if spec['category']!='head' else .68,'preserve_input_latent':True})
    conf=config(prefix,items);conf.pop('controlnet');conf['preserve_input_latent']=True;conf['denoise']=.32
    conf['negative']=NEGATIVE+', dress, sleeves, skirt, shoes, socks, picture frame, wall, room, floor, chair, furniture'
    target=PROJECT/'docs/art/characters-v2'/((prefix.replace('_','-'))+'.json');write(target,conf)
    print(target)
if __name__=='__main__':main()
