"""Remove only exterior neutral backdrop remnants from rig component candidates.

Dark contour ink, warm shadows and enclosed highlights are retained. This is
edge matting, never a way to remove clothes or accept a broken limb.
"""
from pathlib import Path
import argparse,json,hashlib
import numpy as np
from PIL import Image
from scipy import ndimage
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();idx=json.loads(a.index.read_text());records=[]
    if a.target.exists():raise ValueError('Preserve prior alpha versions')
    a.target.mkdir(parents=True)
    for item in idx['items']:
        src=Path(item['full']);arr=np.array(Image.open(src).convert('RGBA'));rgb=arr[:,:,:3].astype(int);neutral=(rgb.max(2)-rgb.min(2)<8)&(rgb[:,:,0]>145)&(rgb[:,:,0]-rgb[:,:,1]<3);transparent=arr[:,:,3]<8
        outside=ndimage.binary_propagation(transparent,mask=transparent|neutral);remove=outside&~transparent
        if item['category']=='rig_hidden_body':
            meta=item['authoring'];mask=np.array(Image.open(meta['edit_mask']))>0;remove&=mask;yy,xx=np.mgrid[:arr.shape[0],:arr.shape[1]];core=meta['protected_center'];protect=(yy<325)|(yy>=850)|((abs(xx-core['x'])<core['half_width'])&(yy>core['from_y']));remove&=~protect
        arr[remove,3]=0;arr[arr[:,:,3]==0,:3]=0;dest=a.target/item['id'];dest.mkdir();Image.fromarray(arr).save(dest/'full.png');bg=Image.new('RGBA',(arr.shape[1],arr.shape[0]),'#101b29');bg.alpha_composite(Image.fromarray(arr));bg.convert('RGB').save(dest/'dark.png')
        record={**item,'full':str(dest/'full.png'),'sha256':sha(dest/'full.png'),'alpha_parent':str(src),'alpha_parent_sha256':sha(src),'exterior_neutral_pixels_removed':int(remove.sum()),'status':'candidate_requires_joint_and_full_pose_review'};(dest/'record.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n');records.append(record)
    (a.target/'index.json').write_text(json.dumps({'schema':1,'source_index':str(a.index),'items':records,'status':'matted_candidates_not_approved'},ensure_ascii=False,indent=2)+'\n');print(json.dumps({'items':len(records),'removed':[i['exterior_neutral_pixels_removed'] for i in records]}))
if __name__=='__main__':main()
