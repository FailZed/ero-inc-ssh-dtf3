"""Create isolated, nonsexual arm-only guides for large bend corrective art.

Only shoulders, arms and hands enter the local image model. No torso or intimate
body pixels enter these jobs. Guides are not counted as finished illustrations.
"""
from pathlib import Path
import argparse,json,math
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from scipy import ndimage
from prepare_pose_pack import config,write,ROOT,PROJECT

AUTHOR=ROOT/'rig-authoring/v2'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def rotate(v,a):
    c,s=math.cos(a),math.sin(a);return np.array([c*v[0]-s*v[1],s*v[0]+c*v[1]])
def limb(points,radii,color):
    # Analytic tapered capsules at four times native resolution.
    factor=4;im=Image.new('L',(832*factor,1472*factor));d=ImageDraw.Draw(im)
    for p,r in zip(points,radii):
        x,y=p*factor;r*=factor;d.ellipse((x-r,y-r,x+r,y+r),fill=255)
    for p,q,r,s in zip(points[:-1],points[1:],radii[:-1],radii[1:]):
        direction=q-p;direction/=np.linalg.norm(direction);n=np.array([-direction[1],direction[0]])
        d.polygon([tuple(v*factor) for v in [p+n*r,q+n*s,q-n*s,p-n*r]],fill=255)
    a=np.array(im.resize((832,1472),Image.Resampling.LANCZOS));inside=a>128;dist=ndimage.distance_transform_edt(inside)
    pixels=np.zeros((1472,832,4),np.uint8);pixels[:,:,:3]=color;pixels[:,:,3]=a
    pixels[(dist<1.35)&(a>0),:3]=np.array(color)*.59
    # Restrained guide shadow along one edge. The model resolves the elbow.
    edge=inside&(dist<5);yy,xx=np.mgrid[:1472,:832];edge&=xx>np.interp(yy,[0,points[0][1],1471],[points[0][0]]*3)
    pixels[edge&(dist>=1.35),:3]=np.array(color)*[.91,.85,.82]
    pixels[a==0,:3]=0
    return Image.fromarray(pixels)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version',required=True);p.add_argument('--ids',nargs='+',default=['female_average','male_toned']);a=p.parse_args()
    dest=ROOT/'input/characters_v2'/('gesture_arms_'+a.version)
    if dest.exists():raise ValueError('Use a new immutable guide version')
    dest.mkdir(parents=True);jobs=[];hand_index=read(AUTHOR/'hands-v4/index.json')['items']
    for ident in a.ids:
        rig=read(ROOT/'workbenches/hybrid-rig-v2/rigs'/(ident+'.json'));bones={b['name']:b for b in rig['bones']};sex=rig['sex'];color=[250,228,210] if sex=='female' else [247,222,202]
        for pose in ['present','wave','shrug','hip']:
            for side in (['right','left'] if pose=='shrug' else ['right']):
                sh=np.array(bones['arm_'+side+'_upper']['start']);old_el=np.array(bones['arm_'+side+'_lower']['start']);old_wr=np.array(bones['hand_'+side]['start']);angles=rig['poses'][pose]['angles'];upper=math.radians(angles['arm_'+side+'_upper']);lower=math.radians(angles['arm_'+side+'_lower']);el=sh+rotate(old_el-sh,upper);wr=el+rotate(old_wr-old_el,upper+lower)
                radii=[23,18,12.5] if sex=='female' else [31,23,16]
                middle=(el+wr)/2;arm=limb([sh,el,middle,wr],[radii[0],radii[1],radii[1]*1.14,radii[2]],color)
                variant=rig['poses'][pose]['hands'][side]
                # The old right palm reference was a narrow, occluded profile.
                # Use the fully visible open palm as the common guide instead.
                hand=next(h for h in hand_index if h['sex']==sex and h['side']==('left' if variant=='palm_up' else side) and h['variant']==variant)
                hi=Image.open(hand['path']).convert('RGBA')
                if variant=='palm_up' and side=='right':
                    hi=hi.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                scale=2*radii[-1]/hand['wrist_width'];direction=wr-el;angle=math.atan2(direction[1],direction[0])-math.pi/2;c,s=math.cos(angle),math.sin(angle)
                # Map native canvas pixels back into a normalized wrist sprite.
                matrix=(c/scale,s/scale,128-(c*wr[0]+s*wr[1])/scale,-s/scale,c/scale,80+(s*wr[0]-c*wr[1])/scale)
                placed=hi.convert('RGBa').transform((832,1472),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC).convert('RGBA');arm.alpha_composite(placed)
                bounds=arm.getchannel('A').getbbox();pad=35;crop=[bounds[0]-pad,bounds[1]-pad,bounds[2]+pad,bounds[3]+pad];size=[crop[2]-crop[0],crop[3]-crop[1]];scale=min(650/size[0],650/size[1]);local_size=[round(v*scale) for v in size];offset=[(768-local_size[0])//2,(768-local_size[1])//2]
                local=Image.new('RGBA',(768,768));local.alpha_composite(arm.crop(crop).convert('RGBa').resize(local_size,Image.Resampling.LANCZOS).convert('RGBA'),offset)
                path=dest/(ident+'_'+pose+'_'+side);path.mkdir();arm.save(path/'guide-full.png');local.save(path/'guide-local.png')
                # Give the image model human context, fully clothed. Only the
                # exposed arm is edited/extracted; the torso never enters a nude
                # generation job. The production body remains separate.
                foundation=Image.open(AUTHOR/'completions/body-pilot-v3c'/(ident+'_body')/'full.png').convert('RGBA');cloth=np.array(foundation);cloth[315:625,:,:3]=[40,58,80];cloth[625:,:,:3]=[72,82,101];foundation=Image.fromarray(cloth)
                d=ImageDraw.Draw(foundation);left=np.array(bones['arm_right_upper']['start']);right=np.array(bones['arm_left_upper']['start']);neck=(left+right)/2
                d.polygon([(neck[0]-35,315),(neck[0]+35,315),tuple(right+[0,-16]),(right[0]+2,650),(left[0]-2,650),tuple(left+[0,-16])],fill='#283a50')
                context=Image.new('RGBA',(832,1472),'#eeeeec');context.alpha_composite(arm);context.alpha_composite(foundation)
                context.convert('RGB').save(path/'reference.png');mask=arm.getchannel('A').filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(4));mask.save(path/'mask.png');crop=[0,0,832,1472];local_size=[832,1472];offset=[0,0]
                rel=path.relative_to(ROOT/'input').as_posix();gesture={'present':'offering an open palm, palm facing up, relaxed separate fingers','shrug':'palm facing up in a natural questioning gesture, relaxed fingers','wave':'open hand raised for greeting, five natural fingers','hip':'relaxed hand at the end of a bent arm, natural wrist and fingers'}[pose]
                jobs.append({'id':ident+'_'+pose+'_'+side,'rig':ident,'category':'isolated_gesture_arm','image':rel+'/reference.png','mask':rel+'/mask.png','seed':2026102500+len(jobs),'denoise':.62,'preserve_input_latent':True,'prompt':'eincanime, original mature adult '+('woman age 30' if sex=='female' else 'man age 35')+', standing front view, fully clothed in sleeveless dark navy high neck shirt and gray trousers, brown hair, blue eyes, natural bent arm, '+gesture+', natural adult anatomy, continuous soft elbow, proportionate hand with five fingers, delicate thin warm brown outlines, matte warm skin, limited peach cel shadows, flat diffuse light, plain pale gray background','negative':'nude, naked, breasts, nipples, genitals, sexual, erotic, child, teen, long sleeves, glove, extra arm, duplicate hand, six fingers, short stump, thin stick arm, huge hand, thick ink, plastic, 3d, text, symbols, watermark, injury, gore','authoring':{'crop':crop,'local_offset':offset,'local_size':local_size,'guide_rgba':str(path/'guide-full.png'),'shoulder':sh.tolist(),'elbow':el.tolist(),'wrist':wr.tolist(),'pose':pose,'side':side,'canvas':[832,1472],'nonsexual_arm_only':True,'context_fully_clothed':True,'approved':False}})
    cfg=config('gesture_arms_'+a.version,jobs);cfg.pop('controlnet',None);cfg.update(width=832,height=1472,encode_individually=True,preserve_input_latent=True,scope='Nonsexual exposed arm edits on a fully clothed adult context. Only arm components are extracted.')
    output=PROJECT/'docs/art/characters-v2'/('gesture-arms-'+a.version+'.json');write(output,cfg);print(output)
if __name__=='__main__':main()
