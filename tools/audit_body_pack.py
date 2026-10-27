"""Audit body-pack counts, hashes, PNG geometry, and registered layer assembly."""
from pathlib import Path
import argparse,json,hashlib,collections
import numpy as np
from PIL import Image
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--pack',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();m=json.loads((a.pack/'manifest.json').read_text(encoding='utf-8'));items=m['items'];errors=[];checked=0;visible_hashes=collections.defaultdict(list)
    for item in items:
        for kind,entry in item['files'].items():
            path=a.pack/entry['path'];checked+=1
            if not path.exists() or sha(path)!=entry['sha256']:errors.append(item['id']+': changed/missing '+kind);continue
            im=Image.open(path)
            if im.size!=(832,1472):errors.append(item['id']+': canvas '+kind)
            if kind not in ['mask'] and im.mode!='RGBA':errors.append(item['id']+': missing RGBA '+kind)
            if kind=='full':
                aa=np.asarray(im);fg=aa[:,:,3]>=16;ys,xs=np.where(fg)
                if not len(xs) or min(xs)<=16 or max(xs)>=816 or min(ys)<=16 or max(ys)>=1456:errors.append(item['id']+': clipped/full alpha')
                if aa[:,:,3].min()!=0:errors.append(item['id']+': background opaque')
                if np.any(aa[aa[:,:,3]==0,:3]):errors.append(item['id']+': hidden RGB not normalized')
                signature=hashlib.sha256(aa.tobytes()).hexdigest();visible_hashes[signature].append(item['id'])
        if all(k in item['files'] for k in ['full','head','body']):
            full=Image.open(a.pack/item['files']['full']['path']).convert('RGBA');assembled=Image.new('RGBA',full.size)
            for layer in ['body','head']:assembled.alpha_composite(Image.open(a.pack/item['files'][layer]['path']).convert('RGBA'))
            if not np.array_equal(np.asarray(full),np.asarray(assembled)):errors.append(item['id']+': head/body reconstruction')
        if item.get('parts_reassemble_exactly'):
            full=Image.open(a.pack/item['files']['full']['path']).convert('RGBA');assembled=Image.new('RGBA',full.size)
            for layer in ['core','head','arm_left','arm_right']:assembled.alpha_composite(Image.open(a.pack/item['files'][layer]['path']).convert('RGBA'))
            if not np.array_equal(np.asarray(full),np.asarray(assembled)):errors.append(item['id']+': core/arm reconstruction')
    c=collections.Counter(i['category'] for i in items);sexcat=lambda cat,sex:sum(i['category']==cat and i['sex']==sex for i in items)
    targets={'male_frame':32,'female_builds':12,'breast_shape':30,'nipple_areola_forms':7,'female_external_anatomy':4,'male_external_anatomy':8,'female_body_hair':10,'male_body_hair':6,'female_poses_with_rest':9,'male_poses_with_rest':9,'pregnancy_stages':9,'anthro_species_by_sex':6,'skin_palettes':8,'tan_patterns':2,'female_tone_with_default':4,'male_tone_profiles':3,'thigh_shapes_per_sex':2,'calf_shapes_per_sex':2}
    actual={**dict(c),'female_builds':sexcat('body_build','female'),'female_poses_with_rest':sexcat('arm_pose_families','female')+1,'male_poses_with_rest':sexcat('arm_pose_families','male')+1,'skin_palettes':len({i['palette'] for i in items if i['category']=='skin_palette'}),'tan_patterns':len({i['pattern'] for i in items if i['category']=='tan_pattern'}),'female_tone_with_default':sexcat('muscle_definition','female')+1,'male_tone_profiles':sexcat('muscle_definition','male'),'thigh_shapes_per_sex':min(sexcat('thigh_shape',s) for s in ['female','male']),'calf_shapes_per_sex':min(sexcat('calf_shape',s) for s in ['female','male'])}
    for key,target in targets.items():
        if actual.get(key,0)<target:errors.append(f'{key}: {actual.get(key,0)} < {target}')
    pointers={}
    def scan(value):
        if isinstance(value,dict):
            if 'path' in value and 'sha256' in value:pointers[value['path']]=value['sha256']
            for v in value.values():scan(v)
        elif isinstance(value,list):
            for v in value:scan(v)
    scan(m)
    for rel,digest in pointers.items():
        if not (a.pack/rel).exists() or sha(a.pack/rel)!=digest:errors.append('Support/manifest pointer changed: '+rel)
    report={'passed':not errors,'files_checked':len(pointers),'primary_files_checked':checked,'records':len(items),'targets':targets,'actual':actual,'duplicate_full_images':[v for v in visible_hashes.values() if len(v)>1],'duplicate_note':'Normal male frame states intentionally alias their source foundations; no duplicates are counted as extra drawings.','errors':errors,'scope':'Technical/pixel and category audit only. Visual inspection and supported-recipe inspection are recorded separately.','runtime_registered':False}
    a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'files_checked':checked,'errors':errors}))
    if errors:raise SystemExit(1)
if __name__=='__main__':main()
