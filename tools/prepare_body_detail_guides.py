"""Whole adult figure references and explicit masks for neutral body-detail sets.

All actual edits run through the pinned local DaSiWa workflow. Source images,
local proportion guides and rendered results are recorded as separate stages.
"""
from pathlib import Path
import argparse,json,hashlib
import numpy as np
from scipy.ndimage import map_coordinates
from PIL import Image,ImageDraw,ImageFilter,ImageChops
ROOT=Path('E:/Ai/ComfyUI-EroInc');PROJECT=Path(__file__).resolve().parents[1]


def deform(im,cases):
    rgba=np.asarray(im,dtype=float)/255;yy,xx=np.mgrid[:im.height,:im.width].astype(float);ix=xx.copy();iy=yy.copy()
    for cx,cy,rx,ry,sx,sy in cases:
        w=np.exp(-((xx-cx)/rx)**4-((yy-cy)/ry)**4)
        ix+=cx+(xx-cx)/(1+(sx-1)*w)-xx;iy+=cy+(yy-cy)/(1+(sy-1)*w)-yy
    pre=rgba.copy();pre[:,:,:3]*=pre[:,:,3:]
    out=np.stack([map_coordinates(pre[:,:,k],[iy,ix],order=1,mode='constant',cval=0) for k in range(4)],axis=2);out=np.clip(out,0,1);out[:,:,:3]/=np.maximum(out[:,:,3:],1/255)
    return Image.fromarray(np.clip(np.rint(out*255),0,255).astype('uint8'))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--target',type=Path,required=True);p.add_argument('--config',type=Path,required=True);a=p.parse_args()
    if a.target.exists():raise ValueError('Preserve prior guide version')
    a.target.mkdir(parents=True)
    c=json.loads((PROJECT/'docs/art/characters-v2/body-reference-v1.json').read_text(encoding='utf-8'));c.update(output_prefix='characters_v2/body_details_v1',preserve_input_latent=True,denoise=.8);c['items']=[]
    candidate=json.loads((ROOT/'training/ero-body-v1/ero_inc_body_v1/candidate.json').read_text(encoding='utf-8'))['adapter'];c['body_lora']={**candidate,'strength':.35}
    records=[]
    def add(name,sex,category,words,regions,seed,denoise=.8,warps=None,protect=None):
        source=ROOT/('input/characters_v2/bases/male_toned/full.png' if sex=='male' else 'input/characters_v2/bases/female_average/full.png')
        original=Image.open(source).convert('RGBA');im=deform(original,warps) if warps else original.copy()
        mask=Image.new('L',im.size);d=ImageDraw.Draw(mask)
        for kind,coords in regions:
            if kind=='ellipse':d.ellipse(coords,fill=255)
            elif kind=='polygon':d.polygon(coords,fill=255)
            else:d.rectangle(coords,fill=255)
        mask=mask.filter(ImageFilter.GaussianBlur(8))
        if protect:
            q=Image.new('L',im.size);painter=ImageDraw.Draw(q)
            for coords in protect:painter.ellipse(coords,fill=255)
            mask=ImageChops.subtract(mask,ImageChops.lighter(q,q.filter(ImageFilter.GaussianBlur(7))))
        folder=a.target/name;folder.mkdir();im.save(folder/'guide.png');mask.save(folder/'mask.png')
        flat=Image.new('RGBA',im.size,'#eeeeec');flat.alpha_composite(im);flat.convert('RGB').save(folder/'reference.png')
        subject='adult man, short brown hair, blue eyes' if sex=='male' else 'adult woman, short brown bob, blue eyes'
        prompt='masterpiece, best quality, eincanime, eincbody, original mature '+subject+', age 30, full body neutral nude anatomical figure, '+words+', same relaxed standing pose, delicate thin brown contours, pale warm skin, matte flat colors, light peach cel shadows, evenly lit, flat light gray background'
        rel=folder.relative_to(ROOT/'input').as_posix()
        c['items'].append({'id':name,'rig':sex+'_canonical','category':category,'image':rel+'/reference.png','mask':rel+'/mask.png','prompt':prompt,'negative':c['negative']+', jacket, coat, sleeves, fabric, clothes, gaping, sexualized expression','seed':seed,'denoise':denoise,'preserve_input_latent':True})
        records.append({'id':name,'sex':sex,'category':category,'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'guide':str(folder/'guide.png'),'mask':str(folder/'mask.png'),'description':words,'not_a_finished_asset':True})
    for size,(sx,sy,word) in enumerate([(.82,.83,'small natural resting proportions'),(1,1,'ordinary natural resting proportions'),(1,1.19,'moderately longer natural resting proportions'),(1.18,1.04,'moderately broader natural resting proportions')],1):
        for form,coverage in [('covered','natural foreskin, uncircumcised anatomy'),('uncovered','natural circumcised anatomy')]:
            add(f'male_external_{size}_{form}','male','male_external_anatomy','natural flaccid penis and natural scrotum, '+word+', '+coverage,[('ellipse',(338,635,477,815))],9891000+size*10+(form=='uncovered'),.86,[(403,728,48,64,sx,sy)])
    for j,words in enumerate(['subtle natural external female anatomy','natural external labia with modest folds','slightly asymmetric natural external female anatomy','natural fuller outer labia, modest anatomical contour'],1):
        add(f'female_external_{j}','female','female_external_anatomy',words,[('ellipse',(419,688,514,783))],9891200+j,.82)
    for j,(sx,sy,words) in enumerate([(.8,.8,'small naturally round areolae'),(1,1,'ordinary naturally round areolae'),(1.24,1.14,'naturally wider areolae'),(1.18,.84,'naturally horizontal oval areolae'),(.86,1.18,'naturally vertical oval areolae'),(.94,.95,'soft edged subtle natural areolae'),(1.1,.92,'slightly asymmetric natural areolae')],1):
        shifts=[(381,452,24,24,sx,sy),(525,452,24,24,1/sx if j==7 else sx,sy)]
        add(f'areola_form_{j}','female','nipple_areola_forms',words+', modest natural nipples',[('ellipse',(351,420,412,484)),('ellipse',(495,420,556,484))],9891400+j,.42,shifts)
    hairs=['sparse fine natural pubic hair','small natural triangular pubic hair patch','moderate natural triangular pubic hair patch','broader natural triangular pubic hair patch','short neatly trimmed natural pubic hair','soft oval natural pubic hair patch','narrow vertical natural pubic hair strip','moderate natural rounded rectangular pubic hair patch','soft diffuse natural pubic hair pattern','slightly asymmetric natural pubic hair pattern']
    for j,words in enumerate(hairs,1):
        add(f'female_hair_{j}','female','female_body_hair',words+', brown body hair, natural adult anatomy',[('polygon',[(395,644),(535,650),(486,737),(449,737)])],9891600+j,.83,protect=[(447,732,490,775)])
    for j,words in enumerate(['sparse natural male pubic hair','moderate natural male pubic hair','full neatly trimmed natural male pubic hair'],1):
        add(f'male_pubic_hair_{j}','male','male_body_hair',words+', brown body hair',[('polygon',[(322,611),(493,611),(451,704),(358,704)])],9891800+j,.83,protect=[(357,686,449,798)])
    for j,words in enumerate(['light natural male chest hair','moderate natural male chest hair'],1):
        add(f'male_chest_hair_{j}','male','male_body_hair',words+', brown body hair, natural nipples',[('ellipse',(291,365,526,507))],9891820+j,.82,protect=[(321,437,344,462),(463,436,486,461)])
    alpha=Image.open(ROOT/'input/characters_v2/bases/male_toned/full.png').getchannel('A')
    add('male_leg_hair','male','male_body_hair','natural sparse short brown leg hair',[('rectangle',(282,850,534,1260))],9891840,.8)
    for sex,levels in [('female',['subtle firm abdominal tone','moderately visible athletic abdominal definition','clearly defined balanced adult abdominal muscles']),('male',['subtle natural abdominal muscle definition','clearly defined balanced adult abdominal muscles'])]:
        for j,words in enumerate(levels,1):
            box=(365,494,548,668) if sex=='female' else (306,466,514,642)
            add(f'{sex}_tone_{j}',sex,'muscle_definition',words+', natural adult build',[('ellipse',box)],9891900+(sex=='male')*20+j,.8)
    a.config.write_text(json.dumps(c,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (a.target/'guides.json').write_text(json.dumps({'items':records,'accepted_drawings':0},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'guides':len(records),'config':str(a.config)}))


if __name__=='__main__':main()
