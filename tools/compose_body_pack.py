"""Compose registered body-pack modules off-line, without changing the game."""
from pathlib import Path
import argparse,json,hashlib
import numpy as np
from PIL import Image,ImageChops,ImageDraw,ImageFilter,PngImagePlugin
from prepare_reference_body_guides import make_guide
from derive_body_pack_assets import frame,palette,PALETTES

def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def blend(dst,src,mask,keep_alpha=False):
    d=np.asarray(dst,dtype=float)/255;s=np.asarray(src,dtype=float)/255;w=np.asarray(mask,dtype=float)[:,:,None]/255
    if keep_alpha:
        out=d.copy();out[:,:,:3]=s[:,:,:3]*w+d[:,:,:3]*(1-w)
    else:
        alpha=s[:,:,3:]*w+d[:,:,3:]*(1-w)
        color=(s[:,:,:3]*s[:,:,3:]*w+d[:,:,:3]*d[:,:,3:]*(1-w))/np.maximum(alpha,1/255)
        out=np.concatenate([color,alpha],axis=2)
    return Image.fromarray(np.clip(np.rint(out*255),0,255).astype('uint8'))

def nipple_centers(im):
    rgb=np.asarray(im.convert('RGB'),dtype=float);centers=[]
    for x0,x1,nominal in [(340,432,389),(479,563,525)]:
        y0,y1=415,486;v=rgb[y0:y1,x0:x1];yy,xx=np.mgrid[y0:y1,x0:x1]
        score=np.clip(v[:,:,0]-v[:,:,1]-38,0,70)*np.exp(-((xx-nominal)/25)**2-((yy-451)/23)**2)*(v[:,:,0]>205)
        total=score.sum();centers.append((float((xx*score).sum()/total),float((yy*score).sum()/total)) if total>5 else (nominal,451))
    return centers

def shoulder_joints(sex):
    image=Image.new('RGBA',(1664,2944));d=ImageDraw.Draw(image)
    if sex=='female':
        for box in [(327,339,363,388),(510,339,550,388)]:d.ellipse(tuple(v*2 for v in box),fill='#ffebd8')
    return image.resize((832,1472),Image.Resampling.LANCZOS)

def register_neck(image,sex):
    if sex!='female':return image
    from scipy.interpolate import PchipInterpolator
    arr=np.array(image);ys=np.arange(325,343);left=PchipInterpolator([325,332,339,343],[415,360,335,333])(ys);right=PchipInterpolator([325,332,339,343],[490,525,540,542])(ys)
    for y,l,r in zip(ys,left,right):arr[y,:int(l),3]=0;arr[y,int(r)+1:,3]=0
    arr[arr[:,:,3]==0,:3]=0;return Image.fromarray(arr)

def fit_arm(arm,sex,side,width_scale,shoulder_scale):
    pivot=335 if sex=='female' and side=='left' else (538 if sex=='female' else (318 if side=='left' else 497))
    anchor=350 if sex=='female' and side=='left' else (526 if sex=='female' else (318 if side=='left' else 497));center=448 if sex=='female' else 407;delta=(anchor-center)*(shoulder_scale-1)
    box=arm.getchannel('A').point(lambda v:255 if v>=16 else 0).getbbox();s=width_scale
    if box:
        if box[0]<pivot:s=min(s,(pivot+delta-18)/(pivot-box[0]))
        if box[2]>pivot:s=min(s,(814-pivot-delta)/(box[2]-pivot))
    return arm.transform(arm.size,Image.Transform.AFFINE,(1/s,0,pivot-(pivot+delta)/s,0,1,0),Image.Resampling.BICUBIC)

