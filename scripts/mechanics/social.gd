extends "res://scripts/mechanics/core/module.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	var social: Dictionary = sim.state.social
	var id := str(args.get("id", ""))
	if operation == "generate": return _generate(id, args)
	if not social.npcs.has(id): return Rules.fail("unknown_npc")
	var npc: Dictionary = social.npcs[id]
	match operation:
		"interact": return _interact(id, str(args.get("action", "talk")))
		"gift":
			if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
			var item_id := str(args.get("item", ""))
			var item := definition("items", item_id)
			if item.is_empty(): return Rules.fail("unknown_item")
			var removed: Dictionary = sim.services.inventory.change(item_id, -1)
			if not removed.ok: return removed
			var liked: bool = str(item.get("category", "")) in npc.preferences
			var key := "gift:%s:%d" % [id, sim.state.clock.day_index]
			var count := int(sim.state.counters.get(key, 0))
			var limit := float(definition("balance_rules", "social").get("gift_reward_limit", 3))
			var novelty := maxf(0, 1.0 - count / limit)
			sim.state.counters[key] = count + 1
			change_relationship(id, "player", {"affinity": (8 if liked else 2) * novelty, "trust": novelty})
			npc.inventory[item_id] = int(npc.inventory.get(item_id, 0)) + 1
			remember(id, "gift", {"item": item_id, "liked": liked})
			return sim.advance(2)
		"contact":
			if not id in social.contacts: social.contacts.append(id)
		"message", "call":
			if not id in social.contacts: return Rules.fail("missing_contact")
			var body := str(args.get("text", ""))
			if body.strip_edges().is_empty(): return Rules.fail("empty_message")
			social.messages.append({"id": social.next_message_id, "npc": id, "text": body,
				"incoming": bool(args.get("incoming", false)), "read": false, "minute": sim.state.clock.total_minutes})
			social.next_message_id += 1
			if operation == "call": return sim.advance(5)
		"read":
			for message in social.messages:
				if message.npc == id: message.read = true
		"appointment":
			var due := int(args.get("minute", 0))
			var location := str(args.get("location", ""))
			if due <= sim.state.clock.total_minutes or definition("locations", location).is_empty(): return Rules.fail("invalid_appointment")
			for existing in social.appointments:
				if existing.status == "pending" and absi(int(existing.minute) - due) < 60:
					return Rules.fail("appointment_conflict")
			social.appointments.append({"npc": id, "minute": due, "location": location, "status": "pending"})
		"relationship":
			var other := str(args.get("other", "player"))
			if other == id or (other != "player" and not social.npcs.has(other)): return Rules.fail("unknown_relationship_target")
			change_relationship(id, other, args.get("changes", {}))
		"invite":
			var available: Dictionary = sim.services.social_rules.availability(id, true)
			if not available.ok: return available
			if int(args.get("minutes", 60)) < 1 or int(args.get("minutes", 60)) > 1440: return Rules.fail("invalid_invitation_duration")
			var relation := relationship(id, "player")
			if float(relation.trust) < 10.0: return Rules.fail("insufficient_trust")
			npc.location = sim.state.world.location
			npc.pinned_until = int(sim.state.clock.total_minutes) + int(args.get("minutes", 60))
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func _generate(id: String, args: Dictionary) -> Dictionary:
	var social: Dictionary = sim.state.social
	if id.is_empty(): id = "npc_%06d" % social.next_npc_id
	if social.npcs.has(id): return Rules.fail("duplicate_npc")
	var template := definition("npc_templates", str(args.get("template", "resident")))
	if template.is_empty(): return Rules.fail("unknown_npc_template")
	return generate_from_template(id, args, template)

