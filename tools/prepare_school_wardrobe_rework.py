"""Prepare authorized School garment-layer repaints with exact source geometry.

Garments only, no character nudity or scenes. All generated/training data is on
E:. Three paint strengths per garment, fifteen independent studies per series.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from prepare_pose_pack import ROOT,PROJECT,write

SELECTION=[
('female_dress_white','Ж · Белое платье','npc/new/clothes/everyday/medium_tits/everyday.png','white sleeveless fitted knee length dress, round neckline, matte white cotton fabric, subtle light steel blue fold shadows'),
('female_dress_two_tone','Ж · Двухцветное платье','npc/new/clothes/everyday/medium_tits/everyday1.png','sleeveless knee length dress, vertically divided black left half and white right half, round neckline, matte fabric, restrained cel fold shadows'),
('female_jeans','Ж · Брюки','npc/new/clothes/down_clothes/jeans.png','brown slim fitted denim trousers with pockets belt loops and rolled cuffs, matte brown fabric, restrained cel fold shadows'),
('male_suit','М · Костюм','npc/npc_m/type2/body_1/clothes/clothes1.png','black business suit jacket, white shirt and red necktie, one sleeve raised and bent, matte black fabric, clear simple lapels, restrained cel fold shadows'),
('male_shirt','М · Рубашка','npc/npc_m/type2/body_1/clothes/usually1.png','steel gray collared button up shirt with chest pocket, one sleeve raised, matte gray cotton, clear thin fold lines, restrained cel fold shadows')]
HAIR_SELECTION=[
('female_hair_short','Ж · Короткие волосы','npc/new/hair/base2/length1/front/1.png','front layer of short silver gray hair with bangs, isolated hairpiece, organized large strands, no face'),
('female_hair_long_front','Ж · Длинные волосы спереди','npc/new/hair/base2/length3/front/1.png','front layer of long silver gray hair with bangs, isolated hairpiece, organized large strands, no face'),
('female_hair_long_back','Ж · Длинные волосы сзади','npc/new/hair/base2/length3/back/1.png','back layer of long silver gray hair, isolated hairpiece, organized large strands, no face'),
('male_hair_short','М · Короткие волосы','npc/npc_m/hair/base1/length1/front/1.png','front layer of short silver gray masculine hair, isolated hairpiece, organized large strands, no face'),
('male_hair_long_back','М · Длинные волосы сзади','npc/npc_m/hair/base1/length3/back/1.png','back layer of long white masculine hair, isolated hairpiece, organized large strands, no face')]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version',required=True);p.add_argument('--family',choices=['wardrobe','hair'],default='wardrobe');a=p.parse_args();dest=ROOT/'input/school-rework'/a.version
    if dest.exists():raise ValueError('Use a fresh version; preserve previous inputs')
    dest.mkdir(parents=True);records=[];jobs=[];sheet=Image.new('RGB',(1500,550),'#101b29');d=ImageDraw.Draw(sheet)
    imported=json.loads((PROJECT/'docs/art/SCHOOL_TEMPORARY_ASSETS.json').read_text());sources={r['target']:r for r in imported['files']}
    for i,(ident,title,rel,subject) in enumerate(HAIR_SELECTION if a.family=='hair' else SELECTION):
        original=PROJECT/'assets/textures/portraits/prototype_school'/rel;entry=sources[rel]
        if sha(original)!=entry['sha256']:raise ValueError('Imported donor image changed: '+rel)
        image=Image.open(original).convert('RGBA');bounds=image.getchannel('A').getbbox();crop=[max(0,bounds[0]-32),max(0,bounds[1]-32),min(image.width,bounds[2]+32),min(image.height,bounds[3]+32)];width,height=crop[2]-crop[0],crop[3]-crop[1];scale=min(664/width,920/height);size=[round(width*scale),round(height*scale)];offset=[(768-size[0])//2,(1024-size[1])//2];local=Image.new('RGBA',(768,1024));local.alpha_composite(image.crop(crop).convert('RGBa').resize(size,Image.Resampling.LANCZOS).convert('RGBA'),offset)
        folder=dest/ident;folder.mkdir();image.save(folder/'source.png');local.save(folder/'local.png');bg=Image.new('RGBA',local.size,'#eeeeec');bg.alpha_composite(local);bg.convert('RGB').save(folder/'reference.png');local.getchannel('A').filter(ImageFilter.GaussianBlur(1)).save(folder/'mask.png');im=local.copy();im.thumbnail((290,490));preview=Image.new('RGBA',(300,500),'#101b29');preview.alpha_composite(im,((300-im.width)//2,0));sheet.paste(preview.convert('RGB'),(i*300,40));d.text((i*300+10,12),ident,fill='white')
        meta={'garment':ident,'asset_family':a.family,'title':title,'source_archive':imported['source'],'donor_path':entry['source'],'source':str(original),'source_sha256':entry['sha256'],'canvas':list(image.size),'source_bounds':bounds,'crop':crop,'local_size':size,'local_offset':offset,'scale':scale,'source_rgba':str(folder/'source.png'),'source_authorization':'User requested School image transfer and repaint on 2026-10-19.','source_kind':'School-derived repaint; not wholly original art.','geometry_policy':'Exact original native canvas, offset and alpha; repaint changes material RGB only.'}
        records.append(meta);input_rel=folder.relative_to(ROOT/'input').as_posix()
        for n,strength in enumerate([.18,.24,.30] if a.family=='hair' else [.28,.36,.44]):
            description='preserve exact hair layer structure, delicate thin colored outlines, matte gray colors, simple two tone cel shading, clean large hair strands' if a.family=='hair' else 'isolated garment layer on invisible mannequin, preserve exact garment construction and fold placement, delicate thin colored lineart, matte flat colors, simple controlled two tone cel shading'
            jobs.append({'id':ident+'_v'+str(n+1),'rig':ident,'category':a.family+'_repaint_candidate','title':title,'candidate_number':n+1,'image':input_rel+'/reference.png','mask':input_rel+'/mask.png','denoise':strength,'preserve_input_latent':True,'seed':981202610+len(jobs),'prompt':'eincanime, '+subject+', '+description+', clean anime sprite material, flat diffuse light, plain pale gray backdrop','negative':'person, head, face, skin, hands, feet, nude, naked, sexual, child, mannequin body, clothing rack, hanger, text, logo, watermark, 3d, glossy, shiny, photorealistic, heavy outlines, busy background, new ornaments, altered silhouette','authoring':meta})
    sheet.save(dest/'source-review.png');cfg={'schema':1,'mode':'masked_reference_edit','scope':'Fifteen '+a.family+'-only School-derived repaint studies. No explicit scenes or nude bodies. Geometry and original alpha must be preserved.','output_prefix':'school_rework/'+a.version,'width':768,'height':1024,'steps':16,'cfg':6,'sampler':'euler','scheduler':'normal','denoise':.36,'preserve_input_latent':True,'encode_individually':True,'lora':{'name':'EroInc/candidate_400.safetensors','sha256':'2da68309cba8e4613d0fbf8c15fb64d60fafc5bea3b9b5a791cca8cd3f225cb9','strength':.65},'negative':jobs[0]['negative'],'items':jobs};out=PROJECT/'docs/art/school-rework-v1'/(a.family+'-'+a.version+'.json');write(out,cfg);write(dest/'sources.json',{'items':records,'raw_is_school_derived':True});print(out)
if __name__=='__main__':main()
