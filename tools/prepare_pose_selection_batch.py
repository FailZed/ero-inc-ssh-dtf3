"""Non-graphic adult anatomy mannequin pose studies for limb selection.

No donor images and no intimate detail. Ten independent candidates: five per
gesture. Magenta is a key background, not claimed transparency.
"""
from pathlib import Path
import argparse,math,json
import numpy as np
from PIL import Image
from prepare_pose_pack import ROOT,PROJECT,config,write,draw_control

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def rotate(v,a):
    c,s=math.cos(a),math.sin(a);return np.array([c*v[0]-s*v[1],s*v[0]+c*v[1]])
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--version',required=True);a=p.parse_args();dest=ROOT/'input/characters_v2'/('pose_selection_'+a.version)
    if dest.exists():raise ValueError('Use a new version')
    dest.mkdir(parents=True);items=[]
    for ident,pose in [('female_average','shrug'),('male_toned','present')]:
        anchor=read(ROOT/'rig-authoring/v2'/ident/'anchors.json');q=np.array(anchor['all_keypoints']);rig=read(ROOT/'workbenches/hybrid-rig-v2/rigs'/(ident+'.json'));used=['right','left'] if pose=='shrug' else ['right']
        for side in used:
            sh,el,wr,start=(6,8,10,112) if side=='right' else (5,7,9,91);q[wr]=q[start];upper=math.radians(rig['poses'][pose]['angles']['arm_'+side+'_upper']);lower=math.radians(rig['poses'][pose]['angles']['arm_'+side+'_lower']);q[wr]=q[sh]+rotate(q[el]-q[sh],upper)+rotate(q[wr]-q[el],upper+lower);q[el]=q[sh]+rotate(q[el]-q[sh],upper)
        op=[q[0],(q[5]+q[6])/2,q[6],q[8],q[10],q[5],q[7],q[9],q[12],q[14],q[16],q[11],q[13],q[15],q[2],q[1],q[4],q[3]];control=dest/(ident+'-'+pose+'.png');draw_control(op,control,size=(832,1472))
        for i in range(5):
            sex='female' if ident.startswith('female') else 'male';body='balanced adult female proportions, short brown bob hair' if sex=='female' else 'moderately athletic adult male proportions, short brown hair';gesture='both elbows naturally bent, palms facing up in a relaxed questioning shrug, open proportional hands, five fingers per hand' if pose=='shrug' else 'right elbow naturally bent, right open palm facing upwards presenting something, other arm relaxed down, proportional hands, five fingers per hand'
            items.append({'id':ident+'_'+pose+'_candidate_'+str(i+1),'rig':ident,'category':'non_graphic_pose_study','control':control.relative_to(ROOT/'input').as_posix(),'prompt':'eincanime, original mature adult age 35, neutral nonsexual anatomical mannequin study, '+body+', smooth featureless chest and pelvis, no intimate anatomical details, no nipples, no genitals, no clothing, full length front view, '+gesture+', natural shoulder elbow wrist anatomy, delicate thin warm brown outlines, matte flat warm skin colors, restrained peach cel shading, plain solid bright magenta chroma key background RGB 255 0 255, even diffuse light, complete feet in frame, generous margins, single figure','negative':'child, teen, young, sexual, erotic, seductive, nipples, areola, genitals, penis, vulva, pubic hair, intimate detail, clothes, underwear, leotard, accessories, extra arms, deformed hand, huge hands, missing fingers, extra fingers, fused fingers, thick black outlines, 3d, plastic, glossy skin, text, labels, gradient background, scenery, shadow on background, cropped feet, multiple figures','seed':2026102600+len(items),'control_strength':[.55,.60,.65,.58,.62][i],'control_end':.7,'reviewed':False})
    cfg=config('pose_selection_'+a.version,items);cfg.update(mode='full_redraw',width=832,height=1472,scope='Ten neutral non-graphic adult mannequin pose studies on magenta. No intimate details. Only reviewed limb art may be selected; no runtime registration.');out=PROJECT/'docs/art/characters-v2'/('pose-selection-'+a.version+'.json');write(out,cfg);print(out)
if __name__=='__main__':main()
