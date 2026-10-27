"""Local background removal and alpha QA, preserving the generated source file.

Run using E:/Ai/ComfyUI-EroInc/postprocess/Scripts/python.exe.
The explicitly selected BiRefNet model runs locally on CPU; no image uploads.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path('E:/Ai/ComfyUI-EroInc')
os.environ['REMBG_HOME'] = str(ROOT/'cache/rembg')
os.environ['XDG_CACHE_HOME'] = str(ROOT/'cache')
os.environ['NUMBA_CACHE_DIR'] = str(ROOT/'cache/numba')
os.environ['TEMP'] = str(ROOT/'temp')
os.environ['TMP'] = str(ROOT/'temp')
os.environ['OMP_NUM_THREADS'] = '4'
from PIL import Image, PngImagePlugin
from rembg import remove, new_session


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('target', type=Path)
    parser.add_argument('--model', choices=('birefnet-general-lite','birefnet-general'), default='birefnet-general-lite')
    parser.add_argument('--largest-component', action='store_true', help='Keep the main connected cutout; remove isolated background objects')
    args = parser.parse_args()
    if args.source.resolve() == args.target.resolve() or args.target.exists():
        raise ValueError('Target must be a new file; preserve original generated PNGs.')
    source = Image.open(args.source)
    session = new_session(args.model, providers=['CPUExecutionProvider'])
    result = remove(source, session=session, decontaminate=True).convert('RGBA')
    if args.largest_component:
        import numpy as np
        from scipy import ndimage
        alpha_array = np.asarray(result.getchannel('A'))
        components,count = ndimage.label(alpha_array >= 16, structure=np.ones((3,3)))
        if count:
            sizes = np.bincount(components.ravel())
            sizes[0] = 0
            keep = ndimage.binary_dilation(components == sizes.argmax(), iterations=2)
            result.putalpha(Image.fromarray((alpha_array * keep).astype('uint8')))
    meta = PngImagePlugin.PngInfo()
    for key,value in source.info.items():
        if isinstance(value,str):
            meta.add_text(key,value)
    source_hash = hashlib.sha256(args.source.read_bytes()).hexdigest()
    meta.add_text('ero_inc_postprocess',json.dumps({'operation':'local background removal','model':args.model,'source_sha256':source_hash}))
    args.target.parent.mkdir(parents=True,exist_ok=True)
    result.save(args.target,pnginfo=meta)
    alpha = result.getchannel('A')
    bounds = alpha.point(lambda v:255 if v>=16 else 0).getbbox()
    report = {'source':str(args.source.resolve()),'target':str(args.target.resolve()),'source_sha256':source_hash,
              'size':list(result.size),'alpha_bounds':bounds,'model':args.model,'provider':'CPUExecutionProvider',
              'largest_component_only':args.largest_component,
              'review':'DRAFT: full-body anatomy, style and seams still require visual inspection'}
    args.target.with_suffix('.qa.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2),flush=True)


if __name__ == '__main__':
    main()
