"""Technical pose variants: modest skeletal widths, same frontal stance and anchors."""
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw
sys.path.insert(0,str(Path(__file__).resolve().parent))
from prepare_character_pose import LINKS,COLORS

ROOT=Path('E:/Ai/ComfyUI-EroInc')
PROJECT=Path(__file__).resolve().parents[1]


def main():
    config=json.loads((PROJECT/'docs/art/characters-v1/local-profiles.json').read_text(encoding='utf-8'))
    target=ROOT/'input/controls/builds'
    target.mkdir(parents=True,exist_ok=True)
    for profile in config['profiles']:
        source=ROOT/'input/controls'/('adult_front_idle_v2.json' if profile['gender']=='female' else 'adult_front_idle.json')
        template=json.loads(source.read_text(encoding='utf-8'))
        points=[list(p) for p in template['points']]
        shape=profile['pose_shape']
        factors={2:shape['shoulders'],5:shape['shoulders'],3:(shape['shoulders']+shape['arms'])/2,
                 6:(shape['shoulders']+shape['arms'])/2,4:shape['arms'],7:shape['arms'],
                 8:shape['hips'],11:shape['hips'],9:(shape['hips']+1)/2,12:(shape['hips']+1)/2}
        for index,factor in factors.items(): points[index][0]=round(416+(points[index][0]-416)*factor)
        canvas=Image.new('RGB',tuple(template['size']),'black')
        draw=ImageDraw.Draw(canvas)
        for (start,end),color in zip(LINKS,COLORS):
            draw.line((tuple(points[start]),tuple(points[end])),fill=tuple(round(c*.6) for c in color),width=24)
        for (x,y),color in zip(points,COLORS): draw.ellipse((x-12,y-12,x+12,y+12),fill=color)
        for x,y in template.get('face',[]): draw.ellipse((x-2,y-2,x+2,y+2),fill='white')
        canvas.save(target/(profile['id']+'.png'))
        template.update(points=points,pose_shape=shape,profile=profile['id'],source='Original technical pose; no donor image or generated body deformation')
        (target/(profile['id']+'.json')).write_text(json.dumps(template,indent=2),encoding='utf-8')
    print('Prepared 16 original build-specific technical poses.')


if __name__=='__main__': main()
