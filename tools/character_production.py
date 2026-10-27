"""Launch and inspect bounded local character batches without a live chat loop.

Pause finishes the current render, then stops between jobs. Does not train on
unreviewed images or mutate game assets/saves. All work, caches and logs stay on E:.
"""
from pathlib import Path
import argparse,datetime as dt,json,os,subprocess,sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art
import psutil

STATE=art.ROOT/'batches/production-2026-10-19'
DEFAULT_FAMILIES=[
    ('anatomy-v3','generate_wardrobe_batch.py','anatomy-v3.json'),
    ('wardrobe-v2','generate_wardrobe_batch.py','wardrobe-v2.json'),
    ('body-diversity-v1','generate_style_batch.py','body-diversity-v1.json')]


def families():
    plan=art.PROJECT/'docs/art/characters-v2/overnight-jobs.json'
    if not plan.exists():return DEFAULT_FAMILIES
    result=[]
    for item in art.read_json(plan)['families']:
        if item['script'] not in ('generate_style_batch.py','generate_wardrobe_batch.py'):
            raise ValueError('Unrecognized art worker.')
        if any('/' in item[k] or '\\' in item[k] or '..' in item[k] for k in ('name','config')):
            raise ValueError('Use simple family/config names.')
        result.append((item['name'],item['script'],item['config']))
    return result


def active():
    stamp=STATE/'worker.pid'
    if not stamp.exists():return False
    try:
        proc=psutil.Process(int(stamp.read_text()))
        command=' '.join(proc.cmdline()).replace('\\','/').lower()
        return str(Path(__file__).resolve()).replace('\\','/').lower() in command and ' run' in command
    except (psutil.Error,ValueError):return False


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['start','status','pause','resume','run']);a=p.parse_args()
    STATE.mkdir(parents=True,exist_ok=True)
    if a.action=='status':
        result={'worker_alive':active(),'state':art.read_json(STATE/'state.json') if (STATE/'state.json').exists() else None,'families':[]}
        for name,_,config in families():
            index=art.ROOT/'batches'/name/'index.json';spec=art.read_json(art.PROJECT/'docs/art/characters-v2'/config)
            data=art.read_json(index) if index.exists() else {}
            result['families'].append({'name':name,'completed':len(data.get('items',[])),
                'total':len(spec.get('items',spec.get('profiles',[]))),'status':data.get('status','pending'),
                'current':data.get('current_id'),'active_run':data.get('active_run'),
                'pause_requested':index.with_name('PAUSE').exists(),'index':str(index)})
        print(json.dumps(result,ensure_ascii=False,indent=2));return
    if a.action in ('pause','resume'):
        for name,_,_ in families():
            marker=art.ROOT/'batches'/name/'PAUSE';marker.parent.mkdir(parents=True,exist_ok=True)
            if a.action=='pause':marker.write_text('Requested pause between jobs.\n',encoding='utf-8')
            elif marker.exists():marker.unlink()
        if a.action=='pause':print('Pause requested; current render will finish.');return
    if a.action in ('start','resume'):
        if active():print('Worker already running.');return
        art.check_production_window()
        for _,_,config in families():art.read_json(art.PROJECT/'docs/art/characters-v2'/config)
        command=[sys.executable,'-u',str(Path(__file__).resolve()),'run']
        env=os.environ.copy();env.update({'PYTHONIOENCODING':'utf-8','TEMP':str(art.ROOT/'temp'),'TMP':str(art.ROOT/'temp')})
        with (STATE/'stdout.log').open('ab',buffering=0) as out,(STATE/'stderr.log').open('ab',buffering=0) as err:
            proc=subprocess.Popen(command,cwd=art.PROJECT,env=env,stdin=subprocess.DEVNULL,stdout=out,stderr=err,
                creationflags=subprocess.DETACHED_PROCESS|subprocess.CREATE_NEW_PROCESS_GROUP|subprocess.CREATE_NO_WINDOW)
        (STATE/'worker.pid').write_text(str(proc.pid),encoding='ascii')
        print(json.dumps({'pid':proc.pid,'logs':str(STATE),'bounded_candidates':True}));return
    state={'started_utc':dt.datetime.now(dt.timezone.utc).isoformat(),'status':'running','pid':os.getpid()}
    try:
        completed=set()
        while True:
            remaining=[f for f in families() if f[0] not in completed]
            if not remaining:
                state['status']='completed_candidates_require_review';break
            name,script,config=remaining[0]
            art.check_production_window()
            state['family']=name;art.write_json(STATE/'state.json',state)
            index=art.ROOT/'batches'/name/'index.json'
            subprocess.run([sys.executable,'-u',str(art.PROJECT/'tools'/script),'--config',
                str(art.PROJECT/'docs/art/characters-v2'/config),'--index',str(index)],cwd=art.PROJECT,
                stdout=sys.stdout,stderr=sys.stderr,check=True)
            if index.with_name('PAUSE').exists():state['status']='paused_between_jobs';break
            if art.read_json(index).get('status')=='deadline_reached':state['status']='deadline_reached';break
            completed.add(name)
    except art.ProductionWindowEnded:
        state['status']='deadline_reached'
    except Exception as exc:
        state.update(status='failed_requires_inspection',error=repr(exc));raise
    finally:
        state['updated_utc']=dt.datetime.now(dt.timezone.utc).isoformat();art.write_json(STATE/'state.json',state)


if __name__=='__main__':main()
