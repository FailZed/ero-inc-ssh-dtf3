"""Restart whole-figure, non-graphic pose studies for the approved gallery.

Five independent seed candidates per pose and adult character. The existing
gallery originals are read-only art-direction references. No generated sprite
is claimed to preserve their identity exactly until visual review.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from prepare_pose_pack import ROOT,PROJECT,write

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version',required=True);a=p.parse_args()
    pack=PROJECT/'assets/art_source/characters_v2/body_pack_v1';source_manifest=pack/'manifest.json';manifest=read(source_manifest);foundations={i['id']:i for i in manifest['items'] if i['category']=='body_build'}
    exact_sheet=PROJECT/'assets/art_source/characters_v2/anatomy_candidates_v1/manifest.json';sheet=read(exact_sheet);sheet_rigs={r['gender']:r for r in sheet['rigs']}
    folder=ROOT/'input/characters_v2'/('gallery_pose_'+a.version)
    if folder.exists():raise ValueError('Preserve immutable batches: choose a fresh version')
    folder.mkdir(parents=True);items=[]
    poses=[('wave','Приветствие','(waving:1.25), (raised hand:1.2), open palm beside head, bent elbow, other arm down, standing'),('present','Открытая ладонь','(palm up:1.25), presenting, bent elbow, other arm down, standing'),('seated','Сидя','(sitting:1.3), knees bent, hands on thighs, both feet on ground, front view')]
    for pose,title,action in poses:
        for sex,ident in [('female','female_average'),('male','male_toned')]:
            body=foundations[ident];sheet_rig=sheet_rigs[sex];variant=next(v for v in sheet_rig['variants'] if v['id']==('medium' if sex=='female' else 'average'));original=Path(variant['source']);digest=sha(original)
            if digest!=variant['source_sha256']:raise ValueError('Exact approved sheet source changed')
            ref=Image.open(original).convert('RGBA');pixels=np.array(ref);base=[250,228,210] if sex=='female' else [247,222,202]
            # The model receives a deliberately non-graphic source: intimate
            # surface details are blanked, not requested or added. Existing
            # gallery originals remain untouched.
            blank=Image.new('L',ref.size);bd=ImageDraw.Draw(blank)
            if sex=='female':
                for x,y in [(379,453),(528,453)]:bd.ellipse((x-22,y-22,x+22,y+22),fill=255)
                bd.ellipse((370,697,532,827),fill=255)
            else:bd.ellipse((350,700,470,850),fill=255)
            weight=np.array(blank.filter(ImageFilter.GaussianBlur(5)),float)/255;pixels[:,:,:3]=np.rint(pixels[:,:,:3]*(1-weight[:,:,None])+np.array(base)*weight[:,:,None]).astype('uint8')
            if sex=='male':
                yy,xx=np.mgrid[:pixels.shape[0],:pixels.shape[1]];gap=(yy>=770)&(yy<900)&(abs(xx-411)<np.minimum(27,np.maximum(0,(yy-770)*.7)));pixels[gap,3]=0
            ref=Image.fromarray(pixels);input_dir=folder/sex;input_dir.mkdir(exist_ok=True);ref.save(input_dir/'non-graphic-guide.png');bg=Image.new('RGBA',ref.size,'#ff00ff');bg.alpha_composite(ref);bg.convert('RGB').save(input_dir/'reference.png')
            # Protect only the actual source head. Protecting every pixel above
            # y=300 amputates a newly raised hand and creates a horizontal seam.
            head=np.array(ref.getchannel('A'));head[315:]=0;protect=Image.fromarray(head).filter(ImageFilter.MaxFilter(9));mask=Image.fromarray(255-np.array(protect));mask=mask.filter(ImageFilter.GaussianBlur(3));mask.save(input_dir/'mask.png');rel=input_dir.relative_to(ROOT/'input').as_posix()
            for n in range(5):
                ident_out=sex+'_'+pose+'_'+str(n+1).zfill(2)
                # Illustrious follows concise action tags more reliably than a
                # long anatomy inventory (which produced phantom shoulder hands).
                person='1girl, mature adult woman age 35, short light brown bob, blue eyes, balanced adult proportions' if sex=='female' else '1boy, male focus, mature adult man age 35, short brown hair, blue eyes, toned masculine body'
                prompt=action+', '+person+', solo, masterpiece, best quality, eincanime, anime screencap, original adult character base, neutral nonsexual pose study, nude, bare arms, smooth undetailed skin, no intimate details, full body, (delicate thin brown lineart:1.2), simple cel shading, matte warm colors, restrained peach shadows, (solid magenta background:1.3), anime sprite'
                negative='child, teen, young, sexual, erotic, nipples, areola, genitals, penis, vulva, pubic hair, intimate detail, internal organs, skeleton, anatomy chart, medical diagram, clothes, underwear, sleeves, extra arms, extra hands, hands on shoulders, disembodied hands, bad hands, fused fingers, extra fingers, huge hands, 3d, glossy, thick black outlines, text, watermark, scenery, cropped, multiple people'
                items.append({'id':ident_out,'rig':ident,'sex':sex,'category':'whole_pose_candidate','pose':pose,'title':title,'candidate_number':n+1,'prompt':prompt,'negative':negative,'seed':2026110100+len(items),'image':rel+'/reference.png','mask':rel+'/mask.png','denoise':[.60,.65,.70,.75,.80][n],'preserve_input_latent':True,'source_gallery':str(pack/'gallery.html'),'approved_sheet':str(exact_sheet),'approved_sheet_sha256':sha(exact_sheet),'art_direction_reference':str(original),'art_direction_reference_sha256':digest,'reference_role':'Non-graphic source edit derived from the exact user-approved anatomy sheet source; only actual head foreground protected; body redrawn without limb warping.','non_graphic':True,'curation':'unreviewed'})
    cfg={'schema':1,'mode':'masked_reference_edit','encode_individually':True,'preserve_input_latent':True,'scope':'Fresh whole-figure neutral non-graphic adult pose candidates for the existing EroInc gallery. No intimate details. Five independent candidates per pose/sex. Not runtime registered.','output_prefix':'characters_v2/gallery_pose_'+a.version,'width':832,'height':1472,'steps':16,'cfg':6,'sampler':'euler','scheduler':'normal','denoise':1.0,'lora':{'name':'EroInc/candidate_400.safetensors','sha256':'2da68309cba8e4613d0fbf8c15fb64d60fafc5bea3b9b5a791cca8cd3f225cb9','strength':.65},'source_manifest_sha256':sha(source_manifest),'negative':items[0]['negative'],'items':items,'review_requirements':['Natural hands and elbows at native size.','No intimate details.','Thin lines, matte colors, restrained cel shadows match approved gallery.','Complete feet and limbs, no clipping.','No borrowed School art.','Separate source drawings from alpha cutouts and combinations.']}
    target=PROJECT/'docs/art/characters-v2'/('gallery-pose-'+a.version+'.json');write(target,cfg);print(target)
if __name__=='__main__':main()
