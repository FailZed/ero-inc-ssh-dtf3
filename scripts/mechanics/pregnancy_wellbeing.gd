extends "res://scripts/mechanics/core/module.gd"
## Adult pregnancy discomfort and self-care. Numerical rates are game balance.
const PATH := "res://data/mechanics/pregnancy_wellbeing.json"
const Care = preload("res://scripts/mechanics/pregnancy_selfcare.gd")
static var _data: Dictionary = {}
var care

static func config() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _data = parsed
	return _data

static func defaults() -> Dictionary:
	return {"version":1,"rules_hash":JSON.stringify(config()).sha256_text(),"records":{},"history":[]}

func _init(simulation) -> void:
	super(simulation)
	care = Care.new(simulation)

func initialize() -> void:
	if not sim.state.has("pregnancy_wellbeing"): sim.state.pregnancy_wellbeing = defaults()

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func actor(id: String) -> Dictionary:
	return sim.state.player if id == "player" else sim.state.social.npcs.get(id,{})

func _unit(key: String) -> float:
	return posmod((str(sim.rng.seed)+":"+key).hash(),10000)/10000.0

func enabled() -> bool:
	return not "pregnancy" in sim.state.preferences.disabled_tags

func month(condition: Dictionary, minute: int) -> int:
	var start := int(condition.started)
	var finish := int(condition.end_time)
	if finish == sim.calendar.add_months(start,9):
		var result := 1
		while result < 9 and minute >= sim.calendar.add_months(start,result): result += 1
		return result
	return clampi(int(floor(float(minute-start)*9.0/maxi(1,finish-start)))+1,1,9)

func synchronize() -> void:
	initialize()
	var records: Dictionary = sim.state.pregnancy_wellbeing.records
	var active := {}
	if enabled():
		for condition in sim.state.conditions.values():
			if condition.get("id","") != "pregnancy" or condition.status != "active": continue
			var id := str(condition.target)
			var subject := actor(id)
			if subject.is_empty() or int(subject.get("age",0)) < 18 or not sim.services.reproduction.view(id).can_gestate: continue
			active[id] = true
			if not records.has(id) or int(records[id].started) != int(condition.started) or records[id].phase != "pregnancy":
				records[id] = {"started":int(condition.started),"phase":"pregnancy","month":1,"symptoms":{},"updated":_now(),
					"bladder":100.0,"soiled":false,"supplies":0,"accidents":0,"last_accident":-10080,"last_remark":-10080,
					"last_support":-10080,"last_vomiting":-10080,"relief_until":0,"postpartum_until":0,"selfcare":{}}
			var record: Dictionary = records[id]
			record.month = month(condition,_now())
			_refresh(id,record)
	for id in records:
		var record: Dictionary = records[id]
		if active.has(id): continue
		if record.phase == "pregnancy":
			care.cancel(str(id),record)
			var birth_time := -1
			for p in sim.state.reproduction.pregnancies.values():
				if p.target == id and int(p.started) == int(record.started) and p.status == "born": birth_time = maxi(birth_time,int(p.outcome_at))
			for birth in sim.state.healthcare.family:
				if birth.get("parent","")==id and int(birth.get("minute",-1))>=int(record.started): birth_time = maxi(birth_time,int(birth.minute))
			record.phase = "postpartum" if birth_time>=0 and enabled() else "ended"
			record.postpartum_until = birth_time+int(config().rules.postpartum_minutes) if birth_time>=0 and enabled() else 0
		if record.phase == "postpartum" and (_now() >= int(record.postpartum_until) or not enabled()):
			care.cancel(str(id),record)
			record.phase = "ended"
		_refresh(str(id),record)

func _refresh(id: String, record: Dictionary) -> void:
	record.symptoms = {}
	if not enabled() or record.phase == "ended": return
	var day := int(sim.state.clock.day_index)
	for key in config().symptoms:
		if id=="player" and key=="urinary_urgency" and sim.services.has("growth") and not sim.services.growth.enabled("bladder"): continue
		var spec: Dictionary = config().symptoms[key]
		var identity := id+":"+str(int(record.started))+":"+str(key)
		if _unit(identity+":susceptibility") > float(spec.frequency): continue
		var base := float(spec.months[int(record.month)-1])
		if record.phase == "postpartum":
			base = float(spec.get("postpartum",0))*clampf(float(int(record.postpartum_until)-_now())/int(config().rules.postpartum_minutes),0.0,1.0)
		var severity := roundi(base*(0.65+0.5*_unit(identity+":constitution"))*(0.85+0.3*_unit(identity+":"+str(day))))
		if _now() < int(record.relief_until): severity = roundi(severity*0.65)
		if severity >= 12: record.symptoms[key] = clampi(severity,0,95)

