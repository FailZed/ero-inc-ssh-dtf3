extends RefCounted
const V = preload("res://scripts/mechanics/core/validation.gd")
const H = preload("res://scripts/mechanics/core/human_validation.gd")
const STAGES := {"invitation":["accept","decline"],"discussion":["non_reproductive","pregnancy_possible","plan_pregnancy","stop"],"protection":["barrier","regular_method","unprotected","stop"],"ready":["start","stop"],"active":["finish","stop"],"aftercare":["close","stop"]}

static func _actor(state: Dictionary, id: String) -> bool:
	return id == "player" or state.social.npcs.has(id)

static func _time(value: Variant) -> bool:
	return H.integer(value, 0, 2147483647)

static func profile_error(profile: Variant) -> String:
	if not profile is Dictionary: return "invalid_reproductive_profile"
	for key in profile:
		match key:
			"can_gestate", "produces_sperm", "cycling", "infertile", "requires_protection":
				if not profile[key] is bool: return "invalid_reproductive_profile"
			"fertility":
				if not H.number(profile[key], 0, 1): return "invalid_reproductive_profile"
			"cycle_offset":
				if not H.integer(profile[key], 0, 89): return "invalid_reproductive_profile"
			"desire":
				if not profile[key] in ["avoid","open","want"]: return "invalid_reproductive_profile"
			_: return "invalid_reproductive_profile"
	return ""

