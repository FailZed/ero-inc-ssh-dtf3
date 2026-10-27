"""Original pose specifications; image-space joints are guides, not final art."""
from copy import deepcopy
from prepare_pose_pack import base_points

ARMS={
 'rest':('Руки опущены','both arms hanging relaxed beside hips',{}),
 'folded':('Руки скрещены','arms folded loosely across mid torso, natural crossed forearms',{3:(310,590),4:(495,510),6:(522,590),7:(337,510)}),
 'hip_left':('Правая рука на бедре','one hand resting on the hip on the left of the image, other arm relaxed',{3:(235,565),4:(340,665)}),
 'hip_right':('Левая рука на бедре','one hand resting on the hip on the right of the image, other arm relaxed',{6:(597,565),7:(492,665)}),
 'palm_left':('Открытая правая ладонь','presenting an open palm on the left of the image, elbow bent naturally',{3:(260,555),4:(160,450)}),
 'palm_right':('Открытая левая ладонь','presenting an open palm on the right of the image, elbow bent naturally',{6:(572,555),7:(672,450)}),
 'shrug':('Пожимает плечами','gentle shrug, both forearms raised sideways with palms up',{3:(255,545),4:(155,420),6:(577,545),7:(677,420)}),
 'wave_left':('Приветствие правой рукой','waving with the hand on the left of the image, open palm, other arm down',{3:(225,490),4:(205,255)}),
 'wave_right':('Приветствие левой рукой','waving with the hand on the right of the image, open palm, other arm down',{6:(607,490),7:(627,255)}),
 'point_left':('Указывает вправо','one arm extended naturally sideways toward the left edge of the image, index finger pointing, other arm down',{3:(95,375),4:(-125,380)}),
 'point_right':('Указывает влево','one arm extended naturally sideways toward the right edge of the image, index finger pointing, other arm down',{6:(737,375),7:(957,380)}),
 'thinking':('Задумался','one elbow bent, fingers lightly touching just below the chin, calm thoughtful posture',{6:(545,565),7:(445,355)})
}
HEADS={
 'front':('Прямо','head facing camera',{}),
 'quarter_left':('Поворот головы вправо','head turned forty five degrees toward the left of the image, body facing camera',{0:(385,230),14:(373,218),15:(410,218),16:(361,235),17:(444,238)}),
 'quarter_right':('Поворот головы влево','head turned forty five degrees toward the right of the image, body facing camera',{0:(447,230),14:(422,218),15:(459,218),16:(388,238),17:(471,235)}),
 'profile_left':('Правый профиль','head turned ninety degrees toward the left of the image, clean side profile, one visible eye, body facing camera',{0:(360,233),14:(376,218),15:None,16:(435,235),17:None}),
 'profile_right':('Левый профиль','head turned ninety degrees toward the right of the image, clean side profile, one visible eye, body facing camera',{0:(472,233),14:None,15:(456,218),16:None,17:(397,235)}),
 'look_up':('Смотрит вверх','head tilted upward slightly, looking upward, chin gently raised',{0:(416,208),14:(398,204),15:(434,204),16:(378,235),17:(454,235)}),
 'look_down':('Смотрит вниз','head bowed slightly, gaze downward, chin lowered',{0:(416,254),14:(398,230),15:(434,230),16:(378,219),17:(454,219)}),
 'tilt_left':('Наклон головы вправо','head tilted twelve degrees toward the left shoulder, shoulders level',{0:(405,231),14:(390,215),15:(425,222),16:(369,224),17:(446,240)}),
 'tilt_right':('Наклон головы влево','head tilted twelve degrees toward the right shoulder, shoulders level',{0:(427,231),14:(407,222),15:(442,215),16:(386,240),17:(463,224)})
}
LEGS={
 'neutral':('Обычная стойка','neutral balanced standing stance',{}),
 'weight_left':('Вес на правой ноге','weight shifted onto the leg on the left of the image, other knee slightly relaxed',{8:(345,795),11:(447,795),9:(340,1070),10:(345,1350),12:(495,1060),13:(520,1350)}),
 'weight_right':('Вес на левой ноге','weight shifted onto the leg on the right of the image, other knee slightly relaxed',{8:(385,795),11:(487,795),9:(337,1060),10:(312,1350),12:(492,1070),13:(487,1350)}),
 'step_left':('Шаг правой ногой','small natural step forward with the leg on the left of the image, other foot behind',{9:(320,1000),10:(300,1350),12:(485,1095),13:(510,1325)}),
 'step_right':('Шаг левой ногой','small natural step forward with the leg on the right of the image, other foot behind',{9:(347,1095),10:(322,1325),12:(512,1000),13:(532,1350)}),
 'close':('Ноги вместе','standing upright, legs close together, feet parallel',{8:(375,795),11:(457,795),9:(390,1070),10:(390,1350),12:(442,1070),13:(442,1350)}),
 'wide':('Устойчивая широкая стойка','comfortable wide standing stance, both feet firmly planted, no exaggerated spread',{9:(315,1060),10:(270,1350),12:(517,1060),13:(562,1350)})
}
FULL={
 'seated_front':('Сидит прямо','sitting upright on a plain gray armless stool, front view, both feet flat on ground, hands resting on thighs',{}),
 'seated_quarter_left':('Сидит в три четверти вправо','sitting upright on a plain gray armless stool in three quarter view toward the left of the image, feet on ground, hands on thighs',{0:(389,450),2:(315,590),5:(480,595),8:(355,935),11:(435,925),9:(270,1115),10:(280,1350),12:(455,1090),13:(460,1320)}),
 'seated_quarter_right':('Сидит в три четверти влево','sitting upright on a plain gray armless stool in three quarter view toward the right of the image, feet on ground, hands on thighs',{0:(443,450),2:(352,595),5:(517,590),8:(397,925),11:(477,935),9:(377,1090),10:(372,1320),12:(562,1115),13:(552,1350)}),
 'seated_ankles_crossed':('Сидит, скрестив лодыжки','sitting on a plain gray bench, knees comfortably close, ankles loosely crossed, hands resting beside hips',{3:(285,785),4:(300,965),6:(547,785),7:(532,965),9:(375,1110),12:(457,1110),10:(465,1350),13:(367,1350)}),
 'sofa_relaxed':('Сидит с опорой на спинку','sitting relaxed on a simple low gray seat, torso leaning back slightly, one forearm resting beside body, feet planted',{0:(425,480),1:(425,595),2:(325,620),5:(525,620),3:(260,825),4:(230,930),6:(560,815),7:(545,960),8:(390,955),11:(490,955),9:(325,1135),12:(555,1135),10:(300,1350),13:(580,1350)}),
 'floor_crossed':('Сидит на полу','sitting upright on the floor with legs folded comfortably in a cross-legged position, hands resting on knees, calm nonsexual figure study',{0:(416,610),1:(416,725),2:(320,750),5:(512,750),3:(285,965),4:(235,1200),6:(547,965),7:(597,1200),8:(365,1210),11:(467,1210),9:(220,1240),12:(612,1240),10:(490,1310),13:(342,1310)}),
 'kneel_one':('На одном колене','kneeling on one knee, other foot planted in front, upright torso, hands resting gently on upper thighs, nonsexual figure study',{0:(416,400),1:(416,515),2:(320,540),5:(512,540),3:(285,745),4:(320,940),6:(547,745),7:(520,940),8:(365,930),11:(467,930),9:(280,1080),10:(270,1350),12:(510,1290),13:(620,1310)}),
 'crouch':('Присел на корточки','balanced natural crouching posture, both feet planted, knees bent, forearms resting lightly on knees, nonsexual everyday pose',{0:(416,630),1:(416,745),2:(320,770),5:(512,770),3:(275,980),4:(270,1110),6:(557,980),7:(562,1110),8:(365,1195),11:(467,1195),9:(260,1085),12:(572,1085),10:(350,1350),13:(482,1350)})
}

def specifications():
    out=[]
    for category,catalogue in [('arms',ARMS),('head',HEADS),('legs',LEGS),('full_pose',FULL)]:
        for name,(title,action,changes) in catalogue.items():
            pts=base_points(category=='full_pose')
            for key,value in changes.items():pts[key]=value
            out.append({'state':name,'category':category,'title':title,'action':action,'points':deepcopy(pts)})
    return out
