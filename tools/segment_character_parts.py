"""Create candidate RGBA layers from original art using local SAM2 point prompts."""
from pathlib import Path
import argparse,hashlib,json,os
os.environ.setdefault('OMP_NUM_THREADS','4')
os.environ.setdefault('HF_HOME','E:/Ai/ComfyUI-EroInc/cache/huggingface')
from PIL import Image,PngImagePlugin
import numpy as np
import torch
from transformers import Sam2Model,Sam2Processor

MODEL=Path('E:/Ai/ComfyUI-EroInc/models/segmentation/sam2.1-hiera-small')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path);p.add_argument('prompts',type=Path);p.add_argument('target',type=Path)
    p.add_argument('--foreground',type=Path)
    a=p.parse_args()
    if a.target.exists():raise ValueError('Use a new layer folder; preserve previous results.')
    torch.set_num_threads(4)
    image=Image.open(a.source).convert('RGB');spec=json.loads(a.prompts.read_text(encoding='utf-8-sig'))
    processor=Sam2Processor.from_pretrained(MODEL,local_files_only=True)
    model=Sam2Model.from_pretrained(MODEL,local_files_only=True).eval().to('cpu')
    names=list(spec)
    inputs=processor(images=image,input_points=[[spec[n]['points'] for n in names]],
                     input_labels=[[spec[n]['labels'] for n in names]],return_tensors='pt')
    with torch.inference_mode():outputs=model(**inputs,multimask_output=True)
    masks=processor.post_process_masks(outputs.pred_masks.cpu(),inputs['original_sizes'])[0]
    scores=outputs.iou_scores[0].cpu()
    rgba=np.asarray(image.convert('RGBA')).copy()
    foreground=np.asarray(Image.open(a.foreground).getchannel('A')) if a.foreground else np.full(rgba.shape[:2],255,dtype=np.uint8)
    a.target.mkdir(parents=True)
    records=[];source_sha=hashlib.sha256(a.source.read_bytes()).hexdigest()
    model_sha=hashlib.sha256((MODEL/'model.safetensors').read_bytes()).hexdigest()
    for i,name in enumerate(names):
        index=int(scores[i].argmax());selected=masks[i,index].numpy().astype(bool)
        # Explicit local point prompts only propose masks; visual acceptance is separate.
        pixels=rgba.copy();pixels[:,:,3]=foreground*selected
        out=Image.fromarray(pixels);meta=PngImagePlugin.PngInfo()
        for k,v in Image.open(a.source).info.items():
            if isinstance(v,str):meta.add_text(k,v)
        record={'name':name,'source':str(a.source.resolve()),'source_sha256':source_sha,'prompt':spec[name],
                'model':'facebook/sam2.1-hiera-small','model_sha256':model_sha,'license':'Apache-2.0',
                'source_url':'https://huggingface.co/facebook/sam2.1-hiera-small','quality_score':float(scores[i,index]),
                'bounds':out.getchannel('A').getbbox(),'status':'candidate_requires_visual_review'}
        meta.add_text('ero_inc_part_segmentation',json.dumps(record))
        out.save(a.target/(name+'.png'),pnginfo=meta)
        Image.fromarray(selected.astype(np.uint8)*255).save(a.target/(name+'.mask.png'))
        records.append(record)
    (a.target/'layers.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
    print(json.dumps([{'name':r['name'],'bounds':r['bounds'],'score':r['quality_score']} for r in records]),flush=True)


if __name__=='__main__':main()
