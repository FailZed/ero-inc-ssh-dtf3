"""Normalize an actual RGBA figure and split complementary head/body layers."""
from pathlib import Path
import argparse,hashlib,json
from PIL import Image,PngImagePlugin,ImageDraw


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path);p.add_argument('target',type=Path)
    p.add_argument('--neck-y',type=int,required=True)
    p.add_argument('--hands',type=int,nargs=8,required=True,help='Two source hand rectangles')
    a=p.parse_args()
    if a.target.exists():raise ValueError('Preserve existing base; choose a new target.')
    source=Image.open(a.source).convert('RGBA');box=source.getchannel('A').point(lambda v:255 if v>=16 else 0).getbbox()
    scale=min(650/(box[2]-box[0]),1300/(box[3]-box[1]))
    figure=source.crop(box).resize((round((box[2]-box[0])*scale),round((box[3]-box[1])*scale)),Image.Resampling.LANCZOS)
    x=(832-figure.width)//2;y=1395-figure.height
    canvas=Image.new('RGBA',(832,1472));canvas.alpha_composite(figure,(x,y))
    def point(px,py):return [round(x+(px-box[0])*scale),round(y+(py-box[1])*scale)]
    neck=point(416,a.neck_y)[1]
    hands=[point(a.hands[i],a.hands[i+1])+point(a.hands[i+2],a.hands[i+3]) for i in (0,4)]
    info={'source':str(a.source.resolve()),'source_sha256':hashlib.sha256(a.source.read_bytes()).hexdigest(),
          'size':[832,1472],'source_bounds':box,'scale':scale,'offset':[x,y],'neck_y':neck,'hands':hands,'baseline_y':1395,
          'operation':'Uniform scale, shared canvas; complementary head/body split. No anatomy warping.'}
    meta=PngImagePlugin.PngInfo()
    for k,v in Image.open(a.source).info.items():
        if isinstance(v,str):meta.add_text(k,v)
    meta.add_text('ero_inc_base_normalization',json.dumps(info))
    a.target.mkdir(parents=True)
    canvas.save(a.target/'full.png',pnginfo=meta)
    for name,upper in [('head',True),('body',False)]:
        layer=canvas.copy();mask=Image.new('L',canvas.size);d=ImageDraw.Draw(mask)
        d.rectangle((0,0,831,neck-1) if upper else (0,neck,831,1471),fill=255)
        from PIL import ImageChops
        layer.putalpha(ImageChops.multiply(layer.getchannel('A'),mask));layer.save(a.target/(name+'.png'),pnginfo=meta)
    flat=Image.new('RGBA',canvas.size,'#eeeeec');flat.alpha_composite(canvas);flat.convert('RGB').save(a.target/'reference.png',pnginfo=meta)
    mask=Image.new('L',canvas.size);d=ImageDraw.Draw(mask);d.rectangle((90,neck,742,1460),fill=255)
    for rect in hands:d.rounded_rectangle((rect[0]-5,rect[1]-5,rect[2]+5,rect[3]+5),radius=12,fill=0)
    mask.save(a.target/'wardrobe-mask.png')
    (a.target/'base.json').write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(info),flush=True)


if __name__=='__main__':main()
