extends RefCounted
const V = preload("res://scripts/mechanics/core/validation.gd")
const H = preload("res://scripts/mechanics/core/human_validation.gd")
const Context = preload("res://scripts/mechanics/npc_reproductive_context.gd")
const STAGES := ["travelling","invitation","discussion","protection","ready","active","aftercare"]
const JOBS := ["buy","contraception","emergency","test","terminate","procedure","prenatal_care","support_case","visit_family"]

static func policy_error(p: Variant) -> String:
	if not V.fields(p,{"enabled":"b","preferred_method":"s","pregnancy_decision":"s","parenthood":"s","procedure":"s","emergency":"b"}) or p.size()!=6: return "invalid_npc_reproductive_policy"
	if not p.preferred_method in ["auto","none","barrier","pill","iud","implant"]: return "invalid_npc_reproductive_policy"
	if not p.pregnancy_decision in ["auto","continue","terminate","adoption"] or not p.parenthood in ["auto","retain","decline"] or not p.procedure in ["none","tubal_ligation","vasectomy"]: return "invalid_npc_reproductive_policy"
	return ""

static func catalog_error(catalog: Dictionary) -> String:
	var group: Variant=catalog.get("npc_reproduction_rules")
	if not group is Dictionary or not group.get("simulation") is Dictionary: return "invalid_npc_reproductive_catalog"
	var r: Dictionary=group.simulation
	for key in ["scan_minutes","health_minutes","stage_minutes","actor_budget","pair_candidates","pair_cooldown","decline_cooldown","job_retry_minutes","decision_delay","barrier_stock","pill_stock","shop_minutes","paperwork_minutes","history_limit"]:
		if not H.integer(r.get(key),1,10080): return "invalid_npc_reproductive_rule:"+key
	if not H.integer(r.get("max_sessions"),1,64) or not H.integer(r.get("max_jobs"),1,256) or int(r.history_limit)>512 or int(r.actor_budget)>256 or int(r.pair_candidates)>32: return "invalid_npc_reproductive_limits"
	if not H.number(r.get("initiative_chance"),0,1) or not H.number(r.get("courtship_trust"),0,100) or not H.integer(r.get("reserve_money"),0,100000): return "invalid_npc_reproductive_rule"
	if not H.integer(r.get("opening_hour"),0,23) or not H.integer(r.get("closing_hour"),1,24) or int(r.opening_hour)>=int(r.closing_hour): return "invalid_npc_reproductive_hours"
	return ""

static func _npc(state: Dictionary, id: Variant) -> bool:
	return id is String and id!="player" and state.social.npcs.has(id) and state.social.npcs[id].has("mind") and int(state.social.npcs[id].age)>=18

static func _time(value: Variant) -> bool:
	return H.integer(value,0,2147483647)

