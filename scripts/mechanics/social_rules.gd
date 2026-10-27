extends "res://scripts/mechanics/core/module.gd"
const Formulas = preload("res://scripts/mechanics/core/formulas.gd")

func initialize_npc(npc: Dictionary, template: Dictionary) -> void:
	if template.has("reproductive_profile"): npc.reproductive_profile = template.reproductive_profile.duplicate(true)
	npc.gender = str(template.get("gender", "female"))
	npc.attracted_to = template.get("attracted_to", ["male", "female", "nonbinary"]).duplicate()
	npc.cohort = str(template.get("cohort", "residents"))
	npc.traits = {}
	for key in ["bravery", "responsibility", "sociability", "romantic", "loyalty", "cunning"]:
		npc.traits[key] = int(template.get("traits", {}).get(key, sim.rng.randi_range(25, 75)))
	npc.biography.education = str(template.get("education", "general"))
	npc.biography.occupation = str(template.get("occupation", "independent"))
	npc.biography.family = template.get("family", {"siblings": 0, "household": "independent"}).duplicate(true)
	var strongest := "intellect"
	for stat in npc.stats:
		if float(npc.stats[stat]) > float(npc.stats[strongest]): strongest = str(stat)
	npc.biography.timeline = [{"age": 8, "kind": "early_interest", "field": strongest},
		{"age": 16, "kind": "education", "field": npc.biography.education},
		{"age": int(npc.age), "kind": "current_goal", "field": npc.biography.goal}]
	npc.combat_style = str(template.get("combat_style", "balanced"))
	npc.weapon = str(template.get("weapon", ""))
	npc.inventory.merge(template.get("inventory", {}).duplicate(true), true)
	if not npc.weapon.is_empty(): npc.inventory[npc.weapon] = maxi(1, int(npc.inventory.get(npc.weapon, 0)))

func compatibility(a: String, b: String) -> Dictionary:
	var first := _actor(a)
	var second := _actor(b)
	if first.is_empty() or second.is_empty() or a == b: return Rules.fail("unknown_relationship_target")
	var mutual: bool = str(second.gender) in first.attracted_to and str(first.gender) in second.attracted_to
	var score := 20.0
	if first.get("cohort", "") == second.get("cohort", ""): score += 20.0
	if first.get("personality", "") == second.get("personality", ""): score += 15.0
	if first.get("biography", {}).get("goal", "") == second.get("biography", {}).get("goal", ""): score += 10.0
	for preference in first.get("preferences", []):
		if preference in second.get("preferences", []): score += 5.0
	return Rules.ok({"mutual_attraction": mutual, "score": minf(100.0, score)})

func _actor(id: String) -> Dictionary:
	if id == "player":
		return {"gender": sim.state.player.appearance.get("gender", "male"), "attracted_to": ["male", "female", "nonbinary"], "cohort": "residents", "traits": {"loyalty": 100}}
	return sim.state.social.npcs.get(id, {})

