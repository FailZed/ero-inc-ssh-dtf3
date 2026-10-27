"""Convert the user-supplied MDRG models into an attributed local Cubism study pack.

Only art/model data is imported. Game code, dialogue, saves and progression are
not imported. Run with the research Python environment containing UnityPy.
"""
from pathlib import Path
import argparse
import ctypes as C
import hashlib
import json
import re
import UnityPy
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator

PROJECT = Path(__file__).resolve().parents[1]
ART = Path('E:/Ai/ComfyUI-EroInc')


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


class Core:
    def __init__(self, path):
        self.dll = C.CDLL(str(path))
        functions = {'csmReviveMocInPlace':([C.c_void_p,C.c_uint],C.c_void_p),
            'csmGetSizeofModel':([C.c_void_p],C.c_uint),
            'csmInitializeModelInPlace':([C.c_void_p,C.c_void_p,C.c_uint],C.c_void_p),
            'csmUpdateModel':([C.c_void_p],None),
            'csmGetParameterCount':([C.c_void_p],C.c_int),
            'csmGetParameterIds':([C.c_void_p],C.POINTER(C.c_char_p)),
            'csmGetDrawableCount':([C.c_void_p],C.c_int),
            'csmGetDrawableIds':([C.c_void_p],C.POINTER(C.c_char_p)),
            'csmGetPartCount':([C.c_void_p],C.c_int),
            'csmGetPartIds':([C.c_void_p],C.POINTER(C.c_char_p))}
        for n in ['Minimum','Maximum','Default']:
            functions['csmGetParameter'+n+'Values']=([C.c_void_p],C.POINTER(C.c_float))
        for name,(args,ret) in functions.items():
            f=getattr(self.dll,name);f.argtypes=args;f.restype=ret

    def inspect(self, raw):
        moc_buf=C.create_string_buffer(len(raw)+64);moc_ptr=(C.addressof(moc_buf)+63)&~63
        C.memmove(moc_ptr,raw,len(raw));moc=self.dll.csmReviveMocInPlace(moc_ptr,len(raw))
        if not moc:raise ValueError('Cubism Core rejected model')
        size=self.dll.csmGetSizeofModel(moc);model_buf=C.create_string_buffer(size+16)
        model=self.dll.csmInitializeModelInPlace(moc,(C.addressof(model_buf)+15)&~15,size)
        if not model:raise ValueError('Cubism Core could not initialize model')
        ids=self.dll.csmGetParameterIds(model);n=self.dll.csmGetParameterCount(model)
        minimum=self.dll.csmGetParameterMinimumValues(model);maximum=self.dll.csmGetParameterMaximumValues(model)
        default=self.dll.csmGetParameterDefaultValues(model)
        params=[{'id':ids[i].decode(),'min':minimum[i],'max':maximum[i],'default':default[i]} for i in range(n)]
        count=self.dll.csmGetDrawableCount(model);meshes=self.dll.csmGetDrawableIds(model)
        part_count=self.dll.csmGetPartCount(model);parts=self.dll.csmGetPartIds(model)
        return params,[meshes[i].decode() for i in range(count)],[parts[i].decode() for i in range(part_count)]


