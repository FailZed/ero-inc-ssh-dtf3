"""Original EroInc progression data. Does not read donor games or user saves."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
rows = [
    ("study","Учёба","mind","Разбирать учебные задачи",["bedroom","training_center"],4,0),
    ("cooking","Кулинария","craft","Отрабатывать кухонные приёмы",["kitchen"],5,6),
    ("computing","Программирование","technical","Практиковать программирование",["bedroom"],4,0),
    ("fighting","Самооборона","body","Отрабатывать безопасные связки",["city_park","training_center"],10,0),
    ("stealth","Скрытность","body","Тренировать тихое движение",["city_park"],7,0),
    ("cards","Карточные игры","mind","Разбирать учебные карточные ситуации",["bedroom","riverside_cafe"],3,0),
    ("journalism","Журналистика","creative","Составить заметку о городе",["bedroom","south_promenade"],4,0),
    ("cybersecurity","Цифровая безопасность","technical","Заниматься на учебном стенде",["bedroom"],5,0),
    ("logic","Логика","mind","Решать логические задачи",["bedroom","city_park"],3,0),
    ("research","Исследование","mind","Сопоставлять источники",["bedroom","training_center"],4,0),
    ("writing","Писательство","creative","Работать над коротким рассказом",["bedroom","riverside_cafe"],4,0),
    ("public_speaking","Ораторское мастерство","social","Репетировать выступление",["bedroom","city_park"],4,0),
    ("empathy","Эмпатия","social","Разбирать разные точки зрения",["bedroom","riverside_cafe"],3,0),
    ("persuasion","Убеждение","social","Готовить аргументированную речь",["bedroom","training_center"],4,0),
    ("fitness","Физическая форма","body","Тренировать общую выносливость",["city_park","training_center"],10,0),
    ("athletics","Атлетика","body","Тренировать координацию и бег",["city_park","north_beach"],10,0),
    ("handiness","Ремонт","technical","Собирать учебный макет",["bedroom"],5,5),
    ("painting","Рисование","creative","Делать зарисовки",["bedroom","city_park"],3,3),
    ("photography","Фотография","creative","Практиковать композицию кадра",["city_park","south_promenade"],4,0),
    ("music","Музыка","creative","Тренировать слух и ритм",["bedroom"],4,0),
    ("performance","Сценическое мастерство","creative","Репетировать короткий номер",["bedroom","south_promenade"],6,0),
    ("comedy","Юмор","social","Готовить комедийный монолог",["bedroom","riverside_cafe"],4,0),
    ("dancing","Танцы","body","Отрабатывать танцевальные движения",["bedroom","city_park"],8,0),
    ("gardening","Садоводство","craft","Ухаживать за учебными посадками",["city_park"],6,3),
    ("fishing","Рыбалка","craft","Практиковать заброс на берегу",["north_beach","south_promenade"],5,0),
    ("crafting","Ремесло","craft","Работать над простым изделием",["bedroom"],5,5),
    ("sales","Торговля","social","Разбирать потребности покупателей",["bedroom","north_shops"],4,0),
    ("logistics","Логистика","mind","Планировать учебные маршруты",["bedroom","north_shops"],4,0),
    ("leadership","Организация людей","social","Планировать совместную работу",["bedroom","training_center"],5,0),
    ("discipline","Самоорганизация","mind","Планировать день и внимание",["bedroom"],3,0),
]
skills = {}
for key,label,category,title,locations,energy,cost in rows:
    entry = dict(label=label,category=category,practice=title,locations=locations,minutes=30,energy=energy,cost=cost,xp=8)
    if key in ("computing","cybersecurity"):entry["tool"]="computer"
    if key=="photography":entry["tool"]="camera"
    skills[key]=entry
rules = {
    "profiles": {
        "easy":{"floor":0.55,"help_cap":0.40,"work_ms":36000,"focus":0.12,"round_ms":6000,"game_factor":1.15},
        "normal":{"floor":0.70,"help_cap":0.28,"work_ms":30000,"focus":0.10,"round_ms":5000,"game_factor":1.0},
        "hard":{"floor":0.85,"help_cap":0.14,"work_ms":24000,"focus":0.08,"round_ms":4000,"game_factor":0.85},
    },
    "habits":{
        "hydration":{"label":"Запас воды","skills":["fitness","discipline"]},
        "satiety":{"label":"Сытость","skills":["cooking","fitness"]},
        "hygiene":{"label":"Гигиена","skills":["handiness","discipline"]},
        "bladder":{"label":"Туалет","skills":["discipline","fitness"]},
        "rested":{"label":"Выспанность","skills":["fitness","discipline"]},
        "fun":{"label":"Досуг","skills":["music","dancing","cards"]},
        "social":{"label":"Общение","skills":["empathy","public_speaking"]},
    },
    "habit_thresholds":[10,50,150],
    "work_care":{"hydration":75,"satiety":65,"bladder":80,"social":60},
}
(ROOT/'data/mechanics/growth.json').write_text(json.dumps({'skills':skills,'growth_rules':rules},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'Growth catalog: {len(skills)} skills, {len(rules["habits"])} optional needs.')