func view(id: String = "player") -> Dictionary:
	# Presenters are read-only, including before the first pregnancy exists.
	var record: Dictionary = sim.state.get("pregnancy_wellbeing",{}).get("records",{}).get(id,{})
	if record.is_empty() or not enabled(): return {}
	var result := record.duplicate(true)
	result.active = record.phase in ["pregnancy","postpartum"]
	result.symptom_list = []
	for key in record.symptoms:
		result.symptom_list.append({"id":key,"label":config().symptoms[key].label,"severity":int(record.symptoms[key])})
	result.symptom_list.sort_custom(func(a,b): return a.severity>b.severity if a.severity!=b.severity else a.id<b.id)
	var subject := actor(id)
	result.bladder = float(subject.get("needs",{}).get("bladder",record.bladder)) if id=="player" else float(record.bladder)
	var medical: Dictionary = sim.state.healthcare.records.get(id,{})
	result.seek_care = float(medical.get("bleeding",0))>0 or float(medical.get("infection",0))>=50 or (int(record.symptoms.get("nausea",0))>=80 and float(subject.get("needs",{}).get("hydration",100))<25)
	return result

func conversation_line(id: String, candid: bool = false) -> Dictionary:
	var status := view(id)
	if status.is_empty() or not status.active: return {}
	var key := "recovery" if status.phase == "postpartum" else "comfortable"
	if status.soiled: key = "privacy"
	elif float(status.bladder)<25: key = "urinary_urgency"
	elif not status.symptom_list.is_empty(): key = str(status.symptom_list[0].id)
	if candid and int(status.accidents)>0 and _now()-int(status.last_accident)<=1440: key = "incontinence"
	var pool: Array = config().lines.get(key,config().lines.comfortable)
	var index := mini(pool.size()-1,int(_unit(id+":"+key+":"+str(sim.state.clock.day_index))*pool.size()))
	var text := str(pool[index])
	var pregnancy: Dictionary = sim.services.reproduction.pregnancy(id)
	if candid and not pregnancy.is_empty() and pregnancy.known:
		var attitude := str(pregnancy.decision)
		if attitude=="undecided": attitude = "wanted" if sim.services.reproduction.view(id).desire=="want" else "uncertain"
		text += " "+str(config().attitudes.get(attitude,""))
	return {"id":"pregnancy_wellbeing."+key+"."+str(index),"text":text.strip_edges(),"symptom":key}

func _log(kind: String, data: Dictionary) -> void:
	var history: Array = sim.state.pregnancy_wellbeing.history
	history.append({"kind":kind,"minute":_now(),"data":data.duplicate(true)})
	while history.size()>int(config().rules.history_limit): history.pop_front()
	emit_event("pregnancy_wellbeing_"+kind,data)

func stress(id: String, trigger: String) -> bool:
	var record: Dictionary = sim.state.pregnancy_wellbeing.records.get(id,{})
	if record.is_empty() or record.phase == "ended" or not enabled(): return false
	if id=="player" and sim.services.has("growth") and not sim.services.growth.enabled("bladder"): return false
	if _now()-int(record.last_accident)<int(config().rules.accident_cooldown): return false
	var status := view(id)
	var predisposition := _unit(id+":"+str(int(record.started))+":pelvic_floor")
	var urgency := 100.0-float(status.bladder)
	var chance := maxf(0.0,(int(record.month)-2)*0.007+urgency*0.0012)*(0.35+predisposition)
	if record.phase == "postpartum": chance *= clampf(float(int(record.postpartum_until)-_now())/int(config().rules.postpartum_minutes),0.0,1.0)
	if trigger == "full_bladder": chance = 1.0
	if _unit(id+":"+trigger+":"+str(_now())+":"+str(int(record.accidents))) >= chance: return false
	var protected: bool = int(record.supplies)>0
	if protected: record.supplies -= 1
	else: record.soiled = true
	record.accidents += 1
	record.last_accident = _now()
	record.bladder = minf(100,float(status.bladder)+20)
	_adjust(id,"bladder",20)
	_adjust(id,"hygiene",-2 if protected else -8)
	_adjust(id,"mood",-1 if protected else -2)
	_log("accident",{"target":id,"trigger":trigger,"protected":protected,"text":"Небольшой эпизод недержания. Гигиеническое средство помогло сохранить одежду сухой." if protected else "Небольшой эпизод недержания. Нужны уединение и смена одежды."})
	return true

func _adjust(id: String, need: String, delta: float) -> void:
	var needs: Dictionary = actor(id).get("needs",{})
	if not needs.has(need): return
	if id=="player": sim.services.character.adjust_need(need,delta)
	else: needs[need] = clampf(float(needs[need])+delta,0,100)
	needs[need] = snappedf(float(needs[need]),0.0001)

