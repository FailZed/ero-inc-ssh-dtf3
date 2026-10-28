extends "res://scripts/mechanics/core/module.gd"
## Adult physiology, discomfort and confidential medical care. Game-balanced rates.
const PATH := "res://data/mechanics/adult_health.json"
const Cycle = preload("res://scripts/mechanics/adult_health_cycle.gd")
const Infections = preload("res://scripts/mechanics/adult_health_infections.gd")
const Plans = preload("res://scripts/mechanics/health_care_plans.gd")
const Care = preload("res://scripts/mechanics/adult_health_care.gd")
const Relationships = preload("res://scripts/mechanics/adult_health_relationships.gd")
static var _config: Dictionary = {}
var cycle
var infections
var care
var relationships
var plans

static func config() -> Dictionary:
	if _config.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary: _config = parsed
	return _config

static func defaults() -> Dictionary:
	return {"version":2,"rules_hash":JSON.stringify(config()).sha256_text(),"records":{},"contacts":[],"history":[]}

func _init(simulation) -> void:
	super(simulation)
	cycle = Cycle.new(simulation)
	infections = Infections.new(simulation)
	care = Care.new(simulation)
	relationships = Relationships.new(simulation)
	plans = Plans.new(simulation)

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func actor(id: String) -> Dictionary:
	return sim.state.player if id=="player" else sim.state.social.npcs.get(id,{})

func adult(id: String) -> bool:
	return not actor(id).is_empty() and int(actor(id).get("age",0))>=18

func enabled() -> bool:
	return not "adult" in sim.state.preferences.disabled_tags

func pregnant(id: String) -> bool:
	return sim.state.conditions.get(id+":pregnancy",{}).get("status","")=="active"

func unit(key: String) -> float:
	return posmod((str(sim.rng.seed)+":adult_health:"+key).hash(),10000)/10000.0

func capabilities(id: String) -> Dictionary:
	if not adult(id): return {}
	var reproduction: Dictionary = sim.services.reproduction.view(id)
	var appearance: Dictionary = actor(id).get("appearance",{})
	return {"menstruates":bool(reproduction.cycling),"has_cervix":bool(appearance.get("has_cervix",reproduction.can_gestate)),
		"erections":bool(appearance.get("has_penis",reproduction.produces_sperm))}

func new_record(id: String) -> Dictionary:
	return {"created":_now(),"updated":_now(),"symptoms":{},"soiled":false,"last_remark":-10080,"relief_until":0,"consult_after":0,"last_consult":-10080,
		"desire":{"baseline":35+int(unit(id+":libido")*45),"libido":50,"intent":"context","satisfaction":60.0,"frustration":0.0,"last_failure":-10080,"failures":0},
		"cycle":{"active":false,"day":0,"flow":0.0,"product":"none","fill":0.0,"changed":0,"leaks":0,"last_leak":-10080,
			"supplies":{"pad":6,"night_pad":2,"cup":0}},
		"erection":{"started":0,"until":0,"painful":false,"persistent":false,"episodes":0,"last_event":-10080,"difficulty_until":0,"difficulties":0},
		"hpv":{},"conditions":{},"care_notices":{},"vaccine":{"doses":0,"next_dose":0},"screening":{"last":-10080,"next":0,"result":"none","followup":false},"selfcare":{}}

func initialize() -> void:
	if not sim.state.has("adult_health"): sim.state.adult_health = defaults()

func synchronize() -> void:
	initialize()
	if not enabled():
		for id in sim.state.adult_health.records: care.cancel(str(id))
		return
	var ids: Array = sim.state.social.npcs.keys()
	ids.append("player")
	ids.sort()
	for target in ids:
		var id := str(target)
		if not adult(id): continue
		if not sim.state.adult_health.records.has(id):
			sim.state.adult_health.records[id] = new_record(id)
			infections.seed_population(id)
		_refresh(id)

func record(id: String) -> Dictionary:
	return sim.state.adult_health.records.get(id,{})

