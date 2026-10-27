"""Build EroInc's own registration metadata for the temporary prototype art pack."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
ART = "res://assets/textures/portraits/prototype_school/npc/"
layers = {}
def layer(key, rig, slot, path, depth, tint="", when=None):
    if not (ROOT / ART.removeprefix("res://") / path).is_file():
        raise ValueError(path)
    layers[key] = {"rig":rig,"slot":slot,"texture":ART+path,"z":depth,"tint":tint,"pose":"idle","when":when or {}}

for sex, folder in [("female","new"),("male","npc_m/type2")]:
    rig = "prototype_"+sex
    f = sex+"_"
    if sex == "female":
        layer(f+"arms_back",rig,"arms_back","new/body/hand/hand_back/hand1.png",15,"skin")
        layer(f+"body",rig,"body","new/body/body_new.png",20,"skin")
        layer(f+"chest",rig,"chest","new/body/tits_medium.png",21,"skin")
        layer(f+"tone",rig,"body_detail","new/body/abs1.png",22,"skin",{"body_type":"athletic"})
        layer(f+"underwear_bottom",rig,"underwear_bottom","new/clothes/pantsu/pantsu.png",30)
        layer(f+"underwear_top",rig,"underwear_top","new/clothes/brassiere/medium_tits/brassiere.png",31)
        layer(f+"arms_front",rig,"arms_front","new/body/hand/hand_forward/hand1.png",65,"skin")
    else:
        layer(f+"legs",rig,"legs",folder+"/legs.png",16,"skin")
        layer(f+"body",rig,"body",folder+"/body_1/main.png",20,"skin")
        layer(f+"tone",rig,"body_detail",folder+"/body_1/abs2.png",22,"skin",{"body_type":"athletic"})
        layer(f+"underwear_bottom",rig,"underwear_bottom",folder+"/undergarment/pants1.png",30)
        # This body already includes the head and nose. The legacy face*.png
        # pack has incompatible painted features and is deliberately excluded.
        layer(f+"eye_base",rig,"eye_base",folder+"/face/eye/fix_eye.png",41,"skin")
    for i in range(1,4):
        if sex == "female": layer(f+f"face_{i}",rig,"face",folder+f"/face/face_type{i}.png",40,"skin",{"face":i})
        # Whites, irises and eyelids are distinct layers. The eyelid artwork
        # masks the pupil edge and must remain above the iris.
        layer(f+f"sclera_{i}",rig,"sclera",folder+f"/face/eye/eye_ap{i}.png",42,"",{"eyes":i})
        layer(f+f"eyes_{i}",rig,"eyes",folder+f"/face/eye/eye_type{i}.png",44,"skin",{"eyes":i})
        for side in ["left","right"]:
            layer(f+f"iris_{side}_{i}",rig,"iris_"+side,folder+f"/face/eye/{side}_eye/eye{i}.png",43,"eyes",{"eyes":i})
    if sex == "female": layer(f+"nose",rig,"nose",folder+"/face/nose_type1.png",45,"skin")
    # Authored expression pairs, chosen by visual inspection of both rigs.
    # Source numbering describes asset files, not matching emotion categories.
    for emotion, mouth, brow in [("neutral",14,None),("smile",9,8),("concern",6,5),("angry",6,1),("attentive",14,3)]:
        if sex == "male": mouth = {"neutral":9,"smile":8,"concern":6,"angry":6,"attentive":9}[emotion]
        layer(f+"mouth_"+emotion,rig,"mouth",folder+f"/face/details/mounth/{mouth}.png",46,"skin",{"expression":emotion})
        brow_path = "/face/eyebrows.png" if brow is None else "/face/details/eyebrows/"+("type1/" if sex=="male" else "")+f"{brow}.png"
        layer(f+"brows_"+emotion,rig,"brows",folder+brow_path,47,"hair",{"expression":emotion})
    families = ({"short":("new/hair/base2/length1",False),"long":("new/hair/base2/length3",True),"loose":("new/hair/base1/length2",True)} if sex=="female" else {"short":("npc_m/hair/base1/length1",False),"long":("npc_m/hair/base1/length3",True),"loose":("npc_m/hair/base1/length2",True)})
    for family,(path,back) in families.items():
        layer(f+"hair_front_"+family,rig,"hair_front",path+"/front/1.png",70,"hair",{"hair":family})
        if back: layer(f+"hair_back_"+family,rig,"hair_back",path+"/back/1.png",10,"hair",{"hair":family})
    layer(f+"ears",rig,"ears","new/accessories/cat_ears/hair1.png",72,"hair",{"morphology":"semi_furry"})
    if sex == "male": layers[f+"ears"]["offset"] = [-80,-70]
    for outfit,number in [("casual",0),("work",1),("training",0)]:
        if sex=="female":
            top="new/clothes/everyday/medium_tits/everyday"+("1" if number else "")+".png"
            bottom="new/clothes/down_clothes/jeans.png"
        else:
            top=folder+("/body_1/clothes/clothes1.png" if number else "/body_1/clothes/usually1.png")
            bottom=folder+"/down_clothes/jeans.png"
        layer(f+"top_"+outfit,rig,"top",top,60,"clothing",{"outfit":outfit})
        layer(f+"bottom_"+outfit,rig,"bottom",bottom,55,"",{"outfit":outfit})

catalog = {
    "schema":1,"temporary_art":True,
    "rigs": {sex: {"canvas":[1920,2596],"frame":[450,70,1100,2160],"mirror_frame":[700,90,600,900],"face_frame":[700,20,530,560],"pose":"idle","gender":sex.removeprefix("prototype_"),"morphologies":["human","semi_furry"]} for sex in ["prototype_female","prototype_male"]},
    "layers":layers,
    "palettes":{"skin":["ffffff","efcfb8","d4a584","b77c58"],"hair":["352f3c","644735","ab714f","dcc08b","6c779c","a8afb8"],"eyes":["729fc2","8ba883","b99361","a58ab9"],"clothing":["62829e","929bb4","c7b9aa","6c8e81"]},
    "story_profiles":{
        "asuka":{"name":"Асука","gender":"female","morphology":"human","face":2,"eyes":2,"hair":"loose","hair_color":"8b584b","skin_color":"ffffff","eye_color":"8ba883","clothing_color":"8598b2"},
        "ellie":{"name":"Элли","gender":"female","morphology":"semi_furry","face":1,"eyes":1,"hair":"short","hair_color":"34333e","skin_color":"ffffff","eye_color":"9cabb5","clothing_color":"93a5ba"},
        "oliver":{"name":"Оливер","gender":"male","morphology":"semi_furry","face":1,"eyes":3,"hair":"loose","hair_color":"4e3c35","skin_color":"ffffff","eye_color":"a4bca3","clothing_color":"9aaba4"},
        "lin":{"name":"Лин","gender":"female","morphology":"human","face":3,"eyes":1,"hair":"long","hair_color":"38313d","skin_color":"ffffff","eye_color":"a58ab9","clothing_color":"929bb4"},
        "mira":{"name":"Мира","gender":"female","morphology":"human","face":2,"eyes":2,"hair":"short","hair_color":"9b6947","skin_color":"ffffff","eye_color":"729fc2","clothing_color":"c7b9aa"},
        "uriel":{"name":"Уриэль","gender":"male","morphology":"human","face":3,"eyes":2,"hair":"short","hair_color":"bca78c","skin_color":"ffffff","eye_color":"729fc2","clothing_color":"8892a5"},
        "ryan":{"name":"Райан","gender":"male","morphology":"human","face":2,"eyes":2,"hair":"short","hair_color":"4b443f","skin_color":"ffffff","eye_color":"b99361","clothing_color":"ffffff","outfit":"work"},
        "rector":{"name":"Михаил Мэтисон","gender":"male","morphology":"human","face":3,"eyes":3,"hair":"short","hair_color":"a8afb8","skin_color":"ffffff","eye_color":"9cabb5","clothing_color":"ffffff","outfit":"work"}
    },
    "aliases":{"Ректор":"rector","Михаил Мэтисон":"rector","Райан":"ryan","Асука":"asuka","Элли":"ellie","Оливер":"oliver","Лин":"lin","Мира":"mira","Уриэль":"uriel","Уриил":"uriel"}
}
catalog['rigs']['prototype_male']['face_frame'] = [660,0,540,570]
catalog['rigs']['prototype_female']['face_frame'] = [710,80,540,570]
for preset in catalog['story_profiles'].values(): preset.setdefault('body_type','slim')
(ROOT/"data/art/character_layers.json").write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(f"Registered {len(layers)} layers across {len(catalog['rigs'])} rigs")
