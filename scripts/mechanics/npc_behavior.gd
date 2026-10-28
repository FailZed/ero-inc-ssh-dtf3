extends "res://scripts/mechanics/core/module.gd"
## Contextual decisions; explicit commitments take priority over free leisure.

func initialize_npc(npc: Dictionary) -> void:
	npc.needs = {"energy": 100.0, "satiety": 100.0, "mood": 70.0}
	npc.decision = {"reason": "schedule", "committed": false}

func context(npc: Dictionary) -> Dictionary:
	var result: Dictionary = sim.state.duplicate()
	result.player = npc
	result.npc = npc
	return result

func plan(npc: Dictionary) -> Dictionary:
	if float(npc.health) <= 10 or not npc.injuries.is_empty() and float(npc.health) < 40:
		return {"activity": "recover", "location": npc.home, "reason": "health", "committed": true}
	if float(npc.needs.energy) < 20 or (npc.activity == "sleep" and float(npc.needs.energy) < 70):
		return {"activity": "sleep", "location": npc.home, "reason": "energy", "committed": true}
	if float(npc.needs.satiety) < 20:
		return {"activity": "eat", "location": npc.home, "reason": "satiety", "committed": true}
	var hour := int(sim.state.clock.minute_of_day) / 60
	if (hour >= 22 or hour < 6) and float(npc.needs.energy) < 85:
		return {"activity": "sleep", "location": npc.home, "reason": "night", "committed": true}
	for entry in npc.schedule:
		if not sim.services.world.is_open(entry) or not Rules.check(context(npc), entry.get("requirements", {})): continue
		var destination := str(entry.get("location", npc.home))
		var spec := definition("locations", destination)
		if spec.is_empty() or not sim.services.world.actor_availability(destination,str(npc.id),int(sim.state.clock.total_minutes)).ok or not Rules.check(context(npc), spec.get("requirements", {})): continue
		var activity := str(entry.get("activity", "idle"))
		return {"activity": activity, "location": destination, "reason": "schedule", "committed": bool(entry.get("mandatory", activity in ["work", "study"]))}
	return {"activity": "rest", "location": npc.home, "reason": "free_time", "committed": false}

func candidates(npc: Dictionary, previous: String = "") -> Array:
	var result: Array = []
	for id in npc.activities:
		var activity := definition("npc_activities", str(id))
		if activity.is_empty(): continue
		if activity.get("home_activity",false):
			if not sim.is_actor_home_location(str(npc.id),str(npc.location)): continue
		elif not npc.location in activity.get("locations", [npc.location]): continue
		if not str(npc.biography.role) in activity.get("roles", [npc.biography.role]): continue
		if not sim.services.world.is_open(activity) or not Rules.check(context(npc), activity.get("requirements", {})): continue
		var weight := maxf(0.0, float(activity.get("weight", 1)))
		if str(id) == previous: weight *= 0.5
		if str(id) in ["socialize", "walk"]: weight *= 1.0 + (100.0 - float(npc.needs.mood)) / 50.0
		for trait_id in activity.get("trait_weights", {}): weight *= maxf(0.0, 1.0 + float(npc.traits.get(trait_id, 50)) * float(activity.trait_weights[trait_id]))
		if weight > 0: result.append({"id": id, "weight": weight})
	return result

func hourly(npc: Dictionary) -> void:
	npc.needs.satiety = maxf(0, float(npc.needs.satiety) - 3)
	npc.needs.energy = maxf(0, float(npc.needs.energy) - 2)
	match str(npc.activity):
		"recover":
			npc.health = minf(100, float(npc.health) + 3)
			npc.needs.energy = minf(100, float(npc.needs.energy) + 15)
		"sleep", "rest": npc.needs.energy = minf(100, float(npc.needs.energy) + 20)
		"eat":
			if int(npc.inventory.get("meal", 0)) > 0:
				npc.inventory.meal -= 1
				if npc.inventory.meal == 0: npc.inventory.erase("meal")
				npc.needs.satiety = minf(100, float(npc.needs.satiety) + 60)
			elif npc.money >= 5:
				npc.money -= 5
				npc.needs.satiety = minf(100, float(npc.needs.satiety) + 60)
			else:
				npc.needs.satiety = minf(100, float(npc.needs.satiety) + 20)
				npc.decision.reason = "community_meal"
		_:
			var activity := definition("npc_activities", str(npc.activity))
			if npc.activity == "work" and npc.biography.role == "worker": activity = definition("npc_activities", "paid_work")
			if npc.activity == "study": activity = {"skill": "study", "xp": 2, "energy_cost": 3}
			npc.needs.energy = maxf(0, float(npc.needs.energy) - float(activity.get("energy_cost", 0)))
			if activity.has("skill"): npc.skills[str(activity.skill)] = int(npc.skills.get(str(activity.skill), 0)) + int(activity.get("xp", 1))
			npc.money += int(activity.get("income", 0))
	var mood_delta := 5.0 if npc.activity in ["socialize", "walk"] else (-1.0 if npc.activity == "work" else 1.0)
	npc.needs.mood = clampf(float(npc.needs.mood) + mood_delta, 0, 100)

func tick(minute: int) -> void:
	if minute % 1440 != 1080: return
	for id in sim.state.social.contacts:
		var npc: Dictionary = sim.state.social.npcs[id]
		if npc.health < 20 or npc.fatigue >= 80 or float(npc.traits.sociability) < 60: continue
		if sim.services.social.relationship(str(id), "player").trust < 20 or sim.rng.randf() > 0.35: continue
		var message := {"id": sim.state.social.next_message_id, "npc": id, "text": "Привет! Если захочешь пообщаться, буду ждать в нашем обычном месте.", "incoming": true, "read": false, "minute": minute}
		sim.state.social.messages.append(message)
		sim.state.social.next_message_id += 1
		emit_event("npc_message_received", {"npc": id, "id": message.id})
