"""Build opaque full-figure QA sheets and finalization specifications."""
from pathlib import Path
import argparse,json,subprocess,sys
from PIL import Image,ImageDraw,ImageFont

ROOT=Path('E:/Ai/ComfyUI-EroInc')
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--offset',type=int,default=0);p.add_argument('--count',type=int,default=4);p.add_argument('--target',type=Path);p.add_argument('--finalize-spec',type=Path);p.add_argument('--background',default='#eeeeec');p.add_argument('--exclude-id',action='append',default=[]);a=p.parse_args()
    idx=read(a.index);items=idx['items'];conf=read(Path(idx['config'])) if 'config' in idx else None
    if a.finalize_spec:
        lookup={i['id']:i for i in conf['items']};out=[]
        for item in items:
            if item['id'] in a.exclude_id:continue
            i=lookup[item['id']];image=ROOT/'input'/i['image'];guide=image.with_name('guide.png')
            sex='male' if i['id'].startswith('male') or i['rig'].startswith('male') else 'female'
            if i['category']=='anthro_species_by_sex':sex=i['id'].rsplit('_',1)[1]
            silhouette=i['category'] in ['male_external_anatomy','female_external_anatomy','nipple_areola_forms','female_body_hair','male_body_hair','muscle_definition','breast_shape']
            out.append({'id':item['id'],'source':item['source'],'guide':str(guide),'mask':str(ROOT/'input'/i['mask']),'neck_y':0 if i['category']=='anthro_species_by_sex' else (332 if sex=='male' else 343),'sex':sex,'category':i['category'],'silhouette_locked':silhouette,'match_skin':i['category']=='pregnancy_stages','retouch_shoulders':i['category']=='arm_pose_families','run':item['run']})
        a.finalize_spec.parent.mkdir(parents=True,exist_ok=True);a.finalize_spec.write_text(json.dumps({'items':out},indent=2)+'\n',encoding='utf-8');print(str(a.finalize_spec))
    if a.target:
        subset=items[a.offset:a.offset+a.count]
        if not subset:raise ValueError('No completed items in the requested review range')
        cols=min(4,len(subset));rows=(len(subset)+cols-1)//cols
        board=Image.new('RGB',(cols*304,rows*600),'#172536');d=ImageDraw.Draw(board);font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',16)
        for j,item in enumerate(subset):
            path=Path(item.get('files',{}).get('full',{}).get('path',item.get('source','')))
            im=Image.open(path).convert('RGBA');opaque=Image.new('RGBA',im.size,a.background);opaque.alpha_composite(im);opaque=opaque.convert('RGB');opaque.thumbnail((288,535),Image.Resampling.LANCZOS)
            x=(j%cols)*304;y=(j//cols)*600;board.paste(opaque,(x+(304-opaque.width)//2,y+35));d.text((x+5,y+5),item['id'],font=font,fill='white')
        a.target.parent.mkdir(parents=True,exist_ok=True);board.save(a.target);print(str(a.target))
if __name__=='__main__':main()