func conversation_forecast(id: String, action_id: String) -> Dictionary:
	if not sim.state.social.npcs.has(id): return Rules.fail("unknown_npc")
	var action := definition("interactions", action_id)
	if action.is_empty(): return Rules.fail("unknown_interaction")
	var npc: Dictionary = sim.state.social.npcs[id]
	var relation: Dictionary = sim.services.social.relationship(id, "player")
	var repeats := 0
	var memory_bias := 0.0
	for memory in npc.memories:
		var age: int = int(sim.state.clock.total_minutes) - int(memory.minute)
		if age > 1440: continue
		if memory.kind == action_id: repeats += 1
		if memory.kind == "crime": memory_bias -= 0.1
		if memory.kind == "gift": memory_bias += 0.02
	var personality: Dictionary = definition("personalities", str(npc.personality))
	var rules := definition("balance_rules", "social")
	repeats = maxi(repeats, int(sim.state.counters.get("conversation:%s:%s:%d" % [id, action_id, sim.state.clock.day_index], 0)))
	var cap := float(rules.get("memory_bias_cap", 0.12))
	memory_bias = clampf(memory_bias, -cap, cap)
	if sim.services.has("npc_agency"): memory_bias += sim.services.npc_agency.conversation_bias(id, action_id)
	var fatigue := Formulas.dialogue_fatigue(float(relation.trust), sim.services.character.effective_stat("erudition"), float(npc.traits.sociability), float(sim.services.preferences.rule("dialogue_fatigue", 1.0)))
	var context: Dictionary = sim.state.duplicate()
	context.npc = npc
	context.relation = relation
	var branch: Dictionary = {}
	for candidate in action.get("branches", []):
		if Rules.check(context, candidate.get("when", {})):
			branch = candidate
			break
	var charisma := Formulas.mastery(sim.services.character.effective_stat("charisma"), float(rules.get("charisma_scale", 30))) * float(rules.get("charisma_cap", 0.28))
	var chance := clampf(float(action.get("chance", 0.7)) + float(relation.affinity) * 0.002 + charisma - maxf(0, float(relation.fear)) * float(rules.get("fear_penalty", 0.003)) - float(npc.fatigue) * 0.005 - repeats * 0.08 + memory_bias + float(personality.get("conversation", 0)) + float(sim.services.preferences.rule("interaction_bonus", 0.0)) + float(branch.get("chance_bias", 0)), 0.03, 0.97)
	return Rules.ok({"chance": chance, "fatigue": fatigue, "repeats": repeats, "memory_bias": memory_bias,
		"reward_multiplier": 1.0 / (1.0 + repeats * 0.65), "branch": branch.get("id", "default"), "text_token": branch.get("text_token", ""), "success": branch.get("success", action.get("success", {})), "failure": branch.get("failure", action.get("failure", {}))})

