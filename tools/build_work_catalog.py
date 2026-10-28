"""Author the current EroInc jobs and challenges; no donor content or save access."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT/'data/mechanics/livelihood.json'
rules = json.loads(path.read_text(encoding='utf-8'))['livelihood_rules']
# id, title, skill, family, category, workplace, hours, minutes, energy, pay, entry level
rows = [
('shop_assistant','Смена в магазине','sales','shift','service','north_shops',[480,1200],180,24,90,0),
('warehouse_shift','Работник склада','logistics','shift','logistics','north_shops',[420,1200],240,34,128,0),
('campus_assistant','Помощник на кампусе','handiness','shift','technical','training_center',[480,1080],150,18,82,0),
('cafe_orders','Кафе: заказы на память','cooking','memory','service','riverside_cafe',[480,1320],120,20,90,0),
('parcel_sorting','Сортировка посылок','logistics','sorting','logistics','north_shops',[480,1260],120,22,94,0),
('repair_bench','Ремонтная мастерская','handiness','focus','technical','north_shops',[540,1200],150,22,120,2),
('street_performer','Уличный перформанс','performance','focus','creative','south_promenade',[600,1320],90,20,66,0),
('studio_session','Студийный иллюстратор','painting','shift','creative','bedroom',[480,1320],180,26,146,2),
('lead_shift','Старший смены','leadership','shift','service','north_shops',[480,1140],240,30,205,4),
('underground_courier','Подпольный курьер','stealth','shift','underground','north_alleys',[1080,1440],120,26,178,0),
('unlicensed_stall','Нелицензированная лавка','sales','memory','underground','north_shops',[600,1320],150,22,180,0),
('shadow_commission','Сомнительный заказ','computing','focus','underground','bedroom',[600,1440],180,30,260,2),
('tutor','Репетитор','study','reasoning','academic','training_center',[780,1320],60,10,55,0),
('defence_assistant','Ассистент самообороны','fighting','sequence','sport','training_center',[780,1320],90,20,78,0),
('card_host','Ведущий карточного клуба','cards','reasoning','service','riverside_cafe',[900,1380],90,12,68,0),
('fact_checker','Проверка редакционных фактов','journalism','reasoning','academic','bedroom',[420,1380],60,10,58,0),
('security_auditor','Аудитор учебных цифровых стендов','cybersecurity','reasoning','technical','bedroom',[420,1380],90,14,84,1),
('puzzle_editor','Редактор головоломок','logic','reasoning','academic','bedroom',[420,1380],60,10,54,0),
('lab_assistant','Лаборант: сверка образцов','research','comparison','academic','training_center',[780,1200],90,13,74,0),
('copy_editor','Редактор коротких текстов','writing','reasoning','creative','bedroom',[420,1380],90,12,72,0),
('event_host','Ведущий городских встреч','public_speaking','sequence','social','riverside_cafe',[900,1320],90,15,76,0),
('community_listener','Собеседник общественного центра','empathy','reasoning','social','training_center',[780,1260],60,10,52,0),
('fundraiser','Координатор городского сбора','persuasion','reasoning','social','south_promenade',[780,1320],90,15,70,0),
('gym_assistant','Ассистент тренера','fitness','sequence','sport','training_center',[780,1320],90,22,76,0),
('race_marshal','Помощник на беговой трассе','athletics','focus','sport','city_park',[360,600],60,18,54,0),
('photo_reviewer','Отбор фотографий для каталога','photography','comparison','creative','bedroom',[420,1380],60,10,60,0),
('music_arranger','Монтажёр ритмических партитур','music','sequence','creative','bedroom',[420,1380],90,12,72,0),
('comedy_writer','Автор комедийных номеров','comedy','reasoning','creative','riverside_cafe',[900,1380],60,12,58,0),
('dance_assistant','Ассистент танцевальной студии','dancing','sequence','sport','training_center',[780,1320],90,20,78,0),
('park_gardener','Садовник городского парка','gardening','sequence','outdoors','city_park',[360,600],90,20,70,0),
('fish_supplier','Рыбак для городской кухни','fishing','focus','outdoors','north_beach',[300,600],90,18,72,0),
('craft_workshop','Мастер небольших изделий','crafting','sequence','technical','bedroom',[420,1380],90,14,76,0),
('day_planner','Помощник по расписаниям','discipline','reasoning','social','bedroom',[420,1380],60,10,54,0),
]
descriptions = {
'shift':'Автоматическая смена с бытовыми перерывами. Ступень оплаты определяется только связанным навыком.',
'memory':'Запомните последовательность и восстановите порядок. Навык уменьшает нагрузку в пределах сложности.',
'sorting':'Направляйте отправления до истечения времени на ответ.',
'focus':'Пять раз поймайте рабочую зону. Точность определяет качество и премию.',
'reasoning':'Пять рабочих ситуаций: выберите обоснованное решение. После ответа доступен разбор.',
'comparison':'Сверьте два набора из девяти отметок и найдите единственное различие в каждом раунде.',
'sequence':'Соберите рабочие этапы в правильном порядке. Выбранный этап можно отменить до завершения раунда.'}
jobs={}
for key,title,skill,kind,category,location,hours,minutes,energy,pay,minimum in rows:
    jobs[key]=dict(title=title,description=descriptions[kind],location=location,hours=hours,minutes=minutes,energy=energy,pay=pay,career=category,skill=skill,kind=kind,min_skill=minimum,risk=0)
for key,risk,fine,fee in [('underground_courier',.25,100,15),('unlicensed_stall',.20,130,20),('shadow_commission',.32,200,30)]:
    jobs[key].update(risk=risk,fine=fine,fee=fee)
for key in ['studio_session','shadow_commission','security_auditor']:jobs[key]['equipment']='computer'
jobs['photo_reviewer']['equipment']='camera'
for key,choices in [('cafe_orders',['Суп','Чай','Салат','Каша','Обед']),('unlicensed_stall',['Альбом','Значок','Лампа','Плакат','Рамка']),('parcel_sorting',['Набережная','Университет','Жилой район'])]:jobs[key]['choices']=choices

# Authored banks are canonical data; the generator only binds jobs to them.
banks = json.loads((ROOT/'data/mechanics/work_banks.json').read_text(encoding='utf-8'))['work_task_banks']
for key,job in jobs.items():
    if job['kind'] in ('reasoning','sequence'):
        assert key in banks
        job['task_bank'] = key
for key in ['lab_assistant','photo_reviewer']:
    jobs[key]['comparison_prompt']='Найдите изменённую отметку: контроль слева, проверяемый набор справа.'
rules['jobs']=jobs
rules['promotion']={'skill_levels':[0,2,4,6,8],'experience':[0,60,180,360,600],'quality_bonus':25}
rules['profession_skills']={'digital':'computing','retail':'sales','journalism':'journalism'}
path.write_text(json.dumps({'livelihood_rules':rules},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert len({job['skill'] for job in jobs.values()})==30
print(f'Work catalog: {len(jobs)} jobs, 30 skills, 6 interactive challenge families; {sum(len(bank["tasks"]) for tiers in banks.values() for bank in tiers)} authored tasks.')