def physics(rig):
    settings=[];types=['X','Y','Angle']
    for i,sub in enumerate(rig['SubRigs']):
        settings.append({'Id':'PhysicsSetting'+str(i+1),
            'Input':[{'Source':{'Target':'Parameter','Id':x['SourceId']},'Weight':x['Weight'],
                'Type':types[x['SourceComponent']],'Reflect':bool(x['IsInverted'])} for x in sub['Input']],
            'Output':[{'Destination':{'Target':'Parameter','Id':x['DestinationId']},
                'VertexIndex':x['ParticleIndex'],'Scale':x['AngleScale'] if x['SourceComponent']==2 else x['TranslationScale']['x' if x['SourceComponent']==0 else 'y'],
                'Weight':x['Weight'],'Type':types[x['SourceComponent']],'Reflect':bool(x['IsInverted'])} for x in sub['Output']],
            'Vertices':[{'Position':{'X':v['InitialPosition']['x'],'Y':v['InitialPosition']['y']},
                **{k:v[k] for k in ('Mobility','Delay','Acceleration','Radius')}} for v in sub['Particles']],
            'Normalization':sub['Normalization']})
    return {'Version':3,'Meta':{'PhysicsSettingCount':len(settings),
        'TotalInputCount':sum(len(s['Input']) for s in settings),
        'TotalOutputCount':sum(len(s['Output']) for s in settings),
        'VertexCount':sum(len(s['Vertices']) for s in settings),
        'EffectiveForces':{'Gravity':{'X':rig['Gravity']['x'],'Y':rig['Gravity']['y']},
            'Wind':{'X':rig['Wind']['x'],'Y':rig['Wind']['y']}},
        'PhysicsDictionary':[{'Id':s['Id'],'Name':r['Name']} for s,r in zip(settings,rig['SubRigs'])],
        'Fps':rig['Fps']},'PhysicsSettings':settings}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,default=Path('E:/factorial-omega-win-64'))
    p.add_argument('--metadata-dlls',type=Path,default=Path('E:/GoDot/.research/mdrg-0.97.12/metadata-dlls'))
    p.add_argument('--target',type=Path,default=PROJECT/'assets/characters/mdrg_study')
    args=p.parse_args();data=args.source/'My Dystopian Robot Girlfriend_Data';target=args.target.resolve()
    if not target.is_relative_to(PROJECT.resolve()):raise ValueError('Target must be inside EroInc')
    gen=TypeTreeGenerator('6000.3.8f1');gen.load_local_dll_folder(str(args.metadata_dlls))
    env=UnityPy.load(str(data/'resources.assets'));env.typetree_generator=gen
    objects={o.path_id:o for o in env.objects};gos={};transforms={};transform_by_go={};records=[];scripts={}
    for o in env.objects:
        if o.type.name=='GameObject':gos[o.path_id]=o.read().m_Name
        elif o.type.name in ('Transform','RectTransform'):
            d=o.read();transforms[o.path_id]={'go':d.m_GameObject.m_PathID,'children':[p.m_PathID for p in d.m_Children]}
            transform_by_go[d.m_GameObject.m_PathID]=o.path_id
    for o in env.objects:
        if o.type.name!='MonoBehaviour':continue
        try:
            h=o.parse_monobehaviour_head();key=(h.m_Script.m_FileID,h.m_Script.m_PathID)
            if key not in scripts:scripts[key]=h.m_Script.deref_parse_as_object().m_ClassName
            cls=scripts[key]
        except ValueError:continue
        if cls not in ['CubismMoc','CubismModel','CubismRenderer','CubismParameter','CubismPart','CubismPhysicsController']:continue
        records.append({'id':o.path_id,'go':h.m_GameObject.m_PathID,'class':cls,'name':h.m_Name,'data':o.read_typetree()})
    core=Core(data/'Plugins/x86_64/Live2DCubismCore.dll');catalog=[]
    names={'interaction_model':'Повседневная модель','shower':'Постановка · душ',
        'bot_doggy':'Постановка · ракурс 1','BlowJob_Scene':'Постановка · ракурс 2',
        'cowgirl':'Постановка · ракурс 3','bot_missionary':'Постановка · ракурс 4'}
    for model in [r for r in records if r['class']=='CubismModel']:
        name=gos[model['go']];ident=re.sub(r'[^a-z0-9_]+','_',name.lower());out=target/ident;out.mkdir(parents=True,exist_ok=True)
        pending=[transform_by_go[model['go']]];children=set()
        while pending:
            t=transforms[pending.pop()];children.add(t['go']);pending.extend(t['children'])
        members=[r for r in records if r['go'] in children]
        moc_id=model['data']['_moc']['m_PathID'];moc=next(r for r in records if r['id']==moc_id)
        raw=bytes(moc['data']['_bytes']);(out/(ident+'.moc3')).write_bytes(raw)
        parameters,drawables,parts=core.inspect(raw)
        textures={r['data']['_mainTexture']['m_PathID'] for r in members if r['class']=='CubismRenderer'}
        texture_files=[]
        for tid in sorted(textures,key=lambda t:objects[t].read().m_Name):
            texture=objects[tid].read();filename=texture.m_Name+'.png';texture.image.save(out/filename);texture_files.append(filename)
        rig=next(r['data']['_rig'] for r in members if r['class']=='CubismPhysicsController')
        write(out/(ident+'.physics3.json'),physics(rig))
        write(out/(ident+'.model3.json'),{'Version':3,'FileReferences':{'Moc':ident+'.moc3',
            'Textures':texture_files,'Physics':ident+'.physics3.json'},'Groups':[],'HitAreas':[]})
        uri='res://'+out.relative_to(PROJECT).as_posix()+'/'+ident+'.model3.json'
        write(out/'model.info.json',{'id':ident,'source_name':name,'parameters':parameters,'drawables':drawables,'parts':parts,
            'provenance':{'source':'My Dystopian Robot Girlfriend 0.97.12, Incontinent Cell',
            'purpose':'User-authorized local study; imported donor model, not original EroInc art',
            'source_game':str(args.source),'moc_sha256':hashlib.sha256(raw).hexdigest()}})
        catalog.append({'id':ident,'title':names[name],'model':uri,'info':uri.rsplit('/',1)[0]+'/model.info.json',
            'study_asset':True,'parameters':len(parameters),'drawables':len(drawables),'physics_chains':len(rig['SubRigs'])})
        print('MODEL_IMPORTED',ident,len(parameters),len(drawables),len(texture_files),flush=True)
    catalog.sort(key=lambda x:(x['id']!='interaction_model',x['id']))
    write(PROJECT/'data/characters/study_catalog.json',{'schema':1,'models':catalog})
    write(target/'provenance.json',{'source':'My Dystopian Robot Girlfriend 0.97.12','author':'Incontinent Cell',
        'authorization':'User explicitly requested use of installed MDRG models for local learning on 2026-10-27',
        'imported':'Compiled model data, texture atlases and model physics; no donor game code or dialogue',
        'source_resources_sha256':hashlib.sha256((data/'resources.assets').read_bytes()).hexdigest()})


if __name__=='__main__':main()
