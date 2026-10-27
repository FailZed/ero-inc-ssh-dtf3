"""Read-only image inventory of School's RPA and loose files.

No donor script is imported/executed. Only metadata is written on E:. A path
category is a routing proposal, never content approval or a finished asset.
"""
from pathlib import Path,PurePosixPath
import argparse,collections,hashlib,io,json,struct,zlib
from research_school import IndexReader

ART=Path('E:/Ai/ComfyUI-EroInc')
IMAGES={'.png','.jpg','.jpeg','.webp','.avif','.bmp','.dds'}
SEX_SCENES={'missionary_pos','sex_insi','doggy_style_new','group_sex','cowgirl','petting','69','masturbation','gay_sex','blowjob_new','female_with_female_sex','gay_minet','male_masturbate','touch_ass','pussy','sex','blowjob','doggy_style','h_pictures'}

def category(name):
    parts=PurePosixPath(name.lower()).parts
    if any(x in SEX_SCENES or 'masturb' in x for x in parts):return 'intimate_scene_excluded'
    if 'cg' in parts or name.lower().startswith('mods/h_'):return 'scene_manual_review'
    if any(x in parts for x in ['brassiere','pantsu','underwear']):return 'underwear_manual_review'
    if any('clothes' in x for x in parts) or 'sleeves' in parts:return 'clothing'
    if 'hair' in parts:return 'hair'
    if 'face' in parts or 'emotions' in parts:return 'face'
    if 'accessories' in parts:return 'accessory'
    if 'body' in parts or any(x.startswith('body_') for x in parts):return 'body_reference_manual_review'
    if 'gui' in parts:return 'interface'
    if 'backgrounds' in parts or 'loc' in parts or parts[0]=='location':return 'environment'
    if name.startswith('renpy/'):return 'engine_builtin_excluded'
    if 'screenshots' in parts:return 'mod_screenshot_excluded'
    return 'unclassified_manual_review'

def prefix(stream,chunks,key,size=32):
    result=bytearray()
    for chunk in chunks:
        pre=chunk[2] if len(chunk)>2 else b''
        if isinstance(pre,str):pre=pre.encode('latin-1')
        result.extend(pre[:size-len(result)])
        if len(result)>=size:break
        stream.seek(chunk[0]^key);result.extend(stream.read(min(chunk[1]^key,size-len(result))))
        if len(result)>=size:break
    return bytes(result)

def png_size(data):
    return list(struct.unpack('>II',data[16:24])) if data.startswith(b'\x89PNG\r\n\x1a\n') else None

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--donor',type=Path,default=Path('E:/GoDot/School-0.981-win'));p.add_argument('--target',type=Path,default=ART/'source-audit/school-rework-v1');a=p.parse_args();donor=a.donor.resolve();target=a.target.resolve()
    if not target.is_relative_to(ART.resolve()):raise ValueError('Audit data must stay under the E: art workspace')
    target.mkdir(parents=True,exist_ok=True);archive=donor/'game/archive.rpa';records=[];logical={}
    with archive.open('rb') as stream:
        header=stream.readline().split()
        if header[0]!=b'RPA-3.0':raise ValueError('Expected RPA-3.0')
        index_at=int(header[1],16);key=int(header[2],16);stream.seek(index_at);packed=stream.read();index=IndexReader(io.BytesIO(zlib.decompress(packed))).load()
        for raw_name,chunks in sorted(index.items()):
            name=raw_name.decode('utf-8') if isinstance(raw_name,bytes) else raw_name
            if Path(name).suffix.lower() not in IMAGES:continue
            rel=PurePosixPath(name)
            if rel.is_absolute() or '..' in rel.parts or ':' in name or '\\' in name:raise ValueError('Unsafe archive path')
            rec={'id':hashlib.sha256(('rpa:'+name).encode()).hexdigest()[:20],'origin':'archive','source':name,'logical_path':name,'bytes':sum((c[1]^key)+len(c[2] if len(c)>2 else b'') for c in chunks),'canvas':png_size(prefix(stream,chunks,key)),'category':category(name),'state':'not_transferred','content_review':'not_reviewed'};records.append(rec);logical.setdefault(name,[]).append(rec['id'])
    for path in sorted(donor.rglob('*')):
        if not path.is_file() or path.suffix.lower() not in IMAGES:continue
        name=path.relative_to(donor).as_posix();logical_name=name
        if name.startswith('game/npc_data/0.50/character/'):logical_name='images/character/'+name.split('/character/',1)[1]
        with path.open('rb') as f:head=f.read(32)
        rec={'id':hashlib.sha256(('loose:'+name).encode()).hexdigest()[:20],'origin':'loose','source':name,'logical_path':logical_name,'bytes':path.stat().st_size,'canvas':png_size(head),'category':category(logical_name),'state':'not_transferred','content_review':'not_reviewed'};records.append(rec);logical.setdefault(logical_name,[]).append(rec['id'])
    counts=collections.Counter(r['category'] for r in records);summary={'schema':1,'donor':str(donor),'archive':{'path':str(archive),'bytes':archive.stat().st_size,'index_sha256':hashlib.sha256(packed).hexdigest()},'images':len(records),'archive_images':sum(r['origin']=='archive' for r in records),'loose_images':sum(r['origin']=='loose' for r in records),'logical_paths':len(logical),'logical_overlaps':sum(len(v)>1 for v in logical.values()),'categories':dict(counts),'routing_not_content_approval':True,'donor_scripts_executed':False,'donor_unchanged':True,'provenance':'School-derived material. A repaint is not labelled as wholly original EroInc art.','scope_exclusion':'Explicit sexual scenes are excluded from generation; ambiguous scene/body files require manual review.'}
    (target/'inventory.json').write_text(json.dumps({**summary,'items':records},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');(target/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(summary,ensure_ascii=False))
if __name__=='__main__':main()
