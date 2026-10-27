"""Create a technical OpenPose control map (not a game illustration)."""
from pathlib import Path
from PIL import Image, ImageDraw
import argparse
import json
import math

ROOT = Path('E:/Ai/ComfyUI-EroInc')
POINTS = [(416,135),(416,245),(318,268),(284,480),(270,711),(514,268),(548,480),(562,711),
          (365,710),(356,973),(354,1210),(467,710),(476,973),(478,1210),
          (402,126),(430,126),(384,140),(448,140)]
LINKS = [(1,2),(1,5),(2,3),(3,4),(5,6),(6,7),(1,8),(8,9),(9,10),(1,11),(11,12),(12,13),
         (1,0),(0,14),(14,16),(0,15),(15,17)]
COLORS = [(255,0,0),(255,85,0),(255,170,0),(255,255,0),(170,255,0),(85,255,0),(0,255,0),
          (0,255,85),(0,255,170),(0,255,255),(0,170,255),(0,85,255),(0,0,255),(85,0,255),
          (170,0,255),(255,0,255),(255,0,170),(255,0,85)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--detail', action='store_true', help='Add a symmetric technical facial landmark map')
    args = parser.parse_args()
    canvas = Image.new('RGB', (832,1344), 'black')
    draw = ImageDraw.Draw(canvas)
    points = list(POINTS)
    if args.detail:
        points[14:] = [(390,113),(442,113),(361,135),(471,135)]
    padded_points = [(x,round(y*.88+70)) for x,y in points]
    for (start,end),color in zip(LINKS,COLORS):
        draw.line((padded_points[start],padded_points[end]), fill=tuple(round(c*.6) for c in color), width=24)
    for (x,y),color in zip(padded_points,COLORS):
        draw.ellipse((x-12,y-12,x+12,y+12),fill=color)
    face = []
    if args.detail:
        # Standard 68-point topology, drawn as small white points as in a
        # whole-body OpenPose control. These coordinates are technical guides.
        face += [(416+55*math.cos(math.pi-i*math.pi/16),125+65*math.sin(math.pi-i*math.pi/16)) for i in range(17)]
        face += [(377+i*7,99-4*math.sin(i*math.pi/4)) for i in range(5)]
        face += [(427+i*7,99-4*math.sin(i*math.pi/4)) for i in range(5)]
        face += [(416,111+i*9) for i in range(4)]
        face += [(400+i*8,144+4*math.sin(i*math.pi/4)) for i in range(5)]
        eye = [(-11,0),(-5,-4),(5,-4),(11,0),(5,4),(-5,4)]
        for cx in (390,442):
            face += [(cx+dx,113+dy) for dx,dy in eye]
        face += [(416+22*math.cos(i*math.pi/6),165+8*math.sin(i*math.pi/6)) for i in range(12)]
        face += [(416+13*math.cos(i*math.pi/4),165+3*math.sin(i*math.pi/4)) for i in range(8)]
        face = [(round(x),round(y*.88+70)) for x,y in face]
        for x,y in face:
            draw.ellipse((x-2,y-2,x+2,y+2),fill='white')
    folder = ROOT/'input/controls'
    folder.mkdir(parents=True,exist_ok=True)
    name = 'adult_front_idle_v2' if args.detail else 'adult_front_idle'
    canvas.save(folder/(name+'.png'))
    (folder/(name+'.json')).write_text(json.dumps({'size':[832,1344],'points':padded_points,'face':face,'links':LINKS,'source':'Original technical joint coordinates for EroInc; no donor images'},indent=2),encoding='utf-8')
    print(folder/(name+'.png'))


if __name__ == '__main__':
    main()
