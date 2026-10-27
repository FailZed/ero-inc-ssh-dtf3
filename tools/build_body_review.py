"""Arrange real body drafts for visual review; never retouch the generated art."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--item', action='append', required=True, help='Caption=absolute PNG path')
    parser.add_argument('--target', type=Path, required=True)
    parser.add_argument('--title', default='ТЕЛОСЛОЖЕНИЯ · ЛОКАЛЬНАЯ DaSiWa')
    parser.add_argument('--columns', type=int, default=4)
    parser.add_argument('--crop-alpha', action='store_true', help='Fill review cells with the body layer, omitting empty head space')
    parser.add_argument('--subtitle', default='Взрослые персонажи · полный рост · пробы перед разделением на слои')
    args = parser.parse_args()
    columns = min(args.columns, len(args.item))
    rows = (len(args.item)+columns-1)//columns
    width, height = columns*380+48, rows*744+154
    board = Image.new('RGB',(width,height),'#0e1825')
    draw = ImageDraw.Draw(board)
    title = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',26)
    label = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',19)
    small = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',15)
    draw.text((24,18),args.title,font=title,fill='#edf1f5')
    draw.text((24,58),args.subtitle,font=small,fill='#a5b7ca')
    for index,item in enumerate(args.item):
        caption,path = item.split('=',1)
        source = Path(path)
        figure = Image.open(source).convert('RGBA')
        if args.crop_alpha:
            figure=figure.crop(figure.getchannel('A').getbbox())
        figure.thumbnail((350,664),Image.Resampling.LANCZOS)
        x,y = 24+(index%columns)*380,100+(index//columns)*744
        draw.rectangle((x,y,x+364,y+724),fill='#172536',outline='#40576f',width=2)
        board.paste(figure,(x+(364-figure.width)//2,y+12),figure)
        draw.text((x+12,y+682),caption,font=label,fill='#dbe7f0')
    draw.text((24,height-30),'Исходные изображения сохранены. Это визуальная проверка, не готовый игровой каталог.',font=small,fill='#93a9bd')
    args.target.parent.mkdir(parents=True,exist_ok=True)
    board.save(args.target)
    print(args.target.resolve())


if __name__=='__main__':
    main()