static func catalog_error(catalog: Dictionary) -> String:
	for group in ["reproduction_rules","contraceptive_methods","reproductive_procedures","intimacy_stages","reproduction_protection","child_support_rules"]:
		if not catalog.get(group) is Dictionary: return "missing_reproduction_catalog"
	var rules: Variant = catalog.reproduction_rules.get("simulation")
	if not rules is Dictionary: return "invalid_reproduction_rules"
	for key in ["cycle_days","period_days","ovulation_day","exposure_minutes","detection_minutes","emergency_minutes","session_minutes","invitation_minutes","termination_limit_days","test_minutes","termination_minutes","vasectomy_delay_minutes","history_limit"]:
		if not H.integer(rules.get(key), 1, 525600): return "invalid_reproduction_rule:" + key
	for key in ["fertile_before","fertile_after","minimum_trust","minimum_comfort","minimum_interest","session_energy","cooldown_minutes","test_cost","termination_cost","recovery_minutes"]:
		if not H.integer(rules.get(key), 0, 1000000): return "invalid_reproduction_rule:" + key
	for key in ["conception_chance","emergency_residual"]:
		if not H.number(rules.get(key), 0, 1): return "invalid_reproduction_probability"
	if int(rules.cycle_days) > 90 or int(rules.period_days) >= int(rules.cycle_days) or int(rules.ovulation_day) > int(rules.cycle_days): return "invalid_reproduction_cycle"
	if int(rules.invitation_minutes) <= int(rules.session_minutes) or int(rules.history_limit) > 512: return "invalid_reproduction_rule"
	for id in ["none","pill","iud","implant"]:
		var method: Variant = catalog.contraceptive_methods.get(id)
		if not V.fields(method, {"label":"s","residual":"n","cost":"n","minutes":"n","onset":"n","duration":"n","daily":"b","item":"s"}): return "invalid_contraceptive_method"
		if not H.number(method.residual, 0, 1): return "invalid_contraceptive_residual"
		for key in ["cost","minutes","onset","duration"]:
			if not _time(method[key]): return "invalid_contraceptive_method"
		if id != "none" and int(method.duration) <= 0: return "invalid_contraceptive_method"
		if not method.item.is_empty() and not catalog.items.has(method.item): return "unknown_contraceptive_item"
	for id in ["tubal_ligation","vasectomy"]:
		var procedure: Variant = catalog.reproductive_procedures.get(id)
		if not V.fields(procedure, {"label":"s","cost":"n","minutes":"n","capability":"s"}): return "invalid_reproductive_procedure"
		if not procedure.capability in ["can_gestate","produces_sperm"] or not _time(procedure.cost) or not H.integer(procedure.minutes, 1, 1440): return "invalid_reproductive_procedure"
	var barrier: Variant = catalog.reproduction_protection.get("barrier")
	if not V.fields(barrier, {"residual":"n","item":"s"}) or not H.number(barrier.residual, 0, 1) or not catalog.items.has(barrier.item): return "invalid_barrier_protection"
	for stage in STAGES:
		var value: Variant = catalog.intimacy_stages.get(stage)
		if not V.fields(value, {"hook":"s","choices":"a"}) or value.hook.is_empty() or value.hook.length() > 128 or value.choices != STAGES[stage]: return "invalid_intimacy_graph"
	var support: Variant = catalog.child_support_rules.get("simulation")
	if not support is Dictionary: return "invalid_support_rules"
	for key in ["monthly_amount","enforcement_delay","adult_months"]:
		if not H.integer(support.get(key), 1, 1000000): return "invalid_support_rules"
	if not H.integer(support.get("filing_cost"), 0, 1000000): return "invalid_support_rules"
	for template in catalog.npc_templates.values():
		if template.has("reproductive_profile"):
			var error := profile_error(template.reproductive_profile)
			if not error.is_empty(): return error
	return ""

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	var r: Variant = state.get("reproduction")
	var i: Variant = state.get("intimacy")
	var s: Variant = state.get("child_support")
	if not V.fields(r, {"version":"n","records":"d","exposures":"d","pregnancies":"d","next_id":"n","history":"a"}) or r.version != 1 or not H.integer(r.next_id, 1, 2147483647): return "invalid_reproduction_state"
	if not V.fields(i, {"version":"n","active":"d","next_id":"n","history":"a","cooldowns":"d"}) or i.version != 1 or not H.integer(i.next_id, 1, 2147483647): return "invalid_intimacy_state"
	if not V.fields(s, {"version":"n","obligations":"d","history":"a"}) or s.version != 1: return "invalid_child_support_state"
	for subject in state.social.npcs.values():
		if subject.has("reproductive_profile"):
			var error := profile_error(subject.reproductive_profile)
			if not error.is_empty(): return error
	for id in r.records:
		if not _actor(state, str(id)): return "unknown_reproductive_actor"
		var a: Variant = r.records[id]
		if not V.fields(a, {"can_gestate":"b","produces_sperm":"b","cycling":"b","infertile":"b","fertility":"n","sterilization":"s","effective_at":"n","recovery_until":"n","cycle_epoch":"n","cycle_offset":"n","cycle_days":"n","period_days":"n","ovulation_day":"n","desire":"s","requires_protection":"b","method":"s","method_started":"n","method_effective":"n","method_until":"n","last_dose":"n"}): return "invalid_reproductive_record"
		if not H.number(a.fertility, 0, 1) or not a.desire in ["avoid","open","want"] or not a.sterilization in ["none","tubal_ligation","vasectomy"] or not catalog.contraceptive_methods.has(a.method): return "invalid_reproductive_record"
		if not H.integer(a.cycle_days, 7, 90) or not H.integer(a.period_days, 1, int(a.cycle_days)-1) or not H.integer(a.ovulation_day, 1, int(a.cycle_days)) or not H.integer(a.cycle_offset, 0, int(a.cycle_days)-1): return "invalid_reproductive_cycle"
		if a.cycling and not a.can_gestate: return "invalid_reproductive_capability"
		if a.sterilization == "tubal_ligation" and not a.can_gestate or a.sterilization == "vasectomy" and not a.produces_sperm: return "invalid_reproductive_capability"
		if a.method != "none" and not a.can_gestate: return "invalid_reproductive_capability"
		for key in ["effective_at","recovery_until","cycle_epoch","method_started","method_effective","method_until"]:
			if not _time(a[key]): return "invalid_reproductive_time"
		if int(a.cycle_epoch) > int(state.clock.total_minutes) or not H.integer(a.last_dose, -1, int(state.clock.total_minutes)): return "invalid_reproductive_time"
	var used_sessions := {}
	var maximum_id := 0
	for id in r.exposures:
		var e: Variant = r.exposures[id]
		if not V.fields(e, {"id":"s","target":"s","partner":"s","session":"s","minute":"n","resolve_at":"n","chance":"n","roll":"n","emergency":"b","intended":"b","status":"s","protection":"s"}): return "invalid_reproductive_exposure"
		if e.id != id or not str(id).begins_with("exposure_") or not str(id).trim_prefix("exposure_").is_valid_int(): return "invalid_reproductive_id"
		maximum_id = maxi(maximum_id, int(str(id).trim_prefix("exposure_")))
		if not _actor(state, e.target) or not _actor(state, e.partner) or e.target == e.partner or used_sessions.has(e.session) or e.session.is_empty(): return "invalid_reproductive_exposure"
		used_sessions[e.session] = true
		if not e.status in ["pending","conceived","no_conception","superseded"] or not e.protection in ["barrier","regular_method","unprotected"] or not H.number(e.chance, 0, 1) or not H.number(e.roll, 0, 1): return "invalid_reproductive_exposure"
		if not H.integer(e.minute, 0, int(state.clock.total_minutes)) or not _time(e.resolve_at) or int(e.resolve_at) <= int(e.minute): return "invalid_reproductive_time"
	var pregnant := {}
	for id in r.pregnancies:
		var p: Variant = r.pregnancies[id]
		if not V.fields(p, {"id":"s","target":"s","partner":"s","exposure":"s","started":"n","detected_at":"n","known":"b","intended":"b","status":"s","decision":"s","partner_response":"s","outcome_at":"n"}): return "invalid_reproductive_pregnancy"
		if p.id != id or not str(id).begins_with("pregnancy_") or not str(id).trim_prefix("pregnancy_").is_valid_int(): return "invalid_reproductive_id"
		maximum_id = maxi(maximum_id, int(str(id).trim_prefix("pregnancy_")))
		if not _actor(state, p.target) or not _actor(state, p.partner) or p.target == p.partner or not r.exposures.has(p.exposure): return "invalid_reproductive_pregnancy"
		var e: Dictionary = r.exposures[p.exposure]
		if e.target != p.target or e.partner != p.partner or e.status != "conceived": return "invalid_reproductive_pregnancy"
		if not p.status in ["active","terminated","born","ended"] or not p.decision in ["undecided","continue","terminate","adoption"]: return "invalid_reproductive_pregnancy"
		if not p.partner_response in ["unasked","support","decline_parenthood"]: return "invalid_parenthood_response"
		if not H.integer(p.started, 0, int(state.clock.total_minutes)) or not _time(p.detected_at) or int(p.detected_at) < int(p.started) or not H.integer(p.outcome_at, 0, int(state.clock.total_minutes)): return "invalid_reproductive_time"
		if p.status == "active":
			if pregnant.has(p.target): return "duplicate_active_pregnancy"
			pregnant[p.target] = id
			var condition: Dictionary = state.conditions.get(str(p.target) + ":pregnancy", {})
			if condition.get("status", "") != "active" or condition.get("partner", "") != p.partner or condition.get("reproduction_id", "") != id: return "inconsistent_reproductive_pregnancy"
	if int(r.next_id) <= maximum_id: return "invalid_reproductive_sequence"
	if r.history.size() > int(catalog.reproduction_rules.simulation.history_limit) or i.history.size() > 64 or s.history.size() > 128: return "invalid_reproductive_history"
	for h in r.history:
		if not V.fields(h, {"kind":"s","minute":"n","data":"d"}) or not H.integer(h.minute, 0, int(state.clock.total_minutes)): return "invalid_reproductive_history"
	for id in i.cooldowns:
		if not state.social.npcs.has(id) or not _time(i.cooldowns[id]): return "invalid_intimacy_cooldown"
	for h in i.history:
		if not V.fields(h, {"id":"s","npc":"s","minute":"n","status":"s","reason":"s","resolved":"b","exposure":"s"}) or not state.social.npcs.has(h.npc) or not H.integer(h.minute, 0, int(state.clock.total_minutes)): return "invalid_intimacy_history"
	if not i.active.is_empty():
		var a: Dictionary = i.active
		if not V.fields(a, {"id":"s","npc":"s","stage":"s","revision":"n","created":"n","expires":"n","location":"s","previous_pin":"n","reserved_until":"n","previous_activity":"s","potential_conception":"b","intended":"b","protection":"s","started":"n","due":"n","resolved":"b","exposure":"s"}): return "invalid_intimacy_session"
		if not state.social.npcs.has(a.npc) or not STAGES.has(a.stage) or not H.integer(a.revision, 1, 1000000) or not catalog.locations.has(a.location): return "invalid_intimacy_session"
		if state.social.npcs[a.npc].location != a.location or state.world.location != a.location: return "inconsistent_intimacy_location"
		if not catalog.locations[a.location].get("private", false): return "invalid_intimacy_location"
		if not str(a.id).begins_with("intimacy_") or not str(a.id).trim_prefix("intimacy_").is_valid_int() or int(str(a.id).trim_prefix("intimacy_")) >= int(i.next_id): return "invalid_intimacy_sequence"
		for key in ["created","expires","previous_pin","reserved_until","started","due"]:
			if not _time(a[key]): return "invalid_intimacy_time"
		if int(a.created) > int(state.clock.total_minutes) or int(a.expires) <= int(a.created) or int(a.reserved_until) != int(a.expires) + 1: return "invalid_intimacy_time"
		if int(state.clock.total_minutes) >= int(a.expires) or int(state.social.npcs[a.npc].pinned_until) != int(a.reserved_until): return "invalid_intimacy_reservation"
		if not a.protection in ["","barrier","regular_method","unprotected"]: return "invalid_intimacy_protection"
		if a.stage in ["ready","active","aftercare"] and a.protection.is_empty(): return "invalid_intimacy_protection"
		if a.resolved != (a.stage == "aftercare"): return "invalid_intimacy_completion"
		if a.stage in ["active","aftercare"] and (int(a.due) <= int(a.started) or int(a.started) > int(state.clock.total_minutes)): return "invalid_intimacy_time"
		if a.stage == "active" and int(a.due) <= int(state.clock.total_minutes): return "invalid_intimacy_time"
		if not a.exposure.is_empty() and (not r.exposures.has(a.exposure) or r.exposures[a.exposure].session != a.id): return "invalid_intimacy_exposure"
	for member in state.family.members.values():
		if member.has("guardians"):
			if not member.guardians is Array or not member.get("custody") in ["adoption","other_parent","public_care","parents"]: return "invalid_family_custody"
			var used := {}
			for guardian in member.guardians:
				if not guardian in member.parents or used.has(guardian): return "invalid_family_custody"
				used[guardian] = true
			if member.guardians.is_empty() and not member.custody in ["adoption","public_care"]: return "invalid_family_custody"
	for id in s.obligations:
		var o: Variant = s.obligations[id]
		if not V.fields(o, {"id":"s","member":"s","payer":"s","recipient":"s","monthly":"n","arrears":"n","paid":"n","billed":"n","next_due":"n","ends_at":"n","active":"b","enforcement_due":"n","order":"b","autopay":"b"}): return "invalid_support_obligation"
		if o.id != id or id != o.member + ":" + o.payer + ":" + o.recipient or not state.family.members.has(o.member) or not _actor(state, o.payer) or o.recipient == o.payer or (o.recipient != "public_care" and not _actor(state, o.recipient)): return "invalid_support_party"
		if not o.payer in state.family.members[o.member].parents: return "invalid_support_party"
		for key in ["monthly","arrears","paid","billed","next_due","ends_at","enforcement_due"]:
			if not _time(o[key]): return "invalid_support_amount"
		if int(o.monthly) <= 0 or int(o.paid) + int(o.arrears) != int(o.billed): return "inconsistent_support_ledger"
	for h in s.history:
		if not V.fields(h, {"kind":"s","id":"s","minute":"n","amount":"n"}) or not s.obligations.has(h.id) or not H.integer(h.minute, 0, int(state.clock.total_minutes)) or not _time(h.amount): return "invalid_support_history"
	return ""
