extends RefCounted
const V = preload("res://scripts/mechanics/core/validation.gd")
const N = preload("res://scripts/mechanics/core/computer_validation.gd")

static func catalog_error(catalog: Dictionary) -> String:
	var r: Variant = catalog.get("antagonism_rules")
	if not V.fields(r,{"interval":"n","global_cooldown":"n","actor_cooldown":"n","case_limit":"n","active_limit":"n","threshold":"n","chance":"n","kinds":"d","responses":"d"}): return "invalid_antagonism_catalog"
	if not N.integer(r.interval,60,1440) or not N.integer(r.global_cooldown,360,10080) or not N.integer(r.actor_cooldown,1440,43200) or r.case_limit != 48 or r.active_limit != 2 or not N.bounded(r.threshold,0.1,2) or not N.bounded(r.chance,0,1): return "invalid_antagonism_balance"
	for id in ["extortion","intimidation","slander","sabotage"]:
		var s: Variant = r.kinds.get(id)
		if not V.fields(s,{"label":"s","motive":"s","tag":"s","deadline":"n","physical":"b","amount":"n","damage":"n","text":"s"}): return "invalid_pressure_kind"
		if not s.motive in ["profit","dominance","resentment","ambition"] or not s.tag in ["crime","conflict","deception"] or not N.integer(s.deadline,120,1440) or not N.integer(s.amount,0,100) or not N.integer(s.damage,0,20): return "invalid_pressure_kind"
	for id in ["document","investigate","ally","refuse","pay","secure","report","expose","evade"]:
		var s: Variant = r.responses.get(id)
		if not V.fields(s,{"label":"s","minutes":"n"}) or not N.integer(s.minutes,0,60): return "invalid_pressure_response"
	return ""

static func state_error(state: Dictionary,catalog: Dictionary) -> String:
	var s: Variant = state.get("antagonism")
	if not V.fields(s,{"version":"n","serial":"n","next_check":"n","actors":"d","cases":"d","history":"a"}): return "invalid_antagonism_state"
	if s.version != 1 or not N.integer(s.serial) or not N.integer(s.next_check) or s.cases.size()>48 or s.history.size()>64: return "invalid_antagonism_state"
	var now := int(state.clock.total_minutes)
	for id in s.actors:
		var a: Variant = s.actors[id]
		if not state.social.npcs.has(id) or not V.fields(a,{"impunity":"n","deterrence":"n","cooldown":"n","exposed":"n"}): return "invalid_antagonist"
		if not N.bounded(a.impunity,0,100) or not N.bounded(a.deterrence,0,100) or not N.integer(a.cooldown) or not N.integer(a.exposed): return "invalid_antagonist"
	var active := 0
	var actors := []; var targets := []
	for id in s.cases:
		var c: Variant = s.cases[id]
		if not V.fields(c,{"id":"s","actor":"s","target":"s","kind":"s","motive":"s","location":"s","created":"n","deadline":"n","status":"s","evidence":"n","documented":"b","investigated":"b","ally":"s","used":"a","witnesses":"a","observed":"b","project":"s","loss":"n","result":"s","ended":"n","rumor_until":"n"}): return "invalid_pressure_case"
		if c.id != id or not id.begins_with("pressure_") or not N.integer(int(id.trim_prefix("pressure_")),1,int(s.serial)): return "invalid_pressure_id"
		if not state.social.npcs.has(c.actor) or (c.target != "player" and not state.social.npcs.has(c.target)) or c.actor == c.target or not catalog.antagonism_rules.kinds.has(c.kind): return "invalid_pressure_actor"
		if not catalog.locations.has(c.location) or c.motive != catalog.antagonism_rules.kinds[c.kind].motive: return "invalid_pressure_context"
		if not N.integer(c.created,0,now) or c.deadline != c.created+int(catalog.antagonism_rules.kinds[c.kind].deadline) or not N.integer(c.evidence,0,3) or not N.integer(c.loss,0,100) or not N.integer(c.ended,0,now) or not N.integer(c.rumor_until): return "invalid_pressure_values"
		if not c.status in ["open","resolved","cancelled"] or (not c.ally.is_empty() and (not state.social.npcs.has(c.ally) or c.ally in [c.actor,c.target])): return "invalid_pressure_status"
		if c.kind != "slander" and c.rumor_until != 0: return "invalid_pressure_rumor"
		if c.status == "open":
			if int(c.deadline)<=now or c.actor in actors or c.target in targets or c.ended != 0 or c.loss != 0: return "invalid_pressure_active"
			active += 1; actors.append(c.actor); targets.append(c.target)
		var used := []
		for choice in c.used:
			if not choice is String or not catalog.antagonism_rules.responses.has(choice) or choice in used: return "invalid_pressure_responses"
			used.append(choice)
		if c.documented != ("document" in used) or c.investigated != ("investigate" in used): return "invalid_pressure_evidence"
		var witnesses := []
		if c.witnesses.size()>8: return "invalid_pressure_witnesses"
		for witness in c.witnesses:
			if not V.fields(witness,{"id":"s","stance":"s"}) or not state.social.npcs.has(witness.id) or witness.id in witnesses or witness.id in [c.actor,c.target] or not witness.stance in ["silent","support","complicit"]: return "invalid_pressure_witness"
			witnesses.append(witness.id)
	if active>2: return "invalid_pressure_capacity"
	for h in s.history:
		if not V.fields(h,{"id":"s","minute":"n","result":"s","loss":"n"}) or not N.integer(h.minute,0,now) or not N.integer(h.loss,0,100): return "invalid_pressure_history"
	return ""
