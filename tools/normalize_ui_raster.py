"""Normalize ImageGen source art; no painting or synthetic replacements."""
from pathlib import Path
from PIL import Image, ImageFilter, ImageDraw, ImageChops
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/art_source/ui-raster-v1'
OUT = ROOT / 'assets/textures/ui/raster-v1'

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    for entry in json.loads((SOURCE / 'provenance.json').read_text())['assets']:
        name = entry['id']
        path = SOURCE / entry['source']
        image = Image.open(path).convert('RGBA')
        original = image.size
        wallpaper = name.startswith('phone_wallpaper')
        if wallpaper:
            image.thumbnail((768, 1620), Image.Resampling.LANCZOS)
        else:
            mask = image.getchannel('A').point(lambda a: 255 if a > 16 else 0)
            if name.startswith('app_'):
                # Normalize adaptive icon plates: ignore isolated alpha specks,
                # preserve the generated symbol, enforce a shared circular edge.
                core = mask.filter(ImageFilter.MinFilter(9)).getbbox()
                assert core, name
                x0,y0,x1,y1 = core
                bounds = (max(0,x0-4),max(0,y0-4),min(image.width,x1+4),min(image.height,y1+4))
                image = image.crop(bounds)
                circle = Image.new('L',image.size)
                ImageDraw.Draw(circle).ellipse((0,0,image.width-1,image.height-1),fill=255)
                image.putalpha(ImageChops.multiply(image.getchannel('A'),circle))
                mask = image.getchannel('A')
            assert mask.getbbox(), name
            image = image.crop(mask.getbbox())
            if name in ('phone_body', 'journal_surface'):
                image.thumbnail((1600, 1200), Image.Resampling.LANCZOS)
            else:
                image.thumbnail((448, 448), Image.Resampling.LANCZOS)
                canvas = Image.new('RGBA', (512, 512))
                canvas.paste(image, ((512-image.width)//2, (512-image.height)//2))
                image = canvas
            assert image.getchannel('A').getextrema() == (0, 255), name
        destination = OUT / (name+'.png')
        image.save(destination, optimize=True)
        records.append({'id':name, 'source_size':original, 'runtime_size':image.size,
                        'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
                        'bytes':destination.stat().st_size, 'alpha':not wallpaper,
                        'filter':'linear_mipmaps', 'repeat':False})
    (OUT / 'manifest.json').write_text(json.dumps({'assets':records},indent=2)+'\n')
    print(f'Normalized {len(records)} ImageGen assets; {sum(v["bytes"] for v in records):,} bytes')

if __name__ == '__main__':
    main()
