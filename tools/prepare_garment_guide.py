"""Original technical color stencils for local garment generation, never final art."""
from pathlib import Path
import argparse,json,hashlib
from PIL import Image,ImageDraw,ImageFilter,ImageChops,PngImagePlugin


def grow(image,pixels):
    # Repeated 3x3 dilation is the same square footprint without Pillow's
    # quadratic 41x41 neighborhood cost on every working-canvas pixel.
    for _ in range(pixels):image=image.filter(ImageFilter.MaxFilter(3))
    return image


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base',type=Path,required=True);p.add_argument('--gender',choices=['female','male'],required=True)
    p.add_argument('--part',choices=['shirt_short','shirt_long','jacket','coat','trousers','shorts','skirt','dress','bra','briefs','boxers'],required=True)
    p.add_argument('--color',default='#617f9c');p.add_argument('--target',type=Path,required=True)
    a=p.parse_args()
    if a.target.exists():raise ValueError('Preserve existing guide; choose another target.')
    base=Image.open(a.base/'full.png').convert('RGBA');reference=Image.open(a.base/'reference.png').convert('RGB')
    if base.size!=(832,1472):raise ValueError('This calibrated guide requires the 832x1472 working rig.')
    female=a.gender=='female';shape=Image.new('L',base.size);draw=ImageDraw.Draw(shape)
    if a.part=='shirt_short':
        points=[(370,328),(335,329),(316,340),(293,494),(333,512),(347,498),(350,610),(328,658),(345,673),(532,673),(547,654),(523,599),(525,520),(545,501),(573,513),(589,496),(560,350),(545,336),(498,329)] if female else [(366,336),(282,342),(263,359),(228,510),(275,536),(300,520),(308,673),(317,702),(501,702),(519,673),(516,522),(535,539),(580,518),(549,363),(532,345),(443,336)]
        draw.polygon(points,fill=255)
    elif a.part in ('shirt_long','jacket','coat','dress'):
        limit={'shirt_long':746,'jacket':824,'coat':965,'dress':975}[a.part]
        extent=Image.new('L',base.size);ImageDraw.Draw(extent).rectangle((170,330 if female else 340,690,limit),fill=255)
        shape=grow(ImageChops.multiply(base.getchannel('A'),extent).point(lambda v:255 if v>100 else 0),11)
        if a.part in ('coat','dress'):
            ImageDraw.Draw(shape).polygon([(345 if female else 308,610),(552 if female else 525,610),(624 if female else 577,limit),(267 if female else 257,limit)],fill=255)
    elif a.part in ('trousers','shorts','boxers'):
        points=[(363,625),(533,625),(596,708),(598,820),(562,960),(557,1090),(526,1300),(462,1300),(479,1090),(474,995),(478,810),(449,741),(430,803),(402,901),(381,995),(330,1120),(296,1304),(232,1298),(266,1140),(270,1066),(314,968),(323,839),(328,740),(342,678)] if female else [(316,605),(512,605),(536,777),(538,960),(550,1120),(548,1304),(480,1304),(465,1100),(442,952),(418,770),(390,770),(378,951),(359,1110),(361,1310),(291,1310),(296,1100),(299,946),(293,785)]
        draw.polygon(points,fill=255)
        if a.part=='trousers':
            leg=Image.new('L',base.size);ImageDraw.Draw(leg).rectangle((160,850,690,1280),fill=255)
            shape=ImageChops.lighter(shape,grow(ImageChops.multiply(base.getchannel('A'),leg).point(lambda v:255 if v>100 else 0),12))
        else:
            extent=Image.new('L',base.size);ImageDraw.Draw(extent).rectangle((0,0,831,875 if a.part=='shorts' else 825),fill=255);shape=ImageChops.multiply(shape,extent)
    elif a.part=='skirt':draw.polygon([(354,625),(539,625),(600,975),(290,975)],fill=255)
    elif a.part=='bra':
        draw.polygon([(354,402),(540,402),(550,492),(345,492)],fill=255);draw.line([(362,337),(369,414)],fill=255,width=12);draw.line([(526,337),(530,412)],fill=255,width=12)
    elif a.part=='briefs':draw.polygon([(350,667),(578,667),(590,732),(462,779),(330,740)],fill=255)
    if a.part in ('shirt_short','shirt_long','jacket','dress'):
        ImageDraw.Draw(shape).polygon([(370,328),(437,367),(498,329)] if female else [(366,334),(403,367),(443,334)],fill=0)
    regions=json.loads((a.base/'protected-regions-v2.json').read_text())
    for poly in regions['hands']:ImageDraw.Draw(shape).polygon([tuple(v) for v in poly],fill=0)
    ImageDraw.Draw(shape).polygon([tuple(v) for v in regions['head']],fill=0)
    mask=grow(shape,20).filter(ImageFilter.GaussianBlur(4))
    for poly in regions['hands']:ImageDraw.Draw(mask).polygon([tuple(v) for v in poly],fill=0)
    ImageDraw.Draw(mask).polygon([tuple(v) for v in regions['head']],fill=0)
    guide=reference.copy();guide.paste(a.color,(0,0,*base.size),shape)
    record={'operation':'Original flat color stencil, technical generation input only','base':str(a.base.resolve()),
        'source_sha256':hashlib.sha256((a.base/'reference.png').read_bytes()).hexdigest(),
        'part':a.part,'color':a.color,'gender':a.gender,'size':list(base.size),'status':'guide_not_art'}
    meta=PngImagePlugin.PngInfo();meta.add_text('ero_inc_garment_guide',json.dumps(record))
    a.target.mkdir(parents=True);guide.save(a.target/'reference.png',pnginfo=meta);mask.save(a.target/'mask.png');shape.save(a.target/'shape.png')
    (a.target/'guide.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record),flush=True)


if __name__=='__main__':main()
