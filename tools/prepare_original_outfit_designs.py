"""Original EroInc wardrobe designs on the approved own adult references.

No School garment pixels or cuts enter these generation inputs. School remains
a technical layer/fit reference only. Inputs are fully clothed neutral guides;
source bodies, heads and saves are never modified.
"""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFilter
from scipy import ndimage
from scipy.spatial import ConvexHull
from prepare_pose_pack import ROOT,PROJECT,write

LOOKS=[
('female_utility','female','Весна / осень · городской комплект','navy cropped utility jacket with asymmetric zip and two flat patch pockets, ivory high neck knit shirt, charcoal straight leg trousers, low black boots','spring_autumn'),
('female_wrap','female','Лето · платье с запахом','teal short sleeve wrap midi dress with asymmetric overlapping front and a narrow matching fabric belt, simple closed flat shoes','summer'),
('female_wool','female','Зима · шерстяное пальто','long navy double breasted wool coat with restrained copper buttons and wide lapels, cream scarf, dark straight trousers, black ankle boots','winter'),
('male_overshirt','male','Весна / осень · куртка-рубашка','slate gray overshirt jacket with contrast square patch pockets and rolled cuffs, ivory crew neck shirt, navy tapered cargo trousers, black low sneakers','spring_autumn'),
('male_parka','male','Зима · парка','forest green hooded winter parka with a diagonal chest zip and quilted inner facing, sand colored scarf, charcoal trousers, black lace up boots','winter')]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version',required=True);a=p.parse_args();dest=ROOT/'input/original-wardrobe'/a.version
    if dest.exists():raise ValueError('Use a new version; preserve previous source guides')
    dest.mkdir(parents=True);jobs=[];sources={};review=Image.new('RGB',(832,1472),'#101b29')
    for sex,ident in [('female','female_average'),('male','male_toned')]:
        folder=ROOT/'rig-authoring/v2'/ident;anchors=read(folder/'anchors.json');source=Path(anchors['source']);image=Image.open(source).convert('RGBA');pixels=np.array(image);pts=np.array(anchors['all_keypoints']);scores=np.array(anchors['all_scores']);yy,xx=np.mgrid[:image.height,:image.width]
        if sha(source)!=anchors['source_sha256']:raise ValueError('Approved own reference changed')
        head=(yy<330)&(pixels[:,:,3]>0);hands=np.zeros((image.height,image.width),bool)
        for start in [91,112]:
            points=pts[start:start+21][scores[start:start+21]>.3]
            if len(points)<4:raise ValueError('Missing own hand anchors')
            mask=Image.new('L',image.size);hull=ConvexHull(points);ImageDraw.Draw(mask).polygon([tuple(v) for v in points[hull.vertices]],fill=255);hand=ndimage.binary_dilation(np.array(mask)>0,iterations=8)&(pixels[:,:,3]>0);hands|=hand
        keep=head|hands;clothed=(pixels[:,:,3]>0)&~keep;pixels[clothed,:3]=[54,69,87];edge=clothed&~ndimage.binary_erosion(pixels[:,:,3]>0,iterations=1);pixels[edge,:3]=[32,43,57]
        guide=Image.fromarray(pixels);sub=dest/sex;sub.mkdir();guide.save(sub/'fully-clothed-guide.png');background=Image.new('RGBA',image.size,'#eeeeec');background.alpha_composite(guide);background.convert('RGB').save(sub/'reference.png');protect=Image.fromarray((keep*255).astype('uint8')).filter(ImageFilter.MaxFilter(5));mask=Image.fromarray(255-np.array(protect)).filter(ImageFilter.GaussianBlur(2));mask.save(sub/'mask.png');Image.fromarray((keep*255).astype('uint8')).save(sub/'protected.png')
        sources[sex]={'source':str(source),'source_sha256':sha(source),'protected_mask':str(sub/'protected.png'),'guide':str(sub/'fully-clothed-guide.png'),'canvas':list(image.size),'body_id':ident,'no_school_clothing_pixels':True};write(sub/'source.json',sources[sex])
    for ident,sex,title,design,season in LOOKS:
        folder=dest/sex;rel=folder.relative_to(ROOT/'input').as_posix();person='1girl, mature adult woman age 30, short brown bob, blue eyes' if sex=='female' else '1boy, male focus, mature adult man age 35, short brown hair, blue eyes'
        for n,denoise in enumerate([.68,.75,.82]):
            jobs.append({'id':ident+'_candidate_'+str(n+1),'rig':sources[sex]['body_id'],'sex':sex,'category':'original_outfit_design','outfit_id':ident,'title':title,'season':season,'candidate_number':n+1,'image':rel+'/reference.png','mask':rel+'/mask.png','denoise':denoise,'preserve_input_latent':True,'seed':2026110300+len(jobs),'prompt':design+', fully clothed, opaque fabric, '+person+', solo, standing front view, arms relaxed at sides, full body, eincanime, anime screencap, delicate thin warm brown outlines, matte colors, simple controlled peach cel shadows, flat diffuse light, original contemporary wardrobe design, no logos, plain light gray backdrop','negative':'nude, naked, nipples, genitals, lingerie, underwear, see through, cleavage, sexual, erotic, child, teen, school uniform, cosplay, glossy, plastic, 3d, photorealistic, thick black outlines, extra hands, extra arms, extra legs, missing limbs, deformed hands, text, logo, watermark, duplicate person, floating objects','authoring':sources[sex]})
    config={'schema':1,'mode':'masked_reference_edit','scope':'15 original fully clothed adult outfit designs. School garment images are not inputs. Reference faces and hands retained; new cut and silhouette require garment-layer extraction and fit review.','output_prefix':'original_wardrobe/'+a.version,'width':832,'height':1472,'steps':16,'cfg':6,'sampler':'euler','scheduler':'normal','denoise':.75,'preserve_input_latent':True,'encode_individually':True,'lora':{'name':'EroInc/candidate_400.safetensors','sha256':'2da68309cba8e4613d0fbf8c15fb64d60fafc5bea3b9b5a791cca8cd3f225cb9','strength':.65},'negative':jobs[0]['negative'],'items':jobs};out=PROJECT/'docs/art/original-wardrobe'/('designs-'+a.version+'.json');write(out,config);print(out)
if __name__=='__main__':main()
