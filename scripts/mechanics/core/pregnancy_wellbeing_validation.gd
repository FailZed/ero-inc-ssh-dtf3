extends RefCounted
const H = preload("res://scripts/mechanics/core/human_validation.gd")
const V = preload("res://scripts/mechanics/core/validation.gd")
const Wellbeing = preload("res://scripts/mechanics/pregnancy_wellbeing.gd")

static func state_error(state: Dictionary) -> String:
	if not state.has("pregnancy_wellbeing"): return ""
	var area: Variant = state.pregnancy_wellbeing
	if not V.fields(area,{"version":"n","rules_hash":"s","records":"d","history":"a"}) or area.version!=1: return "invalid_pregnancy_wellbeing"
	if area.rules_hash!=JSON.stringify(Wellbeing.config()).sha256_text(): return "pregnancy_wellbeing_rules_mismatch"
	var now := int(state.clock.total_minutes)
	if area.records.size()>state.social.npcs.size()+1 or area.history.size()>int(Wellbeing.config().rules.history_limit): return "unbounded_pregnancy_wellbeing"
	for id in area.records:
		if id!="player" and not state.social.npcs.has(id): return "unknown_pregnancy_wellbeing_actor"
		var actor: Dictionary = state.player if id=="player" else state.social.npcs[id]
		if int(actor.get("age",0))<18: return "pregnancy_wellbeing_adults_only"
		var r: Variant = area.records[id]
		if not V.fields(r,{"started":"n","phase":"s","month":"n","symptoms":"d","updated":"n","bladder":"n","soiled":"b","supplies":"n","accidents":"n","selfcare":"d"}): return "invalid_pregnancy_wellbeing_record"
		if not r.phase in ["pregnancy","postpartum","ended"] or not H.integer(r.month,1,9): return "invalid_pregnancy_wellbeing_phase"
		for key in ["started","updated"]:
			if not H.integer(r.get(key),0,now): return "invalid_pregnancy_wellbeing_time"
		for key in ["last_accident","last_remark","last_support","last_vomiting"]:
			if not H.integer(r.get(key),-10080,now): return "invalid_pregnancy_wellbeing_cooldown"
		for key in ["relief_until","postpartum_until"]:
			if not H.integer(r.get(key),0,2147483647): return "invalid_pregnancy_wellbeing_time"
		if not H.number(r.bladder,0,100) or not H.integer(r.supplies,0,99) or not H.integer(r.accidents,0,2147483647): return "invalid_pregnancy_wellbeing_value"
		if r.symptoms.size()>Wellbeing.config().symptoms.size(): return "invalid_pregnancy_symptoms"
		for key in r.symptoms:
			if not Wellbeing.config().symptoms.has(key) or not H.integer(r.symptoms[key],0,95): return "invalid_pregnancy_symptom"
		var job: Dictionary = r.selfcare
		if job.is_empty(): continue
		if id=="player" or not V.fields(job,{"kind":"s","origin":"s","destination":"s","phase":"s","arrival":"n","due":"n","pin":"n","previous_pin":"n"}): return "invalid_pregnancy_selfcare"
		if not job.kind in ["toilet","cleanup","rest","supplies"] or not job.phase in ["travel","action"]: return "invalid_pregnancy_selfcare"
		if not state.social.npcs.has(id) or not state.social.npcs[id].pinned_until==job.pin: return "invalid_pregnancy_selfcare_reservation"
		for key in ["arrival","due","pin","previous_pin"]:
			if not H.integer(job[key],0,2147483647): return "invalid_pregnancy_selfcare_time"
		if int(job.due)<int(job.arrival) or int(job.pin)!=int(job.due)+1 or int(job.due)<now: return "invalid_pregnancy_selfcare_time"
	for event in area.history:
		if not V.fields(event,{"kind":"s","minute":"n","data":"d"}) or not H.integer(event.minute,0,now): return "invalid_pregnancy_wellbeing_history"
	return ""
