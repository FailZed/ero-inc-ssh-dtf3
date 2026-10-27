"""Owned full-figure guides for the remaining body-pack families.

These inputs are explicitly guides. A local DaSiWa render and separate visual
acceptance are required. No reference artwork or pixels come from School.
"""
from pathlib import Path
import argparse, json, hashlib, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops
from scipy.ndimage import map_coordinates
import aggdraw

ROOT=Path('E:/Ai/ComfyUI-EroInc')
PROJECT=Path(__file__).resolve().parents[1]

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def path(im,commands,fill=None,stroke=None,width=1.4):
    ctx=aggdraw.Draw(im);p=aggdraw.Path()
    for command,pts in commands:
        getattr(p,{'M':'moveto','L':'lineto','C':'curveto','Q':'curveto','Z':'close'}[command])(*pts)
    ctx.path(p,aggdraw.Brush(fill) if fill else None,aggdraw.Pen(stroke,width) if stroke else None);ctx.flush()

def sample(im,ix,iy):
    a=np.asarray(im,dtype=float)/255;a[:,:,:3]*=a[:,:,3:]
    out=np.stack([map_coordinates(a[:,:,k],[iy,ix],order=1,mode='constant',cval=0) for k in range(4)],axis=2)
    out=np.clip(out,0,1);out[:,:,:3]/=np.maximum(out[:,:,3:],1/255)
    return Image.fromarray(np.clip(np.rint(out*255),0,255).astype('uint8'))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--family',choices=['anatomy','pregnancy','species','legs','poses','hair','tone'],required=True);p.add_argument('--target',type=Path,required=True);p.add_argument('--config',type=Path,required=True);p.add_argument('--pregnancy-volume',action='store_true');p.add_argument('--pregnancy-progression',action='store_true');p.add_argument('--rig-only',action='store_true');a=p.parse_args()
    if a.target.exists():raise ValueError('Preserve previous inputs; choose a new version')
    a.target.mkdir(parents=True)
    c=json.loads((PROJECT/'docs/art/characters-v2/body-details-v1.json').read_text(encoding='utf-8'));c['items']=[]
    c['output_prefix']='characters_v2/'+a.target.name.replace('_guides','')
    records=[]
    def add(name,sex,category,im,mask,words,denoise=.38,source_override=None):
        source=Path(source_override) if source_override else ROOT/f'input/characters_v2/bases/{"male_toned" if sex=="male" else "female_average"}/full.png'
        dest=a.target/name;dest.mkdir();im.save(dest/'guide.png');mask.save(dest/'mask.png')
        flat=Image.new('RGBA',im.size,'#eeeeec');flat.alpha_composite(im);flat.convert('RGB').save(dest/'reference.png')
        rel=dest.relative_to(ROOT/'input').as_posix()
        j=len(c['items']);subject='mature adult man, short brown hair' if sex=='male' else 'mature adult woman, short brown bob'
        c['items'].append({'id':name,'rig':sex+'_canonical','category':category,'image':rel+'/reference.png','mask':rel+'/mask.png','prompt':'masterpiece, best quality, eincanime, eincbody, original '+subject+', age 30, full body neutral unclothed anatomical character sheet, '+words+', natural adult anatomy, blue eyes, delicate thin brown lineart, pale warm skin, matte flat colors, limited light peach cel shadows, evenly lit, plain light gray background','negative':c['negative']+', jacket, coat, sleeves, fabric, detached limbs, duplicate outlines','seed':9904000+j,'denoise':denoise,'preserve_input_latent':True})
        records.append({'id':name,'sex':sex,'category':category,'source':str(source),'source_sha256':digest(source),'guide':str(dest/'guide.png'),'mask':str(dest/'mask.png'),'method':'Owned reference plus original proportion/pose/anatomical guide; local render required','description':words,'not_a_finished_asset':True})
        return dest
    def base(sex):return Image.open(ROOT/f'input/characters_v2/bases/{"male_toned" if sex=="male" else "female_average"}/full.png').convert('RGBA')
    def ellipse(box,blur=8):
        m=Image.new('L',(832,1472));ImageDraw.Draw(m).ellipse(box,fill=255);return m.filter(ImageFilter.GaussianBlur(blur))
    yy,xx=np.mgrid[:1472,:832].astype(float)
    if a.family=='anatomy':
        for size,(length,width) in enumerate([(36,17),(49,20),(64,20),(49,25)],1):
            for covered in [True,False]:
                original=base('male');im=original.copy();skin=tuple(np.asarray(im)[650:675,390:420,:3].reshape(-1,3).mean(axis=0).astype(int))
                # Original neutral anatomy construction at rest, whole-body context.
                # Replace the fused bag-like draft with separated natural contours.
                cleaned=Image.new('RGBA',im.size,skin+(255,));cleanmask=ellipse((354,663,463,794),5)
                im=Image.composite(cleaned,im,cleanmask)
                edge='#896e60';shade='#c99f88';warm='#eac5af';x=402;y=700
                path(im,[('M',(x-15,y+13)),('C',(x-25,y+24,x-22,y+55,x-7,y+60)),('C',(x+4,y+65,x+21,y+56,x+20,y+38)),('C',(x+20,y+24,x+13,y+17,x+9,y+13)),('Z',())],warm,edge,1.25)
                path(im,[('M',(x+3,y+30)),('C',(x-1,y+41,x+2,y+49,x-2,y+54))],None,shade,1.2)
                end=y+length
                path(im,[('M',(x-width/2,y-2)),('C',(x-width/2-3,y+12,x-width/2-5,end-9,x-width/2-3,end)),('C',(x-width/2+2,end+9,x+width/2-1,end+9,x+width/2+2,end)),('C',(x+width/2+5,end-13,x+width/2+1,y+14,x+width/2,y-2))],skin,edge,1.35)
                path(im,[('M',(x+width/2-2,y+9)),('C',(x+width/2-4,end-17,x+width/2-3,end-5,x+width/2-5,end+1))],None,shade,2.3)
                if covered:
                    path(im,[('M',(x-width/2-1,end-5)),('C',(x-3,end-1,x+3,end-1,x+width/2+1,end-5))],None,edge,1.0)
                else:
                    path(im,[('M',(x-width/2-1,end-7)),('C',(x-width/2-7,end+3,x-4,end+11,x+width/2+1,end+2)),('C',(x+width/2+5,end-2,x+width/2+4,end-7,x+width/2+1,end-9)),('C',(x+2,end-4,x-4,end-4,x-width/2-1,end-7)),('Z',())],'#dfb09b',edge,1.1)
                im.putalpha(original.getchannel('A'))
                add(f'male_external_{size}_{"covered" if covered else "uncovered"}','male','male_external_anatomy',im,ellipse((345,664,465,795),5),'natural flaccid male anatomy at rest, natural separate scrotum, '+('natural foreskin' if covered else 'natural circumcised anatomy')+', same neutral relaxed standing pose',.30)
    elif a.family=='pregnancy':
        if a.pregnancy_progression:
            source=ROOT/'output/characters_v2/body_pregnancy_v4/processed/pregnancy_stage_09/full.png';original=Image.open(source).convert('RGBA')
            arms=ImageChops.lighter(*[Image.open(ROOT/f'input/characters_v2/body_pose_guides_v8/female_arms_both_open/arm-{side}-mask.png').convert('L') for side in ['left','right']]);ownership=np.asarray(arms.filter(ImageFilter.MaxFilter(7)))>8
            core_array=np.array(original);arm_array=core_array.copy();core_array[:,:,3]*=~ownership;arm_array[:,:,3]*=ownership
            core_image=Image.fromarray(core_array);arm_image=Image.fromarray(arm_array)
            for stage in range(1,10):
                t=stage/9;cx=455;cy=618;sx=.62+.38*t;sy=.78+.22*t
                w=np.exp(-((xx-cx)/180)**4-((yy-cy)/150)**4)*np.clip((yy-515)/35,0,1)*np.clip((735-yy)/29,0,1)
                ix=cx+(xx-cx)/(1+(sx-1)*w);iy=cy+(yy-cy)/(1+(sy-1)*w)
                im=sample(core_image,ix,iy);im.alpha_composite(arm_image)
                add(f'pregnancy_stage_{stage:02d}','female','pregnancy_stages',im,ellipse((285,480,630,767),8),f'neutral mature adult pregnant woman, preserve the existing coherent anatomical drawing, pregnancy volume progression {stage} of nine, natural continuous abdomen, relaxed arms held away from torso',.12,source)
            c.pop('body_lora',None);a.config.write_text(json.dumps(c,indent=2)+'\n');(a.target/'guides.json').write_text(json.dumps({'items':records,'method':'Nine controlled volume derivatives from one curated original pregnancy drawing; not nine independent source drawings','accepted_drawings':0},indent=2)+'\n');print('Prepared9 ordered pregnancy volume guides');return
        if a.pregnancy_volume:
            source=ROOT/'output/characters_v2/body_pose_v7/processed/female_arms_both_open/full.png'
            original=Image.open(source).convert('RGBA')
            for stage in range(1,10):
                t=stage/9;im=original.copy();cx=455;cy=615;rx=49+87*t;ry=42+69*t;k=.55228475
                ellipse_path=[('M',(cx-rx,cy)),('C',(cx-rx,cy-k*ry,cx-k*rx,cy-ry,cx,cy-ry)),('C',(cx+k*rx,cy-ry,cx+rx,cy-k*ry,cx+rx,cy)),('C',(cx+rx,cy+k*ry,cx+k*rx,cy+ry,cx,cy+ry)),('C',(cx-k*rx,cy+ry,cx-rx,cy+k*ry,cx-rx,cy)),('Z',())]
                path(im,ellipse_path,'#ffebd8')
                # A restrained lower/right cel plane, not an inked oval around
                # the abdomen; early states remain inside the normal silhouette.
                path(im,[('M',(cx+rx*.88,cy+ry*.16)),('C',(cx+rx*.84,cy+ry*.80,cx+rx*.35,cy+ry*.99,cx-rx*.25,cy+ry*.90)),('C',(cx+rx*.24,cy+ry*.84,cx+rx*.63,cy+ry*.63,cx+rx*.88,cy+ry*.16)),('Z',())],'#d4a792')
                path(im,[('M',(cx+5,cy-17)),('C',(cx+1,cy-10,cx+3,cy-6,cx+6,cy-4))],None,'#b28c79',1.0)
                add(f'pregnancy_stage_{stage:02d}','female','pregnancy_stages',im,ellipse((290,485,625,762),8),f'neutral mature adult pregnant woman, natural pregnancy progression stage {stage} of nine, full rounded abdominal volume appropriate to stage, relaxed arms held away from abdomen, calm neutral standing reference',.24,source)
            a.config.write_text(json.dumps(c,indent=2)+'\n');(a.target/'guides.json').write_text(json.dumps({'items':records,'accepted_drawings':0},indent=2)+'\n');print('Prepared9 full-volume pregnancy guides');return
        original=base('female')
        for stage in range(1,10):
            t=stage/9;cx=455;cy=615;w=np.exp(-((xx-cx)/112)**4-((yy-cy)/100)**4)
            amount=.42*t+max(0,t-.4)*.65
            ix=cx+(xx-cx)/(1+amount*w);iy=yy-12*t*w
            im=sample(original,ix,iy)
            # Simple original cel contour guide for steadily growing abdominal volume.
            path(im,[('M',(396-20*t,572)),('C',(387-14*t,625,408-18*t,665+12*t,453,675+15*t)),('C',(493+19*t,680+15*t,527+19*t,643,520+20*t,583))],None,'#c6937d',1.2+1.1*t)
            add(f'pregnancy_stage_{stage:02d}','female','pregnancy_stages',im,ellipse((309,481,604,738),9),f'neutral adult pregnant woman, pregnancy progression stage {stage} of nine, '+('slight natural abdominal fullness' if stage<4 else 'naturally rounded pregnant abdomen')+', same resting arms, same standing pose',.29)
    elif a.family=='tone':
        for sex in ['female','male']:
            for level in range(1,4 if sex=='female' else 3):
                im=base(sex);cx=458 if sex=='female' else 407;top=515 if sex=='female' else 505
                color=['#e6c5b1','#dbb09a','#cda18c'][level-1]
                for side in [-1,1]:
                    for row in range(level):
                        y=top+row*40;x=cx+side*24
                        path(im,[('M',(x-side*6,y)),('C',(x+side*9,y+3,x+side*13,y+12,x+side*10,y+20)),('C',(x+side*5,y+14,x+side*2,y+8,x-side*6,y)),('Z',())],color)
                mask=ellipse((370,492,540,661),8) if sex=='female' else ellipse((311,482,507,658),8)
                add(sex+'_tone_'+str(level),sex,'muscle_definition',im,mask,['subtle firm abdominal muscle tone','moderately visible abdominal muscle definition','clearly defined balanced adult abdominal muscles'][level-1],.30)
    elif a.family=='hair':
        rng=np.random.default_rng(990910)
        for sex in ['female','male']:
            patterns=['sparse','small_triangle','triangle','broad_triangle','trimmed','oval','strip','rectangle','diffuse','asymmetric'] if sex=='female' else ['sparse','triangle','broad_triangle','chest_light','chest_full','legs']
            for j,shape in enumerate(patterns):
                im=base(sex);marks=Image.new('RGBA',im.size);cx=465 if sex=='female' else 405;cy=705 if sex=='female' else 672
                count=65 if shape=='sparse' else 150
                if shape.startswith('chest'):cx=408;cy=450;count=130 if shape=='chest_light' else 300
                if shape=='legs':count=600
                for n in range(count):
                    if shape=='legs':
                        x=rng.uniform(295,526);y=rng.uniform(845,1250)
                        if im.getpixel((int(x),int(y)))[3]<240:continue
                    elif shape.startswith('chest'):
                        x=cx+rng.normal(0,45);y=cy+rng.normal(0,24)
                        if ((x-333)**2+(y-450)**2)<200 or ((x-475)**2+(y-450)**2)<200:continue
                    else:
                        ry=14 if shape=='trimmed' else 24;rx=8 if shape=='strip' else (21 if shape=='small_triangle' else 33)
                        x=cx+rng.uniform(-rx,rx);y=cy+rng.uniform(-ry,ry)
                        if 'triangle' in shape or shape in ['trimmed','sparse','diffuse']:
                            if abs(x-cx)>rx*(1-(y-(cy-ry))/(2*ry))*(1.28 if shape=='broad_triangle' else 1):continue
                        if shape in ['oval','asymmetric'] and ((x-cx)/rx)**2+((y-cy)/ry)**2>1:continue
                        if shape=='asymmetric':x+=(y-cy)*.3
                    x=float(x);y=float(y);length=float(rng.uniform(2,5));curl=float(rng.uniform(-2,2));color='#8b6d58' if shape!='diffuse' else '#ab8d78'
                    path(marks,[('M',(x,y)),('C',(x+curl,y+length*.2,x-curl,y+length*.7,x+curl*.2,y+length))],None,color,float(rng.uniform(.55,1.05)))
                im.alpha_composite(marks);im.putalpha(base(sex).getchannel('A'))
                mask=ellipse((290,385,530,518),8) if shape.startswith('chest') else (ellipse((273,813,552,1280),8) if shape=='legs' else ellipse((cx-47,cy-38,cx+47,cy+39),6))
                add(sex+'_hair_'+str(j+1),sex,sex+'_body_hair',im,mask,shape.replace('_',' ')+' natural short brown body hair, same neutral standing pose',.22)
    elif a.family=='species':
        for species,fur in [('cat','warm taupe short fur'),('fox','warm russet and cream short fur'),('wolf','cool gray and cream short fur')]:
            for sex in ['female','male']:
                im=base(sex);m=Image.new('L',im.size);ImageDraw.Draw(m).rectangle((105,80,730,1415),fill=255);m=m.filter(ImageFilter.GaussianBlur(10))
                add(species+'_'+sex,sex,'anthro_species_by_sex',im,m,'original mature anthropomorphic '+species+' person, '+fur+', fully fur covered neutral body, upright biped, humanlike adult proportions, natural muzzle, animal ears, natural tail, relaxed hands at sides, nonsexual standing character reference',.82)
    elif a.family=='legs':
        for sex in ['female','male']:
            original=base(sex);center=448 if sex=='female' else 407
            for area,cy,ry in [('thigh',872,125),('calf',1138,120)]:
                for level,s in [('slender',.86),('full',1.14)]:
                    w=np.exp(-((yy-cy)/ry)**4);ix=center+(xx-center)/(1+(s-1)*w)
                    im=sample(original,ix,yy);mask=Image.new('L',im.size);ImageDraw.Draw(mask).rectangle((180,cy-ry-20,650,cy+ry+20),fill=255);mask=mask.filter(ImageFilter.GaussianBlur(9))
                    add(sex+'_'+area+'_'+level,sex,area+'_shape',im,mask,'natural '+level+' '+area+' proportions, same relaxed adult standing pose',.24)
    else:
        # Each whole-arm affine construction preserves the original hand shape.
        # DaSiWa is asked to resolve the shoulder joins, not invent a new body.
        from derive_body_pack_assets import split_parts
        poses=[('rest',0,0),('left_open',-22,0),('right_open',0,22),('both_open',-22,22),('left_in',15,0),('right_in',0,-15),('both_in',15,-15),('left_wide',-35,10),('right_wide',-10,27)]
        for sex in ['female','male']:
            original=base(sex);arr=np.asarray(original);fg=arr[:,:,3]>16
            parts=split_parts(original,343 if sex=='female' else 332,448 if sex=='female' else 407)
            masks=[parts['arm_left'].getchannel('A'),parts['arm_right'].getchannel('A')]
            clean_core=None
            if sex=='female':
                # Trace the actual body contour behind the touching right arm.
                # Reconstruct the small occluded hip strip before moving it.
                from scipy.interpolate import PchipInterpolator
                sy=[343,370,430,480,500,530,550,570,600,650,700,740,770,800,835,850]
                lx=[350,352,348,355,365,377,385,384,371,357,344,334,329,326,325,325]
                rx=[526,528,543,545,532,525,526,536,550,566,582,590,590,586,576,572]
                left=PchipInterpolator(sy,lx)(np.arange(343,850));right=PchipInterpolator(sy,rx)(np.arange(343,850))
                cm=np.asarray(original.getchannel('A')).copy();lm=np.zeros_like(cm);rm=np.zeros_like(cm)
                for row,l,r in zip(range(343,850),left,right):
                    cm[row,:int(l)]=0;cm[row,int(r)+1:]=0
                    lm[row,:int(l)+2]=arr[row,:int(l)+2,3]
                    rc=min(r,574) if row>=738 else r
                    rm[row,int(rc):]=arr[row,int(rc):,3]
                clean_core=original.copy();clean_core.putalpha(Image.fromarray(cm))
                ca=np.array(clean_core)
                for row in range(738,835):
                    l=int(left[row-343]);r=int(right[row-343]);edge=min(574,r)
                    ca[row,edge:r+1,:3]=arr[row,int(edge-12),:3]
                    ca[row,edge:r+1,3]=255
                    if row>=770:
                        ca[row,l:l+8,:3]=arr[row,l+16,:3];ca[row,l:l+8,3]=255
                clean_core=Image.fromarray(ca)
                for contour,start in [(left,770),(right,738)]:
                    points=[(float(contour[row-343]),float(row)) for row in range(start,850)]
                    ImageDraw.Draw(clean_core).line(points,fill='#8d796b',width=1)
                masks=[Image.fromarray(lm),Image.fromarray(rm)]
            else:
                from scipy.interpolate import PchipInterpolator
                sy=[332,350,370,430,480,500,530,600,700,780,835,850]
                left=PchipInterpolator(sy,[320,320,317,314,314,315,317,317,309,301,300,300])(np.arange(332,850))
                right=PchipInterpolator(sy,[496,496,500,504,506,504,498,496,507,519,524,524])(np.arange(332,850))
                cm=arr[:,:,3].copy();lm=np.zeros_like(cm);rm=np.zeros_like(cm)
                for row,l,r in zip(range(332,850),left,right):
                    cm[row,:int(l)]=0;cm[row,int(r)+1:]=0
                    lm[row,:int(l)]=arr[row,:int(l),3];rm[row,int(r)+1:]=arr[row,int(r)+1:,3]
                clean_core=original.copy();clean_core.putalpha(Image.fromarray(cm));masks=[Image.fromarray(lm),Image.fromarray(rm)]
                ImageDraw.Draw(clean_core).ellipse((300,341,336,390),fill='#f9dfca')
                ImageDraw.Draw(clean_core).ellipse((479,341,515,390),fill='#f9dfca')
            centers=[]
            for mask in masks:
                ys,xs=np.where(np.asarray(mask)[355:430]>128)
                centers.append((int(np.median(xs)),366))
            arm_images=[]
            if sex=='female':
                # Complete the arm portions hidden by the chest/hip with original
                # neutral cel construction, retaining the painted source hands.
                # Rotating an occluded cutout otherwise carries body contours
                # and disconnected fingers into the new pose.
                skin='#ffebd8';edge='#8d796b';shade='#d2a590'
                shapes=[
                    [('M',(321,352)),('C',(308,420,318,488,307,557)),('C',(300,630,286,686,284,749)),('L',(317,753)),('C',(325,675,350,602,353,529)),('C',(358,466,350,405,350,356)),('C',(341,350,329,349,321,352)),('Z',())],
                    [('M',(551,352)),('C',(559,420,553,485,573,557)),('C',(584,620,598,686,607,746)),('L',(588,752)),('C',(578,673,559,623,540,556)),('C',(525,496,522,431,524,356)),('C',(533,350,543,349,551,352)),('Z',())]
                ]
                hand_polys=[[(284,745),(317,747),(320,777),(328,810),(326,834),(306,838),(289,821),(278,800),(279,774)],[(590,742),(607,742),(608,773),(615,788),(607,816),(581,826),(580,804),(586,782)]]
                for side in range(2):
                    arm=Image.new('RGBA',original.size);path(arm,shapes[side],skin)
                    path(arm,shapes[side][:4],None,edge,1.25)
                    path(arm,[('M',shapes[side][3][1]),*shapes[side][4:6]],None,edge,1.25)
                    if side==0:path(arm,[('M',(330,528)),('C',(322,540,324,548,336,552)),('L',(338,541)),('Z',())],shade)
                    else:path(arm,[('M',(548,529)),('C',(552,539,555,545,560,545)),('L',(559,535)),('Z',())],shade)
                    hm=Image.new('L',original.size);ImageDraw.Draw(hm).polygon(hand_polys[side],fill=255);hm=ImageChops.multiply(hm,original.getchannel('A'))
                    hand=original.copy();hand.putalpha(hm);arm.alpha_composite(hand);arm_images.append(arm)
                centers=[(335,366),(538,366)]
            else:
                shapes=[
                    [('M',(292,350)),('C',(266,356,259,388,260,431)),('C',(260,465,256,500,256,530)),('L',(304,530)),('C',(309,485,313,435,317,388)),('C',(320,364,316,353,313,351)),('Z',())],
                    [('M',(518,350)),('C',(543,356,554,388,555,431)),('C',(556,465,560,500,564,530)),('L',(515,530)),('C',(508,485,504,435,495,388)),('C',(492,364,496,353,499,351)),('Z',())]
                ]
                for side,mask in enumerate(masks):
                    arm=Image.new('RGBA',original.size);path(arm,shapes[side],'#f9dfca');path(arm,shapes[side][:4],None,'#927661',1.3);path(arm,[('M',shapes[side][3][1]),*shapes[side][4:6]],None,'#927661',1.3)
                    if side==0:path(arm,[('M',(272,414)),('C',(279,421,289,424,299,423)),('L',(287,439)),('Z',())],'#bc947d')
                    else:path(arm,[('M',(542,414)),('C',(535,421,525,424,515,423)),('L',(527,439)),('Z',())],'#bc947d')
                    lower=original.copy();ma=mask.copy();ma.paste(0,(0,0,832,514));lower.putalpha(ma);arm.alpha_composite(lower);arm_images.append(arm)
                centers=[(318,366),(497,366)]
            for name,la,ra in poses:
                if name=='rest' and not a.rig_only:continue
                if sex=='male' and name=='left_wide':la=-25
                core=clean_core.copy() if clean_core is not None else original.copy()
                if clean_core is None:
                    alpha=core.getchannel('A');alpha=ImageChops.subtract(alpha,ImageChops.lighter(*masks));core.putalpha(alpha)
                union=Image.new('L',original.size);pose_arm_masks=[];pose_arm_images=[]
                for arm,mask,angle,center in zip(arm_images,masks,[la,ra],centers):
                    rot=arm.rotate(angle,resample=Image.Resampling.BICUBIC,center=center)
                    pose_arm_masks.append(rot.getchannel('A'))
                    pose_arm_images.append(rot)
                    core.alpha_composite(rot);union=ImageChops.lighter(union,ImageChops.lighter(mask,rot.getchannel('A')))
                mask=union.filter(ImageFilter.MaxFilter(19)).filter(ImageFilter.GaussianBlur(9));mask.paste(0,(0,0,832,330))
                dest=add(sex+'_arms_'+name,sex,'arm_pose_families',core,mask,'relaxed standing adult figure, '+name.replace('_',' ')+' arm gesture, bare shoulders and bare arms, natural relaxed hands, preserve body and legs',.30)
                for side,pm in zip(['left','right'],pose_arm_masks):pm.save(dest/('arm-'+side+'-mask.png'))
                if a.rig_only:
                    clean_core.save(dest/'core.png')
                    for side,arm in zip(['left','right'],pose_arm_images):arm.save(dest/('arm-'+side+'.png'))
    if a.family=='anatomy':c.pop('body_lora',None)
    a.config.write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (a.target/'guides.json').write_text(json.dumps({'items':records,'accepted_drawings':0},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'family':a.family,'guides':len(records),'config':str(a.config)}))

if __name__=='__main__':main()
