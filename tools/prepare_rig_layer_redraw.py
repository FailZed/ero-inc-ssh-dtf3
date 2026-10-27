"""Prepare small masked completions of owned body flanks and complete arm layers.

The guides are explicitly unfinished authoring data. Bodies retain all original
central anatomy. No intimate area is inpainted. Shoulder/side contours and hidden
arm surfaces are authored separately from the neutral hand sprites.
"""
from pathlib import Path
import argparse,copy,json,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from scipy import ndimage
from scipy.interpolate import PchipInterpolator
from scipy.spatial import ConvexHull
from prepare_pose_pack import config,write,ROOT,PROJECT

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def palette(a):
    rgb=a[:,:,:3];good=(a[:,:,3]>240)&(rgb[:,:,0]>205)&(rgb[:,:,1]>170)&(rgb[:,:,2]>135)
    colors,n=np.unique(rgb[good],axis=0,return_counts=True);return colors[n.argmax()] if len(n) else np.array([250,228,210])
def hull_mask(mask):
    yy,xx=np.where(mask)
    out=Image.new('L',(mask.shape[1],mask.shape[0]))
    if len(xx)>2:
        pts=np.c_[xx,yy];h=ConvexHull(pts);ImageDraw.Draw(out).polygon([tuple(p) for p in pts[h.vertices]],fill=255)
    return np.array(out)>0
def paint_new_surface(source,visible,target,base):
    a=np.array(source);alpha=a[:,:,3];out=a.copy();visible=visible&(alpha>240)
    old_edge=(alpha>0)&~ndimage.binary_erosion(alpha>0,iterations=2)
    visible&=~(old_edge&ndimage.binary_erosion(target,iterations=3));new=target&~visible
    out[new,:3]=base;out[:,:,3]=target.astype('uint8')*255
    # A thin warm contour is an authoring guide for the missing surface, not a
    # claim that a generated new edge was preserved from the original drawing.
    edge=target&~ndimage.binary_erosion(target);newedge=edge&ndimage.binary_dilation(new,iterations=2)
    out[newedge,:3]=np.rint(base*.58).astype('uint8');out[~target,:3]=0
    return Image.fromarray(out),new

