"""Append visually reviewed pose studies to the existing gallery, preserving art.

Only the gallery document and a separate review folder change. The body pack
manifest, original drawings, runtime catalog and saves are never modified.
"""
from pathlib import Path
import argparse,hashlib,json,re,shutil

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--review',type=Path,required=True);p.add_argument('--pack',type=Path,required=True);p.add_argument('--version',required=True);a=p.parse_args();records=read(a.review)['items'];page=a.pack/'gallery.html';html=page.read_text(encoding='utf-8');pattern=r'(<script id="data" type="application/json">)(.*?)(</script>)';match=re.search(pattern,html,re.S)
    if not match:raise ValueError('Existing gallery payload was not found')
    payload=json.loads(match[2]);category='pose_review_'+a.version.replace('-','_');payload['items']=[i for i in payload['items'] if i['category']!=category];payload['labels'][category]='Позы · новый отбор';target=a.pack/'review'/('poses-'+a.version);target.mkdir(parents=True,exist_ok=True);published=[]
    for r in records:
        review=r['visual_review']
        if review['decision'] in ['pending','reject_content']:continue
        dest=target/r['id'];dest.mkdir(exist_ok=True);raw=Path(r['source']);full=Path(r['full']);shutil.copy2(raw,dest/'source.png');shutil.copy2(full,dest/'full.png');(dest/'record.json').write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');decision={'select':'Выбран для следующего этапа','candidate':'Проба · нужна доработка','reject':'Отклонён после просмотра'}[review['decision']]
        note=decision+'. '+review.get('note','')+' '+('Замечания: '+', '.join(review['issues'])+'.' if review.get('issues') else '')+' Цельный рисунок позы; RGBA — производный вырез. Это референс, не готовый многослойный персонаж.'
        item={'id':'pose_'+a.version+'_'+r['id'],'title':('Ж · ' if r['sex']=='female' else 'М · ')+r['title']+' · '+str(r['candidate_number']),'sex':r['sex'],'category':category,'kind':decision,'files':{'full':{'path':(dest/'full.png').relative_to(a.pack).as_posix(),'sha256':sha(full)}},'note':note,'recipe':{'pose':r['pose'],'candidate':r['candidate_number'],'decision':review['decision'],'issues':review.get('issues',[]),'original_render':(dest/'source.png').relative_to(a.pack).as_posix(),'source_body':r['rig'],'runtime_registered':False}};payload['items'].append(item);published.append(item)
    backup=page.with_name('gallery.before-'+a.version+'.html')
    if not backup.exists():shutil.copy2(page,backup)
    serialized=json.dumps(payload,ensure_ascii=False).replace('</','<\\/');html=html[:match.start(2)]+serialized+html[match.end(2):]
    html=html.replace(";render();\n</script>",";const requested=new URLSearchParams(location.search).get('category');if(requested&&[...$('category').options].some(o=>o.value===requested))$('category').value=requested;render();\n</script>")
    page.write_text(html,encoding='utf-8');(target/'index.json').write_text(json.dumps({'source_review':str(a.review),'items':published,'candidate_count':len(published),'game_registered':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'gallery':str(page),'category':category,'published':len(published)},ensure_ascii=False))
if __name__=='__main__':main()
