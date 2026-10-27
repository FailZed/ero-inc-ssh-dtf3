extends "res://scripts/mechanics/core/module.gd"
## Content-free, revisioned scene protocol. The presenter never commits outcomes itself.
const CHECK = preload("res://scripts/mechanics/core/human_validation.gd")

static func defaults() -> Dictionary:
	return {"version":1, "active":{}, "next_id":1, "history":[], "cooldowns":{}}

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func rules() -> Dictionary:
	return sim.catalog.reproduction_rules.simulation

func command_allowed(module_id: String, operation: String) -> Dictionary:
	if module_id=="adult_health" and operation in ["inspect","desire"]: return Rules.ok()
	if sim.state.intimacy.active.is_empty(): return Rules.ok()
	if module_id in ["intimacy", "clock", "preferences"]: return Rules.ok()
	if module_id == "npc_relationships" and operation == "boundary": return Rules.ok()
	if module_id == "world" and operation in ["travel", "journey"]: return Rules.ok()
	if module_id == "reproduction" and operation in ["inspect", "preference"]: return Rules.ok()
	return Rules.fail("finish_active_intimacy")

func blocked(id: String, check_pin: bool = true) -> String:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if npc.is_empty(): return "unknown_npc"
	if int(npc.age) < 18 or int(sim.state.player.age) < 18: return "adults_only"
	if "romance" in sim.state.preferences.disabled_tags: return "content_disabled"
	if npc.location != sim.state.world.location: return "npc_not_present"
	if not sim.catalog.locations.get(str(npc.location), {}).get("private", false): return "private_location_required"
	var reason: String = sim.services.npc_relationships.blocked("player", id, "court")
	if not reason.is_empty(): return reason
	var bond: Dictionary = sim.services.npc_relationships.view(id, "player")
	if float(bond.trust) < float(rules().minimum_trust) or float(bond.comfort) < float(rules().minimum_comfort) or float(bond.interest) < float(rules().minimum_interest): return "intimacy_declined"
	if float(sim.state.player.needs.energy) < float(rules().session_energy) or float(npc.needs.energy) < float(rules().session_energy): return "insufficient_energy"
	if float(npc.health) < 30 or float(sim.state.player.needs.health) < 30: return "npc_needs_recovery"
	for participant in ["player", id]:
		var wellbeing: String = sim.services.adult_health.intimate_blocked(participant)
		if not wellbeing.is_empty(): return wellbeing
		var medical: Dictionary = sim.state.healthcare.records.get(participant, {})
		if float(medical.get("intoxication", 0)) >= 30 or int(medical.get("unconscious_until", 0)) > _now(): return "participant_unavailable"
		if int(sim.services.reproduction.view(participant).recovery_until) > _now(): return "reproductive_recovery"
	if npc.activity in ["sleep", "recover", "eat", "work", "study", "family_care"]: return "npc_busy"
	if check_pin and int(npc.pinned_until) > _now(): return "npc_busy"
	for offset in range(int(rules().session_minutes) + 1):
		var clock: Dictionary = sim.calendar.snapshot(_now() + offset)
		for entry in npc.schedule:
			if not entry.get("mandatory", entry.get("activity", "") in ["work", "study"]): continue
			var hours: Array = entry.get("hours", [0, 0])
			if int(clock.weekday) in entry.get("weekdays", [1,2,3,4,5,6,7]) and Rules.in_window(int(clock.minute_of_day), int(hours[0]), int(hours[1])): return "npc_busy"
	return ""

func choices() -> Array:
	var session: Dictionary = sim.state.intimacy.active
	if session.is_empty(): return []
	var result: Array = []
	for choice in sim.catalog.intimacy_stages[session.stage].choices:
		var reason := _choice_blocked(str(choice), session)
		result.append({"id":choice, "enabled":reason.is_empty(), "reason":reason})
	return result