F_Y=[320,335,360,400,430,455,480,505,540,580,620,660,700,740,790,850,900]
F_L=[395,350,347,348,345,350,359,375,385,372,354,345,334,328,325,322,316]
F_R=[493,536,540,538,544,548,540,520,520,541,560,578,592,593,585,574,562]
M_Y=[320,345,375,410,450,475,510,550,590,630,670,710,760,820,870,900]
M_L=[370,304,299,296,304,312,316,320,322,316,310,304,300,301,306,311]
M_R=[442,505,514,514,507,501,504,507,509,507,514,520,526,526,522,520]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version',required=True);p.add_argument('--ids',nargs='+',default=['female_average','male_toned']);a=p.parse_args()
    author=ROOT/'rig-authoring/v2';dest_root=ROOT/'input/characters_v2'/('rig_layers_'+a.version)
    if dest_root.exists():raise ValueError('Use a new version; preserve previous masks and renders')
    dest_root.mkdir(parents=True);body_jobs=[];arm_jobs=[];records=[]
    for ident in a.ids:
        folder=author/ident;anchors=read(folder/'anchors.json');sex=anchors['sex'];src=Image.open(folder/'source.png').convert('RGBA');arr=np.array(src);base=palette(arr);pts=np.array(anchors['all_keypoints']);scores=np.array(anchors['all_scores']);h,w=arr.shape[:2];yy,xx=np.mgrid[:h,:w]
        if sha(Path(anchors['source']))!=anchors['source_sha256']:raise ValueError('Changed reviewed source')
        # Author core contours against the two actual native reference drawings.
        ys,ls,rs=copy.deepcopy((F_Y,F_L,F_R) if sex=='female' else (M_Y,M_L,M_R))
        keep=[i for i,y in enumerate(ys) if y<850];ys=[ys[i] for i in keep];ls=[ls[i] for i in keep];rs=[rs[i] for i in keep]
        for y in [850,900]:
            native=np.flatnonzero(arr[y,:,3]>16);ys.append(y);ls.append(float(native.min()));rs.append(float(native.max()))
        left=PchipInterpolator(ys,ls)(np.arange(320,901));right=PchipInterpolator(ys,rs)(np.arange(320,901));target=arr[:,:,3]>0;target[320:901]=False
        for k,y in enumerate(range(320,901)):target[y,max(0,round(left[k])):min(w,round(right[k])+1)]=True
        # Existing gaps between legs and lower-body silhouette remain untouched.
        target[850:901]=arr[850:901,:,3]>0
        center=(pts[11,0]+pts[12,0])/2
        protect_center=(abs(xx-center)<85)&(yy>625)
        target[protect_center]=arr[:,:,3][protect_center]>0
        guide,new=paint_new_surface(src,arr[:,:,3]>0,target,base)
        # Only side bands and newly exposed areas are painted. The adult body's
        # central chest, face and intimate anatomy are excluded geometrically.
        boundary=target&~ndimage.binary_erosion(target,iterations=1)
        band=ndimage.binary_dilation(boundary,iterations=15)&(yy>=325)&(yy<850)
        band&=~protect_center
        mask=Image.fromarray(band.astype('uint8')*255).filter(ImageFilter.GaussianBlur(3));mask.paste(0,(0,0,w,325));mask.paste(0,(0,850,w,h))
        body_dest=dest_root/(ident+'_body');body_dest.mkdir();guide.save(body_dest/'guide-full.png');Image.fromarray(target.astype('uint8')*255).save(body_dest/'target-alpha.png');mask.save(body_dest/'edit-full.png')
        bg=Image.new('RGBA',src.size,'#eeeeec');bg.alpha_composite(guide);bg.convert('RGB').crop((0,0,832,1024)).save(body_dest/'reference.png');mask.crop((0,0,832,1024)).save(body_dest/'mask.png')
        rel=body_dest.relative_to(ROOT/'input').as_posix();body_id=ident+'_body'
        body_jobs.append({'id':body_id,'rig':ident,'category':'rig_hidden_body','image':rel+'/reference.png','mask':rel+'/mask.png','seed':2026102100+len(body_jobs),'denoise':.4,'preserve_input_latent':True,
                         'prompt':'eincanime, '+('mature adult woman age 30, short brown bob' if sex=='female' else 'mature adult man age 35, short brown hair')+', neutral artistic figure study, standing front view, arms held behind back and completely hidden, unobstructed bare chest waist and hips, same original body proportions, delicate thin brown outlines, matte warm skin, controlled peach cel shadows, plain pale gray background',
                         'negative':'child, teen, clothes, bra, shirt, underwear, sleeves, jacket, glove, extra arms, hands at hips, hands in front, toy, sticker, symbols, text, glossy skin, plastic, 3d, photorealistic, injury, gore, erotic pose',
                         'authoring':{'source':anchors['source'],'source_sha256':anchors['source_sha256'],'guide_rgba':str(body_dest/'guide-full.png'),'target_alpha':str(body_dest/'target-alpha.png'),'edit_mask':str(body_dest/'edit-full.png'),'canvas':[832,1472],'crop':[0,0,832,1024],'protected_center':{'x':center,'half_width':85,'from_y':625},'not_yet_approved':True}})
        for side,sh,el,wr,start in [('left',5,7,9,91),('right',6,8,10,112)]:
            # Refine the body detector's wrist using the dedicated hand detector.
            wrist=pts[start].copy() if scores[start]>.3 else pts[wr].copy();elbow=pts[el];shoulder=pts[sh];d=wrist-elbow;d/=max(np.linalg.norm(d),1)
            sam=np.array(Image.open(folder/('arm-'+side+'-mask.png')))>0
            components,count=ndimage.label(sam);sizes=np.bincount(components.ravel());sizes[0]=0
            sam=ndimage.binary_fill_holes(components==sizes.argmax())
            projection=(xx-wrist[0])*d[0]+(yy-wrist[1])*d[1]
            shaft_only=sam&(projection<8)
            upper=hull_mask(shaft_only&(yy<elbow[1]+28));lower=hull_mask(shaft_only&(yy>elbow[1]-28));complete=upper|lower
            radius=27 if sex=='female' else 37
            cap=Image.new('L',src.size);cd=ImageDraw.Draw(cap);cd.ellipse((shoulder[0]-radius,shoulder[1]-radius,shoulder[0]+radius,shoulder[1]+radius),fill=255)
            axis=elbow-shoulder;axis/=max(np.linalg.norm(axis),1);normal=np.array([-axis[1],axis[0]]);r0=21 if sex=='female' else 30;r1=20 if sex=='female' else 25
            shaft=[shoulder+normal*r0,elbow+normal*r1,elbow-normal*r1,shoulder-normal*r0];cd.polygon([tuple(v) for v in shaft],fill=255);cd.ellipse((elbow[0]-r1,elbow[1]-r1,elbow[0]+r1,elbow[1]+r1),fill=255);complete|=np.array(cap)>0
            complete&=projection<18
            # Preserve actual shoulder/biceps pixels even where SAM omitted
            # shadows. Only surfaces hidden by the body need newly painted skin.
            visible=(arr[:,:,3]>0)&complete&(~target|(yy<shoulder[1]+40))
            arm,new=paint_new_surface(src,visible,complete,base)
            edge=complete&~ndimage.binary_erosion(complete);edit=ndimage.binary_dilation(new,iterations=7)|ndimage.binary_dilation(edge,iterations=3)
            # Native guide is enlarged uniformly for a small local completion.
            top=max(0,int(shoulder[1])-70);bottom=min(h,int(wrist[1])+55);x0=int(min(shoulder[0],elbow[0],wrist[0]))-95;x1=int(max(shoulder[0],elbow[0],wrist[0]))+95;crop=(x0,top,x1,bottom);scale=min(700/(bottom-top),400/(x1-x0));nw=round((x1-x0)*scale);nh=round((bottom-top)*scale);offset=((512-nw)//2,(1024-nh)//2)
            local=Image.new('RGBA',(512,1024));patch=arm.crop(crop).convert('RGBa').resize((nw,nh),Image.Resampling.LANCZOS).convert('RGBA');local.alpha_composite(patch,offset)
            bg=Image.new('RGBA',local.size,'#eeeeec');bg.alpha_composite(local);lm=Image.new('L',local.size);lm.paste(Image.fromarray(edit.astype('uint8')*255).crop(crop).resize((nw,nh),Image.Resampling.BILINEAR),offset);lm=lm.filter(ImageFilter.GaussianBlur(2))
            arm_dest=dest_root/(ident+'_arm_'+side);arm_dest.mkdir();arm.save(arm_dest/'guide-full.png');Image.fromarray(complete.astype('uint8')*255).save(arm_dest/'target-alpha.png');Image.fromarray(edit.astype('uint8')*255).save(arm_dest/'edit-full.png');bg.convert('RGB').save(arm_dest/'reference.png');lm.save(arm_dest/'mask.png');local.save(arm_dest/'guide-local.png')
            rel=arm_dest.relative_to(ROOT/'input').as_posix();arm_jobs.append({'id':ident+'_arm_'+side,'rig':ident,'category':'rig_complete_arm','image':rel+'/reference.png','mask':rel+'/mask.png','seed':2026102200+len(arm_jobs),'denoise':.35,'preserve_input_latent':True,
                'prompt':'eincanime, single complete adult '+('woman' if sex=='female' else 'man')+' upper arm and forearm, original anime character sprite component, relaxed natural straight arm, continuous shoulder elbow and wrist, delicate thin brown lineart, matte warm skin, restrained peach cel shadows, empty pale gray background',
                'negative':'child, clothing, glove, sleeve, shirt, wristband, jewelry, tattoo, torso, face, body, second arm, extra hand, text, watermark, plastic, 3d, photorealistic, gore, injury, glossy skin',
                'authoring':{'source':anchors['source'],'source_sha256':anchors['source_sha256'],'guide_rgba':str(arm_dest/'guide-full.png'),'target_alpha':str(arm_dest/'target-alpha.png'),'edit_mask':str(arm_dest/'edit-full.png'),'canvas':[832,1472],'crop':list(crop),'local_canvas':[512,1024],'local_size':[nw,nh],'local_offset':list(offset),'scale':scale,'shoulder':shoulder.tolist(),'elbow':elbow.tolist(),'wrist':wrist.tolist(),'hand_landmark_start':start,'side':side,'not_yet_approved':True}})
        records.append({'id':ident,'sex':sex,'body_job':body_id,'source':anchors['source'],'source_sha256':anchors['source_sha256']})
    for kind,jobs in [('body',body_jobs),('arms',arm_jobs)]:
        c=config('rig_layers_'+a.version+'/'+kind,jobs);c.pop('controlnet',None);c.update(encode_individually=True,preserve_input_latent=True,scope='Small owned-art rig-layer completions. No intimate region is painted. Candidates require full-figure pose review.')
        path=PROJECT/'docs/art/characters-v2'/('rig-layers-'+a.version+'-'+kind+'.json');write(path,c);print(path)
    write(dest_root/'authoring.json',{'version':a.version,'items':records,'status':'guides_only_not_completed_assets'})

if __name__=='__main__':main()
