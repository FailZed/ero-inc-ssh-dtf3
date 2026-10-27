"""Check real masked outputs against their recorded inputs; does not judge art."""
from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
    data=art.read_json(a.index);results=[]
    for item in data['items']:
        run=art.read_json(Path(item['run']));graph=run['prompt']
        source=Path(item['source']);source_ok=hashlib.sha256(source.read_bytes()).hexdigest()==item['sha256']
        composite_id=item.get('output_map',{}).get('composite_node','13')
        if graph.get(composite_id,{}).get('class_type')!='ImageCompositeMasked':continue
        composite=graph[composite_id]['inputs']
        image_id=composite['destination'][0]
        mask_id=graph[composite['mask'][0]]['inputs']['image'][0]
        reference=art.ROOT/'input'/graph[image_id]['inputs']['image'];mask=art.ROOT/'input'/graph[mask_id]['inputs']['image']
        input_hashes={i['path']:i['sha256'] for i in run['input_images']}
        input_ok=all(hashlib.sha256(v.read_bytes()).hexdigest()==input_hashes[str(v.resolve())] for v in [reference,mask])
        before=np.asarray(Image.open(reference).convert('RGB'));after=np.asarray(Image.open(source).convert('RGB'))
        outside=np.asarray(Image.open(mask).convert('L'))==0
        difference=np.abs(before.astype(np.int16)-after.astype(np.int16));values=difference[outside]
        result={'id':item['id'],'size':list(Image.open(source).size),'source_hash_ok':source_ok,'input_hashes_ok':input_ok,
                'unchanged_pixel_count':int(outside.sum()),'max_outside_mask_delta':int(values.max()),
                'changed_pixels_outside_mask':int(np.any(values!=0,axis=1).sum()),'visual_review':'separate_required'}
        result['passed']=source_ok and input_ok and result['changed_pixels_outside_mask']==0
        results.append(result)
    report={'scope':'Pixel preservation, dimensions and lineage only; no anatomy, style or garment fit acceptance.',
            'passed':all(r['passed'] for r in results),'count':len(results),'items':results}
    art.write_json(a.report,report)
    print(json.dumps({'passed':report['passed'],'count':report['count'],'report':str(a.report)}))
    if not report['passed']:sys.exit(1)


if __name__=='__main__':main()