func presentation() -> Dictionary:
	var session: Dictionary = sim.state.intimacy.active
	if session.is_empty(): return {}
	return {"session":session.id, "revision":session.revision, "stage":session.stage,
		"hook":sim.catalog.intimacy_stages[session.stage].hook, "participants":["player", session.npc], "choices":choices()}

func _request() -> void:
	emit_event("intimacy_scene_requested", presentation())

func _stage(stage: String) -> void:
	var session: Dictionary = sim.state.intimacy.active
	session.stage = stage
	session.revision += 1
	_request()

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "inspect": return Rules.ok(presentation())
	if operation == "begin": return _begin(str(args.get("id", "")))
	var session: Dictionary = sim.state.intimacy.active
	if session.is_empty(): return Rules.fail("no_active_intimacy")
	if str(args.get("session", "")) != str(session.id) or not CHECK.integer(args.get("revision"), 1, 1000000) or int(args.revision) != int(session.revision): return Rules.fail("stale_intimacy_callback")
	if operation == "interrupt":
		_end("interrupted", "withdrawn")
		return Rules.ok({"status":"interrupted"})
	if operation != "choose": return Rules.fail("unknown_operation")
	var choice := str(args.get("choice", ""))
	if not choice in sim.catalog.intimacy_stages[session.stage].choices: return Rules.fail("invalid_intimacy_choice")
	var reason := _choice_blocked(choice, session)
	if not reason.is_empty(): return Rules.fail(reason)
	if choice in ["stop", "decline"]:
		_end("declined" if session.stage == "invitation" else "interrupted", "withdrawn")
		return Rules.ok({"status":"stopped"})
	match session.stage:
		"invitation": _stage("discussion")
		"discussion":
			session.potential_conception = choice != "non_reproductive"
			session.intended = choice == "plan_pregnancy"
			_stage("protection")
		"protection":
			if choice == "unprotected" and session.potential_conception and args.get("risk_acknowledged", false) != true: return Rules.fail("risk_acknowledgement_required")
			session.protection = choice
			_stage("ready")
		"ready":
			if not sim.services.adult_health.try_intimacy("player",str(session.npc)):
				_end("interrupted","adult_health_difficulty")
				return Rules.ok({"status":"health_pause"})
			if session.protection == "barrier":
				var consumed: Dictionary = sim.services.inventory.change("barrier_protection", -1)
				if not consumed.ok: return consumed
			# Protection is consumed once, even when an ongoing encounter is interrupted later.
			session.started = _now()
			session.due = _now() + int(rules().session_minutes)
			_stage("active")
		"active":
			var result: Dictionary = sim.advance(maxi(0, int(session.due) - _now()))
			if not result.ok: return result
			return Rules.ok({"status":str(sim.state.intimacy.active.get("stage", "interrupted"))})
		"aftercare": _end("completed", "")
	return Rules.ok(presentation())

func _begin(id: String) -> Dictionary:
	if not sim.state.intimacy.active.is_empty(): return Rules.fail("finish_active_intimacy")
	if int(sim.state.intimacy.cooldowns.get(id, 0)) > _now(): return Rules.fail("intimacy_cooldown")
	var reason := blocked(id)
	if not reason.is_empty(): return Rules.fail(reason)
	var npc: Dictionary = sim.state.social.npcs[id]
	var serial := "intimacy_%d" % int(sim.state.intimacy.next_id)
	sim.state.intimacy.next_id += 1
	var expiry := _now() + int(rules().invitation_minutes)
	var previous_pin := int(npc.pinned_until)
	if npc.has("mind"): sim.services.npc_agency._cancel(npc, "private_time")
	npc.pinned_until = expiry + 1
	sim.state.intimacy.active = {"id":serial, "npc":id, "stage":"invitation", "revision":1,
		"created":_now(), "expires":expiry, "location":str(sim.state.world.location), "previous_pin":previous_pin,
		"reserved_until":expiry + 1, "previous_activity":str(npc.activity), "potential_conception":false,
		"intended":false, "protection":"", "started":0, "due":0, "resolved":false, "exposure":""}
	npc.activity = "private_time"
	_request()
	return Rules.ok(presentation())

