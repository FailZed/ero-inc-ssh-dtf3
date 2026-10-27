"""Extract reviewed whole-figure pose candidates without geometric distortion.

Segmentation and visible-part proposals follow actual rendered anatomy. No
source limb is rotated, warped or pasted; no hidden anatomy is invented here.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, os
ROOT=Path('E:/Ai/ComfyUI-EroInc')
for k,v in {'REMBG_HOME':ROOT/'cache/rembg','XDG_CACHE_HOME':ROOT/'cache','NUMBA_CACHE_DIR':ROOT/'cache/numba','TEMP':ROOT/'temp','TMP':ROOT/'temp','OMP_NUM_THREADS':'4'}.items():os.environ[k]=str(v)
import numpy as np
from PIL import Image,PngImagePlugin
from scipy import ndimage
import onnxruntime as ort
from rembg import new_session,remove

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def save(im,p,meta):
    aa=np.array(im);aa[aa[:,:,3]==0,:3]=0;Image.fromarray(aa).save(p,pnginfo=meta)
    return {'path':str(p.resolve()),'sha256':sha(p)}

def distance_segment(xx,yy,a,b):
    v=b-a;t=np.clip(((xx-a[0])*v[0]+(yy-a[1])*v[1])/max(float(v@v),1),0,1)
    return np.hypot(xx-a[0]-t*v[0],yy-a[1]-t*v[1])

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args()
    idx=read(a.index);conf=read(Path(idx['config']));lookup={i['id']:i for i in conf['items']};a.target.mkdir(parents=True,exist_ok=True)
    impl=ROOT/'postprocess/vendor/DWPose/ControlNet-v1-1-nightly/annotator/dwpose/onnxpose.py';spec=importlib.util.spec_from_file_location('ero_pose_export_dwpose',impl);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    opt=ort.SessionOptions();opt.intra_op_num_threads=4;opt.inter_op_num_threads=1
    pose=ort.InferenceSession(str(ROOT/'models/pose/dwpose/dw-ll_ucoco_384.onnx'),sess_options=opt,providers=['CPUExecutionProvider'])
    segment=new_session('birefnet-general-lite',providers=['CPUExecutionProvider']);records=[]
    for item in idx['items']:
        dest=a.target/item['id'];source=Path(item['source']);digest=sha(source)
        if (dest/'record.json').exists():
            rec=read(dest/'record.json')
            if rec['source_sha256']!=digest:raise ValueError('Changed source after processing')
            records.append(rec);continue
        dest.mkdir(exist_ok=True);raw=Image.open(source).convert('RGB');sampler_canvas=list(raw.size);meta_item=item.get('pose_metadata',lookup.get(item['id'],{}));protected=None;full_mask=None
        if meta_item.get('protected_rgba'):
            protected_path=Path(meta_item['protected_rgba']);mask_path=Path(meta_item['edit_mask_full'])
            if sha(protected_path)!=meta_item['protected_sha256'] or sha(mask_path)!=meta_item['edit_mask_sha256']:raise ValueError('Changed protected reference or edit mask')
            protected=Image.open(protected_path).convert('RGBA');full_mask=np.array(Image.open(mask_path).convert('L'))
            reconstructed=Image.new('RGBA',protected.size,'#eeeeec');reconstructed.alpha_composite(protected);reconstructed=reconstructed.convert('RGB');reconstructed.paste(raw,tuple(meta_item['crop_box'][:2]));raw=reconstructed
        rgba=remove(raw,session=segment,decontaminate=True).convert('RGBA');arr=np.array(rgba);alpha=arr[:,:,3]
        cc,n=ndimage.label(alpha>160);sizes=np.bincount(cc.ravel());sizes[0]=0
        if not n:raise ValueError('No foreground')
        major=cc==sizes.argmax();major=ndimage.binary_dilation(major,iterations=3);alpha=(alpha*major).astype('uint8')
        ys,xs=np.where(alpha>=16);bounds=[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)]
        pts,scores=module.inference_pose(pose,[bounds],np.asarray(raw)[:,:,::-1].copy());pts=np.asarray(pts)[0];scores=np.asarray(scores)[0]
        shoulders=(pts[5]+pts[6])/2;hips=(pts[11]+pts[12])/2
        neck=int(round(shoulders[1]-.055*(hips[1]-shoulders[1])))
        # Neutral bodies are skin plus the head/hair. Remove nonhuman stool and
        # floor pixels by material adjacency, retaining the actual painted edge.
        material_filter=meta_item.get('foreground_policy')!='whole_foreground_no_material_deletion'
        if material_filter:
            rgb=arr[:,:,:3].astype(int);skin=(rgb[:,:,0]>170)&(rgb[:,:,1]>125)&(rgb[:,:,2]>90)&(rgb[:,:,0]-rgb[:,:,1]>7)&(rgb[:,:,1]-rgb[:,:,2]>3)&(alpha>16)
            near=ndimage.binary_dilation(skin,iterations=4);head_keep=np.zeros(alpha.shape,bool)
            lx=max(0,int(min(pts[5,0],pts[6,0])-65));rx=min(raw.width,int(max(pts[5,0],pts[6,0])+65));head_keep[:max(neck+12,0),lx:rx]=True
            alpha=(alpha*(near|head_keep)).astype('uint8')
        arr[:,:,3]=alpha
        cc,n=ndimage.label(alpha>32);sizes=np.bincount(cc.ravel());sizes[0]=0
        keep=ndimage.binary_dilation(cc==sizes.argmax(),iterations=2);arr[:,:,3]*=keep
        protected_exact=None
        if protected is not None:
            reference=np.array(protected);arr[full_mask==0]=reference[full_mask==0];protected_exact=np.array_equal(arr[full_mask==0],reference[full_mask==0])
        arr[arr[:,:,3]==0,:3]=0
        ys,xs=np.where(arr[:,:,3]>=16);height=int(ys.max()-ys.min());uniform_scale=min(1.0,(1395-32)/max(height,1))
        if uniform_scale<1:
            nw=round(raw.width*uniform_scale);nh=round(raw.height*uniform_scale);nx=(raw.width-nw)//2
            scaled=Image.fromarray(arr).convert('RGBa').resize((nw,nh),Image.Resampling.LANCZOS).convert('RGBA');canvas=Image.new('RGBA',raw.size);canvas.paste(scaled,(nx,0));arr=np.array(canvas)
            pts[:,0]=pts[:,0]*uniform_scale+nx;pts[:,1]*=uniform_scale;neck=round(neck*uniform_scale)
            ys,xs=np.where(arr[:,:,3]>=16)
        dy=1395-int(ys.max())
        if dy:
            shifted=np.zeros_like(arr)
            if dy>0:shifted[dy:]=arr[:-dy]
            else:shifted[:dy]=arr[-dy:]
            arr=shifted;pts[:,1]+=dy;neck+=dy
        for correction in item.get('alpha_cleanup',[]):
            if correction['operation']!='right_edge_from_skin':raise ValueError('Unknown explicit alpha correction')
            x0,y0,x1,y1=correction['box'];pad=correction.get('edge_padding',2)
            for row in range(y0,y1):
                r=arr[row,x0:x1,:3].astype(int);skinrow=(r[:,0]>225)&(r[:,1]>185)&(r[:,2]>145)&(r[:,0]-r[:,1]>7)&(arr[row,x0:x1,3]>100)
                ids=np.flatnonzero(skinrow);limit=x0+int(ids.max())+pad+1 if len(ids) else x0
                arr[row,min(limit,x1):x1,3]=0
        arr[arr[:,:,3]==0,:3]=0
        padding_x=max(0,(1472-raw.width)//2)
        if padding_x:
            canvas=np.zeros((raw.height,1472,4),np.uint8);canvas[:,padding_x:padding_x+raw.width]=arr;arr=canvas;pts[:,0]+=padding_x
        canvas_size=(arr.shape[1],arr.shape[0]);alpha=arr[:,:,3]
        full=Image.fromarray(arr);actual=full.getchannel('A').point(lambda x:255 if x>=16 else 0).getbbox()
        yy,xx=np.mgrid[:canvas_size[1],:canvas_size[0]];owner=np.zeros(alpha.shape,np.uint8);owner[:neck]=1
        for label,(shoulder,elbow,wrist) in enumerate([(6,8,10),(5,7,9)],2):
            upper=distance_segment(xx,yy,pts[shoulder],pts[elbow]);lower=distance_segment(xx,yy,pts[elbow],pts[wrist]);radius=float(np.linalg.norm(pts[elbow]-pts[wrist])*.12)
            selected=(upper<max(radius,19))|(lower<max(radius*.83,16));selected&=yy>neck;owner[selected]=label
        legs=[]
        for label,(hip,knee,ankle) in enumerate([(12,14,16),(11,13,15)],4):
            ds=np.minimum(distance_segment(xx,yy,pts[hip],pts[knee]),distance_segment(xx,yy,pts[knee],pts[ankle]));legs.append(ds)
        leg_region=(yy>min(pts[11,1],pts[12,1])+22)&(owner==0);owner[leg_region]=np.where(legs[0][leg_region]<legs[1][leg_region],4,5)
        meta=PngImagePlugin.PngInfo()
        for k,v in Image.open(source).info.items():
            if isinstance(v,str):meta.add_text(k,v)
        meta.add_text('ero_inc_pose_export',json.dumps({'full_redraw':True,'runtime_registered':False,'source_sha256':digest,'visible_parts_only':True}))
        files={'full':save(full,dest/'full.png',meta)};assembled=Image.new('RGBA',canvas_size)
        for label,name in enumerate(['torso','head','arm_left','arm_right','leg_left','leg_right']):
            part=arr.copy();part[:,:,3]*=owner==label;im=Image.fromarray(part);files[name]=save(im,dest/(name+'.png'),meta);assembled.alpha_composite(im)
        body=arr.copy();body[:neck,:,3]=0;files['body']=save(Image.fromarray(body),dest/'body.png',meta)
        exact=np.array_equal(np.array(assembled),np.array(full))
        errors=[]
        if not exact:errors.append('parts do not reconstruct full figure')
        if not actual or actual[0]<=16 or actual[1]<=16 or actual[2]>=canvas_size[0]-16 or actual[3]>=canvas_size[1]-16:errors.append('figure clipped or too close to edge')
        rec={**meta_item,'id':item['id'],'source':str(source),'source_sha256':digest,'run':item['run'],'files':files,'canvas':list(canvas_size),'source_canvas':list(raw.size),'sampler_canvas':sampler_canvas,'neck_y':neck,'baseline_y':1395,'uniform_scale':uniform_scale,'padding_x':padding_x,'translation_y':dy,'alpha_bounds':actual,'all_keypoints':pts.tolist(),'all_scores':scores.tolist(),'protected_rgba_exact_before_floor_fit':protected_exact,'postprocess':'Reconstruct region render when applicable; CPU BiRefNet foreground; nonhuman material removal; protected RGBA restoration; whole-figure uniform fit and floor translation; horizontal padding; DWPose-guided visible-part proposals. No limb deformation or head paste.','parts_reassemble_exactly':exact,'part_status':'visible-cut candidates, image-space side names, source-pose-specific, no hidden-surface or arbitrary cross-pose compatibility claim','technical_errors':errors,'visual_acceptance':'required separately','runtime_registered':False}
        write(dest/'record.json',rec);records.append(rec);print('Processed '+item['id']+(' WARN '+repr(errors) if errors else ''),flush=True)
    write(a.target/'index.json',{'config':idx['config'],'status':'processed_requires_visual_review','items':records})
if __name__=='__main__':main()