func generate_from_template(id: String, args: Dictionary, template: Dictionary) -> Dictionary:
	var social: Dictionary = sim.state.social
	if social.npcs.has(id): return Rules.fail("duplicate_npc")
	var prepared: Dictionary = sim.prepare_npc_template(id, args, template)
	if not prepared.ok: return prepared
	template = prepared.data
	var personality: Array = template.get("personalities", ["calm", "confident", "reserved"])
	if sim.services.has("npc_personalities") and sim.services.npc_personalities.enabled(): personality = sim.services.npc_personalities.generation_choices(template)
	var origins: Array = template.get("origins", ["local"])
	var goals: Array = template.get("goals", ["community"])
	var npc := {
		"id": id, "name": str(args.get("name", "Resident %d" % social.next_npc_id)),
		"age": maxi(18, int(args.get("age", template.get("age", 24)))),
		"personality": personality[sim.rng.randi_range(0, personality.size() - 1)],
		"stats": {}, "skills": {}, "appearance": args.get("appearance", {}).duplicate(true),
		"preferences": template.get("preferences", []).duplicate(), "money": int(template.get("money", 100)),
		"inventory": {}, "health": 100.0, "injuries": {}, "home": template.get("home", "bedroom"), "location": template.get("home", "bedroom"),
		"schedule": template.get("schedule", []).duplicate(true), "activity": "rest",
		"activities": template.get("activities", []).duplicate(),
		"biography": {"origin": origins[sim.rng.randi_range(0, origins.size() - 1)], "goal": goals[sim.rng.randi_range(0, goals.size() - 1)], "role": template.get("role", "resident")},
		"fatigue": 0.0, "pinned_until": 0, "memories": [],
	}
	for stat in sim.catalog.attributes:
		npc.stats[stat] = sim.rng.randi_range(int(template.get("stat_min", 3)), int(template.get("stat_max", 10)))
	sim.services.social_rules.initialize_npc(npc, template)
	sim.services.npc_behavior.initialize_npc(npc)
	sim.services.appearance.initialize_npc(npc, template)
	if args.has("employment") or template.has("employment"):
		var plan: Variant = args.get("employment",template.get("employment"))
		var assignment = preload("res://scripts/mechanics/npc_employment.gd")
		var error: String = assignment.assignment_error(plan,sim.catalog,npc)
		if not error.is_empty(): return Rules.fail(error)
		if args.has("employment") and template.has("employment"):
			error = assignment.assignment_error(template.employment,sim.catalog,npc)
			if not error.is_empty(): return Rules.fail(error)
			if plan.job!=template.employment.job or plan.workplace!=template.employment.workplace or int(plan.skill_level)!=int(template.employment.skill_level): return Rules.fail("employment_assignment_conflict")
		npc.employment_plan = plan.duplicate(true)
	social.npcs[id] = npc
	social.next_npc_id += 1
	_schedule(npc)
	return Rules.ok({"id": id, "npc": npc.duplicate(true)})

func relationship(a: String, b: String) -> Dictionary:
	var ids := [a, b]
	ids.sort()
	var key := "%s|%s" % [ids[0], ids[1]]
	if not sim.state.social.relationships.has(key):
		sim.state.social.relationships[key] = {"affinity": 0.0, "trust": 0.0, "fear": 0.0, "attraction": 0.0, "status": "acquaintance"}
	return sim.state.social.relationships[key]

func change_relationship(a: String, b: String, changes: Dictionary) -> void:
	var relation := relationship(a, b)
	for scale in ["affinity", "trust", "fear", "attraction"]:
		var delta := float(changes.get(scale, 0))
		if (a == "player" or b == "player") and delta > 0 and scale != "fear": delta *= sim.multiplier("relation_gain")
		if delta > 0 and scale != "fear": delta *= maxf(0.25, 1.0 - maxf(0, float(relation[scale]) - 30.0) / 100.0)
		relation[scale] = clampf(float(relation[scale]) + delta, -100.0, 100.0)
	if changes.has("status"): relation.status = str(changes.status)

func remember(id: String, kind: String, data: Dictionary) -> void:
	var memories: Array = sim.state.social.npcs[id].memories
	memories.append({"kind": kind, "minute": sim.state.clock.total_minutes, "data": data.duplicate(true)})
	while memories.size() > int(sim.catalog.settings.memory_limit): memories.pop_front()
	if sim.services.has("npc_agency"): sim.services.npc_agency.observe(id, kind, data)

