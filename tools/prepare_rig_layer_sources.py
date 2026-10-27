"""Cache adult body anchors and propose independent arm masks for rig authoring.

All models/data remain on E:. These masks are proposals, not completed layers or
approved anatomy. Existing body-pack PNGs, the game and saves are read-only.
"""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os
ROOT=Path('E:/Ai/ComfyUI-EroInc');PROJECT=Path(__file__).resolve().parents[1]
for k,v in {'TEMP':ROOT/'temp','TMP':ROOT/'temp','HF_HOME':ROOT/'cache/huggingface','OMP_NUM_THREADS':'4'}.items():os.environ[k]=str(v)
import numpy as np
from PIL import Image,ImageDraw

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--ids',nargs='*');p.add_argument('--all-anchors',action='store_true');p.add_argument('--masks-only',action='store_true');p.add_argument('--anchors-only',action='store_true');p.add_argument('--target',type=Path,default=ROOT/'rig-authoring/v2');a=p.parse_args()
    pack=PROJECT/'assets/art_source/characters_v2/body_pack_v1';manifest=read(pack/'manifest.json')
    bodies=[i for i in manifest['items'] if i['category']=='body_build'];selected=a.ids or ['female_average','male_toned'];records=[]
    session=None
    if not a.masks_only:
        impl=ROOT/'postprocess/vendor/DWPose/ControlNet-v1-1-nightly/annotator/dwpose/onnxpose.py';spec=importlib.util.spec_from_file_location('ero_rig_dwpose',impl);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        import onnxruntime as ort
        options=ort.SessionOptions();options.intra_op_num_threads=4;options.inter_op_num_threads=1
        session=ort.InferenceSession(str(ROOT/'models/pose/dwpose/dw-ll_ucoco_384.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
    for body in bodies:
        if body['id'] not in selected and not a.all_anchors:continue
        path=pack/body['files']['full']['path'];digest=sha(path)
        if digest!=body['files']['full']['sha256']:raise ValueError('Changed body source')
        dest=a.target/body['id'];dest.mkdir(parents=True,exist_ok=True);anchor=dest/'anchors.json';image=Image.open(path).convert('RGBA');bg=Image.new('RGBA',image.size,'#eeeeec');bg.alpha_composite(image);rgb=bg.convert('RGB')
        if anchor.exists():
            rec=read(anchor)
            if rec['source_sha256']!=digest:raise ValueError('Cached anchors belong to another source')
        else:
            if a.masks_only:raise ValueError('Prepare anchors first with postprocess Python')
            bounds=image.getchannel('A').point(lambda x:255 if x>=16 else 0).getbbox();pts,scores=module.inference_pose(session,[list(bounds)],np.asarray(rgb)[:,:,::-1].copy());pts=np.asarray(pts)[0];scores=np.asarray(scores)[0]
            rec={'id':body['id'],'sex':body['sex'],'source':str(path),'source_sha256':digest,'canvas':list(image.size),'all_keypoints':pts.tolist(),'all_scores':scores.tolist(),'status':'anchors_require_visual_review'};write(anchor,rec)
        records.append(rec);print('Anchors '+body['id'],flush=True)
        if body['id'] not in selected:continue
        image.save(dest/'source.png');rgb.save(dest/'source-rgb.png')
    del session
    write(a.target/'index.json',{'schema':1,'source_pack':str(pack),'items':records,'mask_selection':selected,'status':'authoring_proposals_not_rig_ready'})
    if a.anchors_only:return
    selected_records=[r for r in records if r['id'] in selected]
    if any(not (a.target/r['id']/'arm-masks.json').exists() for r in selected_records):
        import torch
        from transformers import Sam2Model,Sam2Processor
        torch.set_num_threads(4);model_dir=ROOT/'models/segmentation/sam2.1-hiera-small'
        processor=Sam2Processor.from_pretrained(model_dir,local_files_only=True);model=Sam2Model.from_pretrained(model_dir,local_files_only=True).eval().to('cpu')
        for rec in selected_records:
            dest=a.target/rec['id']
            if (dest/'arm-masks.json').exists():continue
            pts=np.array(rec['all_keypoints']);scores=np.array(rec['all_scores']);center=(pts[11]+pts[12])/2;shoulders=(pts[5]+pts[6])/2;prompts=[];labels=[]
            for side,sh,el,wr,start in [('left',5,7,9,91),('right',6,8,10,112)]:
                hand=pts[start:start+21][scores[start:start+21]>.3];hc=hand.mean(0) if len(hand) else pts[wr]+[0,40]
                positive=[pts[sh]*.3+pts[el]*.7,pts[el],(pts[el]+pts[wr])/2,pts[wr],hc]
                negative=[shoulders+[0,90],(shoulders+center)/2,center,pts[8 if el==7 else 7],np.array([pts[11 if sh==5 else 12,0],hc[1]])]
                prompts.append(np.array(positive+negative).tolist());labels.append([1]*len(positive)+[0]*len(negative))
            image=Image.open(dest/'source-rgb.png').convert('RGB');inputs=processor(images=image,input_points=[prompts],input_labels=[labels],return_tensors='pt')
            with torch.inference_mode():outputs=model(**inputs,multimask_output=True)
            masks=processor.post_process_masks(outputs.pred_masks.cpu(),inputs['original_sizes'])[0];quality=outputs.iou_scores[0].cpu();fg=np.array(Image.open(dest/'source.png').getchannel('A'))
            previews=Image.new('RGB',(image.width*3,image.height),'#101b29');previews.paste(image,(0,0));details=[]
            for i,side in enumerate(['left','right']):
                choices=[]
                for k in range(masks.shape[1]):
                    mask=masks[i,k].numpy().astype(bool)&(fg>0);area=int(mask.sum());penalty=10 if area>int(np.count_nonzero(fg)*.3) else 0
                    choices.append((float(quality[i,k])-penalty,k,area))
                rank=max(choices);mask=masks[i,rank[1]].numpy().astype(bool);alpha=(fg*mask).astype('uint8');Image.fromarray(alpha).save(dest/('arm-'+side+'-mask.png'))
                cut=Image.open(dest/'source.png').convert('RGBA');cut.putalpha(Image.fromarray(alpha));cut.save(dest/('arm-'+side+'-visible.png'));panel=Image.new('RGBA',cut.size,'#101b29');panel.alpha_composite(cut);previews.paste(panel.convert('RGB'),(image.width*(i+1),0))
                details.append({'side':side,'points':prompts[i],'labels':labels[i],'mask_index':rank[1],'iou_score':float(quality[i,rank[1]]),'foreground_pixels':rank[2],'status':'candidate_not_approved'})
            previews.thumbnail((1450,900));previews.save(dest/'mask-review.png');write(dest/'arm-masks.json',{'source_sha256':rec['source_sha256'],'items':details,'status':'visible_masks_only_hidden_surfaces_missing'});print('SAM arm candidates '+rec['id'],flush=True)
    write(a.target/'index.json',{'schema':1,'source_pack':str(pack),'items':records,'mask_selection':selected,'status':'authoring_proposals_not_rig_ready'})

if __name__=='__main__':main()