func availability(id: String, long_visit: bool = false) -> Dictionary:
	if not sim.state.social.npcs.has(id): return Rules.fail("unknown_npc")
	var npc: Dictionary = sim.state.social.npcs[id]
	if npc.health <= 10 or npc.activity in ["sleep", "recover", "eat"]: return Rules.fail("npc_needs_recovery")
	if long_visit and npc.activity in ["work", "study"] and npc.decision.get("committed", false): return Rules.fail("npc_busy")
	return Rules.ok()

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "gathering": return _gathering(args)
	var id := str(args.get("id", ""))
	if not sim.state.social.npcs.has(id): return Rules.fail("unknown_npc")
	var npc: Dictionary = sim.state.social.npcs[id]
	var social = sim.services.social
	var relation: Dictionary = social.relationship(id, "player")
	if operation in ["partner", "date"] and "romance" in sim.state.preferences.disabled_tags: return Rules.fail("content_disabled")
	match operation:
		"biography": return Rules.ok({"biography": npc.biography.duplicate(true), "traits": npc.traits.duplicate(true), "personality": npc.personality, "description": describe(id)})
		"ask_history":
			if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
			if relation.trust < 10: return Rules.fail("history_requires_trust")
			if npc.fatigue >= 90: return Rules.fail("dialogue_fatigue")
			var key := "history:%s" % id
			var first: bool = not sim.state.counters.has(key)
			sim.state.counters[key] = 1
			npc.fatigue = minf(100.0, float(npc.fatigue) + 5)
			if first: social.change_relationship(id, "player", {"trust": 2})
			social.remember(id, "shared_history", {})
			var result: Dictionary = sim.advance(5)
			if not result.ok: return result
			return Rules.ok({"description": describe(id), "new_disclosure": first})
		"apologize":
			if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
			var incident := -1
			for memory in npc.memories:
				if memory.kind in ["crime", "promise_broken", "appointment_missed"] or memory.data.get("accepted", true) == false:
					incident = maxi(incident, int(memory.minute))
			if incident <= int(relation.get("apology_resolved_at", -1)) and (relation.has("apology_resolved_at") or float(relation.trust) >= 0): return Rules.fail("no_apology_needed")
			var key := "apology:%s:%d" % [id, sim.state.clock.day_index]
			if sim.state.counters.has(key): return Rules.fail("apology_daily_limit")
			sim.state.counters[key] = 1
			relation.apology_resolved_at = int(sim.state.clock.total_minutes)
			social.change_relationship(id, "player", {"trust": 3, "affinity": 1})
			social.remember(id, "apology", {})
			return sim.advance(5)
		"partner":
			if "romance" in sim.state.preferences.disabled_tags: return Rules.fail("content_disabled")
			var match_result := compatibility(id, "player")
			if not match_result.ok or not match_result.data.mutual_attraction: return Rules.fail("incompatible_attraction")
			if social._has_partner(id) or social._has_partner("player"): return Rules.fail("existing_partner")
			if relation.trust < 30 or relation.attraction < 30 or relation.affinity < 20: return Rules.fail("relationship_requirements")
			if int(relation.get("separated_until", 0)) > int(sim.state.clock.total_minutes): return Rules.fail("relationship_cooldown")
			relation.status = "partner"
			social.remember(id, "partnership", {})
		"breakup":
			if relation.status != "partner": return Rules.fail("not_partners")
			relation.status = "separated"
			relation.separated_until = int(sim.state.clock.total_minutes) + 10080
			social.change_relationship(id, "player", {"trust": -10, "affinity": -10})
			social.remember(id, "separation", {})
		"date":
			if npc.location != sim.state.world.location: return Rules.fail("npc_not_present")
			var venue := str(args.get("venue", "coffee"))
			var plan := definition("date_activities", venue)
			if plan.is_empty(): return Rules.fail("unknown_date_activity")
			if not sim.state.world.location in plan.get("locations", [sim.state.world.location]): return Rules.fail("wrong_date_location")
			if not sim.state.world.weather in plan.get("weather", [sim.state.world.weather]): return Rules.fail("date_weather")
			var available := availability(id, true)
			if not available.ok: return available
			if not compatibility(id, "player").data.mutual_attraction: return Rules.fail("incompatible_attraction")
			if int(relation.get("next_date_at", 0)) > int(sim.state.clock.total_minutes): return Rules.fail("date_cooldown")
			if relation.trust < 10 or relation.fear > 50: return Rules.fail("date_requirements")
			var rules := definition("balance_rules", "social")
			var energy: float = float(plan.get("energy", rules.get("date_energy", 6))) * sim.multiplier("resource_cost")
			if sim.state.player.needs.energy < energy: return Rules.fail("insufficient_energy")
			if sim.state.economy.cash < int(plan.cost): return Rules.fail("insufficient_funds")
			sim.state.economy.cash -= int(plan.cost)
			sim.services.character.adjust_need("energy", -energy)
			sim.services.character.adjust_need("mood", float(plan.mood))
			npc.needs.mood = minf(100, float(npc.needs.mood) + float(plan.mood))
			relation.next_date_at = int(sim.state.clock.total_minutes) + int(rules.get("date_cooldown", 1440))
			npc.pinned_until = int(sim.state.clock.total_minutes) + int(plan.minutes)
			var changes: Dictionary = plan.success.duplicate()
			if npc.biography.goal in plan.get("goals", []): changes.trust = float(changes.get("trust", 0)) + 2
			social.change_relationship(id, "player", changes)
			social.remember(id, "date", {"location": sim.state.world.location,"venue":venue})
			return sim.advance(int(plan.minutes))
		"promise":
			var promise_id := str(args.get("promise", ""))
			var spec := definition("promises", promise_id)
			var key := id + ":" + promise_id
			if spec.is_empty() or sim.state.social.promises.has(key): return Rules.fail("promise_unavailable")
			sim.state.social.promises[key] = {"npc": id, "id": promise_id, "deadline": int(sim.state.clock.total_minutes) + int(spec.get("minutes", 1440)), "status": "active"}
		"fulfill":
			var key := id + ":" + str(args.get("promise", ""))
			if not sim.state.social.promises.has(key) or sim.state.social.promises[key].status != "active": return Rules.fail("promise_not_active")
			var spec := definition("promises", str(sim.state.social.promises[key].id))
			if not Rules.check(sim.state, spec.get("requirements", {})): return Rules.fail("promise_requirements")
			sim.state.social.promises[key].status = "fulfilled"
			social.change_relationship(id, "player", {"trust": 8})
			social.remember(id, "promise_kept", {})
		_: return Rules.fail("unknown_operation")
	return Rules.ok()

