"""Prepare whole-figure adult non-graphic pose renders, never warped cutouts."""
from pathlib import Path
import argparse,json,math,copy
from prepare_pose_pack import ROOT,PROJECT,STYLE,NEGATIVE,subject,config,write,draw_control
from pose_pack_catalogue import specifications

def hand_maps(spec):
    state=spec['state'];pts=spec['points'];hands=[]
    if spec['category']!='arms':return hands
    for side,wrist in [('left',4),('right',7)]:
        used=state in ['shrug'] or state in ['wave_'+side,'palm_'+side,'point_'+side] or (state=='thinking' and side=='right')
        if not used:continue
        canonical=[(0,0),(-20,-16),(-32,-30),(-42,-40),(-48,-48),(-18,-35),(-22,-58),(-23,-75),(-24,-90),(0,-38),(0,-66),(0,-85),(0,-100),(17,-34),(20,-58),(22,-74),(23,-88),(30,-29),(38,-48),(42,-61),(45,-73)]
        if state.startswith('point'):
            canonical[9:]=[(0,-28),(6,-36),(10,-28),(7,-23),(18,-25),(23,-32),(26,-25),(22,-19),(30,-19),(35,-25),(36,-19),(32,-14)]
        angle=(-90 if side=='left' else 90) if state.startswith('point') else ((-60 if side=='left' else 60) if state.startswith('palm') or state=='shrug' else 0)
        scale=.55 if state=='thinking' else .85;theta=math.radians(angle);co=math.cos(theta);si=math.sin(theta);wx,wy=pts[wrist]
        hands.append([(wx+scale*(co*x-si*y),wy+scale*(si*x+co*y)) for x,y in canonical])
    return hands

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--pilot',action='store_true');p.add_argument('--all',action='store_true');p.add_argument('--version',default='v1');p.add_argument('--reuse-index',type=Path);p.add_argument('--only',nargs='*');a=p.parse_args()
    specs=specifications();canvas=(1344,1472)
    if a.pilot:specs=[s for s in specs if (s['category'],s['state']) in [('arms','folded'),('full_pose','seated_front')]]
    elif not a.all:p.error('Choose --pilot or --all')
    prefix='pose_redraw_'+('pilot_' if a.pilot else 'all_')+a.version;folder=ROOT/'input/characters_v2'/prefix
    if folder.exists():raise ValueError('Use a new guide version')
    folder.mkdir(parents=True);items=[];reuse=set()
    if a.reuse_index:reuse={i['id'] for i in json.loads(a.reuse_index.read_text(encoding='utf-8-sig'))['items']}
    for spec in specs:
        spec=copy.deepcopy(spec);spec['points']=[(xy[0]+256,xy[1]) if xy is not None else None for xy in spec['points']]
        for sex in ['female','male']:
            ident=sex+'_'+spec['category']+'_'+spec['state']
            if a.only and ident not in a.only:continue
            dest=folder/ident;dest.mkdir();hands=hand_maps(spec);draw_control(spec['points'],dest/'control.png',hands,size=canvas)
            if a.all and (ident in reuse or (spec['category'],spec['state']) in [('head','front'),('legs','neutral')]):continue
            person='(1girl:1.15), solo, mature adult woman age 30, short brown bob haircut, blue eyes, balanced natural proportions' if sex=='female' else '(1boy:1.4), (male focus:1.3), solo, (mature adult man age 35:1.3), masculine adult face, short brown hair, blue eyes, broad shoulders, (flat masculine chest:1.2), natural male pectoral muscles'
            action=spec['action'].replace('on a plain gray armless stool','on an implied seat').replace('on a plain gray bench','on an implied seat').replace('on a simple low gray seat','in a relaxed seated posture')
            if spec['category'] in ['arms','legs']:action+=', (front view:1.2), facing the viewer, head facing forward'
            if spec['category']=='head':action+=', torso facing the viewer, shoulders level'
            words=STYLE+', '+person.replace(', blue eyes','')+', (nude:1.15), (bare shoulders:1.2), (bare arms:1.2), (bare legs:1.2), (barefoot:1.15), '+action+', smooth unadorned skin, matte colors without shine, isolated body only on a simple empty backdrop, one adult only'
            words=words.replace('and shoes','and feet')
            negative=NEGATIVE+', (dress:1.4), (shirt:1.4), pants, trousers, sleeves, skirt, shoes, socks, picture frame, wall, room, duplicate character, long neck, dislocated shoulder, separated limb, rigid doll joint, inset, diagram, miniature, icon, glowing skin, highlights, glossy skin, (censored:1.4), (censor bar:1.3), mosaic, sticker, emoji, symbol, heart, toy, plushie, teddy bear, blue skin, skin drawing, skin tattoo, sparkling, magic effects, chair, stool, bench, furniture'
            negative+=', 1girl, girl, woman, female, breasts, feminine, long hair' if sex=='male' else ', 1boy, man, male, masculine, huge breasts, obese'
            if sex=='female':negative=negative.replace('nipples, areola, ','')
            items.append({'id':ident,'rig':sex+'_canonical','category':spec['category'],'sex':sex,'state':spec['state'],'title':spec['title'],'control':(dest/'control.png').relative_to(ROOT/'input').as_posix(),'prompt':words,'negative':negative,'seed':2026110100+len(items)})
            write(dest/'joints.json',{**spec,'sex':sex,'canvas':list(canvas),'hands':hands,'renderer':'Official vendored IDEA-Research DWPose util.draw_bodypose/draw_handpose, standard palette','technical_guide_only':True})
    conf=config(prefix,items);conf.update(mode='full_redraw',width=canvas[0],height=canvas[1],preserve_input_latent=False)
    conf['controlnet'].update(strength=.75,end_percent=.9)
    conf['negative']=NEGATIVE+', (dress:1.4), (shirt:1.4), pants, trousers, sleeves, skirt, shoes, socks, picture frame, wall, room, duplicate character, long neck, dislocated shoulder, separated limb, rigid doll joint'
    target=PROJECT/'docs/art/characters-v2'/(prefix.replace('_','-')+'.json');write(target,conf);print(target)
if __name__=='__main__':main()
