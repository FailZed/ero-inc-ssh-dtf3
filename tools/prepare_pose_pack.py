"""Prepare original adult non-graphic anatomy pose controls and local jobs.

Technical joint maps are authored here; they are never counted as illustrations.
No gameplay registration or donor image use. All training/generation data stays on E:.
"""
from pathlib import Path
import argparse, hashlib, json, importlib.util, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT=Path('E:/Ai/ComfyUI-EroInc')
PROJECT=Path(__file__).resolve().parents[1]
SIZE=(832,1472)
LINKS=[(1,2),(1,5),(2,3),(3,4),(5,6),(6,7),(1,8),(8,9),(9,10),(1,11),(11,12),(12,13),(1,0),(0,14),(14,16),(0,15),(15,17)]
COLORS=[(255,0,0),(255,85,0),(255,170,0),(255,255,0),(170,255,0),(85,255,0),(0,255,0),(0,255,85),(0,255,170),(0,255,255),(0,170,255),(0,85,255),(0,0,255),(85,0,255),(170,0,255),(255,0,255),(255,0,170),(255,0,85)]
NEGATIVE='clothes, shirt, trousers, underwear, lingerie, swimsuit, fabric, genitals, penis, testicles, vulva, labia, nipples, areola, pubic hair, erotic, sexual, seductive pose, child, teen, school uniform, chibi, 3d, photorealistic, plastic, glossy skin, thick black ink, crosshatching, text, logo, watermark, extra limbs, extra fingers, fused hands, missing hands, malformed feet, cropped head, cropped feet, multiple people, duplicate body, busy background'
STYLE='masterpiece, best quality, eincanime, original mature adult age 30, full body visual novel character sprite, delicate thin brown lineart, matte flat colors, limited soft peach cel shadows, even diffuse light, plain light gray background, complete hands and shoes, generous canvas margins'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def base_points(seated=False):
    if seated:
        return [(416,450),(416,565),(320,590),(288,785),(325,975),(512,590),(544,785),(507,975),(365,935),(314,1120),(340,1350),(467,935),(518,1120),(492,1350),(398,438),(434,438),(378,453),(454,453)]
    return [(416,230),(416,345),(320,370),(292,595),(278,815),(512,370),(540,595),(554,815),(365,795),(355,1070),(350,1350),(467,795),(477,1070),(482,1350),(398,218),(434,218),(378,233),(454,233)]
_drawing=None
def draw_control(points,path,hands=None,size=SIZE):
    global _drawing
    if _drawing is None:
        os.environ.setdefault('MPLCONFIGDIR',str(ROOT/'cache/matplotlib'))
        impl=ROOT/'postprocess/vendor/DWPose/ControlNet-v1-1-nightly/annotator/dwpose/util.py'
        spec=importlib.util.spec_from_file_location('ero_official_pose_drawing',impl);_drawing=importlib.util.module_from_spec(spec);spec.loader.exec_module(_drawing)
    candidate=np.array([p if p is not None else (0,0) for p in points],float)/np.array(size)
    subset=np.array([[i if p is not None else -1 for i,p in enumerate(points)]])
    canvas=_drawing.draw_bodypose(np.zeros((size[1],size[0],3),np.uint8),candidate,subset)
    if hands:canvas=_drawing.draw_handpose(canvas,[np.array(h,float)/np.array(size) for h in hands])
    Image.fromarray(canvas).save(path)
def config(prefix,items):
    control=ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/controlnet/xinsir-openpose-sdxl.safetensors'
    return {'schema':1,'scope':'Original mature adult neutral artistic body bases without clothing, non-graphic anatomy, no intimate detail. Not runtime registered.',
            'output_prefix':'characters_v2/'+prefix,'steps':16,'cfg':6,'sampler':'euler','scheduler':'normal','denoise':1.0,'preserve_input_latent':False,
            'lora':{'name':'EroInc/candidate_400.safetensors','sha256':'2da68309cba8e4613d0fbf8c15fb64d60fafc5bea3b9b5a791cca8cd3f225cb9','strength':.65},
            'controlnet':{'name':control.name,'sha256':sha(control),'strength':.58,'start_percent':0.0,'end_percent':.75},'negative':NEGATIVE,'items':items}
def subject(sex):
    return ('adult woman, short brown bob haircut, blue eyes, balanced natural adult proportions' if sex=='female' else 'adult man, short brown hair, blue eyes, moderately athletic adult proportions')+', unclothed neutral artistic figure study, smooth simplified anatomical base, non-graphic anatomy, no intimate details, bare feet, relaxed nonsexual posture'

def pilot():
    prefix='pose_neutral_pilot_v2';folder=ROOT/'input/characters_v2'/prefix;items=[]
    for seated in [False,True]:
        for sex in ['female','male']:
            name=sex+('_seated_front' if seated else '_arms_folded');dest=folder/name;dest.mkdir(parents=True,exist_ok=True)
            canonical=PROJECT/'assets/art_source/characters_v2/body_pack_v1/provenance'/(sex+'-canonical.png')
            original=Image.open(canonical).convert('RGBA');neck=343 if sex=='female' else 332;shift=220 if seated else 0
            guide=Image.new('RGBA',SIZE);guide.alpha_composite(original.crop((0,0,832,neck)),(0,shift));guide.save(dest/'guide.png')
            bg=Image.new('RGBA',SIZE,'#eeeeec');bg.alpha_composite(guide);bg.convert('RGB').save(dest/'reference.png')
            mask=Image.new('L',SIZE,255);d=ImageDraw.Draw(mask);d.rectangle((150,shift+40,680,neck+shift-8),fill=0)
            mask=mask.filter(ImageFilter.GaussianBlur(2));mask.save(dest/'mask.png')
            points=base_points(seated)
            if not seated:points[3:5]=[(310,590),(495,510)];points[6:8]=[(522,590),(337,510)]
            draw_control(points,dest/'control.png')
            action='sitting upright on a plain gray armless stool, both feet firmly on the ground, knees naturally apart, hands resting naturally on thighs, front view' if seated else 'standing upright, arms folded loosely across mid torso, both forearms crossing naturally, front view'
            write(dest/'joints.json',{'points_openpose18':points,'coordinates':'image pixel coordinates, screen left at smaller x','technical_guide_only':True,'neck_y':neck+shift})
            items.append({'id':name,'rig':sex+'_canonical','category':'full_pose' if seated else 'arms','image':(dest/'reference.png').relative_to(ROOT/'input').as_posix(),'mask':(dest/'mask.png').relative_to(ROOT/'input').as_posix(),'control':(dest/'control.png').relative_to(ROOT/'input').as_posix(),'prompt':STYLE+', '+subject(sex)+', '+action,'seed':2026101900+len(items),'head_neck_y':neck+shift,'sex':sex})
    target=PROJECT/'docs/art/characters-v2/pose-neutral-pilot-v2.json';write(target,config(prefix,items));print(target)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--pilot',action='store_true');a=p.parse_args()
    if a.pilot:raise SystemExit('Pasted-head experiment rejected. Use prepare_pose_redraw.py for complete figures.')
    else:p.error('Choose --pilot')
if __name__=='__main__':main()
