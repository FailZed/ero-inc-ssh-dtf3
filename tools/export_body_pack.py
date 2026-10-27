"""Export curated local body art separately from the game and its save data."""
from pathlib import Path
import argparse,json,hashlib,shutil,collections
import numpy as np
from PIL import Image,ImageDraw,ImageFilter,PngImagePlugin
from derive_body_pack_assets import split_parts,frame,palette,PALETTES
from prepare_reference_body_guides import make_guide
from compose_body_pack import blend,register_neck,shoulder_joints
from body_torso_layers import chest_core

def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--selection',type=Path,required=True);p.add_argument('--target',type=Path,required=True);a=p.parse_args();sel=read(a.selection);a.target.mkdir(parents=True,exist_ok=True)
    records=[];sources={};specs=[];profiles={i['id']:i for i in read(sel['build_guides'])['items']}
    for group in sel['groups']:
        path=Path(group['processed_index'])
        if not path.exists():raise ValueError('Missing processed family: '+str(path))
        for item in read(path)['items']:
            if group.get('categories') and item['category'] not in group['categories']:continue
            if group.get('ids') and item['id'] not in group['ids']:continue
            if group.get('exclude_prefixes') and any(item['id'].startswith(s) for s in group['exclude_prefixes']):continue
            item={**item}
            if 'sex' not in item:item['sex']='male' if item['id'].startswith('male') or item.get('rig','').startswith('male') else 'female'
            if group.get('rename',{}).get(item['id']):item['original_id']=item['id'];item['id']=group['rename'][item['id']]
            if group.get('category_override'):item['category']=group['category_override']
            if item['id'] in sources:raise ValueError('Duplicate curated asset '+item['id'])
            sources[item['id']]=item;specs.append(item)
    def save(im,p,record):
        p.parent.mkdir(parents=True,exist_ok=True);arr=np.array(im.convert('RGBA'));arr[arr[:,:,3]==0,:3]=0;im=Image.fromarray(arr)
        meta=PngImagePlugin.PngInfo();meta.add_text('ero_inc_pack',json.dumps(record));im.save(p,pnginfo=meta)
        return {'path':p.relative_to(a.target).as_posix(),'sha256':sha(p)}
    def provenance(item):
        run=Path(item['run']);dest=a.target/'provenance'/'runs'/run.name;dest.parent.mkdir(parents=True,exist_ok=True)
        if not dest.exists():shutil.copy2(run,dest)
        return {'processed_sha256':item['files']['full']['sha256'],'original_render_sha256':item['source_sha256'],'run':dest.relative_to(a.target).as_posix(),'guide_sha256':item['guide_sha256'],'mask_sha256':item['mask_sha256']}
    def store_parts(im,folder,neck,record):
        files={'full':save(im,folder/'full.png',record)}
        head=im.copy();body=im.copy();ha=head.getchannel('A');ba=body.getchannel('A');ImageDraw.Draw(ha).rectangle((0,neck,831,1471),fill=0);ImageDraw.Draw(ba).rectangle((0,0,831,neck-1),fill=0);head.putalpha(ha);body.putalpha(ba)
        files['head']=save(head,folder/'head.png',record);files['body']=save(body,folder/'body.png',record)
        joined=Image.new('RGBA',im.size);joined.alpha_composite(body);joined.alpha_composite(head)
        va=np.asarray(im)[:,:,3]>0
        assert np.array_equal(np.asarray(joined)[va],np.asarray(im)[va])
        return files
    default=sources['male_external_2_uncovered'];default_im=Image.open(default['files']['full']['path']).convert('RGBA');default_mask=Image.open(default['mask']).convert('L')
    fdefault=sources['female_external_1'];fdefault_im=Image.open(fdefault['files']['full']['path']).convert('RGBA');fdefault_mask=Image.open(fdefault['mask']).convert('L')
    foundations={}
    for item in specs:
        ident=item['id'];sex=item['sex'];category=item['category'];source=Path(item['files']['full']['path']);assert sha(source)==item['files']['full']['sha256']
        im=Image.open(source).convert('RGBA');neck=332 if sex=='male' else 343
        rec={'id':ident,'sex':sex,'category':category,'kind':'reference_reuse' if item.get('original_id') else 'local_rendered_reference_edit','canvas':[832,1472],'baseline_y':1395,'neck_y':neck,'provenance':provenance(item),'runtime_registered':False}
        if category=='body_build':
            if sex=='male':
                alpha=im.getchannel('A');im=Image.composite(default_im,im,default_mask);im.putalpha(alpha);rec['default_anatomy']='male_external_2_uncovered'
            else:
                prof=profiles[ident];ref=make_guide(fdefault_im,prof['widths'],prof['center']);q=Image.new('RGBA',im.size,(255,255,255,0));q.putalpha(fdefault_mask);mask=make_guide(q,prof['widths'],prof['center']).getchannel('A');im=blend(im,ref,mask);rec['default_anatomy']='female_external_1'
            foundations[ident]=im.copy();folder=a.target/'foundations'/ident;rec['files']=store_parts(im,folder,neck,rec)
            for label,part in split_parts(im,neck,407 if sex=='male' else 448).items():rec['files'][label]=save(part,folder/(label+'.png'),rec)
            rec['parts_reassemble_exactly']=True;rec['part_usage']='Disjoint registered slices. Change pose through the matching complete pose state, not by rotating these ownership slices.'
        else:
            folder=a.target/'modules'/category/ident;rec['files']=store_parts(im,folder,neck,rec)
            mask=Image.open(item['mask']).convert('L');maskpath=folder/'replace-mask.png';mask.save(maskpath);rec['files']['mask']={'path':maskpath.relative_to(a.target).as_posix(),'sha256':sha(maskpath)}
            rec['operation']='registered_rgb_replacement' if item['silhouette_locked'] else 'registered_rgba_replacement'
            if category=='anthro_species_by_sex':rec['head_status']='Generation reference only; body/coat/tail kit, final species faces belong to the separate face pack.';rec['kind']='species_coat_and_tail_variant'
            if category=='breast_shape':
                core,trace=chest_core(im,ident.split('_')[1],'_'.join(ident.split('_')[2:]));rec['files']['torso']=save(core,folder/'torso.png',rec);(folder/'torso-contour.json').write_text(json.dumps(trace,indent=2)+'\n')
            if category=='arm_pose_families':
                guidefolder=Path(item['guide']).parent
                if not (guidefolder/'arm-left-mask.png').exists():guidefolder=guidefolder.parent.parent/'body_pose_guides_v8'/ident
                rec['arm_masks']={}
                for side in ['left','right']:
                    src=guidefolder/('arm-'+side+'-mask.png');dst=folder/src.name
                    if src.exists():shutil.copy2(src,dst);rec['arm_masks'][side]={'path':dst.relative_to(a.target).as_posix(),'sha256':sha(dst)}
                if len(rec['arm_masks'])!=2:raise ValueError('Missing pose ownership masks: '+ident)
        records.append(rec)
    # Four male frame states are separated from the eight rendered build drawings.
    for ident,im in foundations.items():
        if not ident.startswith('male'):continue
        for name in ['normal','compact','tall','long_leg']:
            out,neck=frame(im,name);rec={'id':ident+'_'+name,'sex':'male','category':'male_frame','kind':'identity_frame' if name=='normal' else 'proportion_derivative','base':ident,'frame':name,'neck_y':neck,'baseline_y':1395,'canvas':[832,1472],'runtime_registered':False};rec['files']=store_parts(out,a.target/'frames'/rec['id'],neck,rec);records.append(rec)
    for sex,ident in [('female','female_average'),('male','male_toned')]:
        im=foundations[ident]
        for name,color in PALETTES.items():
            rec={'id':sex+'_'+name,'sex':sex,'category':'skin_palette','kind':'material_recolor','base':ident,'palette':name,'canvas':[832,1472],'runtime_registered':False};rec['files']=store_parts(palette(im,color,sex),a.target/'palettes'/rec['id'],332 if sex=='male' else 343,rec);records.append(rec)
        for pattern in ['two_piece','bandeau_trunks']:
            mask=Image.new('L',im.size);d=ImageDraw.Draw(mask)
            if sex=='female':
                if pattern=='two_piece':
                    d.polygon([(351,476),(380,389),(433,478)],fill=255);d.polygon([(465,478),(522,391),(553,480)],fill=255)
                    d.line([(378,397),(363,343)],fill=255,width=9);d.line([(520,398),(531,343)],fill=255,width=9)
                else:d.rounded_rectangle((341,414,553,482),radius=13,fill=255)
                d.polygon([(350,658),(549,659),(475,746),(450,746)],fill=255)
            else:
                if pattern=='two_piece':d.polygon([(298,649),(519,649),(472,745),(341,745)],fill=255)
                else:d.rounded_rectangle((289,642,525,837),radius=12,fill=255)
            mask=mask.filter(ImageFilter.GaussianBlur(2));tan=palette(im,PALETTES['tan'],sex);out=Image.composite(im,tan,mask);out.putalpha(im.getchannel('A'))
            rec={'id':sex+'_tan_'+pattern,'sex':sex,'category':'tan_pattern','kind':'material_pattern','pattern':pattern,'base':ident,'canvas':[832,1472],'runtime_registered':False};folder=a.target/'tan'/rec['id'];rec['files']=store_parts(out,folder,332 if sex=='male' else 343,rec);mp=folder/'pale-region-mask.png';mask.save(mp);rec['files']['mask']={'path':mp.relative_to(a.target).as_posix(),'sha256':sha(mp)};records.append(rec)
    counts=dict(collections.Counter(i['category'] for i in records));manifest={'schema':1,'status':'exported_requires_final_audit','scope':sel['scope'],'canvas':[832,1472],'adult_age_minimum':30,'reference_rendering':'Thin brown contours, matte warm skin, restrained peach cel shadows. Original adult identities.','profile':{'checkpoint':'DaSiWa Illustrious EpitaphEcstasy FP16','steps':16,'cfg':6,'sampler':'euler','scheduler':'normal','smart_memory':True},'counts_by_category':counts,'kind_counts':dict(collections.Counter(i['kind'] for i in records)),'items':records,'palette_definitions':PALETTES,'raw_reference_drawings':'Canonical own male/female plus own chest/proportion reference edits; source studies and recolors are not additional independent characters.','runtime_registered':False}
    manifest['build_width_profiles']={i['id']:{k:i[k] for k in ['widths','center','arm_width_scale']} for i in read(sel['build_guides'])['items']}
    manifest['body_defaults']={}
    for ident,prof in profiles.items():
        if prof['sex']=='female':
            source=Path(prof['source']).name;size='xs' if ident=='female_compact' else ('s' if '_small_' in source else ('m' if '_medium_' in source else 'l'));manifest['body_defaults'][ident]={'chest':'chest_'+size+'_round'}
    manifest['canonical_references']={}
    for sex,source in sel['canonical_references'].items():
        dest=a.target/'provenance'/(sex+'-canonical.png');dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest);manifest['canonical_references'][sex]={'path':dest.relative_to(a.target).as_posix(),'sha256':sha(dest)}
    rigroot=Path('E:/Ai/ComfyUI-EroInc/input/characters_v2/body_layer_rig_v1');manifest['registered_rig']={}
    states=['rest','left_open','right_open','both_open','left_in','right_in','both_in','left_wide','right_wide']
    for sex in ['female','male']:
        folder=a.target/'rig'/sex;core=register_neck(Image.open(rigroot/(sex+'_arms_rest')/'core.png').convert('RGBA'),sex);rig={'core':save(core,folder/'core.png',{'kind':'original registered core with reconstructed occluded skin'}),'joints':save(shoulder_joints(sex),folder/'shoulder-joints.png',{'kind':'original concealed shoulder connection'}),'poses':{}}
        targetpix=np.asarray(Image.open(sel['canonical_references'][sex]).convert('RGBA'));good=(targetpix[:,:,3]>250)&(targetpix[:,:,0]>220)&(targetpix[:,:,1]>185)&(targetpix[:,:,2]>145);vals,nums=np.unique(targetpix[:,:,:3][good],axis=0,return_counts=True);skin=vals[nums.argmax()].astype(float)
        for state in states:
            ident=sex+'_arms_'+state;sourcefolder=rigroot/ident;pose={};beauty=Image.open(sources[ident]['files']['full']['path']).convert('RGBA') if ident in sources else None
            for side in ['left','right']:
                arm=Image.open(sourcefolder/('arm-'+side+'.png')).convert('RGBA');pix=np.array(arm)
                if beauty is not None:
                    b=np.asarray(beauty);selected=b[:,:,3]>220;pix[selected,:3]=b[selected,:3]
                good=(pix[:,:,3]>250)&(pix[:,:,0]>220)&(pix[:,:,1]>185)&(pix[:,:,2]>145)
                if good.sum()>100:
                    vals,nums=np.unique(pix[:,:,:3][good],axis=0,return_counts=True);delta=skin-vals[nums.argmax()].astype(float);pix[:,:,:3]=np.clip(pix[:,:,:3].astype(float)+delta,0,255).astype('uint8')
                pose[side]=save(Image.fromarray(pix),folder/state/('arm-'+side+'.png'),{'kind':'registered complete arm, source hand and original hidden-limb construction; curated local render colors','sex':sex,'pose':state,'side':side})
            pose['front']=['left','right'] if state=='both_in' else (['left'] if state=='left_in' else (['right'] if state=='right_in' else []));rig['poses'][state]=pose
        manifest['registered_rig'][sex]=rig
    (a.target/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(counts))
if __name__=='__main__':main()
