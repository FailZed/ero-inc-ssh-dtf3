extends "res://scripts/mechanics/npc_life_simulation.gd"
## Instrumentation only: same per-minute order as Simulation.advance.
var service_us: Dictionary = {}
var clock_us := 0
var planner_us := 0

func advance(minutes: int) -> Dictionary:
	if not _busy: return Rules.fail("use_clock_command")
	if minutes < 0 or minutes > int(catalog.settings.max_advance_minutes): return Rules.fail("invalid_time_delta")
	for step in range(minutes):
		var minute := int(state.clock.total_minutes) + 1
		var started := Time.get_ticks_usec()
		state.clock = calendar.snapshot(minute)
		clock_us += Time.get_ticks_usec()-started
		for id in services:
			started = Time.get_ticks_usec()
			services[id].tick(minute)
			service_us[id] = int(service_us.get(id,0))+Time.get_ticks_usec()-started
		started = Time.get_ticks_usec()
		after_minute(minute)
		planner_us += Time.get_ticks_usec()-started
	return Rules.ok({"clock":state.clock.duplicate(true)})
