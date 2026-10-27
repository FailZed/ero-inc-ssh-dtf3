"""Export reviewed anatomical candidates with shared head/body canvas and anchors.

Only uniform technical transforms and complementary alpha splits. It does not
invent hidden facial/hair layers or register the results in the running game.
"""
from pathlib import Path
import argparse,hashlib,json,sys
from PIL import Image,ImageDraw,ImageChops,PngImagePlugin
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--spec',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args()
    spec=art.read_json(a.spec)
    if a.target.exists():raise ValueError('Preserve existing pack; choose a new version.')
    sources=[Path(r['canonical']) for r in spec['rigs']]+[Path(i['source']) for r in spec['rigs'] for i in r['variants']]
    for path in sources:
        im=Image.open(path)
        if im.mode!='RGBA' or im.size!=(832,1472):raise ValueError('Every working layer must be RGBA 832x1472.')
    a.target.mkdir(parents=True)
    manifest={'schema':1,'status':'reviewed_anatomy_candidates_not_runtime_registered','runtime_ready':False,
        'canvas':[720,1280],'baseline_y':1244,'scope':'Two original adult identities, three anatomical body variants each. Head contains face and hair together; no claim of a complete character rig.',
        'adapter_sha256':spec['adapter_sha256'],'rigs':[]}
    for rig in spec['rigs']:
        canonical=Image.open(rig['canonical']).convert('RGBA');scale=1145/1300
        size=(round(832*scale),round(1472*scale));offset=((720-size[0])//2,1244-round(1395*scale))
        neck=round(rig['neck_y']*scale)+offset[1]
        def project(im):
            canvas=Image.new('RGBA',(720,1280));canvas.paste(im.resize(size,Image.Resampling.LANCZOS),offset);return canvas
        mask=Image.new('L',(720,1280));ImageDraw.Draw(mask).rectangle((0,0,719,neck-1),fill=255)
        canonical=project(canonical);head=canonical.copy();head.putalpha(ImageChops.multiply(head.getchannel('A'),mask))
        target=a.target/rig['id'];target.mkdir()
        head.save(target/'head.png')
        record={'id':rig['id'],'gender':rig['gender'],'body_build':rig['body_build'],'age':28,'morphology':'human',
            'head':'head.png','head_sha256':hashlib.sha256((target/'head.png').read_bytes()).hexdigest(),
            'head_source':rig['canonical'],'head_source_sha256':hashlib.sha256(Path(rig['canonical']).read_bytes()).hexdigest(),
            'head_scope':'combined head, face and hair; not independently customizable yet',
            'working_canvas':[832,1472],'export_canvas':[720,1280],'neck_y':neck,
            'uniform_transform':{'scale':scale,'size':size,'offset':offset},'variants':[]}
        for item in rig['variants']:
            source=Path(item['source']);original=Image.open(source);full=project(original.convert('RGBA'))
            body=full.copy();body.putalpha(ImageChops.multiply(body.getchannel('A'),ImageChops.invert(mask)))
            composite=Image.new('RGBA',full.size);composite.alpha_composite(body);composite.alpha_composite(head)
            bounds=composite.getchannel('A').point(lambda x:255 if x>=16 else 0).getbbox()
            if bounds[0]<16 or bounds[1]<16 or bounds[2]>704 or bounds[3]>1264:raise AssertionError('Insufficient figure margins.')
            assert not np.any(np.asarray(head.getchannel('A'))[neck:])
            assert not np.any(np.asarray(body.getchannel('A'))[:neck])
            lineage={'source':str(source.resolve()),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                'run':item['run'],'operation':'Shared uniform transform and complementary head/body split',
                'anatomical_variant':item['id'],'canvas':[720,1280],'baseline_y':1244}
            meta=PngImagePlugin.PngInfo()
            for k,v in original.info.items():
                if isinstance(v,str):meta.add_text(k,v)
            meta.add_text('ero_inc_anatomy_export',json.dumps(lineage))
            body_name='body_'+item['id']+'.png';preview_name='preview_'+item['id']+'.png'
            body.save(target/body_name,pnginfo=meta);composite.save(target/preview_name,pnginfo=meta)
            record['variants'].append({**lineage,'id':item['id'],'label':item['label'],'body':body_name,
                'body_sha256':hashlib.sha256((target/body_name).read_bytes()).hexdigest(),'preview':preview_name,
                'alpha_bounds':bounds,'technical_qa':'passed: shared canvas, complementary layers, full figure margins',
                'status':'candidate_needs_clothing_fit_and_final_visual_acceptance'})
        art.write_json(target/'rig.json',record);manifest['rigs'].append(record)
    art.write_json(a.target/'manifest.json',manifest)
    print(json.dumps({'path':str(a.target.resolve()),'bodies':sum(len(r['variants']) for r in manifest['rigs']),
        'shared_heads':len(manifest['rigs']),'canvas':manifest['canvas'],'runtime_ready':False}))


if __name__=='__main__':main()