def compose(root,manifest,body,features=(),pose=None,palette_name=None,frame_name='normal'):
    byid={i['id']:i for i in manifest['items']};base=byid[body];sex=base['sex'];rig=manifest['registered_rig'][sex];image=Image.open(root/rig['core']['path']).convert('RGBA')
    profile=manifest['build_width_profiles'][body];widths=profile['widths'];center=profile['center']
    def warp(im):return make_guide(im,widths,center)
    state=pose or 'rest';pose_layers=rig['poses'][state];leg_effects=[]
    if sex=='female' and frame_name!='normal':raise ValueError('Male proportion frames only; female builds have their own profiles')
    selected=[byid[i] for i in features]
    pregnant=any(i['category']=='pregnancy_stages' for i in selected)
    if sex=='female' and not pregnant and not any(i['category']=='breast_shape' for i in selected):selected.append(byid[manifest.get('body_defaults',{}).get(body,{}).get('chest','chest_l_round')])
    if sex=='male' and not any(i['category']=='male_external_anatomy' for i in selected):selected.append(byid['male_external_2_uncovered'])
    if sex=='female' and not any(i['category']=='female_external_anatomy' for i in selected):selected.append(byid['female_external_1'])
    if sex=='male' and body in ['male_slim','male_soft','male_average','male_solid'] and not any(i['category']=='muscle_definition' for i in selected):selected.append(byid['male_tone_0'])
    if len({i['category'] for i in selected})!=len(selected):raise ValueError('Select one variant per category')
    if any(i['sex']!=sex for i in selected):raise ValueError('Module sex does not match body')
    if pregnant and (pose or any(i['category'] in ['muscle_definition','breast_shape','thigh_shape','calf_shape'] for i in selected)):raise ValueError('Pregnancy is a complete volume/pose family. It accepts interior pigmentation, anatomy and hair modules; separate ordinary torso/leg/arm shapes do not replace it.')
    order={'pregnancy_stages':0,'thigh_shape':1,'calf_shape':2,'muscle_definition':3,'breast_shape':4,'nipple_areola_forms':5,'female_external_anatomy':6,'male_external_anatomy':6,'female_body_hair':7,'male_body_hair':7}
    for item in sorted(selected,key=lambda i:order.get(i['category'],100)):
        source=Image.open(root/item['files']['full']['path']).convert('RGBA');mask=Image.open(root/item['files']['mask']['path']).convert('L')
        category=item['category']
        if category=='pregnancy_stages':image=source.copy();continue
        if category in ['thigh_shape','calf_shape']:leg_effects.append(item['id']);continue
        if category=='breast_shape':
            torso=Image.open(root/item['files']['torso']['path']).convert('RGBA');image.paste(torso.crop((0,343,832,576)),(0,343));continue
        if category=='nipple_areola_forms':
            targets=nipple_centers(image);origins=nipple_centers(source)
            for side,((tx,ty),(sx,sy)) in enumerate(zip(targets,origins)):
                part=mask.copy();part.paste(0,(448 if side==0 else 0,0,832 if side==0 else 448,1472))
                pigment=Image.new('L',part.size);ImageDraw.Draw(pigment).ellipse((sx-22,sy-22,sx+22,sy+22),fill=255);pigment=pigment.filter(ImageFilter.GaussianBlur(1.4));part=ImageChops.multiply(part,pigment)
                delta=(1,0,sx-tx,0,1,sy-ty)
                shifted=source.transform(source.size,Image.Transform.AFFINE,delta,Image.Resampling.BICUBIC);part=part.transform(part.size,Image.Transform.AFFINE,delta,Image.Resampling.BICUBIC)
                image=blend(image,shifted,part,True)
            continue
        if category in ['female_body_hair','male_body_hair']:
            ref=Image.open(root/manifest['canonical_references'][sex]['path']).convert('RGB');s=np.asarray(source.convert('RGB'),float);b=np.asarray(ref,float)
            # Transfer the actual hair drawing, not the surrounding canonical skin
            # or anatomy. The source image and complete mask remain in the pack.
            darkness=b.mean(2)-s.mean(2);support=(darkness>10)&(np.asarray(mask)>0)
            from scipy.ndimage import gaussian_filter,maximum_filter
            opacity=np.clip(gaussian_filter(maximum_filter(support.astype(float),size=3),.6),0,1)
            mask=Image.fromarray(np.rint(np.asarray(mask)*opacity).astype('uint8'))
        source_w=source;mask_w=mask
        keep=item['operation']=='registered_rgb_replacement' and category not in ['breast_shape','female_external_anatomy','male_external_anatomy']
        if keep:mask_w=ImageChops.multiply(mask_w,source_w.getchannel('A'))
        image=blend(image,source_w,mask_w,keep)
    if leg_effects:
        from scipy.ndimage import map_coordinates
        yy,xx=np.mgrid[:1472,:832].astype(float)
        for ident in leg_effects:
            cy,ry=(872,125) if '_thigh_' in ident else (1138,120);s=.86 if ident.endswith('_slender') else 1.14
            weight=np.exp(-((yy-cy)/ry)**4)*np.clip((yy-790)/45,0,1);ix=center+(xx-center)/(1+(s-1)*weight)
            arr=np.asarray(image,dtype=float)/255;arr[:,:,:3]*=arr[:,:,3:];out=np.stack([map_coordinates(arr[:,:,k],[yy,ix],order=1,mode='constant',cval=0) for k in range(4)],2);out=np.clip(out,0,1);out[:,:,:3]/=np.maximum(out[:,:,3:],1/255);image=Image.fromarray(np.rint(out*255).astype('uint8'))
    if not pregnant:
        image=register_neck(image,sex);joined=shoulder_joints(sex);joined.alpha_composite(image);image=warp(joined)
        scale=profile.get('arm_width_scale',1);fitted={side:fit_arm(Image.open(root/pose_layers[side]['path']).convert('RGBA'),sex,side,scale,widths[2]) for side in ['left','right']}
        assembled=Image.new('RGBA',image.size)
        for side in ['left','right']:
            if side not in pose_layers['front']:assembled.alpha_composite(fitted[side])
        assembled.alpha_composite(image)
        for side in pose_layers['front']:assembled.alpha_composite(fitted[side])
        image=assembled
        from scipy.ndimage import distance_transform_edt
        pix=np.array(image);inside=distance_transform_edt(pix[:,:,3]>220)>4;roi=Image.new('L',image.size);rd=ImageDraw.Draw(roi)
        for side,pivot in [('left',335 if sex=='female' else 318),('right',538 if sex=='female' else 497)]:
            anchor=350 if sex=='female' and side=='left' else (526 if sex=='female' else pivot);dx=(anchor-center)*(widths[2]-1);rd.ellipse((pivot+dx-25,343,pivot+dx+25,391),fill=255)
        weight=np.asarray(roi.filter(ImageFilter.GaussianBlur(3)),float)/255*inside
        eligible=(pix[:,:,3]>250)&(pix[:,:,0]>225)&(pix[:,:,1]>190)&(pix[:,:,2]>150);values,counts=np.unique(pix[:,:,:3][eligible],axis=0,return_counts=True)
        if len(values):pix[:,:,:3]=np.rint(pix[:,:,:3]*(1-weight[:,:,None])+values[counts.argmax()]*weight[:,:,None]).astype('uint8');image=Image.fromarray(pix)
        if sex=='female':
            from scipy.ndimage import minimum_filter
            pix=np.array(image);aa=pix[:,:,3].astype(float);edge=(aa-minimum_filter(aa,size=3))/255;roi=np.zeros(aa.shape);roi[330:410,300:580]=1;weight=(edge*roi*.7)[:,:,None];pix[:,:,:3]=np.rint(pix[:,:,:3]*(1-weight)+np.array([149,121,104])*weight).astype('uint8');image=Image.fromarray(pix)
    # Every component is registered once in the canonical canvas. Applying one
    # shared deformation avoids contour doubling from independently warped edits.
    if pregnant:image=warp(image)
    if palette_name:image=palette(image,PALETTES[palette_name],sex)
    neck=base['neck_y']
    if frame_name!='normal':image,neck=frame(image,frame_name,neck)
    pix=np.array(image);pix[pix[:,:,3]==0,:3]=0;image=Image.fromarray(pix)
    return image,{'body':body,'features':[i['id'] for i in selected],'pose':pose or 'rest','palette':palette_name or 'source','frame':frame_name,'neck_y':neck,'baseline_y':1395,'not_runtime_registered':True}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--pack',type=Path,required=True);p.add_argument('--body',required=True);p.add_argument('--feature',action='append',default=[]);p.add_argument('--pose');p.add_argument('--palette',choices=list(PALETTES));p.add_argument('--frame',default='normal',choices=['normal','compact','tall','long_leg']);p.add_argument('--target',type=Path,required=True);a=p.parse_args();manifest=load(a.pack/'manifest.json')
    image,recipe=compose(a.pack,manifest,a.body,a.feature,a.pose,a.palette,a.frame);meta=PngImagePlugin.PngInfo();meta.add_text('ero_inc_body_recipe',json.dumps(recipe));a.target.parent.mkdir(parents=True,exist_ok=True);image.save(a.target,pnginfo=meta);a.target.with_suffix('.json').write_text(json.dumps(recipe,indent=2)+'\n');print(str(a.target))
if __name__=='__main__':main()