func _refresh(id: String) -> void:
	var r := record(id)
	if r.is_empty(): return
	r.symptoms = {}
	cycle.refresh(id)
	for key in r.conditions:
		var condition: Dictionary = r.conditions[key]
		if condition.status!="active": continue
		for symptom in config().conditions[key].symptoms:
			r.symptoms[symptom] = maxi(int(r.symptoms.get(symptom,0)),int(condition.severity))
	infections.refresh_symptoms(id)
	var erection: Dictionary = r.erection
	if not capabilities(id).erections:
		erection.until = 0
		erection.persistent = false
		erection.painful = false
		erection.difficulty_until = 0
	if int(erection.until)>_now():
		r.symptoms["painful_erection" if erection.painful else "spontaneous_erection"] = 75 if erection.painful else 25
	if int(erection.difficulty_until)>_now(): r.symptoms.erectile_difficulty = 50
	if _now()<int(r.relief_until):
		for key in r.symptoms:
			if not key in ["painful_erection","spontaneous_erection"]: r.symptoms[key] = roundi(int(r.symptoms[key])*0.7)
	var discomfort := 0
	for key in r.symptoms:
		if key!="spontaneous_erection": discomfort = maxi(discomfort,int(r.symptoms[key]))
	var maternal: Dictionary = sim.state.get("pregnancy_wellbeing",{}).get("records",{}).get(id,{})
	if maternal.get("phase","") in ["pregnancy","postpartum"]:
		for value in maternal.get("symptoms",{}).values(): discomfort = maxi(discomfort,int(value))
	var needs: Dictionary = actor(id).needs
	var penalty := maxf(0,45-float(needs.energy))*0.5+maxf(0,45-float(needs.mood))*0.35+discomfort*0.22
	var variability := (unit(id+":libido_day:"+str(int(sim.state.clock.day_index)))-0.5)*16
	r.desire.libido = clampi(roundi(int(r.desire.baseline)+variability-penalty),0,100)

func view(id: String = "player") -> Dictionary:
	if not adult(id) or not enabled(): return {}
	var r := record(id)
	if r.is_empty(): return {}
	# Actual hidden pathogens are intentionally absent from this public projection.
	var result := {"capabilities":capabilities(id),"symptoms":r.symptoms.duplicate(true),"soiled":r.soiled,
		"desire":r.desire.duplicate(true),
		"cycle":r.cycle.duplicate(true),"erection":r.erection.duplicate(true),"vaccine":r.vaccine.duplicate(true),
		"screening":r.screening.duplicate(true),"diagnoses":[],"symptom_list":[],"selfcare":r.selfcare.duplicate(true),"care_plan":plans.view(id)}
	for key in r.conditions:
		if r.conditions[key].known and r.conditions[key].status=="active": result.diagnoses.append({"id":key,"label":config().conditions[key].label})
	for strain in r.hpv:
		var infection: Dictionary = r.hpv[strain]
		if infection.known and infection.last_result!="negative": result.diagnoses.append({"id":"hpv_"+str(strain),"label":config().hpv.strains[strain].label})
	for key in r.symptoms:
		result.symptom_list.append({"id":key,"label":config().symptoms[key].label,"severity":int(r.symptoms[key])})
	result.symptom_list.sort_custom(func(a,b): return a.severity>b.severity if a.severity!=b.severity else str(a.id)<str(b.id))
	result.urgent = (bool(r.erection.persistent) and int(r.erection.until)>_now() and _now()-int(r.erection.started)>=int(config().rules.erection_urgent_minutes)) or int(r.symptoms.get("acute_pelvic_pain",0))>=80
	result.seek_care = result.urgent or int(r.erection.difficulties)>=3 or int(r.symptoms.get("heavy_flow",0))>=70 or int(r.symptoms.get("urinary_burning",0))>=35 or int(r.symptoms.get("visible_growths",0))>0 or bool(r.screening.followup)
	return result

func adjust(id: String, need: String, amount: float) -> void:
	var needs: Dictionary = actor(id).get("needs",{})
	if not needs.has(need): return
	if id=="player": sim.services.character.adjust_need(need,amount)
	else:
		# Add fixed decimal units: a JSON float must not change rounding at a half-unit.
		needs[need] = clampi(roundi(float(needs[need])*10000.0)+roundi(amount*10000.0),0,1000000)/10000.0
	needs[need] = snappedf(float(needs[need]),0.0001)

func log_event(kind: String, data: Dictionary) -> void:
	var history: Array = sim.state.adult_health.history
	history.append({"kind":kind,"minute":_now(),"data":data.duplicate(true)})
	while history.size()>int(config().rules.history_limit): history.pop_front()
	emit_event("adult_health_"+kind,data)

