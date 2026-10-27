extends "res://scripts/mechanics/core/module.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	var journal: Dictionary = sim.state.journal
	var id := str(args.get("id", ""))
	match operation:
		"poll":
			poll()
			return Rules.ok({"ready": journal.ready_events.duplicate()})
		"fire":
			if not eligible(id): return Rules.fail("event_unavailable")
			var event := definition("events", id)
			var result: Dictionary = sim.apply_effects(event.get("effects", []))
			if not result.ok: return result
			journal.fired[id] = int(journal.fired.get(id, 0)) + 1
			journal.cooldowns[id] = int(sim.state.clock.total_minutes) + maxi(1, int(event.get("cooldown", 1)))
			journal.ready_events.erase(id)
			emit_event("event_fired", {"id": id, "timeline": event.get("timeline", "")})
		"start_quest":
			var quest := definition("quests", id)
			if quest.is_empty() or journal.quests.has(id) or not Rules.check(sim.state, quest.get("requirements", {})): return Rules.fail("quest_unavailable")
			var deadline := int(quest.get("deadline_minutes", 0))
			journal.quests[id] = {"status": "active", "objectives": {}, "claimed": false,
				"deadline": int(sim.state.clock.total_minutes) + deadline if deadline > 0 else 0}
		"progress":
			if not journal.quests.has(id) or journal.quests[id].status != "active": return Rules.fail("quest_not_active")
			var objective := str(args.get("objective", ""))
			var count := int(args.get("amount", 1))
			var quest := definition("quests", id)
			if not quest.objectives.has(objective) or count <= 0: return Rules.fail("invalid_objective")
			var progress: Dictionary = journal.quests[id]
			progress.objectives[objective] = mini(int(quest.objectives[objective]), int(progress.objectives.get(objective, 0)) + count)
			var completed := true
			for key in quest.objectives:
				completed = completed and int(progress.objectives.get(key, 0)) >= int(quest.objectives[key])
			if completed:
				progress.status = "completed"
				emit_event("quest_completed", {"id": id})
		"claim_quest":
			if not journal.quests.has(id) or journal.quests[id].status != "completed" or journal.quests[id].claimed: return Rules.fail("quest_reward_unavailable")
			var result: Dictionary = sim.apply_effects(definition("quests", id).get("rewards", []))
			if not result.ok: return result
			journal.quests[id].claimed = true
		"claim_achievement":
			var achievement := definition("achievements", id)
			if achievement.is_empty() or id in journal.achievements: return Rules.fail("achievement_unavailable")
			if not Rules.check(sim.state, achievement.get("requirements", {})): return Rules.fail("achievement_requirements")
			var result: Dictionary = sim.apply_effects(achievement.get("rewards", []))
			if not result.ok: return result
			journal.achievements.append(id)
			emit_event("achievement_unlocked", {"id": id})
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func eligible(id: String) -> bool:
	var event := definition("events", id)
	var journal: Dictionary = sim.state.journal
	if event.is_empty(): return false
	if bool(event.get("once", true)) and int(journal.fired.get(id, 0)) > 0: return false
	if int(journal.cooldowns.get(id, 0)) > int(sim.state.clock.total_minutes): return false
	for tag in event.get("tags", []):
		if tag in sim.state.preferences.disabled_tags: return false
	return Rules.check(sim.state, event.get("requirements", {}))

func poll() -> void:
	var ready: Array = []
	for id in sim.catalog.events:
		if eligible(id): ready.append(id)
	ready.sort_custom(func(a, b):
		var pa := int(definition("events", a).get("priority", 0))
		var pb := int(definition("events", b).get("priority", 0))
		return str(a) < str(b) if pa == pb else pa > pb)
	if ready != sim.state.journal.ready_events:
		sim.state.journal.ready_events = ready
		emit_event("events_ready", {"ids": ready.duplicate()})

func tick(minute: int) -> void:
	for id in sim.state.journal.quests:
		var quest: Dictionary = sim.state.journal.quests[id]
		if quest.status == "active" and int(quest.deadline) > 0 and minute >= int(quest.deadline):
			quest.status = "failed"
			emit_event("quest_failed", {"id": id})
	poll()
