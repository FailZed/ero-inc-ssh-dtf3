"""Validate body candidates, record local-generation lineage, and build review sheets."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

PROJECT=Path(__file__).resolve().parents[1]
ROOT=Path('E:/Ai/ComfyUI-EroInc')
FOLDER=PROJECT/'assets/art_source/characters_v1/bodies_v2'
DOCS=PROJECT/'docs/art/characters-v1'
LABELS={'slim':'Стройное','average':'Обычное','toned':'Подтянутое','athletic':'Спортивное',
        'muscular':'Сильное','broad':'Широкий каркас','soft':'Слегка мягкое','solid':'Крепкое',
        'curvy':'Выраженная талия','pear':'Шире бёдра'}


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def key(path):return str(Path(path).resolve()).casefold()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--folder',type=Path,default=FOLDER)
    args=parser.parse_args()
    folder=args.folder.resolve()
    config=read(DOCS/'local-profiles.json')
    runs={}
    output_runs={}
    hash_runs={}
    for path in (ROOT/'runs').glob('*.json'):
        run=read(path);runs[run['prompt_id']]=run
        for node in run.get('history',{}).get('outputs',{}).values():
            for image in node.get('images',[]):
                file=ROOT/'output'/image.get('subfolder','')/image['filename']
                if file.is_file():
                    output_runs[key(file)]=run['prompt_id']
                    hash_runs[digest(file)]=run['prompt_id']
    entries=[]
    for profile in config['profiles']:
        variant=profile['id'];file=folder/(variant+'.png')
        image=Image.open(file)
        assert image.mode=='RGBA' and image.size==(720,1280),variant
        alpha=np.asarray(image.getchannel('A'))
        assert not alpha[:245].any(),variant+' has baked head pixels'
        bounds=image.getchannel('A').point(lambda v:255 if v>=16 else 0).getbbox()
        assert bounds[0]>16 and bounds[2]<704 and 1243<=bounds[3]<=1246,variant+' margins'
        components,count=ndimage.label(alpha>=16,structure=np.ones((3,3)))
        sizes=np.bincount(components.ravel())[1:]
        main_fraction=float(sizes.max()/sizes.sum())
        assert main_fraction>.999,variant+' detached fragments'
        layer=read(file.with_suffix('.qa.json'))
        cutout=Path(layer['source']);assert digest(cutout)==layer['source_sha256']
        cutout_info=read(cutout.with_suffix('.qa.json'))
        source=Path(cutout_info['source']);assert digest(source)==cutout_info['source_sha256']
        initial=output_runs[key(source)];lineage=[];pending=[initial]
        while pending:
            run_id=pending.pop()
            if run_id in lineage:continue
            lineage.append(run_id);run=runs[run_id]
            assert run['model']['sha256'].lower()==config['checkpoint_sha256'].lower()
            for item in run.get('input_images',[]):
                parent=hash_runs.get(item['sha256'])
                if parent and parent!=run_id:pending.append(parent)
        if profile['gender']=='male':
            assert any('flaccid penis' in runs[r]['prompt']['6']['inputs']['text'] for r in lineage),variant+' missing requested anatomy provenance'
        entries.append({'id':variant,'gender':profile['gender'],'label':LABELS[variant.split('_',1)[1]],
            'file':file.relative_to(PROJECT).as_posix(),'sha256':digest(file),
            'source':str(source),'source_sha256':digest(source),'local_run_lineage':lineage,
            'neck_attach':layer['neck_attach'],'feet_baseline_y':1244,'alpha_bounds':bounds,
            'main_component_fraction':main_fraction,'head_included':False,'clothes_included':False,
            'approval':'agent-selected body candidate; only the separate style target was approved by user',
            'runtime_eligible':False,'training_eligible':False})
    manifest={'schema':1,'date':'2026-10-18','status':'16 body layer candidates, not a complete character pack',
        'generator':'Local ComfyUI / DaSiWa EpitaphEcstasy','checkpoint_sha256':config['checkpoint_sha256'],
        'checkpoint_included':False,'donor_school_images_used_as_inputs':False,
        'canvas':[720,1280],'body_top_y':245,'feet_baseline_y':1244,
        'male_anatomy':'Natural adult male sexual characteristics retained at user request.',
        'female_builds':'Moderate variants; extreme female_full studies rejected.',
        'remaining':['Review final style consistency at game scale with the separate heads and clothing.',
            'Finish independent heads, facial features, front/back hair and clothing fitted to each build.',
            'Review neck joins, poses and full compositions in game before runtime activation.'],
        'lora_trained':False,'assets':entries}
    (folder/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    summary={'bodies':len(entries),'males':sum(v['gender']=='male' for v in entries),
        'females':sum(v['gender']=='female' for v in entries),'rgba_canvas_alpha_margins_lineage':'passed',
        'visual_review':'Body candidates; art style consistency and complete character review remain.'}
    (DOCS/'body-pack-qa.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for gender,title in [('male','МУЖСКИЕ ОСНОВЫ · DaSiWa'),('female','ЖЕНСКИЕ ОСНОВЫ · DaSiWa')]:
        cmd=[sys.executable,str(PROJECT/'tools/build_body_review.py'),'--crop-alpha',
            '--target',str(DOCS/'previews'/(gender+'_'+folder.name+'.png')),'--title',title,
            '--subtitle','Отдельный слой тела · кисти и стопы в кадре · голова и одежда собираются отдельно']
        for entry in entries:
            if entry['gender']==gender:cmd+=['--item',entry['label']+'='+str(PROJECT/entry['file'])]
        subprocess.run(cmd,check=True)
    print(json.dumps(summary,ensure_ascii=True),flush=True)


if __name__=='__main__':main()