func start_erection(id: String, persistent: bool = false, painful: bool = false) -> bool:
	if not adult(id) or not capabilities(id).erections or not enabled(): return false
	var r := record(id)
	if r.is_empty() or int(r.erection.until)>_now(): return false
	var e: Dictionary = r.erection
	e.started = _now()
	e.until = 2147483647 if persistent else _now()+3+int(unit(id+":erection_length:"+str(_now()))*10)
	e.persistent = persistent
	e.painful = painful
	e.episodes += 1
	e.last_event = _now()
	_refresh(id)
	log_event("erection",{"target":id,"text":"Возникла болезненная эрекция. Нужно обсудить это с врачом." if painful else "Внезапная физиологическая реакция. Можно сделать короткий перерыв."})
	return true

func readiness(id: String, partner: String = "") -> Dictionary:
	var r := record(id)
	if r.is_empty() or not capabilities(id).get("erections",false): return {"difficulty":false}
	var needs: Dictionary = actor(id).needs
	var intoxication := float(sim.state.healthcare.records.get(id,{}).get("intoxication",0))
	var stress := maxf(0,35-float(needs.mood))+maxf(0,35-float(needs.energy))+intoxication*0.5
	if not partner.is_empty(): stress += relationships.worry(id,partner)
	return {"difficulty":int(r.erection.difficulty_until)>_now() or (stress>=20 and unit(id+":readiness:"+str(_now()))<minf(0.75,stress/140.0))}

func note_readiness(id: String, partner: String = "") -> void:
	if not readiness(id,partner).difficulty: return
	var r := record(id)
	if int(r.erection.difficulty_until)<=_now():
		r.erection.difficulties += 1
		r.erection.difficulty_until = _now()+180
		log_event("difficulty",{"target":id,"text":"Из-за самочувствия возникли трудности с эрекцией. Можно отложить планы и отдохнуть."})
	_refresh(id)

func intimate_blocked(id: String, partner: String = "") -> String:
	var status := view(id)
	if status.is_empty(): return ""
	if status.urgent: return "adult_health_urgent_care"
	if status.desire.intent=="not_now" or (id!="player" and int(status.desire.libido)<10): return "adult_health_no_desire"
	if not partner.is_empty() and relationships.desire_for(id,partner).get("reason","")!="": return "adult_health_no_desire"
	if int(status.symptoms.get("genital_irritation",0))>=70 or int(status.symptoms.get("urinary_burning",0))>=70: return "adult_health_painful_discomfort"
	return ""

func try_intimacy(first: String, second: String) -> bool:
	if not enabled(): return true
	var failed := false
	for id in [first,second]:
		var partner := second if id==first else first
		if readiness(id,partner).difficulty: note_readiness(id,partner); failed = true
		var r := record(id)
		var pain := 0
		for key in ["period_cramps","painful_erection","urinary_burning","genital_irritation","pelvic_discomfort"]: pain = maxi(pain,int(r.get("symptoms",{}).get(key,0)))
		if pain>=55 and unit(id+":pain_interruption:"+str(_now()))<pain/130.0: failed = true
	if not failed: return true
	for id in [first,second]:
		var r := record(id)
		if r.is_empty() or r.desire.intent=="not_now" or _now()-int(r.desire.last_failure)<180: continue
		var expectation := 1.25 if r.desire.intent=="want_intimacy" else 0.75
		var anxiety := float(actor(id).get("psychology",{}).get("facets",{}).get("anxiety",50))/100.0
		var loss := clampf((2+int(r.desire.libido)*0.06)*expectation*(0.7+anxiety*0.6),1,12)
		adjust(id,"mood",-loss)
		r.desire.frustration = minf(100,float(r.desire.frustration)+loss)
		r.desire.satisfaction = maxf(0,float(r.desire.satisfaction)-loss)
		r.desire.last_failure = _now()
		r.desire.failures += 1
		relationships.setback(id,second if id==first else first,loss)
		log_event("setback",{"target":id,"partner":second if id==first else first,"mood_loss":loss,"text":"Хотелось близости, но самочувствие помешало. Это расстроило; сейчас помогут спокойствие и поддержка."})
	return false

