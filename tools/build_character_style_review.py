"""Arrange actual generated PNGs for art review. Does not draw or retouch characters."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT/'assets/art_source/characters_v1/color_studies'
TARGET = PROJECT/'docs/art/characters-v1/previews/female_color_studies.png'


def main():
    board = Image.new('RGB',(1440,1460),'#0e1825')
    draw = ImageDraw.Draw(board)
    title = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',34)
    label = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',23)
    small = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',18)
    draw.text((44,24),'ЦВЕТНЫЕ ОСНОВЫ · 2D-АНИМЕ',font=title,fill='#edf1f5')
    draw.text((45,75),'Рабочие референсы в полный рост · локальная DaSiWa',font=small,fill='#a5b7ca')
    for column,(file_name,caption) in enumerate((('female_reference_13.png','Каштановые волосы · бирюзовые глаза'),('female_reference_20.png','Светлые волосы · янтарные глаза'))):
        x=36+column*702
        draw.rectangle((x,118,x+666,1390),fill='#172536',outline='#40576f',width=2)
        draw.rectangle((x+1,119,x+665,123),fill='#be8654')
        figure=Image.open(SOURCE/file_name).convert('RGBA')
        figure.thumbnail((640,1190),Image.Resampling.LANCZOS)
        board.paste(figure,(x+(666-figure.width)//2,134),figure)
        draw.text((x+22,1344),caption,font=label,fill='#dbe7f0')
    draw.text((44,1414),'Референсы по переданным рисункам. Разделение на игровые слои ещё предстоит.',font=small,fill='#93a9bd')
    TARGET.parent.mkdir(parents=True,exist_ok=True)
    board.save(TARGET)
    print(TARGET)


if __name__=='__main__':
    main()
