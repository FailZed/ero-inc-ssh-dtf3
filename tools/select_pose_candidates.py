"""Resolve explicit curated pose candidates with accurate per-render lineage."""
from pathlib import Path
import argparse,json
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--selection',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();s=read(a.selection);items=[]
    for pick in s['items']:
        idx=read(pick['index']);cand=next(i for i in idx['items'] if i['id']==pick.get('candidate',pick['id']));conf=read(idx['config']);render=next(i for i in conf['items'] if i['id']==cand['id']);meta=render
        if pick.get('pose_index'):
            parent=read(pick['pose_index']);pose_conf=read(parent['config']);meta=next(i for i in pose_conf['items'] if i['id']==pick['id'])
        items.append({**cand,'id':pick['id'],'pose_metadata':meta,'render_metadata':render,'render_config':idx['config'],'acceptance':pick['acceptance'],'alpha_cleanup':pick.get('alpha_cleanup',[])})
    out={'config':items[0]['render_config'],'status':'raw_curated_requires_rgba_and_layer_review','items':items};a.target.parent.mkdir(parents=True,exist_ok=True);a.target.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(len(items))
if __name__=='__main__':main()
