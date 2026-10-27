"""Render real fit proofs that exercise every anatomical family and pose."""
from pathlib import Path
import argparse,json,time,hashlib
import numpy as np
from PIL import Image,PngImagePlugin
from scipy.ndimage import label
from compose_body_pack import compose,PALETTES

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--pack',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();m=json.loads((a.pack/'manifest.json').read_text());a.target.mkdir(parents=True,exist_ok=True);records=[];errors=[];start=time.time()
    fem=[i['id'] for i in m['items'] if i['category']=='body_build' and i['sex']=='female'];male=[i['id'] for i in m['items'] if i['category']=='body_build' and i['sex']=='male'];chests=[i['id'] for i in m['items'] if i['category']=='breast_shape'];poses=[None,'left_open','right_open','both_open','left_in','right_in','both_in','left_wide','right_wide'];palettes=list(PALETTES);jobs=[]
    for j,chest in enumerate(chests):
        features=[chest,'areola_form_'+str(j%7+1),'female_external_'+str(j%4+1),'female_hair_'+str(j%10+1)]
        if j%3==0:features.append('female_tone_'+str((j//3)%3+1))
        if j%4==0:features.append('female_thigh_'+('full' if j%8==0 else 'slender'))
        if j%4==1:features.append('female_calf_'+('full' if j%8==1 else 'slender'))
        jobs.append((f'female_fit_{j+1:02d}',fem[j%len(fem)],features,poses[j%9],palettes[j%8],'normal'))
    external=[i['id'] for i in m['items'] if i['category']=='male_external_anatomy']
    for j in range(9):jobs.append((f'male_fit_{j+1:02d}',male[j%8],[external[j%8],'male_hair_'+str(j%6+1),'male_tone_'+str(j%3)],poses[j],palettes[j%8],['normal','compact','tall','long_leg'][j%4]))
    for j in range(9):jobs.append((f'pregnancy_fit_{j+1:02d}','female_average',[f'pregnancy_stage_{j+1:02d}','areola_form_'+str(j%7+1),'female_external_'+str(j%4+1)],None,palettes[j%8],'normal'))
    for n,(ident,body,features,pose,pal,fr) in enumerate(jobs):
        image,recipe=compose(a.pack,m,body,features,pose,pal,fr);arr=np.asarray(image);fg=arr[:,:,3]>=32;ys,xs=np.where(fg);components,num=label(fg);sizes=np.bincount(components.ravel())[1:];large=sorted([int(s) for s in sizes if s>500],reverse=True)
        passed=len(xs)>0 and xs.min()>16 and xs.max()<816 and ys.min()>16 and ys.max()<1456 and len(large)==1
        file=a.target/(ident+'.png');meta=PngImagePlugin.PngInfo();meta.add_text('ero_inc_body_recipe',json.dumps(recipe));image.save(file,pnginfo=meta)
        record={'id':ident,'source':str(file),'recipe':recipe,'large_foreground_components':large,'alpha_bounds':[int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)],'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'technical_passed':passed,'visual_review':'required separately; native proof is the actual composed file'};records.append(record)
        if not passed:errors.append(ident)
        if (n+1)%4==0:print(f'Composed {n+1}/{len(jobs)}; {time.time()-start:.1f}s; failed={errors}',flush=True)
    # Compare the actual same-frame pregnancy silhouettes, not just names/seeds.
    values=[]
    for item in sorted([i for i in m['items'] if i['category']=='pregnancy_stages'],key=lambda i:i['id']):
        alpha=np.asarray(Image.open(a.pack/item['files']['full']['path']))[:,:,3]/255;values.append({'id':item['id'],'abdominal_alpha_area':round(float(alpha[550:715,320:615].sum()),2)})
    progression=all(b['abdominal_alpha_area']>a['abdominal_alpha_area'] for a,b in zip(values,values[1:]))
    if not progression:errors.append('pregnancy progression must increase')
    report={'passed':not errors,'count':len(records),'errors':errors,'items':records,'pregnancy_progression':values,'pregnancy_progression_increasing':progression,'scope':'Real composed fit proofs; components and bounds checked. Requires separate visual inspection. These are combinations, not new source drawings.'};(a.target/'index.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'count':len(records),'seconds':time.time()-start,'errors':errors}))
    if errors:raise SystemExit(1)
if __name__=='__main__':main()
