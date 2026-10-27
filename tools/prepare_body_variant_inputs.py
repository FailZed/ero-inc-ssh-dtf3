"""Register owned body references and technical masks/pose controls on E:."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from PIL import Image,ImageDraw,ImageFilter
from prepare_character_pose import LINKS,COLORS

ROOT=Path('E:/Ai/ComfyUI-EroInc')
PROJECT=Path(__file__).resolve().parents[1]


def pose(points,path,size=(720,1280)):
    image=Image.new('RGB',size,'black')
    draw=ImageDraw.Draw(image)
    for (start,end),color in zip(LINKS,COLORS):
        draw.line((points[start],points[end]),fill=tuple(round(c*.6) for c in color),width=24)
    for (x,y),color in zip(points,COLORS):
        draw.ellipse((x-12,y-12,x+12,y+12),fill=color)
    image.save(path)


def main():
    folder=ROOT/'input/body_variants'
    folder.mkdir(parents=True,exist_ok=True)
    source=Image.open(PROJECT/'assets/art_source/characters_v1/male_full_a.png').convert('RGBA')
    for index,name in enumerate(('slim','average','athletic','muscular')):
        x,y=index%2*512,index//2*768
        cell=source.crop((x,y,x+512,y+768))
        cell.putalpha(cell.getchannel('A').point(lambda a:0 if a<8 else 255 if a>248 else a))
        bounds=cell.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox()
        cropped=cell.crop(bounds)
        cropped=cropped.resize((round(cropped.width*980/cropped.height),980),Image.Resampling.LANCZOS)
        canvas=Image.new('RGB',(720,1280),'#ededed')
        canvas.paste(cropped,((720-cropped.width)//2,250),cropped)
        canvas.save(folder/f'male_{name}.png')
        print(f'Placed male {name}: source {bounds}, size {cropped.size}')
    mask=Image.new('L',(720,1280),0)
    ImageDraw.Draw(mask).rectangle((70,280,650,1150),fill=255)
    mask.filter(ImageFilter.GaussianBlur(8)).convert('RGB').save(folder/'male_mask.png')
    male=[(360,130),(360,270),(275,305),(240,510),(230,760),(445,305),(480,510),(490,760),
          (308,690),(305,955),(305,1190),(412,690),(415,955),(415,1190),(345,120),(375,120),(325,138),(395,138)]
    female=[(400,176),(388,262),(302,280),(277,474),(266,656),(492,284),(526,475),(533,657),
            (340,594),(370,900),(397,1152),(454,594),(420,900),(431,1197),(390,165),(426,165),(366,175),(444,175)]
    pose(male,folder/'male_pose.png')
    pose(female,folder/'female_pose.png')


if __name__=='__main__':main()
