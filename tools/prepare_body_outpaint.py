"""Place our own ImageGen torso study on a full-body canvas for a local edit.

Only canvas/crop/alpha normalization. No anatomy is drawn by this preparation.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path('E:/Ai/ComfyUI-EroInc')
PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / 'assets/art_source/characters_v1/body_male_1.png'


def main():
    image = Image.open(SOURCE).convert('RGBA')
    cell_width, cell_height = image.width // 2, image.height // 2
    for index, name in enumerate(('slim', 'average', 'athletic', 'muscular')):
        column, row = index % 2, index // 2
        cell = image.crop((column * cell_width, row * cell_height, (column + 1) * cell_width, (row + 1) * cell_height))
        # Generated source has stray RGB at alpha 1-3/255. Keep visible art only.
        alpha = cell.getchannel('A').point(lambda value: value if value >= 8 else 0)
        cell.putalpha(alpha)
        bounds = alpha.getbbox()
        if bounds is None:
            raise ValueError('Empty source cell')
        cell = cell.crop(bounds)
        scaled = cell.resize((round(cell.width * 800 / cell.height), 800), Image.Resampling.LANCZOS)
        canvas = Image.new('RGB', (832, 1344), 'white')
        canvas.paste(scaled, ((832 - scaled.width) // 2, 180), scaled)
        mask = Image.new('L', canvas.size, 0)
        draw = ImageDraw.Draw(mask)
        draw.rectangle((0, 0, 831, 205), fill=255)
        draw.rectangle((0, 935, 831, 1343), fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(6))
        folder = ROOT / 'input/owned_bodies'
        folder.mkdir(parents=True, exist_ok=True)
        canvas.save(folder / f'male_{name}_canvas.png')
        mask.convert('RGB').save(folder / f'male_{name}_mask.png')
        print(f'Prepared owned body {name}: {bounds}, placed at y=180..980')


if __name__ == '__main__':
    main()