func _interact(id: String, action_id: String) -> Dictionary:
	var action := definition("interactions", action_id)
	var npc: Dictionary = sim.state.social.npcs[id]
	if action.is_empty(): return Rules.fail("unknown_interaction")
	if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
	if npc.fatigue >= 90.0: return Rules.fail("dialogue_fatigue")
	var available: Dictionary = sim.services.social_rules.availability(id)
	if not available.ok: return available
	for tag in action.get("tags", []):
		if tag in sim.state.preferences.disabled_tags: return Rules.fail("content_disabled")
	if action.get("requires_attraction", false) and not sim.services.social_rules.compatibility(id, "player").data.mutual_attraction: return Rules.fail("incompatible_attraction")
	if not Rules.check(sim.state, action.get("requirements", {})): return Rules.fail("interaction_requirements")
	var forecast: Dictionary = sim.services.social_rules.conversation_forecast(id, action_id)
	var chance := float(forecast.data.chance)
	var accepted: bool = sim.rng.randf() < chance
	var outcome := "success" if accepted else "failure"
	var changes: Dictionary = forecast.data.get(outcome, action.get(outcome, {})).duplicate()
	for scale in changes:
		if float(changes[scale]) > 0: changes[scale] *= float(forecast.data.reward_multiplier)
	change_relationship(id, "player", changes)
	var key := "conversation:%s:%s:%d" % [id, action_id, sim.state.clock.day_index]
	sim.state.counters[key] = int(sim.state.counters.get(key, 0)) + 1
	if accepted:
		sim.services.character.adjust_need("mood", float(action.get("mood", 1)))
		npc.needs.mood = minf(100, float(npc.needs.mood) + float(action.get("mood", 1)))
	npc.fatigue = minf(100.0, float(npc.fatigue) + float(forecast.data.fatigue))
	remember(id, action_id, {"accepted": accepted})
	var result: Dictionary = sim.advance(int(action.get("minutes", 5)))
	if not result.ok: return result
	return Rules.ok({"accepted": accepted, "chance": chance, "branch": forecast.data.get("branch", "default"), "text_token": forecast.data.get("text_token", "")})

func _schedule(npc: Dictionary) -> void:
	if sim.services.has("npc_agency") and sim.services.npc_agency.enabled():
		sim.services.npc_agency.initialize_npc(npc)
		return
	if int(npc.pinned_until) > int(sim.state.clock.total_minutes): return
	var previous := str(npc.activity)
	var plan: Dictionary = sim.services.npc_behavior.plan(npc)
	npc.location = plan.location
	npc.activity = plan.activity
	npc.decision = {"reason": plan.reason, "committed": plan.committed}
	if plan.committed:
		sim.services.appearance.dress_for_context(npc)
		return
	var candidates: Array = sim.services.npc_behavior.candidates(npc, previous)
	var total_weight := 0.0
	for candidate in candidates:
		total_weight += float(candidate.weight)
		candidate.cumulative = total_weight
	if total_weight > 0.0:
		var roll: float = sim.rng.randf() * total_weight
		for candidate in candidates:
			if roll < float(candidate.cumulative):
				npc.activity = str(candidate.id)
				break
	sim.services.appearance.dress_for_context(npc)

func tick(minute: int) -> void:
	var agency_enabled: bool = sim.services.has("npc_agency") and sim.services.npc_agency.enabled()
	for npc in sim.state.social.npcs.values():
		if agency_enabled: continue
		if minute % 60 == 0:
			npc.fatigue = maxf(0.0, float(npc.fatigue) - 10.0)
			_schedule(npc)
			sim.services.npc_behavior.hourly(npc)
		elif int(npc.pinned_until) == minute:
			_schedule(npc)
	if minute % 1440 == 1080:
		sim.services.social_rules.autonomy()

func settle_appointments(minute: int) -> void:
	for appointment in sim.state.social.appointments:
		if appointment.status != "pending" or minute < int(appointment.minute): continue
		var npc: Dictionary = sim.state.social.npcs[appointment.npc]
		var ready: bool = npc.location==appointment.location and (int(npc.pinned_until)<=minute or int(appointment.get("journey",{}).get("pin",-1))==int(npc.pinned_until))
		if minute >= int(appointment.minute) + 30:
			appointment.status = "missed"
			if ready:
				change_relationship(str(appointment.npc), "player", {"trust": -5})
				remember(str(appointment.npc), "appointment_missed", {})
				emit_event("appointment_missed", appointment)
			else:
				appointment.reason = "npc_unavailable"
				emit_event("appointment_unavailable", appointment)
			continue
		if ready and sim.state.world.location == appointment.location:
			appointment.status = "met"
			change_relationship(str(appointment.npc), "player", {"trust": 5})
			emit_event("appointment_met", appointment)

func _has_partner(id: String) -> bool:
	for key in sim.state.social.relationships:
		if id in str(key).split("|") and sim.state.social.relationships[key].status == "partner": return true
	return false
