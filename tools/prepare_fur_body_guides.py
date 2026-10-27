"""Original neutral adult anthropomorphic full-body guides, no donor pixels."""
from pathlib import Path
import json,argparse
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from prepare_body_pack_extensions import path
from derive_body_pack_assets import palette
ROOT=Path('E:/Ai/ComfyUI-EroInc');PROJECT=Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--target',type=Path,required=True);p.add_argument('--config',type=Path,required=True);a=p.parse_args()
    if a.target.exists():raise ValueError('Preserve old guides')
    a.target.mkdir(parents=True);c=json.loads((PROJECT/'docs/art/characters-v2/body-species-v1.json').read_text());c.pop('body_lora',None);c['items']=[];c['output_prefix']='characters_v2/body_species_v2';records=[]
    for species,color,cream in [('cat',(178,161,145),(235,222,210)),('fox',(197,125,76),(245,229,206)),('wolf',(148,160,173),(215,221,224))]:
        for sex in ['female','male']:
            source=ROOT/f'input/characters_v2/bases/{"male_toned" if sex=="male" else "female_average"}/full.png';original=Image.open(source).convert('RGBA');im=palette(original,color,sex);headcx=407 if sex=='male' else 448
            # Recolor the ventral coat while retaining the original cel contours.
            ventral=Image.new('L',im.size);d=ImageDraw.Draw(ventral);d.ellipse((headcx-79,355,headcx+79,715),fill=210);ventral=ventral.filter(ImageFilter.GaussianBlur(9))
            alt=palette(original,cream,sex);im=Image.composite(alt,im,ventral)
            tail=Image.new('RGBA',im.size);startx=480 if sex=='male' else 548
            path(tail,[('M',(startx,739)),('C',(startx+170,780,720,952,652,1045)),('C',(602,1088,567,1040,596,1012)),('C',(671,939,startx+103,809,startx-8,774)),('Z',())],color,'#74675f',1.8)
            whole=tail;whole.alpha_composite(im);im=whole
            if species=='fox':path(im,[('M',(652,1045)),('C',(616,1067,587,1048,594,1025)),('C',(613,1015,634,1016,665,1015)),('Z',())],cream)
            # Original ears and a small non-human muzzle establish a fur-covered
            # species guide before neural cleanup; not a costume or face mask.
            for side in [-1,1]:
                x=headcx+side*69
                path(im,[('M',(x-24,148)),('L',(x-18,65 if species!='wolf' else 55)),('L',(x+30,135)),('Z',())],color,'#74675f',1.8)
                path(im,[('M',(x-14,131)),('L',(x-12,84)),('L',(x+14,128)),('Z',())],'#bc9690')
            cy=265;path(im,[('M',(headcx-27,cy-9)),('C',(headcx-34,cy+13,headcx-15,cy+24,headcx,cy+18)),('C',(headcx+18,cy+26,headcx+35,cy+11,headcx+27,cy-9)),('C',(headcx+14,cy-21,headcx-13,cy-20,headcx-27,cy-9)),('Z',())],cream,'#9e8b7d',1.0)
            path(im,[('M',(headcx-8,cy-8)),('C',(headcx-4,cy-13,headcx+5,cy-13,headcx+9,cy-8)),('L',(headcx,cy)),('Z',())],'#705b56')
            path(im,[('M',(headcx,cy)),('L',(headcx,cy+8)),('C',(headcx-5,cy+14,headcx-9,cy+12,headcx-12,cy+10)),('M',(headcx,cy+8)),('C',(headcx+5,cy+14,headcx+9,cy+12,headcx+12,cy+10))],None,'#8a716a',1.0)
            name=species+'_'+sex;dest=a.target/name;dest.mkdir();im.save(dest/'guide.png');bg=Image.new('RGBA',im.size,'#eeeeec');bg.alpha_composite(im);bg.convert('RGB').save(dest/'reference.png')
            mask=Image.new('L',im.size);ImageDraw.Draw(mask).rectangle((100,35,775,1410),fill=255);mask=mask.filter(ImageFilter.GaussianBlur(8));mask.save(dest/'mask.png')
            rel=dest.relative_to(ROOT/'input').as_posix();male=sex=='male';subject='1boy, male focus, mature adult man, flat masculine chest, broad shoulders' if male else '1girl, mature adult woman, natural adult build'
            words=f'{subject}, age 30, original anthropomorphic {species} person, fully fur covered body, natural {species} muzzle and nose, animal ears, natural fur tail, upright biped, humanlike adult proportions, neutral full-body standing reference, relaxed bare arms at sides, same original brown hair and blue eyes, matte limited cel shading, thin brown contours, evenly lit, flat light gray background'
            c['items'].append({'id':name,'rig':sex+'_canonical','category':'anthro_species_by_sex','image':rel+'/reference.png','mask':rel+'/mask.png','prompt':'masterpiece, best quality, eincanime, '+words,'negative':c['negative']+', human skin, costume, mask, muzzle gag, collar, palette swatches, character sheet labels, extra tail'+(', breasts, female, girl, vagina' if male else ', male, beard'),'seed':9919000+len(c['items']),'denoise':.40,'preserve_input_latent':True})
            records.append({'id':name,'sex':sex,'source':str(source),'guide':str(dest/'guide.png'),'mask':str(dest/'mask.png'),'not_a_finished_asset':True})
    a.config.write_text(json.dumps(c,indent=2)+'\n');(a.target/'guides.json').write_text(json.dumps({'items':records},indent=2)+'\n')
    print('Prepared6 original full-figure fur guides')
if __name__=='__main__':main()
