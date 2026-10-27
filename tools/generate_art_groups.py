"""Resumable groups of 4-5 independent local masked edits.

Encoders run before the group's samplers; decoding follows all samplers. Each
KSampler still has batch 1, its own prompt/seed/denoise, and the selected 16-step
profile. No prompt mixing, multi-image denoising, precision or driver changes.
PNG core metadata and run JSON retain the full graph and output-node mapping.
"""
from pathlib import Path
import argparse, datetime as dt, hashlib, time, uuid, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def graph_full_redraw(config,items):
    """Independent whole-figure renders; no affine parts or pasted head pixels."""
    nodes={};counter=0;inputs=[];outputs=[]
    def add(kind,**values):
        nonlocal counter
        counter+=1;key=str(counter);nodes[key]={'class_type':kind,'inputs':values};return [key,0]
    ckpt=add('CheckpointLoaderSimple',ckpt_name=config['checkpoint'])
    model=add('LoraLoader',model=ckpt,clip=[ckpt[0],1],lora_name=config['lora']['name'],strength_model=config['lora']['strength'],strength_clip=0.0)
    control=config.get('controlnet');cn=add('ControlNetLoader',control_net_name=control['name']) if control else None
    latent=add('EmptyLatentImage',width=config['width'],height=config['height'],batch_size=len(items));conditions=[]
    from PIL import Image
    for item in items:
        pos=add('CLIPTextEncode',clip=[model[0],1],text=item['prompt']);neg=add('CLIPTextEncode',clip=[model[0],1],text=item.get('negative',config['negative']))
        if control:
            path=(art.ROOT/'input'/item['control']).resolve()
            if not path.is_relative_to((art.ROOT/'input').resolve()) or not path.is_file():raise ValueError('Control missing or outside input/')
            if Image.open(path).size!=(config['width'],config['height']):raise ValueError('Control canvas differs')
            inputs.append({'path':str(path),'sha256':sha(path),'role':'control','item':item['id']})
            picture=add('LoadImage',image=item['control'])
            result=add('ControlNetApplyAdvanced',positive=pos,negative=neg,control_net=cn,image=picture,strength=item.get('control_strength',control['strength']),start_percent=control.get('start_percent',0.0),end_percent=item.get('control_end',control.get('end_percent',.65)),vae=[ckpt[0],2])
            pos=result;neg=[result[0],1]
        conditions.append((pos,neg))
    deps={'latent':latent}
    for i,(pos,neg) in enumerate(conditions):deps['conditioning_'+str(2*i+1)]=pos;deps['conditioning_'+str(2*i+2)]=neg
    ready=add('EroIncConditioningBarrier',**deps);samples=[];samplers=[]
    for i,item in enumerate(items):
        one=add('LatentFromBatch',samples=ready,batch_index=i,length=1);one=add('LatentBatchSeedBehavior',samples=one,seed_behavior='random')
        sampled=add('KSampler',model=model,positive=conditions[i][0],negative=conditions[i][1],latent_image=one,seed=item['seed'],steps=config['steps'],cfg=config['cfg'],sampler_name=config['sampler'],scheduler=config['scheduler'],denoise=1.0)
        samples.append(sampled);samplers.append(sampled[0])
    combined=samples[0]
    for sampled in samples[1:]:combined=add('LatentBatch',samples1=combined,samples2=sampled)
    for i,item in enumerate(items):
        # The join enforces all samplers before decoding. Decode one frame at a
        # time so 4-5 high-resolution figures do not multiply peak VAE memory.
        latent_one=add('LatentFromBatch',samples=combined,batch_index=i,length=1)
        one=add('VAEDecode',samples=latent_one,vae=[ckpt[0],2]);saved=add('SaveImage',images=one,filename_prefix=config['output_prefix']+'/'+item['id'])
        outputs.append({'id':item['id'],'save_node':saved[0],'sampler_node':samplers[i],'composite_node':None})
    return nodes,inputs,outputs