func describe(id: String) -> String:
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if npc.is_empty(): return ""
	var origins := {"river_district": "района у реки", "city_center": "центрального района", "suburbs": "пригорода", "local": "этого города"}
	var goals := {"career": "развиваться в профессии", "creativity": "заниматься творчеством", "community": "найти своё место среди людей"}
	var personality := {"calm": "спокойный", "confident": "уверенный", "reserved": "сдержанный", "reliable": "надёжный", "aggressive": "вспыльчивый"}
	var education := {"general": "общее", "vocational": "профессиональное", "higher": "высшее"}
	var occupation := {"independent": "самостоятельные проекты", "student": "учёба", "employed": "работа по найму"}
	return "%s — житель из %s. Характер %s. За плечами образование: %s; текущее занятие: %s. Сейчас важнее всего %s." % [
		npc.name, origins.get(npc.biography.origin, npc.biography.origin), personality.get(npc.personality, npc.personality),
		education.get(npc.biography.education, npc.biography.education), occupation.get(npc.biography.occupation, npc.biography.occupation), goals.get(npc.biography.goal, npc.biography.goal)]

func _gathering(args: Dictionary) -> Dictionary:
	var ids: Array = args.get("candidates", [])
	if ids.size() < 2 or ids.size() > 6: return Rules.fail("invalid_gathering_size")
	var key := "gathering:%d" % sim.state.clock.day_index
	if sim.state.counters.has(key): return Rules.fail("gathering_daily_limit")
	var unique := {}
	for id in ids:
		if unique.has(id) or not sim.state.social.npcs.has(id): return Rules.fail("invalid_guest")
		var available := availability(str(id), true)
		if not available.ok: return available
		unique[id] = true
		if sim.state.social.npcs[id].location != sim.state.world.location: return Rules.fail("guest_not_present")
		if sim.services.social.relationship(str(id), "player").trust < 10: return Rules.fail("guest_trust")
	if sim.state.player.needs.energy < 10: return Rules.fail("insufficient_energy")
	var food: Dictionary = sim.services.inventory.change("meal", -ids.size())
	if not food.ok: return food
	sim.state.counters[key] = 1
	sim.services.character.adjust_need("energy", -10)
	for id in ids:
		var npc: Dictionary = sim.state.social.npcs[id]
		npc.pinned_until = int(sim.state.clock.total_minutes) + 90
		npc.needs.satiety = minf(100, float(npc.needs.satiety) + 35)
		npc.needs.mood = minf(100, float(npc.needs.mood) + 8)
		sim.services.social.change_relationship(str(id), "player", {"affinity": 5, "trust": 2})
		sim.services.social.remember(str(id), "gathering", {"participants": ids.duplicate()})
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()): sim.services.social.change_relationship(str(ids[i]), str(ids[j]), {"affinity": 3, "trust": 1})
	sim.services.character.adjust_need("mood", 10)
	emit_event("gathering_completed", {"participants": ids.duplicate()})
	return sim.advance(90)

