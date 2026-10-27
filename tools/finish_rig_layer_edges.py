"""Finish authoring mattes and wrist taper without painting new anatomy.

The authored silhouette is authoritative. Partial background pixels cannot turn
into opaque halos. Protected central body art is copied from the owned source.
"""
from pathlib import Path
import argparse,json,hashlib
import numpy as np
from scipy import ndimage
from PIL import Image

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,j):p.write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();records=[]
    for item in read(a.index)['items']:
        out=a.target/item['id'];out.mkdir(parents=True,exist_ok=True);pixels=np.array(Image.open(item['full']).convert('RGBA'));meta=item['authoring'];shape=np.array(Image.open(meta['target_alpha']))>128;yy,xx=np.mgrid[:pixels.shape[0],:pixels.shape[1]];dist=ndimage.distance_transform_edt(shape);outside=ndimage.distance_transform_edt(~shape)
        alpha=np.clip((dist-outside+1)/2,0,1)
        valid=shape&(pixels[:,:,3]>230)&(dist>3)
        # Nearest solid foreground provides RGB padding beneath AA pixels.
        _,near=ndimage.distance_transform_edt(~valid,return_indices=True)
        edge=dist<3;pixels[edge,:3]=pixels[near[0][edge],near[1][edge],:3]
        base=np.array([250,228,210]) if item['rig'].startswith('female') else np.array([247,222,202])
        ink=np.rint(base*.59).astype('uint8');border=shape&(dist<1.6);pixels[border,:3]=ink;pixels[:,:,3]=np.rint(alpha*255).astype('uint8')
        if item['category']=='rig_hidden_body':
            original=np.array(Image.open(meta['source']).convert('RGBA'));center=meta['protected_center'];protected=(yy<325)|(yy>=850)|((abs(xx-center['x'])<center['half_width'])&(yy>center['from_y']));pixels[protected]=original[protected]
            # Shoulder overlaps have no drawn transverse border.
            anchor=read(Path('E:/Ai/ComfyUI-EroInc/rig-authoring/v2')/item['rig']/'anchors.json');pts=np.array(anchor['all_keypoints'])
            for joint in [pts[5],pts[6]]:
                overlap=(xx-joint[0])**2+(yy-joint[1])**2<42**2
                touch=border&overlap&~protected;pixels[touch,:3]=pixels[near[0][touch],near[1][touch],:3]
            exact=bool(np.array_equal(pixels[protected],original[protected]));assert exact
        else:
            # Match a plausible native wrist width, not an occluded hand hull.
            sh=np.array(meta['shoulder']);el=np.array(meta['elbow']);wr=np.array(meta['wrist']);d=wr-el;d/=np.linalg.norm(d);n=np.array([-d[1],d[0]]);along=(xx-wr[0])*d[0]+(yy-wr[1])*d[1];cross=(xx-wr[0])*n[0]+(yy-wr[1])*n[1]
            probe=wr-d*9+np.arange(-65,66)[:,None]*n;xy=np.rint(probe).astype(int);width=np.count_nonzero(pixels[xy[:,1],xy[:,0],3]>128);target=25.0 if item['rig'].startswith('female') else 32.0
            ratio=min(1,target/max(width,1));t=np.clip((along+110)/100,0,1);t=t*t*(3-2*t);factor=1+(ratio-1)*t;src_x=wr[0]+along*d[0]+cross/factor*n[0];src_y=wr[1]+along*d[1]+cross/factor*n[1]
            # Premultiplied interpolation avoids dark RGB fringes.
            prem=pixels.astype(float);prem[:,:,:3]*=prem[:,:,3:]/255
            moved=np.stack([ndimage.map_coordinates(prem[:,:,c],[src_y,src_x],order=1,mode='constant') for c in range(4)],2);moved[:,:,:3]/=np.maximum(moved[:,:,3:]/255,1/255);pixels=np.rint(np.clip(moved,0,255)).astype('uint8');pixels[along>10]=0;exact=None
        pixels[pixels[:,:,3]==0,:3]=0;path=out/'full.png';Image.fromarray(pixels).save(path);r={**item,'full':str(path),'sha256':sha(path),'parent_full':item['full'],'protected_body_pixels_exact':exact,'edge_finish':'Authoritative silhouette AA, foreground RGB padding, thin warm contour, shoulder overlap, wrist taper.'};write(out/'record.json',r);records.append(r);print(item['id'],flush=True)
    write(a.target/'index.json',{'schema':1,'source_index':str(a.index),'items':records,'status':'edge_finished_candidates_require_pose_review'})
if __name__=='__main__':main()
