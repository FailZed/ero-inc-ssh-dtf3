"""Normalize reviewed own-art hands into wrist slots; no new anatomy generation.

Original hand drawings, mirrored derivatives and palette/size variants are
counted separately. Each crop still requires native hand and assembled rig QA.
"""
from pathlib import Path
import argparse,json,hashlib,math
import numpy as np
from PIL import Image,ImageDraw
from scipy import ndimage
from scipy.spatial import ConvexHull

ROOT=Path('E:/Ai/ComfyUI-EroInc');AUTHOR=ROOT/'rig-authoring/v2';SELECTED=ROOT/'output/characters_v2/pose_selected_v3/processed'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def base_color(im):
    a=np.array(im);rgb=a[:,:,:3];m=(a[:,:,3]>240)&(rgb[:,:,0]>205)&(rgb[:,:,1]>170)&(rgb[:,:,2]>135);u,n=np.unique(rgb[m],axis=0,return_counts=True);return u[n.argmax()]
def source(kind,side):
    if kind in ['relaxed','fist']:
        ident='female_average' if kind=='relaxed' else 'male_toned';p=AUTHOR/ident;j=read(p/'anchors.json');path=p/'source.png';alpha=p/('arm-'+side+'-mask.png')
    else:
        ident=('female_arms_palm_right' if side=='left' else 'female_arms_palm_left') if kind=='palm_up' else 'female_arms_wave_left'
        p=SELECTED/ident;j=read(p/'record.json');path=Path(j['source']);alpha=None
        # Earlier pose cutouts had material-filter holes in fingers. Recover
        # hands from the original RGB render, never from those damaged alphas.
        q=np.array(j['all_keypoints'],float);scale=j.get('uniform_scale',1.0);width=j['source_canvas'][0];nx=(width-round(width*scale))//2 if scale<1 else 0
        q[:,0]=(q[:,0]-j.get('padding_x',0)-nx)/scale;q[:,1]=(q[:,1]-j.get('translation_y',0))/scale;j={**j,'all_keypoints':q.tolist()}
    return ident,j,path,alpha

def hand_crop(kind,side):
    preferred={'open_front':'right','relaxed':'right','palm_up':'left'}
    source_side=preferred.get(kind,side);ident,j,path,alpha=source(kind,source_side);mirror=source_side!=side;start=91 if source_side=='left' else 112;el=7 if source_side=='left' else 8
    im=Image.open(path).convert('RGBA');pts=np.array(j['all_keypoints']);score=np.array(j['all_scores']);wr=pts[start];direction=wr-pts[el];direction/=max(np.linalg.norm(direction),1);normal=np.array([-direction[1],direction[0]])
    hand=pts[start:start+21][score[start:start+21]>.3];mask=Image.new('L',im.size);d=ImageDraw.Draw(mask);lo=hand.min(0)-30;hi=hand.max(0)+30;d.rectangle((*lo,*hi),fill=255);a=np.array(mask)>0
    yy,xx=np.mgrid[:im.height,:im.width];along=(xx-wr[0])*direction[0]+(yy-wr[1])*direction[1];across=(xx-wr[0])*normal[0]+(yy-wr[1])*normal[1];a|=(along>-26)&(along<8)&(abs(across)<30)
    pixels=np.array(im);pixels[:,:,3]*=a
    if kind not in ['relaxed','fist']:
        rgb=pixels[:,:,:3].astype(float);background=np.median(np.array(im).reshape(-1,4)[:,:3],axis=0);distance=np.max(abs(rgb-background),axis=2);matte=np.clip((distance-8)/18,0,1)*a
        # Keep dark contour ink and all finger surfaces; no skin-only deletion.
        support=ndimage.binary_fill_holes(distance>22)&a;matte=np.maximum(matte,support.astype(float));components,count=ndimage.label(matte>.25);sizes=np.bincount(components.ravel());sizes[0]=0;keep=ndimage.binary_dilation(components==sizes.argmax(),iterations=1);matte*=keep
        partial=(matte>0)&(matte<1);rgb[partial]=(rgb[partial]-(1-matte[partial,None])*background)/matte[partial,None];pixels[:,:,:3]=np.clip(np.rint(rgb),0,255).astype('uint8');pixels[:,:,3]=np.rint(matte*255).astype('uint8')
    if alpha is not None:pixels[:,:,3]=np.minimum(pixels[:,:,3],np.array(Image.open(alpha).convert('L')))
    im=Image.fromarray(pixels);source_color=base_color(im);angle=math.atan2(direction[1],direction[0])-math.pi/2;c=math.cos(angle);s=math.sin(angle);sign=-1 if mirror else 1
    matrix=(c*sign,-s,wr[0]-c*sign*128+s*80,s*sign,c,wr[1]-s*sign*128-c*80)
    local=im.convert('RGBa').transform((256,256),Image.Transform.AFFINE,matrix,Image.Resampling.BICUBIC).convert('RGBA');a=np.array(local);a[:55,:,3]=0;a[a[:,:,3]==0,:3]=0
    return Image.fromarray(a),{'source_id':ident,'source':str(path),'source_sha256':sha(path),'source_side':source_side,'mirrored':mirror,'wrist_source':wr.tolist(),'source_axis_angle':angle,'original_crop':True,'not_new_ai_drawing':True,'base_rgb':source_color.tolist()}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--target',type=Path,default=AUTHOR/'hands-v1');a=p.parse_args()
    if a.target.exists():raise ValueError('Keep prior hand candidates; choose another target')
    a.target.mkdir(parents=True);records=[];sheet=Image.new('RGB',(256*4,290*4),'#101b29');d=ImageDraw.Draw(sheet)
    for sex in ['female','male']:
        target_color=base_color(Image.open(AUTHOR/('female_average' if sex=='female' else 'male_toned')/'source.png').convert('RGBA'))
        for side in ['left','right']:
            for kind in ['relaxed','palm_up','open_front','fist']:
                hand,meta=hand_crop(kind,side);aa=np.array(hand);rgb=aa[:,:,:3].astype(float);factor=target_color/np.array(meta['base_rgb']);aa[:,:,:3]=np.clip(np.rint(rgb*factor),0,255).astype('uint8');aa[aa[:,:,3]==0,:3]=0;out=Image.fromarray(aa)
                ident=sex+'_'+side+'_'+kind;path=a.target/(ident+'.png');out.save(path);i=len(records);bg=Image.new('RGBA',(256,256),'#101b29');bg.alpha_composite(out);sheet.paste(bg.convert('RGB'),((i%4)*256,(i//4)*290+30));d.text(((i%4)*256+8,(i//4)*290+8),ident,fill='white')
                rows=np.array(out.getchannel('A'))[65:76];widths=[np.count_nonzero(row>128) for row in rows];wrist_width=float(np.median([v for v in widths if v>0]))
                records.append({'id':ident,'sex':sex,'side':side,'variant':kind,'path':str(path),'sha256':sha(path),'wrist_pivot':[128,80],'wrist_width':wrist_width,'forearm_axis':'+Y','palette_target':target_color.tolist(),'source':meta,'status':'candidate_requires_native_hand_and_wrist_review'})
    sheet.save(a.target/'review.png');(a.target/'index.json').write_text(json.dumps({'schema':1,'items':records,'output_count':16,'unique_original_hand_drawings':5,'note':'One fully visible relaxed hand, two fists, one complete palm up, one frontal open hand. The occluded relaxed hand and narrow palm profile were rejected. Other outputs are mirrored and/or recolored derivatives, not independent new drawings.'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('Prepared 16 hand-slot candidates from five original own-art hand drawings.')
if __name__=='__main__':main()
