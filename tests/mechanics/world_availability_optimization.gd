extends SceneTree
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
const Rules = preload("res://scripts/mechanics/core/rules.gd")

func _initialize() -> void:
	_run.call_deferred()

# The pre-optimization implementation, kept only as a test oracle.
func _deep_availability(sim, location_id: String, actor_id: String, minute: int, ignore_hours: bool = false) -> Dictionary:
	var location: Dictionary = sim.catalog.locations.get(location_id,{})
	if location.is_empty(): return Rules.fail("unknown_location")
	if not ignore_hours and not sim.services.world.is_open_at(location,minute): return Rules.fail("location_closed")
	var context: Dictionary = sim.state if actor_id == "player" else sim.services.npc_behavior.context(sim.state.social.npcs[actor_id])
	context = context.duplicate(true)
	context.clock = sim.calendar.snapshot(minute)
	return Rules.ok(location.duplicate(true)) if Rules.check(context,location.get("requirements",{})) else Rules.fail("location_requirements")

func _run() -> void:
	var sim = Life.new(128,{"settings":{"start_minutes":480}})
	var setup_ok := true
	for command in [["npc_agency","enable",{}],["population","configure",{"values":{"count":3}}],["population","generate",{}]]:
		setup_ok = setup_ok and bool(sim.command(command[0],command[1],command[2]).ok)
	var ids: Array = sim.state.social.npcs.keys()
	ids.sort()
	var actors: Array = ["player",ids[0],ids[1]]
	var before: Dictionary = sim.export_snapshot()
	var rng_before: int = sim.rng.state
	var checks := 0
	var mismatch := 0
	for id in sim.catalog.locations:
		for actor_id in actors:
			for minute in [480,900,1200,1920]:
				for ignore_hours in [false,true]:
					var actual: Dictionary = sim.services.world.actor_availability(str(id),str(actor_id),minute,ignore_hours)
					var expected: Dictionary = _deep_availability(sim,str(id),str(actor_id),minute,ignore_hours)
					checks += 1
					if actual != expected: mismatch += 1
	var location_id := "bedroom"
	var had_requirements: bool = sim.catalog.locations[location_id].has("requirements")
	var original: Dictionary = sim.catalog.locations[location_id].get("requirements",{}).duplicate(true)
	sim.catalog.locations[location_id].requirements = {"all":[{"path":"clock.weekday","op":"gte","value":1},{"any":[{"path":"player.biography.role","value":"student"},{"path":"npc.biography.role","value":"worker"}]}]}
	for actor_id in actors:
		for minute in [480,1920]:
			var actual: Dictionary = sim.services.world.actor_availability(location_id,str(actor_id),minute,true)
			var expected: Dictionary = _deep_availability(sim,location_id,str(actor_id),minute,true)
			checks += 1
			if actual != expected: mismatch += 1
	if had_requirements: sim.catalog.locations[location_id].requirements = original
	else: sim.catalog.locations[location_id].erase("requirements")
	var pure: bool = sim.export_snapshot() == before and sim.rng.state == rng_before
	print("WORLD_AVAILABILITY_OPTIMIZATION ",JSON.stringify({"checks":checks,"mismatch":mismatch,"pure":pure,"setup_ok":setup_ok}))
	quit(0 if setup_ok and mismatch==0 and pure else 1)