func tick(minute: int) -> void:
	if minute % 15 == 0: synchronize()
	for id in sim.state.pregnancy_wellbeing.records.keys():
		var record: Dictionary = sim.state.pregnancy_wellbeing.records[id]
		care.tick_job(str(id),record,minute)
		if not enabled() or record.phase == "ended" or actor(str(id)).is_empty() or minute%15!=0: continue
		var elapsed := mini(15,maxi(0,minute-int(record.updated)))
		record.updated = minute
		if elapsed==0: continue
		var symptoms: Dictionary = record.symptoms
		var urgency := float(symptoms.get("urinary_urgency",0))
		if id == "player" and actor(str(id)).needs.has("bladder"):
			_adjust(str(id),"bladder",-(2+urgency*0.08)*elapsed/60.0)
			record.bladder = float(actor(str(id)).needs.get("bladder",record.bladder))
		else: record.bladder = snappedf(maxf(0,float(record.bladder)-(10+urgency*0.08)*elapsed/60.0),0.0001)
		for symptom in symptoms:
			for need in config().symptoms[symptom].get("need_rates",{}):
				_adjust(str(id),str(need),float(config().symptoms[symptom].need_rates[need])*float(symptoms[symptom])/100.0*elapsed/60.0)
		if float(record.bladder)<=0: stress(str(id),"full_bladder")
		elif minute%60==0 and ((id=="player" and sim.get("action_context") is Dictionary and sim.action_context.get("physical",false)) or (id!="player" and actor(str(id)).activity in ["work","walk","practice"])): stress(str(id),"movement")
		if int(symptoms.get("nausea",0))>=70 and minute-int(record.last_vomiting)>=360 and _unit(str(id)+":nausea:"+str(int(minute/60)))<0.08:
			record.last_vomiting = minute
			_adjust(str(id),"hydration",-3)
			_adjust(str(id),"energy",-3)
			_log("nausea",{"target":id,"text":"Приступ тошноты: нужен спокойный перерыв."})
		if id!="player" and sim.services.npc_agency.enabled(): care.consider(str(id),record)
		if minute-int(record.last_remark)>=int(config().rules.remark_cooldown): _remark(str(id),record)

func _remark(id: String, record: Dictionary) -> void:
	if id!="player":
		var subject := actor(id)
		if subject.activity=="sleep" or (subject.has("mind") and not subject.mind.boundaries.contact): return
	var line := conversation_line(id)
	if line.is_empty(): return
	record.last_remark = _now()
	var listener := ""
	if id!="player":
		var subject := actor(id)
		var candidates: Array = sim.state.social.npcs.keys()
		candidates.sort()
		for other in candidates:
			var npc: Dictionary = actor(str(other))
			if other==id or int(npc.age)<18 or npc.location!=subject.location or npc.activity=="sleep": continue
			if npc.has("mind") and not npc.mind.boundaries.contact: continue
			listener = str(other)
			break
	_log("remark",{"target":id,"listener":listener,"line_id":line.id,"symptom":line.symptom,"text":line.text})
	if not listener.is_empty():
		var replies: Array = config().support_lines
		var reply := str(replies[mini(replies.size()-1,int(_unit(listener+":"+str(sim.state.clock.day_index))*replies.size()))])
		_log("reply",{"target":listener,"listener":id,"text":reply})
		if _now()-int(record.last_support)>=1440:
			record.last_support = _now()
			record.relief_until = maxi(int(record.relief_until),_now()+120)
			_adjust(id,"mood",3)

func observe(module_id: String, operation: String, args: Dictionary, _before: Dictionary) -> void:
	synchronize()
	if module_id=="needs" and operation=="toilet": care.apply("player","toilet")
	elif module_id=="world" and operation=="shower": care.apply("player","cleanup")
	elif module_id=="character" and operation=="rest" or module_id=="needs" and operation in ["sleep","nap"]: care.apply("player","rest")
	elif module_id=="health" and operation=="prenatal_care":
		var id := str(args.get("target","player"))
		if sim.state.pregnancy_wellbeing.records.has(id): sim.state.pregnancy_wellbeing.records[id].relief_until = _now()+720
	elif operation in ["interact","choose"] and (args.get("action","")=="joke" or args.get("choice","")=="joke"):
		stress("player","laughter")
		if actor(str(args.get("id",""))).has("id"): stress(str(args.id),"laughter")
	elif module_id=="activities" and operation=="practice" and args.get("id","") in ["strength","running"]: stress("player","exercise")

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation=="inspect": return Rules.ok(view(str(args.get("target","player"))))
	return care.execute(operation,args)
