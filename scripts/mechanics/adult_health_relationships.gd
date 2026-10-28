extends "res://scripts/mechanics/core/module.gd"
## Directed wishes and remembered reassurance reuse the existing bounded social memory.

func health():
	return sim.services.adult_health

func now() -> int:
	return int(sim.state.clock.total_minutes)

func rules() -> Dictionary:
	return health().config().relationships

func memories(id: String) -> Array:
	return health().actor(id).get("memories",[]) if id!="player" else sim.state.adult_health.history

func worry(id: String, partner: String) -> float:
	var reassurance := -10080
	var failures: Array = []
	for entry in memories(id):
		var data: Dictionary = entry.get("data",{})
		if id=="player" and data.get("target","")!=id: continue
		if data.get("partner","")!=partner: continue
		if entry.kind in ["health_support","support"]: reassurance = maxi(reassurance,int(entry.minute))
		if entry.kind in ["health_setback","setback"]: failures.append(entry)
	var result := 0.0
	for entry in failures:
		var age := now()-int(entry.minute)
		if int(entry.minute)<=reassurance or age>=int(rules().memory_minutes): continue
		result += float(entry.data.get("mood_loss",3))*float(rules().worry_gain)*(1.0-age/float(rules().memory_minutes))
	return minf(float(rules().worry_cap),result)

func desire_for(id: String, partner: String) -> Dictionary:
	if id==partner or not health().enabled() or not health().adult(id) or not health().adult(partner): return {}
	var r: Dictionary = health().record(id)
	if r.is_empty(): return {}
	var intent := str(r.desire.intent)
	var anxiety := worry(id,partner)
	var result := {"libido":int(r.desire.libido),"intent":intent,"worry":snappedf(anxiety,0.001),
		"score":float(r.desire.libido),"reason":"","factors":{}}
	# The player's explicit choice is authoritative; NPC feelings cannot define it.
	if id!="player":
		var bond: Dictionary = sim.services.npc_relationships.view(id,partner)
		result.affection = float(bond.affection)
		result.attraction = float(bond.interest)
		result.trust = float(bond.trust)
		result.comfort = float(bond.comfort)
		result.factors = {"libido":int(r.desire.libido)*0.6,"attraction":float(bond.interest)*0.25,
			"comfort":float(bond.comfort)*0.1,"trust":float(bond.trust)*0.05,
			"unresolved_harm":-float(bond.grievance)*0.5,"remembered_worry":-anxiety,
			"intention":10.0 if intent=="want_intimacy" else 0.0}
		result.score = 0.0
		for value in result.factors.values(): result.score += float(value)
		result.score = snappedf(clampf(result.score,0,100),0.001)
	if intent=="not_now" or (id!="player" and (int(r.desire.libido)<10 or float(result.score)<float(rules().minimum_desire))): result.reason = "adult_health_no_desire"
	return result

func _moodlet(id: String, key: String, emotion: String, strength: float, duration: int) -> void:
	var npc: Dictionary = health().actor(id)
	if id=="player" or not npc.has("mind"): return
	var entries: Array = npc.mind.moodlets
	for index in range(entries.size()-1,-1,-1):
		if entries[index].key==key: entries.remove_at(index)
	if strength>0:
		var profile: Dictionary = sim.services.npc_personalities.profile(npc)
		var remembered := maxi(1,roundi(duration*float(profile.memory_duration)))
		entries.append({"key":key,"emotion":emotion,"strength":clampf(strength,0,100),"duration":remembered,"expires":now()+remembered})
	while entries.size()>int(sim.services.npc_agency.rules().moodlet_limit): entries.pop_front()
	sim.services.npc_agency._emotion(npc)

func setback(id: String, partner: String, mood_loss: float) -> void:
	if id=="player" or not health().actor(id).has("mind"): return
	sim.services.social.remember(id,"health_setback",{"partner":partner,"mood_loss":mood_loss})
	# A physiological difficulty produces worry, not blame or a rejection sentiment.
	_moodlet(id,"health_setback:"+partner,"anxious",mood_loss*2,1440)

func distress(id: String, observer: String = "") -> float:
	if not observer.is_empty():
		# AI sees mood and an experience it shared, never another actor's hidden diagnosis.
		var visible := maxf(0,75-float(health().actor(id).get("needs",{}).get("mood",100)))/50.0
		return clampf(maxf(visible,worry(observer,id)/float(rules().worry_cap)),0,1)
	var r: Dictionary = health().record(id)
	var pressure := float(r.get("desire",{}).get("frustration",0))/30.0
	for symptom in r.get("symptoms",{}):
		if symptom!="spontaneous_erection": pressure = maxf(pressure,float(r.symptoms[symptom])/100.0)
	var maternal: Dictionary = sim.state.get("pregnancy_wellbeing",{}).get("records",{}).get(id,{})
	if maternal.get("phase","") in ["pregnancy","postpartum"]:
		for severity in maternal.get("symptoms",{}).values(): pressure = maxf(pressure,float(severity)/100.0)
	return clampf(pressure,0,1)

func support(helper: String, recipient: String) -> void:
	if not health().enabled() or helper==recipient or not health().adult(helper) or not health().adult(recipient): return
	var r: Dictionary = health().record(recipient)
	if r.is_empty() or distress(recipient)<=0: return
	for entry in memories(recipient):
		if entry.kind in ["health_support","support"] and entry.data.get("partner","")==helper and (recipient!="player" or entry.data.get("target","")==recipient) and now()-int(entry.minute)<int(rules().support_cooldown): return
	health().adjust(recipient,"mood",3)
	r.desire.frustration = maxf(0,float(r.desire.frustration)-8)
	r.relief_until = maxi(int(r.relief_until),now()+120)
	health().adjust(helper,"energy",-2)
	var maternal: Dictionary = sim.state.get("pregnancy_wellbeing",{}).get("records",{}).get(recipient,{})
	if maternal.get("phase","") in ["pregnancy","postpartum"]:
		maternal.relief_until = maxi(int(maternal.relief_until),now()+120)
		maternal.last_support = now()
	if recipient!="player": sim.services.social.remember(recipient,"health_support",{"partner":helper})
	_moodlet(recipient,"health_setback:"+helper,"anxious",0,1)
	_moodlet(recipient,"health_support:"+helper,"grateful",8,360)
	health().log_event("support",{"target":recipient,"partner":helper,"text":"Спокойный разговор помог справиться с переживаниями и попросить о перерыве."})
	health()._refresh(recipient)

func conversation_line(id: String, partner: String, candid: bool) -> Dictionary:
	if not candid or not health().enabled() or worry(id,partner)<1: return {}
	return {"id":"adult_health.remembered_setback","symptom":"remembered_setback",
		"text":"После той неудачи я немного волнуюсь. Давай без спешки: мне важно знать, что можно остановиться и просто побыть рядом."}
