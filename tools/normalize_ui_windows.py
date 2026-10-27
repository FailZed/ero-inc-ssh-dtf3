"""Normalize original ImageGen UI surfaces and record deterministic import metadata."""
from pathlib import Path
from PIL import Image
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/art_source/ui-windows-v2'
OUT = ROOT / 'assets/textures/ui/windows-v2'

def main():
    records = []
    for name in ['window_surface','room_floor','card_face']:
        source = SOURCE / (name+'.png')
        destination = OUT / (name+'.png')
        if name == 'card_face':
            pixels = Image.open(source).convert('RGBA')
            bounds = pixels.getchannel('A').point(lambda a:255 if a>245 else 0).getbbox()
            assert bounds
            pixels = pixels.crop(bounds)
            pixels.thumbnail((320,480),Image.Resampling.LANCZOS)
            pixels.save(destination)
        else:
            shutil.copy2(source,destination)
        pixels = Image.open(destination)
        records.append({'id':name,'file':name+'.png','size':pixels.size,
                        'sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
                        'bytes':destination.stat().st_size,'filter':'linear_mipmaps','repeat':False})
        imported = destination.with_suffix('.png.import')
        if imported.exists():
            text = imported.read_text(encoding='utf-8-sig').replace('mipmaps/generate=false','mipmaps/generate=true')
            imported.write_text(text,encoding='utf-8')
    (OUT/'manifest.json').write_text(json.dumps({'assets':records},indent=2)+'\n',encoding='utf-8')
    print(f'Normalized {len(records)} UI raster surfaces')

if __name__ == '__main__':
    main()