def graph(config,items):
    if config.get('mode')=='full_redraw':return graph_full_redraw(config,items)
    nodes={};counter=0
    def add(kind,**inputs):
        nonlocal counter
        counter+=1;key=str(counter);nodes[key]={'class_type':kind,'inputs':inputs};return [key,0]
    ckpt=add('CheckpointLoaderSimple',ckpt_name=config['checkpoint'])
    model=add('LoraLoader',model=ckpt,clip=[ckpt[0],1],lora_name=config['lora']['name'],strength_model=config['lora']['strength'],strength_clip=0.0)
    if config.get('body_lora'):
        body=config['body_lora']
        model=add('LoraLoader',model=model,clip=[model[0],1],lora_name=body['name'],strength_model=body['strength'],strength_clip=0.0)
    control=config.get('controlnet')
    control_model=add('ControlNetLoader',control_net_name=control['name']) if control else None
    images=[];masks=[];conditions=[];inputs=[];sizes=set()
    from PIL import Image
    for item in items:
        for field,digest_key in [('protected_rgba','protected_sha256'),('edit_mask_full','edit_mask_sha256')]:
            if field in item:
                extra=Path(item[field]).resolve()
                if not extra.is_relative_to((art.ROOT/'input').resolve()) or sha(extra)!=item[digest_key]:raise ValueError('Changed/outside protected reference input')
                inputs.append({'path':str(extra),'sha256':sha(extra),'role':field,'item':item['id']})
        for role in ['image','mask']:
            path=(art.ROOT/'input'/item[role]).resolve()
            if not path.is_relative_to((art.ROOT/'input').resolve()) or not path.is_file():raise ValueError('Input missing or outside input/')
            sizes.add(Image.open(path).size);inputs.append({'path':str(path),'sha256':sha(path),'role':role,'item':item['id']})
        images.append(add('LoadImage',image=item['image']))
        masks.append(add('LoadImage',image=item['mask']))
        positive=add('CLIPTextEncode',clip=[model[0],1],text=item['prompt'])
        negative=add('CLIPTextEncode',clip=[model[0],1],text=item.get('negative',config['negative']))
        if control:
            path=(art.ROOT/'input'/item['control']).resolve()
            if not path.is_relative_to((art.ROOT/'input').resolve()) or not path.is_file():raise ValueError('Control input missing or outside input/')
            sizes.add(Image.open(path).size);inputs.append({'path':str(path),'sha256':sha(path),'role':'control','item':item['id']})
            guide=add('LoadImage',image=item['control'])
            applied=add('ControlNetApplyAdvanced',positive=positive,negative=negative,control_net=control_model,image=guide,strength=item.get('control_strength',control['strength']),start_percent=control.get('start_percent',0.0),end_percent=item.get('control_end',control.get('end_percent',0.75)),vae=[ckpt[0],2])
            positive=applied;negative=[applied[0],1]
        conditions.append((positive,negative))
    if len(sizes)!=1:raise ValueError('Group canvases must match; no automatic image resizing')
    def join(values,kind,key1,key2):
        out=values[0]
        for v in values[1:]:out=add(kind,**{key1:out,key2:v})
        return out
    pixels=join(images,'ImageBatch','image1','image2')
    preserve=items[0].get('preserve_input_latent',config.get('preserve_input_latent',False))
    if config.get('encode_individually'):
        encoded=[]
        for j,image in enumerate(images):
            if preserve:encoded.append(add('VAEEncode',pixels=image,vae=[ckpt[0],2]))
            else:
                one_mask=add('ImageToMask',image=masks[j],channel='red');encoded.append(add('VAEEncodeForInpaint',pixels=image,vae=[ckpt[0],2],mask=one_mask,grow_mask_by=6))
        latent=join(encoded,'LatentBatch','samples1','samples2')
    elif preserve:latent=add('VAEEncode',pixels=pixels,vae=[ckpt[0],2])
    else:
        mask_images=join(masks,'ImageBatch','image1','image2')
        mask=add('ImageToMask',image=mask_images,channel='red')
        latent=add('VAEEncodeForInpaint',pixels=pixels,vae=[ckpt[0],2],mask=mask,grow_mask_by=6)
    deps={'latent':latent}
    for j,(pos,neg) in enumerate(conditions):deps['conditioning_'+str(2*j+1)]=pos;deps['conditioning_'+str(2*j+2)]=neg
    ready=add('EroIncConditioningBarrier',**deps);samples=[];mask_refs=[];sampling=[]
    for j,item in enumerate(items):
        one=add('LatentFromBatch',samples=ready,batch_index=j,length=1)
        # Restore standalone per-item noise semantics; LatentFromBatch sets batch_index.
        one=add('LatentBatchSeedBehavior',samples=one,seed_behavior='random')
        mask=add('ImageToMask',image=masks[j],channel='red');mask_refs.append(mask)
        one=add('SetLatentNoiseMask',samples=one,mask=mask)
        sample=add('KSampler',model=model,positive=conditions[j][0],negative=conditions[j][1],latent_image=one,seed=item['seed'],steps=config['steps'],cfg=config['cfg'],sampler_name=config['sampler'],scheduler=config['scheduler'],denoise=item.get('denoise',config['denoise']))
        samples.append(sample);sampling.append(sample[0])
    combined=join(samples,'LatentBatch','samples1','samples2');outputs=[]
    for j,item in enumerate(items):
        latent_one=add('LatentFromBatch',samples=combined,batch_index=j,length=1)
        one=add('VAEDecode',samples=latent_one,vae=[ckpt[0],2])
        composite=add('ImageCompositeMasked',destination=images[j],source=one,x=0,y=0,resize_source=False,mask=mask_refs[j])
        saved=add('SaveImage',images=composite,filename_prefix=config['output_prefix']+'/'+item['id'])
        outputs.append({'id':item['id'],'save_node':saved[0],'sampler_node':sampling[j],'composite_node':composite[0]})
    return nodes,inputs,outputs


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',type=Path,required=True);p.add_argument('--index',type=Path,required=True);p.add_argument('--group-size',type=int,choices=[4,5],default=4);p.add_argument('--limit',type=int)
    a=p.parse_args();config=art.read_json(a.config);digest=sha(a.config)
    if (config['steps'],config['cfg'],config['sampler'],config['scheduler'])!=(16,6,'euler','normal'):raise ValueError('Current production profile is DaSiWa 16/CFG6/Euler/Normal')
    model=art.verify_model(art.read_json(art.PROFILE_PATH))
    adapter=art.ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/loras'/config['lora']['name']
    if sha(adapter)!=config['lora']['sha256']:raise ValueError('Adapter checksum mismatch')
    choices=art.api('/object_info/LoraLoader')['LoraLoader']['input']['required']['lora_name'][0]
    adapter_name=next((n for n in choices if n.replace('\\','/')==config['lora']['name'].replace('\\','/')),None)
    if adapter_name is None:raise ValueError('ComfyUI does not list the verified adapter')
    if not art.api('/object_info/EroIncConditioningBarrier').get('EroIncConditioningBarrier'):raise RuntimeError('Install current project extension and restart only an idle ComfyUI')
    config={**config,'checkpoint':Path(model['path']).name,'lora':{**config['lora'],'name':adapter_name}}
    if config.get('controlnet'):
        control=config['controlnet'];path=art.ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/controlnet'/control['name']
        if sha(path)!=control['sha256']:raise ValueError('Control model checksum mismatch')
        choices_control=art.api('/object_info/ControlNetLoader')['ControlNetLoader']['input']['required']['control_net_name'][0]
        control_name=next((n for n in choices_control if n.replace('\\','/')==control['name'].replace('\\','/')),None)
        if control_name is None:raise ValueError('ComfyUI does not list the verified control model')
        config={**config,'controlnet':{**control,'name':control_name}}
    if config.get('body_lora'):
        body=config['body_lora'];path=art.ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/loras'/body['name']
        if sha(path)!=body['sha256']:raise ValueError('Body adapter checksum mismatch')
        name=next((n for n in choices if n.replace('\\','/')==body['name'].replace('\\','/')),None)
        if name is None:raise ValueError('ComfyUI does not list the verified body adapter')
        config={**config,'body_lora':{**body,'name':name}}
    idx=art.read_json(a.index) if a.index.exists() else {'schema':2,'config':str(a.config.resolve()),'config_sha256':digest,'status':'pending','items':[],'groups':[]}
    if idx['config_sha256']!=digest:raise ValueError('Config changed; preserve this index and use another version')
    def save():
        idx['updated_utc']=dt.datetime.now(dt.timezone.utc).isoformat();art.write_json(a.index,idx)
    done={i['id'] for i in idx['items']};pending=[i for i in config['items'] if i['id'] not in done]
    if a.limit is not None:pending=pending[:a.limit]
    try:
        while pending:
            if a.index.with_name('PAUSE').exists():idx['status']='paused_between_groups';save();return
            group=pending[:a.group_size]
            mode=group[0].get('preserve_input_latent',config.get('preserve_input_latent',False))
            group=group[:next((j for j,i in enumerate(group) if i.get('preserve_input_latent',config.get('preserve_input_latent',False))!=mode),len(group))]
            ids=[i['id'] for i in group];active=idx.get('active_group')
            if active:
                if active['ids']!=ids:raise RuntimeError('Active group differs; recover it before submitting')
                run_path=Path(active['run']);run=art.read_json(run_path)
            else:
                q=art.api('/queue')
                if q['queue_running'] or q['queue_pending']:raise RuntimeError('Queue busy; never append to unknown work')
                prompt,input_images,outputs=graph(config,group)
                result=art.api('/prompt',{'prompt':prompt,'client_id':str(uuid.uuid4()),'extra_data':{'extra_pnginfo':{'ero_inc_group':{'ids':ids,'config_sha256':digest,'independent_sampler_batch_size':1}}}})
                run_path=art.ROOT/'runs'/f"{result['prompt_id']}.json"
                run={'prompt_id':result['prompt_id'],'created_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'generator':'Local ComfyUI / DaSiWa grouped independent '+('whole-figure redraws' if config.get('mode')=='full_redraw' else 'masked edits'),'model':model,'adapter':config['lora'],'body_adapter':config.get('body_lora'),'input_images':input_images,'items':group,'output_map':outputs,'prompt':prompt,'gpu_budget':art.read_json(art.ROOT/'gpu-budget.json'),'acceptance':'Unreviewed candidates; never runtime registered'}
                art.write_json(run_path,run);idx['active_group']={'ids':ids,'run':str(run_path)};idx['status']='running';save()
                print('Queued group '+run['prompt_id']+': '+', '.join(ids),flush=True)
            deadline=time.monotonic()+2400
            while True:
                history=art.poll(run['prompt_id']);state=history.get('status',{})
                if state.get('completed') or state.get('status_str')=='error':break
                if state.get('status_str')=='unknown':raise RuntimeError('Recorded group absent from ComfyUI; inspect before retrying')
                if time.monotonic()>deadline:raise TimeoutError('Group still active; inspect before retrying')
                time.sleep(2)
            run['history']=history;art.write_json(run_path,run)
            if state.get('status_str')!='success':raise RuntimeError('Group failed; retain inputs, outputs and history')
            for item,mapping in zip(group,run['output_map']):
                output=history['outputs'][mapping['save_node']]['images'][0];source=art.ROOT/'output'/output['subfolder']/output['filename']
                idx['items'].append({'id':item['id'],'rig':item['rig'],'category':item['category'],'source':str(source),'sha256':sha(source),'run':str(run_path),'seed':item['seed'],'output_map':mapping,'curation':'unreviewed','layers':'not_yet_extracted'})
            messages=dict(history['status']['messages']);seconds=(messages['execution_success']['timestamp']-messages['execution_start']['timestamp'])/1000
            idx['groups'].append({'ids':ids,'run':str(run_path),'seconds':seconds,'seconds_per_image':seconds/len(ids)})
            idx.pop('active_group',None);save();print(f'Recorded {len(idx["items"])}/{len(config["items"])}; group {seconds:.2f}s, {seconds/len(ids):.2f}s/image',flush=True)
            pending=pending[len(group):]
        idx['status']='completed_candidates_require_review' if len(idx['items'])==len(config['items']) else 'partial_candidates_require_review';save()
    except Exception as exc:idx['status']='failed_requires_inspection';idx['error']=repr(exc);save();raise


if __name__=='__main__':main()