static func _serial(value: String, prefix: String) -> int:
	if not value.begins_with(prefix) or not value.trim_prefix(prefix).is_valid_int(): return -1
	var result:=int(value.trim_prefix(prefix))
	return result if result>0 else -1

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var s: Variant=state.get("npc_reproduction")
	if not V.fields(s,{"version":"n","enabled":"b","sessions":"d","jobs":"d","routines":"d","policies":"d","decisions":"d","cooldowns":"d","next_id":"n","next_scan":"n","next_health":"n","cursor":"n","history":"a"}) or s.version!=1: return "invalid_npc_reproductive_state"
	for key in ["next_scan","next_health","cursor"]:
		if not _time(s[key]): return "invalid_npc_reproductive_time"
	if not H.integer(s.next_id,1,2147483647): return "invalid_npc_reproductive_sequence"
	var rules: Dictionary=catalog.npc_reproduction_rules.simulation
	if s.sessions.size()>int(rules.max_sessions) or s.jobs.size()>int(rules.max_jobs) or s.history.size()>int(rules.history_limit): return "unbounded_npc_reproductive_state"
	for id in s.policies:
		if not state.social.npcs.has(id): return "unknown_npc_reproductive_actor"
		var error:=policy_error(s.policies[id])
		if not error.is_empty(): return error
	for id in s.routines:
		var routine: Variant=s.routines[id]
		if not _npc(state,id) or not V.fields(routine,{"due":"n","next_try":"n"}) or not _time(routine.due) or not H.integer(routine.next_try,int(routine.due),2147483647): return "invalid_npc_reproductive_routine"
		var record: Dictionary=state.reproduction.records.get(id,{})
		if not s.enabled or record.get("method","")!="pill" or int(routine.due)!=int(record.get("last_dose",-1))+1440: return "inconsistent_npc_reproductive_routine"
	for key in s.cooldowns:
		if not key is String or not _time(s.cooldowns[key]): return "invalid_npc_reproductive_cooldown"
		var ids: PackedStringArray=key.split("|")
		if ids.size()!=2 or not _npc(state,ids[0]) or not _npc(state,ids[1]) or ids[0]>=ids[1]: return "invalid_npc_reproductive_cooldown"
	for id in s.decisions:
		var p: Dictionary=state.reproduction.pregnancies.get(id,{})
		if p.is_empty() or "player" in [p.target,p.partner]: return "invalid_npc_pregnancy_plan"
		var plan: Variant=s.decisions[id]
		if not V.fields(plan,{"decision":"s","care":"s","created":"n","next_try":"n","applied":"b"}): return "invalid_npc_pregnancy_plan"
		if not plan.decision in ["continue","terminate","adoption"] or not plan.care in ["retain","relinquish"] or not H.integer(plan.created,0,int(state.clock.total_minutes)) or not _time(plan.next_try): return "invalid_npc_pregnancy_plan"
	for p in state.reproduction.pregnancies.values():
		if p.has("gestator_parenthood") and not p.gestator_parenthood in ["retain","relinquish"]: return "invalid_npc_parental_plan"
	var used: Dictionary={}
	var serials: Dictionary={}
	var maximum:=0
	for id in s.sessions:
		var a: Variant=s.sessions[id]
		if not V.fields(a,{"id":"s","a":"s","b":"s","venue":"s","scope":"s","stage":"s","revision":"n","created":"n","next_step":"n","reserved_until":"n","saved":"d","protection":"s","barrier_owner":"s","potential_conception":"b","intended":"b","resolved":"b","exposure":"s","due":"n"}): return "invalid_npc_encounter"
		var serial:=_serial(str(id),"npc_encounter_")
		if a.id!=id or serial<1 or serials.has(serial): return "invalid_npc_reproductive_sequence"
		serials[serial]=true
		maximum=maxi(maximum,serial)
		if not _npc(state,a.a) or not _npc(state,a.b) or a.a==a.b or used.has(a.a) or used.has(a.b): return "conflicting_npc_reproductive_reservation"
		if not s.policies.get(a.a,{}).get("enabled",true) or not s.policies.get(a.b,{}).get("enabled",true): return "invalid_npc_reproductive_reservation"
		if not catalog.locations.has(a.venue) or a.venue!=state.social.npcs[a.a].home or a.scope!="npc_home:"+a.a: return "invalid_npc_private_scope"
		if not a.stage in STAGES or not H.integer(a.revision,1,1000000): return "invalid_npc_encounter_stage"
		if not H.integer(a.created,0,int(state.clock.total_minutes)) or not H.integer(a.next_step,int(state.clock.total_minutes)+1,2147483647) or not H.integer(a.reserved_until,int(a.next_step)+1,2147483647) or not _time(a.due): return "invalid_npc_encounter_time"
		if not s.enabled or not state.world.flags.get("npc_agency_enabled",false) or a.saved.size()!=2: return "invalid_npc_reproductive_reservation"
		for actor_id in [a.a,a.b]:
			var saved: Variant=a.saved.get(actor_id)
			if not V.fields(saved,{"pin":"n","activity":"s","origin":"s","arrival":"n","arrived":"b"}) or not _time(saved.pin) or not catalog.locations.has(saved.origin) or not H.integer(saved.arrival,int(a.created),int(a.reserved_until)): return "invalid_npc_encounter_reservation"
			if int(state.social.npcs[actor_id].pinned_until)!=int(a.reserved_until): return "inconsistent_npc_reproductive_pin"
			if state.social.npcs[actor_id].location!=(a.venue if saved.arrived else saved.origin): return "inconsistent_npc_reproductive_location"
			if a.stage!="travelling" and not saved.arrived: return "inconsistent_npc_reproductive_arrival"
			used[actor_id]=id
		if not a.protection in ["","non_reproductive","barrier","regular_method","unprotected"]: return "invalid_npc_encounter_protection"
		if a.protection=="barrier" and not a.barrier_owner in [a.a,a.b]: return "invalid_npc_barrier_owner"
		if a.stage in ["ready","active","aftercare"] and a.protection.is_empty(): return "invalid_npc_encounter_protection"
		if a.resolved!=(a.stage=="aftercare"): return "invalid_npc_encounter_outcome"
		if a.stage=="active" and (int(a.due)<=int(state.clock.total_minutes) or int(a.next_step)!=int(a.due)): return "invalid_npc_encounter_time"
		if not a.exposure.is_empty():
			var exposure: Dictionary=state.reproduction.exposures.get(a.exposure,{})
			if exposure.is_empty() or exposure.session!=id or not exposure.target in [a.a,a.b] or not exposure.partner in [a.a,a.b]: return "invalid_npc_encounter_exposure"
	for id in s.jobs:
		var j: Variant=s.jobs[id]
		if not V.fields(j,{"id":"s","npc":"s","kind":"s","destination":"s","origin":"s","created":"n","arrival":"n","due":"n","phase":"s","previous_pin":"n","previous_activity":"s","reserved_until":"n","payload":"d"}): return "invalid_npc_reproductive_job"
		var serial:=_serial(str(j.id),"npc_job_")
		if j.npc!=id or not _npc(state,id) or used.has(id) or serial<1 or serials.has(serial): return "conflicting_npc_reproductive_reservation"
		if not s.policies.get(id,{}).get("enabled",true): return "invalid_npc_reproductive_reservation"
		serials[serial]=true
		maximum=maxi(maximum,serial)
		used[id]=j.id
		if not j.kind in JOBS or not j.phase in ["travel","action"] or not catalog.locations.has(j.destination) or not catalog.locations.has(j.origin): return "invalid_npc_reproductive_job"
		if not H.integer(j.created,0,int(state.clock.total_minutes)) or not H.integer(j.arrival,int(j.created),2147483647) or not H.integer(j.due,int(j.arrival)+1,2147483647) or int(j.due)<=int(state.clock.total_minutes): return "invalid_npc_reproductive_job_time"
		if not _time(j.previous_pin) or not _time(j.reserved_until) or int(j.reserved_until)!=int(j.due)+1 or int(state.social.npcs[id].pinned_until)!=int(j.reserved_until): return "inconsistent_npc_reproductive_pin"
		if state.social.npcs[id].location!=(j.origin if j.phase=="travel" else j.destination): return "inconsistent_npc_reproductive_location"
		if not s.enabled or not state.world.flags.get("npc_agency_enabled",false): return "invalid_npc_reproductive_reservation"
		var p: Dictionary=j.payload
		match str(j.kind):
			"buy":
				if not V.fields(p,{"item":"s","quantity":"n","shop":"s"}) or not catalog.items.has(p.item) or not catalog.shops.has(p.shop) or not H.integer(p.quantity,1,64): return "invalid_npc_supply_job"
			"contraception":
				if not p.get("method") is String or not catalog.contraceptive_methods.has(p.method): return "invalid_npc_contraception_job"
			"procedure":
				if not p.get("procedure") is String or not catalog.reproductive_procedures.has(p.procedure): return "invalid_npc_procedure_job"
			"terminate", "prenatal_care":
				if not p.get("pregnancy") is String or not state.reproduction.pregnancies.has(p.pregnancy) or state.reproduction.pregnancies[p.pregnancy].target!=id: return "invalid_npc_pregnancy_job"
			"support_case":
				if not p.get("obligation") is String or not state.child_support.obligations.has(p.obligation) or state.child_support.obligations[p.obligation].recipient!=id: return "invalid_npc_support_job"
			"visit_family":
				if not p.get("member") is String or not state.family.members.has(p.member) or not id in state.family.members[p.member].get("guardians",state.family.members[p.member].parents): return "invalid_npc_family_job"
	for h in s.history:
		if not V.fields(h,{"kind":"s","minute":"n","data":"d"}) or not H.integer(h.minute,0,int(state.clock.total_minutes)): return "invalid_npc_reproductive_history"
		for field in ["session","job"]:
			if not h.data.has(field): continue
			if not h.data[field] is String: return "invalid_npc_reproductive_history"
			var serial:=_serial(h.data[field],"npc_encounter_" if field=="session" else "npc_job_")
			if serial<1: return "invalid_npc_reproductive_history"
			maximum=maxi(maximum,serial)
	if int(s.next_id)<=maximum: return "invalid_npc_reproductive_sequence"
	return ""