func _choice_blocked(choice: String, session: Dictionary) -> String:
	if choice in ["stop", "decline", "close"]: return ""
	var reason := blocked(str(session.npc), false)
	if session.resolved and reason in ["insufficient_energy", "npc_needs_recovery"]: reason = ""
	if not reason.is_empty(): return reason
	var player: Dictionary = sim.services.reproduction.view("player")
	var npc: Dictionary = sim.services.reproduction.view(str(session.npc))
	if choice in ["pregnancy_possible", "plan_pregnancy"] and "pregnancy" in sim.state.preferences.disabled_tags: return "content_disabled"
	if choice == "plan_pregnancy" and (player.desire != "want" or npc.desire != "want"): return "mutual_family_intention_required"
	if choice == "barrier" and int(sim.state.inventory.items.get("barrier_protection", 0)) < 1: return "missing_contraception"
	if choice == "regular_method":
		var pairing: Dictionary = sim.services.reproduction.risk("player", str(session.npc))
		if str(pairing.target).is_empty() or not sim.services.reproduction.view(str(pairing.target)).method_active: return "contraception_not_active"
	if choice == "unprotected" and session.potential_conception and (player.requires_protection or npc.requires_protection): return "protection_required"
	if choice == "start":
		var protected_reason := _choice_blocked(str(session.protection), session)
		if not protected_reason.is_empty(): return protected_reason
	return ""

func recheck() -> void:
	var session: Dictionary = sim.state.intimacy.active
	if session.is_empty(): return
	var reason := blocked(str(session.npc), false)
	if session.location != sim.state.world.location: reason = "location_changed"
	if _now() >= int(session.expires): reason = "expired"
	if session.stage in ["ready", "active"] and not session.resolved:
		var protection_reason := _choice_blocked(str(session.protection), session)
		# A used barrier no longer needs a second item in inventory.
		if protection_reason == "missing_contraception" and session.stage == "active" and session.protection == "barrier": protection_reason = ""
		if not protection_reason.is_empty(): reason = protection_reason
	if not reason.is_empty(): _end("interrupted", reason)

func tick(minute: int) -> void:
	recheck()
	var session: Dictionary = sim.state.intimacy.active
	if session.is_empty() or session.stage != "active" or minute < int(session.due): return
	if session.potential_conception:
		session.exposure = sim.services.reproduction.expose("player", str(session.npc), str(session.protection), bool(session.intended), str(session.id))
	sim.services.adult_health.contact("player",str(session.npc),str(session.protection),"player:"+str(session.id))
	session.resolved = true
	sim.services.character.adjust_need("energy", -float(rules().session_energy))
	var npc: Dictionary = sim.state.social.npcs[session.npc]
	npc.needs.energy = maxf(0, float(npc.needs.energy) - float(rules().session_energy))
	sim.services.social.change_relationship(str(session.npc), "player", {"trust":2, "affinity":2})
	sim.services.social.remember(str(session.npc), "private_time", {"session":session.id})
	_stage("aftercare")

func _end(status: String, reason: String) -> void:
	var session: Dictionary = sim.state.intimacy.active
	var npc: Dictionary = sim.state.social.npcs.get(str(session.npc), {})
	if not npc.is_empty():
		if int(npc.pinned_until) == int(session.reserved_until): npc.pinned_until = int(session.previous_pin)
		if npc.activity == "private_time": npc.activity = str(session.previous_activity)
	var result := {"id":session.id, "npc":session.npc, "minute":_now(), "status":status, "reason":reason,
		"resolved":session.resolved, "exposure":session.exposure}
	sim.state.intimacy.history.append(result)
	while sim.state.intimacy.history.size() > 64: sim.state.intimacy.history.pop_front()
	sim.state.intimacy.cooldowns[session.npc] = _now() + int(rules().cooldown_minutes)
	sim.state.intimacy.active = {}
	emit_event("intimacy_ended", result)
