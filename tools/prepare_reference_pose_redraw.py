"""Redraw complete changing body regions against an intact adult reference.

Joint math authors ControlNet maps only. No existing limb/head pixels are
rotated or bent. Actual new limbs and occluded skin are rendered by DaSiWa.
"""
from pathlib import Path
import argparse,copy,json,math,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,ImageChops
from prepare_pose_pack import ROOT,PROJECT,config,write,draw_control
from prepare_pose_redraw import hand_maps
from pose_pack_catalogue import specifications

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def body18(pts):
    return np.array([pts[0],(pts[5]+pts[6])/2,pts[6],pts[8],pts[10],pts[5],pts[7],pts[9],pts[12],pts[14],pts[16],pts[11],pts[13],pts[15],pts[2],pts[1],pts[4],pts[3]],float)
def direction(v):return v/max(np.linalg.norm(v),1)
def stroke(draw,points,radius):
    points=[tuple(map(float,p)) for p in points];draw.line(points,fill=255,width=radius*2,joint='curve')
    for x,y in points:draw.ellipse((x-radius,y-radius,x+radius,y+radius),fill=255)

def upper_body_edit_mask(rgba,src,target,neck,wholebody,scores):
    """Replace the entire old arm silhouettes, including shoulders and fingers.

    A neck-height head slice includes shoulder pixels and must not protect them.
    Cover shoulder volumes, old hand landmarks and the new arm corridors, while
    retaining torso landmarks as visual anchors for the pose.
    """
    mask=Image.new('L',rgba.size);d=ImageDraw.Draw(mask)
    top=round(src[0,1]+.48*(neck-src[0,1]))
    alpha=np.array(rgba.getchannel('A'))
    hips=(src[8]+src[11])/2
    # Old arms can overlap the thighs and have fingers well below the wrist.
    bottom=min(1000,round(max(src[4,1],src[7,1],target[4,1],target[7,1])+180))
    for ids in [(2,3,4),(5,6,7)]:
        stroke(d,src[list(ids)],90)
        stroke(d,target[list(ids)],64)
        x,y=src[ids[-1]]
        d.ellipse((x-100,y-50,x+100,y+165),fill=255)
        x,y=target[ids[-1]]
        d.ellipse((x-85,y-85,x+85,y+95),fill=255)
    hand_checks=[]
    for start in [91,112]:
        hand=wholebody[start:start+21][scores[start:start+21]>.3]
        if len(hand):
            lo=hand.min(0)-35;hi=hand.max(0)+35
            d.rectangle((*lo,*hi),fill=255)
            hand_checks.append((start,hand))
    d.rectangle((0,0,rgba.width-1,top-1),fill=0)
    # Preserve the neutral source pelvic surface, never inpaint intimate detail.
    rx=max(40,abs(src[8,0]-src[11,0])*.42)
    d.ellipse((hips[0]-rx,hips[1]-55,hips[0]+rx,hips[1]+120),fill=0)
    probe=np.array(mask)
    checks=[]
    for start,hand in hand_checks:
        xy=np.rint(hand).astype(int)
        checks.append({'source_hand_landmark_start':start,'landmarks':len(hand),
                       'uncovered_pixels':int(np.count_nonzero(probe[xy[:,1],xy[:,0]]<255))})
    if any(c['uncovered_pixels'] for c in checks):raise ValueError('Old arm silhouette survives the redraw mask')
    return mask,{'method':'complete shoulder and old-hand coverage; new arm corridors; torso anchors retained; no head-slice subtraction','transition_y':top,'bottom_y':bottom,'coverage':checks}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--basis',type=Path,required=True);p.add_argument('--family',choices=['arms','head','legs','full_pose'],required=True);p.add_argument('--version',required=True);p.add_argument('--only',nargs='*');a=p.parse_args()
    if not a.only or len(a.only)!=1:
        raise SystemExit('Reference pose edits are diagnostic only: specify exactly one --only pose until native RGB and RGBA family acceptance is recorded.')
    entries={i['id']:i for i in read(a.basis)['items']};prefix='pose_reference_'+a.family+'_'+a.version;folder=ROOT/'input/characters_v2'/prefix
    if folder.exists():raise ValueError('Preserve previous generation inputs; use another --version')
    folder.mkdir(parents=True);items=[]
    for spec in specifications():
        if spec['category']!=a.family or spec['state'] in ['rest','front','neutral','seated_front']:continue
        for sex in ['female','male']:
            ident=sex+'_'+a.family+'_'+spec['state']
            if a.only and ident not in a.only:continue
            base=entries[sex+('_full_pose_seated_front' if a.family=='full_pose' else '_arms_rest')]
            rgba=Image.open(base['files']['full']['path']).convert('RGBA');pts=np.array(base['all_keypoints']);src=body18(pts);target=src.copy();template=np.array([v if v is not None else (0,0) for v in spec['points']],float)
            mask=Image.new('L',rgba.size);d=ImageDraw.Draw(mask);neck=base['neck_y'];hip=(src[8]+src[11])/2
            if a.family=='arms':
                for ids in [(2,3,4),(5,6,7)]:
                    sh,el,wr=ids;l1=np.linalg.norm(src[el]-src[sh]);l2=np.linalg.norm(src[wr]-src[el]);target[el]=src[sh]+direction(template[el]-template[sh])*l1;target[wr]=target[el]+direction(template[wr]-template[el])*l2
                    if spec['state'].startswith('point') and ((ids[0]==2 and spec['state'].endswith('left')) or (ids[0]==5 and spec['state'].endswith('right'))):
                        sign=-1 if ids[0]==2 else 1;wx=max(120,src[sh,0]-l1-l2) if sign<0 else min(rgba.width-120,src[sh,0]+l1+l2);ex=wx-sign*l2;ey=src[sh,1]+math.sqrt(max(0,l1*l1-(ex-src[sh,0])**2));target[el]=[ex,ey];target[wr]=[wx,ey]
                    # Skeletons guide the new drawing, not the replacement mask.
                    # Entire old silhouettes are cleared after both arms move.
                mask,mask_validation=upper_body_edit_mask(rgba,src,target,neck,pts,np.array(base['all_scores']));d=ImageDraw.Draw(mask)
                hands=hand_maps({**spec,'points':target.tolist()})
                for h in hands:
                    hh=np.array(h);d.rectangle((hh[:,0].min()-20,hh[:,1].min()-20,hh[:,0].max()+20,hh[:,1].max()+20),fill=255)
                crop=(0,0,rgba.width,1024);denoise=.9
            elif a.family=='head':
                from prepare_pose_pack import base_points
                original=np.array(base_points(False),float);sx=np.clip(abs(src[14,0]-src[15,0])/36,.8,1.5);sy=np.clip(abs(src[0,1]-src[1,1])/115,.8,1.4)
                for k in [0,14,15,16,17]:target[k]=src[k]+(template[k]-original[k])*[sx,sy]
                for k in [0,14,15,16,17]:
                    if spec['points'][k] is None:target[k]=[np.nan,np.nan]
                headbox=Image.open(base['files']['head']['path']).getchannel('A').getbbox();d.rectangle((headbox[0]-60,max(32,headbox[1]-18),headbox[2]+60,neck+24),fill=255)
                crop=(224,0,1248,768);denoise=.72;hands=[]
            elif a.family=='legs':
                for ids in [(8,9,10),(11,12,13)]:
                    hp,kn,an=ids;l1=np.linalg.norm(src[kn]-src[hp]);l2=np.linalg.norm(src[an]-src[kn]);target[kn]=src[hp]+direction(template[kn]-template[hp])*l1;target[an]=target[kn]+direction(template[an]-template[kn])*l2
                    stroke(d,src[list(ids)],100);stroke(d,target[list(ids)],100)
                    for x,y in [src[an],target[an]]:d.rectangle((x-100,y-65,x+100,y+115),fill=255)
                rx=max(40,abs(src[8,0]-src[11,0])*.42);d.ellipse((hip[0]-rx,hip[1]-65,hip[0]+rx,hip[1]+85),fill=0)
                for ids in [(2,3,4),(5,6,7)]:
                    pm=Image.new('L',rgba.size);stroke(ImageDraw.Draw(pm),src[list(ids)],45);mask=ImageChops.subtract(mask,pm)
                crop=(0,640,rgba.width,1472);denoise=.78;hands=[]
            else:
                target=template.copy();target[:,0]+=320;d.rectangle((0,0,rgba.width-1,rgba.height-1),fill=255);crop=(0,0,rgba.width,rgba.height);denoise=.78;hands=[]
            mask=mask.filter(ImageFilter.GaussianBlur(3));dest=folder/ident;dest.mkdir()
            rgba.save(dest/'protected-full.png');mask.save(dest/'edit-mask-full.png');bg=Image.new('RGBA',rgba.size,'#eeeeec');bg.alpha_composite(rgba);bg.convert('RGB').crop(crop).save(dest/'reference.png');mask.crop(crop).save(dest/'mask.png')
            shifted=[]
            for point in target:
                x,y=point-np.array(crop[:2]);shifted.append((float(x),float(y)) if np.isfinite([x,y]).all() and 0<=x<crop[2]-crop[0] and 0<=y<crop[3]-crop[1] else None)
            hh=[[(x-crop[0],y-crop[1]) for x,y in h] for h in hands];draw_control(shifted,dest/'control.png',hh,size=(crop[2]-crop[0],crop[3]-crop[1]))
            rel=dest.relative_to(ROOT/'input').as_posix();person='1girl, mature adult woman age 30, short brown bob haircut' if sex=='female' else '1boy, male focus, mature adult man age 35, masculine face, short brown hair, flat male chest'
            words='eincanime, '+person+', original anime illustration, same adult character, same body proportions and skin palette, delicate thin brown lineart, matte flat colors, controlled peach cel shading, natural complete hands and joints, '+spec['action']+', redraw changed anatomy naturally, unclothed neutral artistic figure study, bare shoulders, bare chest, bare arms and legs, plain light gray backdrop'
            negative='child, teen, clothes, bra, underwear, jacket, coat, shirt, trousers, sleeves, skirt, fabric, shoes, socks, text, watermark, logo, sticker, emoji, symbols, toy, miniature, inset, censor bar, mosaic, distorted anatomy, extra limbs, extra fingers, missing fingers, cut wrist, disconnected arm, long neck, 3d, glossy skin, photorealistic'
            if a.family=='full_pose':negative+=', detailed genitals, explicit intimate details, sexual, erotic, seductive pose'
            items.append({'id':ident,'rig':sex+'_canonical','sex':sex,'state':spec['state'],'title':spec['title'],'category':a.family,'image':rel+'/reference.png','mask':rel+'/mask.png','control':rel+'/control.png','prompt':words,'negative':negative,'seed':2026111000+len(items),'denoise':denoise,'preserve_input_latent':False if a.family=='arms' else True,'protected_rgba':str(dest/'protected-full.png'),'protected_sha256':sha(dest/'protected-full.png'),'edit_mask_full':str(dest/'edit-mask-full.png'),'edit_mask_sha256':sha(dest/'edit-mask-full.png'),'crop_box':list(crop),'source_basis_record':str(Path(base['files']['full']['path']).with_name('record.json')),'region_redraw_not_deformation':True})
            if a.family=='arms':items[-1]['mask_validation']=mask_validation;items[-1]['foreground_policy']='whole_foreground_no_material_deletion'
            write(dest/'joints.json',{'source_openpose18':src.tolist(),'target_openpose18':[[float(v) for v in t] if np.isfinite(t).all() else None for t in target],'crop_box':crop,'hands':hh,'technical_control_only':True,'renderer':'official DWPose palette and drawing implementation',**({'mask_validation':mask_validation} if a.family=='arms' else {})})
    conf=config(prefix,items);conf['controlnet'].update(strength=.85,end_percent=.9);conf.update(encode_individually=True,preserve_input_latent=a.family!='arms',scope='Original adult non-graphic reference poses. Entire changing regions redrawn by the model; no rotated or bent existing body pixels. Protected body and neutral pelvic surface stay unchanged. Not runtime registered.')
    out=PROJECT/'docs/art/characters-v2'/(prefix.replace('_','-')+'.json');write(out,conf);print(out)
if __name__=='__main__':main()
