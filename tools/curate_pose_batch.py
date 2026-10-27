"""Record explicit visual choices after viewing a real whole-figure board."""
from pathlib import Path
import argparse,json,datetime
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--selection',type=Path,required=True);p.add_argument('--index',type=Path,required=True);p.add_argument('--board',type=Path,required=True);p.add_argument('--accept',nargs='*',default=[]);p.add_argument('--reject',nargs='*',default=[]);p.add_argument('--reason',required=True);p.add_argument('--replace',action='store_true');a=p.parse_args();s=read(a.selection);idx=read(a.index);byid={i['id']:i for i in idx['items']};selected={i['id']:i for i in s['items']}
    if not a.board.exists():raise ValueError('Actual review board required')
    for name in a.accept:
        if name not in byid:raise ValueError('Unknown candidate '+name)
        if name in selected and not a.replace:raise ValueError('Existing selection; use explicit --replace')
        selected[name]={'id':name,'index':str(a.index.resolve()),'review_board':str(a.board.resolve()),'acceptance':a.reason,'inspection':'Full-figure board; transparent/native layer review remains separate.'}
    s['items']=list(selected.values());s.setdefault('rejections',[])
    for name in a.reject:
        if name not in byid:raise ValueError('Unknown rejected candidate '+name)
        s['rejections'].append({'id':name,'index':str(a.index.resolve()),'board':str(a.board.resolve()),'reason':a.reason})
    s['status']='raw_curation_in_progress';s['updated_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat();a.selection.write_text(json.dumps(s,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'selected':len(s['items']),'rejected_records':len(s['rejections'])}))
if __name__=='__main__':main()
