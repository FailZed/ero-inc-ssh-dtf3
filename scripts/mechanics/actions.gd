extends "res://scripts/mechanics/core/module.gd"

func availability(id: String) -> Dictionary:
	var action := definition("actions", id)
	if action.is_empty(): return Rules.fail("unknown_action")
	if not Rules.check(sim.state, action.get("requirements", {})): return Rules.fail("action_requirements")
	if action.has("locations") and not sim.state.world.location in action.locations: return Rules.fail("wrong_location")
	if not sim.services.world.is_open(action): return Rules.fail("action_closed")
	for tag in action.get("tags", []):
		if tag in sim.state.preferences.disabled_tags: return Rules.fail("content_disabled")
	var key := "%s:%d" % [id, sim.state.clock.day_index]
	if int(sim.state.counters.get(key, 0)) >= int(action.get("daily_limit", 2147483647)): return Rules.fail("action_daily_limit")
	for path in action.get("costs", {}):
		var actual: Variant = Rules.read(sim.state, path)
		if not (actual is float or actual is int) or float(actual) < float(action.costs[path]) * sim.multiplier("resource_cost"): return Rules.fail("insufficient_resource:%s" % path)
	return Rules.ok(action.duplicate(true))

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation != "perform": return Rules.fail("unknown_operation")
	var id := str(args.get("id", ""))
	var available := availability(id)
	if not available.ok: return available
	var action := definition("actions", id)
	for path in action.get("costs", {}):
		Rules.write(sim.state, path, Rules.read(sim.state, path) - action.costs[path] * sim.multiplier("resource_cost"))
	var key := "%s:%d" % [id, sim.state.clock.day_index]
	sim.state.counters[key] = int(sim.state.counters.get(key, 0)) + 1
	var result: Dictionary = sim.apply_effects(action.get("effects", []))
	if not result.ok: return result
	result = sim.advance(int(action.get("minutes", 0)))
	if not result.ok: return result
	emit_event("action_completed", {"id": id})
	return Rules.ok({"id": id})