func contact(first: String, second: String, protection: String, key: String) -> void:
	if not enabled() or not adult(first) or not adult(second) or first==second or key.is_empty(): return
	if key in sim.state.adult_health.contacts: return
	synchronize()
	sim.state.adult_health.contacts.append(key)
	while sim.state.adult_health.contacts.size()>128: sim.state.adult_health.contacts.pop_front()
	infections.contact(first,second,protection,key)
	for id in [first,second]:
		var d: Dictionary = record(id).desire
		d.satisfaction = minf(100,float(d.satisfaction)+5+int(d.libido)*0.04)
		d.frustration = maxf(0,float(d.frustration)-5)

func conversation_line(id: String, candid: bool = false, partner: String = "player") -> Dictionary:
	var status := view(id)
	if status.is_empty(): return {}
	var remembered: Dictionary = relationships.conversation_line(id,partner,candid)
	if not remembered.is_empty(): return remembered
	var key := ""
	if status.soiled: key = "privacy"
	elif candid and status.erection.until>_now(): key = "spontaneous_erection"
	elif candid and int(status.erection.difficulties)>0: key = "erectile_difficulty"
	elif candid and not status.diagnoses.is_empty(): key = "hpv" if str(status.diagnoses[0].id).begins_with("hpv_") else "consultation"
	elif not status.symptom_list.is_empty():
		key = str(status.symptom_list[0].id)
		if key in ["spontaneous_erection","painful_erection","erectile_difficulty"] and not candid: key = "privacy"
	if key.is_empty(): return {}
	var pool: Array = config().lines.get(key,config().lines.discomfort)
	var index := mini(pool.size()-1,int(unit(id+":"+key+":"+str(int(sim.state.clock.day_index)))*pool.size()))
	return {"id":"adult_health."+key+"."+str(index),"text":str(pool[index]),"symptom":key}

func tick(minute: int) -> void:
	if minute%15==0: synchronize()
	var targets: Array = sim.state.adult_health.records.keys()
	targets.sort()
	for target in targets:
		var id := str(target)
		if not adult(id): continue
		care.tick_job(id)
		if not enabled(): continue
		var r := record(id)
		if int(r.erection.until)>0 and minute>=int(r.erection.until) and not r.erection.persistent:
			r.erection.until = 0
			r.erection.painful = false
			_refresh(id)
		if minute%15!=0: continue
		var elapsed := mini(15,maxi(0,minute-int(r.updated)))
		r.updated = minute
		r.desire.frustration = snappedf(maxf(0,float(r.desire.frustration)-elapsed/30.0),0.0001)
		cycle.tick_actor(id,elapsed)
		plans.tick_actor(id)
		infections.tick_actor(id)
		if minute%60==0 and capabilities(id).erections and minute-int(r.erection.last_event)>=180:
			if unit(id+":spontaneous:"+str(minute))<float(config().rules.spontaneous_hourly_chance): start_erection(id)
		for key in r.symptoms:
			for need in config().symptoms[key].get("need_rates",{}): adjust(id,str(need),float(config().symptoms[key].need_rates[need])*float(r.symptoms[key])/100.0*elapsed/60.0)
		if id!="player" and sim.services.npc_agency.enabled(): care.consider(id)
		if minute-int(r.last_remark)>=int(config().rules.remark_cooldown) and not (id!="player" and actor(id).activity=="sleep"):
			var line := conversation_line(id)
			if not line.is_empty():
				r.last_remark = minute
				log_event("remark",{"target":id,"line_id":line.id,"text":line.text})

func observe(module_id: String, operation: String, args: Dictionary, _before: Dictionary, result: Dictionary) -> void:
	synchronize()
	if module_id=="world" and operation=="shower": care.apply("player","cleanup")
	if module_id=="character" and operation=="rest" or module_id=="needs" and operation in ["sleep","nap"]:
		care.apply("player","rest")
		if operation=="sleep" or int(args.get("minutes",0))>=120: start_erection("player")

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("target","player"))
	if not adult(id): return Rules.fail("adult_health_adults_only")
	if not enabled(): return Rules.fail("content_disabled")
	if operation=="inspect": return Rules.ok(view(id))
	if id!="player": return Rules.fail("patient_decision_required")
	if operation=="snooze_care": return plans.snooze(id,str(args.get("id","")))
	if operation=="desire":
		var intent := str(args.get("intent","context"))
		if not intent in ["context","want_intimacy","not_now"]: return Rules.fail("invalid_intimacy_intention")
		record(id).desire.intent = intent
		return Rules.ok()
	return care.execute(operation,args)