func autonomy() -> void:
	_review_partners()
	var social = sim.services.social
	var ids: Array = sim.state.social.npcs.keys()
	ids.sort()
	var visited := {}
	for id in ids:
		var npc: Dictionary = sim.state.social.npcs[id]
		var candidates: Array = []
		for other in ids:
			if other != id and sim.state.social.npcs[other].location == npc.location: candidates.append(other)
		if candidates.is_empty(): continue
		var other := str(candidates[sim.rng.randi_range(0, candidates.size() - 1)])
		var pair := [id, other]
		pair.sort()
		var key := "%s|%s" % [pair[0], pair[1]]
		if visited.has(key): continue
		visited[key] = true
		var relation: Dictionary = social.relationship(str(id), other)
		var match_result := compatibility(str(id), other)
		var attractive: bool = match_result.ok and bool(match_result.data.mutual_attraction)
		social.change_relationship(str(id), other, {"affinity": 3 if npc.personality == sim.state.social.npcs[other].personality else 1, "trust": 1,
			"attraction": 2 if attractive and float(relation.affinity) >= 20.0 else 0})
		if relation.status == "partner":
			if relation.trust < 0 or not attractive:
				relation.status = "separated"
				relation.separated_until = int(sim.state.clock.total_minutes) + 10080
		elif attractive and not "romance" in sim.state.preferences.disabled_tags and float(relation.trust) >= 30 and float(relation.attraction) >= 40 and float(match_result.data.score) + float(relation.affinity) * 0.5 >= 55.0:
			if not social._has_partner(str(id)) and not social._has_partner(other) and int(relation.get("separated_until", 0)) <= int(sim.state.clock.total_minutes):
				relation.status = "partner"
				emit_event("npc_relationship_formed", {"a": id, "b": other})
		elif relation.status == "acquaintance" and float(relation.affinity) >= 30: relation.status = "friend"
		if attractive and relation.status != "partner" and float(relation.attraction) >= 65.0:
			_consider_betrayal(str(id), other)

func betrayal_risk(id: String) -> float:
	if "romance" in sim.state.preferences.disabled_tags or "betrayal" in sim.state.preferences.disabled_tags: return 0.0
	var npc: Dictionary = sim.state.social.npcs.get(id, {})
	if npc.is_empty(): return 0.0
	return clampf((60.0 - float(npc.traits.loyalty)) * 0.005, 0.0, 0.3)

func _review_partners() -> void:
	for key in sim.state.social.relationships:
		var relation: Dictionary = sim.state.social.relationships[key]
		if relation.status != "partner": continue
		var ids := str(key).split("|")
		var match_result := compatibility(ids[0], ids[1])
		var a_location: String = sim.state.world.location if ids[0] == "player" else sim.state.social.npcs[ids[0]].location
		var b_location: String = sim.state.world.location if ids[1] == "player" else sim.state.social.npcs[ids[1]].location
		if a_location == b_location: relation.last_together = sim.state.clock.total_minutes
		elif int(sim.state.clock.total_minutes) - int(relation.get("last_together", sim.state.clock.total_minutes)) >= 10080: relation.trust = maxf(-100, float(relation.trust) - 2)
		if not relation.has("last_together"): relation.last_together = sim.state.clock.total_minutes
		if float(relation.trust) < 0 or not match_result.ok or not match_result.data.mutual_attraction:
			relation.status = "separated"
			relation.separated_until = int(sim.state.clock.total_minutes) + 10080
			emit_event("npc_relationship_separated", {"a": ids[0], "b": ids[1]})

func _consider_betrayal(id: String, other: String) -> void:
	if not sim.services.social._has_partner(id) or sim.rng.randf() >= betrayal_risk(id): return
	for key in sim.state.social.relationships:
		var relation: Dictionary = sim.state.social.relationships[key]
		var ids := str(key).split("|")
		if not id in ids or relation.status != "partner": continue
		relation.trust = maxf(-100.0, float(relation.trust) - 30.0)
		relation.affinity = maxf(-100.0, float(relation.affinity) - 20.0)
		relation.betrayals = int(relation.get("betrayals", 0)) + 1
		var hurt := str(ids[1] if ids[0] == id else ids[0])
		if hurt == "player": sim.services.character.adjust_need("mood", -10)
		elif sim.state.social.npcs.has(hurt): sim.services.social.remember(hurt, "betrayal", {"actor": id, "other": other})
		if relation.trust < 0:
			relation.status = "separated"
			relation.separated_until = int(sim.state.clock.total_minutes) + 10080
		emit_event("relationship_betrayal", {"actor": id, "other": other, "affected": hurt})

func tick(minute: int) -> void:
	for promise in sim.state.social.promises.values():
		if promise.status == "active" and minute >= int(promise.deadline):
			promise.status = "broken"
			sim.services.social.change_relationship(str(promise.npc), "player", {"trust": -8})
			sim.services.social.remember(str(promise.npc), "promise_broken", {})
