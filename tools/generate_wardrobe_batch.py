"""Resumable masked wardrobe candidates. Never marks generated art as approved.

Runs locally on the already selected body; pause with an index-adjacent PAUSE file.
An interrupted worker recovers its own submitted ComfyUI job instead of duplicating it.
"""
from pathlib import Path
import argparse, datetime as dt, hashlib, time, shutil, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art
import local_art_edit as edit


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',type=Path,required=True)
    p.add_argument('--index',type=Path,required=True)
    p.add_argument('--limit',type=int)
    a=p.parse_args()
    config=art.read_json(a.config)
    digest=hashlib.sha256(a.config.read_bytes()).hexdigest()
    index=art.read_json(a.index) if a.index.exists() else {
        'schema':1,'config':str(a.config.resolve()),'config_sha256':digest,'status':'pending','items':[]}
    if index['config_sha256']!=digest:raise ValueError('Config changed; use a new version/index.')
    def save():
        index['updated_utc']=dt.datetime.now(dt.timezone.utc).isoformat()
        art.write_json(a.index,index)
    done={item['id'] for item in index['items']}
    pending=[item for item in config['items'] if item['id'] not in done]
    if a.limit is not None:pending=pending[:a.limit]
    try:
        for item in pending:
            if a.index.with_name('PAUSE').exists():
                index['status']='paused_between_jobs';save();return
            index['status']='running';index['current_id']=item['id'];save()
            active=index.get('active_run')
            if active:
                if active['id']!=item['id']:raise RuntimeError('Active run/item mismatch.')
                run=art.read_json(Path(active['path']))
                deadline=time.monotonic()+1800
                while True:
                    history=art.poll(run['prompt_id']);state=history.get('status',{})
                    if state.get('completed') or state.get('status_str')=='error':break
                    if state.get('status_str')=='unknown':
                        raise RuntimeError('Recorded job is absent from ComfyUI; inspect it before retrying.')
                    if time.monotonic()>deadline:raise TimeoutError('Recorded job remains active.')
                    time.sleep(2)
                if state.get('status_str')!='success':raise RuntimeError('Recovered job failed.')
                run['history']=history;art.write_json(Path(active['path']),run)
            else:
                image=item.get('image')
                if item.get('image_from'):
                    parent=next((x for x in index['items'] if x['id']==item['image_from']),None)
                    if not parent:raise ValueError('Previous garment stage must finish before the next one.')
                    source=Path(parent['source'])
                    if hashlib.sha256(source.read_bytes()).hexdigest()!=parent['sha256']:
                        raise ValueError('Previous garment stage checksum changed.')
                    image=f"characters_v2/staged/{digest[:12]}/{item['image_from']}.png"
                    destination=art.ROOT/'input'/image
                    if destination.exists():
                        if hashlib.sha256(destination.read_bytes()).hexdigest()!=parent['sha256']:
                            raise ValueError('Existing staged input differs; preserve it for inspection.')
                    else:
                        destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,destination)
                args=['--image',image,'--mask',item['mask'],'--prompt',item['prompt'],
                      '--negative',item.get('negative',config['negative']),'--seed',str(item['seed']),
                      '--denoise',str(item.get('denoise',config['denoise'])),
                      '--steps',str(config['steps']),'--cfg',str(config['cfg']),
                      '--sampler',config['sampler'],'--scheduler',config['scheduler'],
                      '--prefix',config['output_prefix']+'/'+item['id'],
                      '--lora',config['lora']['name'],'--lora-sha256',config['lora']['sha256'],
                      '--lora-strength',str(config['lora']['strength']),'--watch']
                if item.get('preserve_input_latent',config.get('preserve_input_latent')):args.append('--preserve-input-latent')
                def submitted(run):
                    index['active_run']={'id':item['id'],'path':str(art.ROOT/'runs'/f"{run['prompt_id']}.json")};save()
                run=edit.main(args,on_submitted=submitted)
            result=run['history']['outputs']['9']['images'][0]
            source=art.ROOT/'output'/result['subfolder']/result['filename']
            index['items'].append({'id':item['id'],'rig':item['rig'],'category':item['category'],
                'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                'run':str(art.ROOT/'runs'/f"{run['prompt_id']}.json"),'seed':item['seed'],
                'curation':'unreviewed','layers':'not_yet_extracted'})
            index.pop('active_run',None);save()
            print(f"Wardrobe recorded {len(index['items'])}/{len(config['items'])}: {item['id']}",flush=True)
        index.pop('current_id',None)
        index['status']='completed_candidates_require_review' if len(index['items'])==len(config['items']) else 'partial_candidates_require_review'
        save()
    except art.ProductionWindowEnded:
        index['status']='deadline_reached';save();return
    except Exception as exc:
        index['status']='failed_requires_inspection';index['error']=repr(exc);save();raise


if __name__=='__main__':main()
