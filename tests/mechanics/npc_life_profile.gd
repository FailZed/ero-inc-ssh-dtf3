extends SceneTree
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
const Profiled = preload("res://tests/mechanics/profile_life_simulation.gd")
const ProfiledAgency = preload("res://tests/mechanics/profile_human_agency.gd")
const ProfiledPersonalities = preload("res://tests/mechanics/profile_npc_personalities.gd")
const ProfiledCalendar = preload("res://tests/mechanics/profile_npc_calendar.gd")

func _initialize() -> void:
	_run.call_deferred()

func _fresh(kind):
	var sim = kind.new(128,{"settings":{"start_minutes":480}})
	for command in [["npc_agency","enable",{}],["population","configure",{"values":{"count":100}}],["population","generate",{}]]:
		var result: Dictionary = sim.command(command[0],command[1],command[2])
		if not result.ok: push_error("profile setup failed: "+str(result))
	return sim

func _run() -> void:
	var minutes := 15
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--minutes="): minutes = int(str(arg).get_slice("=",1))
	var setup_start := Time.get_ticks_msec()
	var baseline = _fresh(Life)
	print("NPC_LIFE_PROFILE setup_baseline_ms=", Time.get_ticks_msec()-setup_start)
	setup_start = Time.get_ticks_msec()
	var profiled = _fresh(Profiled)
	profiled.services.npc_agency = ProfiledAgency.new(profiled)
	profiled.services.npc_personalities = ProfiledPersonalities.new(profiled)
	profiled.services.npc_planner.calendar = ProfiledCalendar.new(profiled)
	print("NPC_LIFE_PROFILE setup_instrumented_ms=", Time.get_ticks_msec()-setup_start)
	var same_start: bool = baseline.export_snapshot() == profiled.export_snapshot() and baseline.rng.state == profiled.rng.state
	var start := Time.get_ticks_msec()
	var result: Dictionary = baseline.command("clock","advance",{"minutes":minutes})
	var baseline_ms := Time.get_ticks_msec()-start
	print("NPC_LIFE_PROFILE baseline_advance_ms=", baseline_ms)
	start = Time.get_ticks_msec()
	var measured: Dictionary = profiled.command("clock","advance",{"minutes":minutes})
	var profiled_ms := Time.get_ticks_msec()-start
	var same_end: bool = baseline.export_snapshot() == profiled.export_snapshot() and baseline.rng.state == profiled.rng.state
	var restored = Life.new(128,{"settings":{"start_minutes":480}})
	var restore_result: Dictionary = restored.restore_snapshot(baseline.export_snapshot())
	var same_restore: bool = restore_result.ok and restored.export_snapshot() == baseline.export_snapshot() and restored.rng.state == baseline.rng.state
	var order: Array = profiled.service_us.keys()
	order.sort_custom(func(a,b): return int(profiled.service_us[a]) > int(profiled.service_us[b]))
	var top: Array = []
	for id in order.slice(0,12): top.append({"service":str(id),"ms":float(profiled.service_us[id])/1000.0})
	var agency = profiled.services.npc_agency
	var personalities = profiled.services.npc_personalities
	var calendar = profiled.services.npc_planner.calendar
	print("NPC_LIFE_PROFILE ",JSON.stringify({"minutes":minutes,"baseline_ms":baseline_ms,"instrumented_ms":profiled_ms,"same_start":same_start,"same_end":same_end,"same_restore":same_restore,"ok":result.ok and measured.ok,"clock_ms":float(profiled.clock_us)/1000.0,"after_minute_ms":float(profiled.planner_us)/1000.0,"agency_choose_ms":float(agency.choose_us)/1000.0,"agency_evaluate_ms":float(agency.evaluate_us)/1000.0,"agency_index_ms":float(agency.index_us)/1000.0,"agency_partner_ms":float(agency.partner_us)/1000.0,"agency_route_ms":float(agency.route_us)/1000.0,"agency_agenda_ms":float(agency.agenda_us)/1000.0,"agency_action_spec_ms":float(agency.action_spec_us)/1000.0,"agency_choose_calls":agency.choose_calls,"personality_profile_ms":float(personalities.profile_us)/1000.0,"personality_profile_calls":personalities.profile_calls,"calendar_windows_ms":float(calendar.windows_us)/1000.0,"calendar_windows_calls":calendar.windows_calls,"top":top}))
	quit(0 if same_start and same_end and same_restore and result.ok and measured.ok else 1)
