"""Extract a contrast-colored generated garment as a candidate transparent layer.

Uses the actual local drawing, hue separation and a reviewed ROI. Technical
masking only; all colors/line art come from the generated PNG. No automatic approval.
"""
from pathlib import Path
import argparse,hashlib,json
from PIL import Image,ImageFilter,PngImagePlugin
import numpy as np
from scipy import ndimage


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('target',type=Path)
    p.add_argument('--hue',type=float,required=True,help='Hue degrees, 0..360');p.add_argument('--tolerance',type=float,default=35)
    p.add_argument('--roi',type=int,nargs=4,required=True);p.add_argument('--base',type=Path)
    a=p.parse_args()
    if a.target.exists():raise ValueError('Preserve existing layer; choose another name.')
    source=Image.open(a.source).convert('RGB');hsv=np.asarray(source.convert('HSV')).astype(np.float32)
    delta=np.abs(hsv[:,:,0]*(360/255)-a.hue);delta=np.minimum(delta,360-delta)
    color=(delta<=a.tolerance)&(hsv[:,:,1]>=35)
    x0,y0,x1,y1=a.roi;roi=np.zeros(color.shape,bool);roi[y0:y1,x0:x1]=True;color &=roi
    labels,count=ndimage.label(color);sizes=np.bincount(labels.ravel());sizes[0]=0
    keep=np.where(sizes>=max(64,sizes.max()*.005))[0];mask=np.isin(labels,keep)
    mask=ndimage.binary_closing(mask,iterations=2)
    mask=ndimage.binary_fill_holes(mask)
    rgb=np.asarray(source).astype(np.float32)
    near=ndimage.binary_dilation(mask,iterations=2)&roi
    contour=near&(hsv[:,:,2]<110)
    faint=near&(delta<=a.tolerance)&(hsv[:,:,1]>=5)
    mask=(mask|contour|faint)&roi
    inner=ndimage.binary_erosion(mask,iterations=2)
    if not inner.any():raise ValueError('No usable garment interior detected.')
    _,nearest=ndimage.distance_transform_edt(~inner,return_indices=True)
    ink=rgb[nearest[0],nearest[1]]
    backdrop=Image.new('RGBA',source.size,'#eeeeec')
    if a.base:backdrop.alpha_composite(Image.open(a.base).convert('RGBA'))
    background=np.asarray(backdrop.convert('RGB')).astype(np.float32)
    direction=ink-background
    coverage=np.clip(np.sum((rgb-background)*direction,axis=2)/np.maximum(np.sum(direction**2,axis=2),1),0,1)
    coverage[inner]=1;coverage[~mask]=0
    pixels=np.asarray(source.convert('RGBA')).copy()
    edge=mask&~inner&(coverage>.02)
    clean=(rgb-background*(1-coverage[:,:,None]))/np.maximum(coverage[:,:,None],.02)
    pixels[edge,:3]=np.clip(np.rint(clean[edge]),0,255).astype('uint8')
    pixels[:,:,3]=np.rint(coverage*255).astype('uint8')
    layer=Image.fromarray(pixels)
    record={'source':str(a.source.resolve()),'source_sha256':hashlib.sha256(a.source.read_bytes()).hexdigest(),
        'operation':'Hue mask, connected components, filled holes and contour; boundary RGB unmatted against the original body/neutral background, interior generated RGB retained',
        'hue':a.hue,'tolerance':a.tolerance,'roi':a.roi,'size':list(layer.size),'alpha_bounds':layer.getchannel('A').getbbox(),
        'status':'candidate_requires_visual_fit_review'}
    meta=PngImagePlugin.PngInfo()
    for k,v in Image.open(a.source).info.items():
        if isinstance(v,str):meta.add_text(k,v)
    meta.add_text('ero_inc_color_garment_extraction',json.dumps(record))
    a.target.parent.mkdir(parents=True,exist_ok=True);layer.save(a.target,pnginfo=meta)
    record['sha256']=hashlib.sha256(a.target.read_bytes()).hexdigest()
    if a.base:
        base=Image.open(a.base).convert('RGBA')
        if base.size!=layer.size:raise ValueError('Layer and body dimensions differ.')
        base.alpha_composite(layer);base.save(a.target.with_name(a.target.stem+'-composite.png'),pnginfo=meta)
    for color,name in [('#172536','dark'),('#faf8f5','light')]:
        bg=Image.new('RGBA',layer.size,color);bg.alpha_composite(layer);bg.convert('RGB').save(a.target.with_name(a.target.stem+'-'+name+'.jpg'))
    a.target.with_suffix('.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps(record),flush=True)


if __name__=='__main__':main()
