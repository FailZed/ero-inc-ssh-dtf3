extends "res://scripts/mechanics/core/module.gd"
## Long-lived medical, family or story conditions, without scene dependencies.

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id", ""))
	var target := str(args.get("target", "player"))
	if target != "player" and not sim.state.social.npcs.has(target): return Rules.fail("unknown_target")
	var key := "%s:%s" % [target, id]
	match operation:
		"start":
			var condition := definition("conditions", id)
			if condition.is_empty() or sim.state.conditions.has(key): return Rules.fail("condition_unavailable")
			sim.state.conditions[key] = {"id": id, "target": target, "started": sim.state.clock.total_minutes, "stage": 0, "status": "active"}
			var active: Dictionary = sim.state.conditions[key]
			active.stage_times = []
			for stage in condition.get("stages", []):
				active.stage_times.append(sim.calendar.add_months(int(active.started), int(stage.after_months)) if stage.has("after_months") else int(active.started) + int(stage.get("after", 0)))
			active.end_time = sim.calendar.add_months(int(active.started), int(condition.duration_months)) if condition.has("duration_months") else int(active.started) + int(condition.get("duration", 1440))
			if id == "pregnancy":
				sim.state.conditions[key].care = 0
				sim.state.conditions[key].partner = str(args.get("partner", ""))
		"remove":
			if not sim.state.conditions.has(key): return Rules.fail("unknown_condition")
			if id == "pregnancy": sim.services.health.actor(target).appearance.pregnancy_stage = 0
			sim.state.conditions.erase(key)
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func tick(minute: int) -> void:
	for key in sim.state.conditions:
		var condition: Dictionary = sim.state.conditions[key]
		if condition.status != "active": continue
		var spec := definition("conditions", str(condition.id))
		var stages: Array = spec.get("stages", [])
		while int(condition.stage) < stages.size() and minute >= int(condition.stage_times[int(condition.stage)]):
			condition.stage += 1
			if condition.id == "pregnancy": sim.services.health.actor(str(condition.target)).appearance.pregnancy_stage = condition.stage
			emit_event("condition_stage", {"key": key, "stage": condition.stage, "target": condition.target})
		var completed: bool = minute >= int(condition.end_time)
		if completed:
			condition.status = "completed"
			if condition.id == "pregnancy":
				sim.services.health.actor(str(condition.target)).appearance.pregnancy_stage = 0
				sim.state.healthcare.family.append({"parent": condition.target, "partner": condition.get("partner", ""), "minute": minute, "care": condition.get("care", 0), "status": "dependent"})
			emit_event("condition_completed", {"key": key, "target": condition.target})

