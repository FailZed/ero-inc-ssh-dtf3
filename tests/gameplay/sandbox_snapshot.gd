extends SceneTree
## Test-owned JSON fixture only; no user save slot is created or modified.
var gameplay
var session
var dialogic

func _initialize() -> void:
	call_deferred("_run")

func _normal(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _continue() -> bool:
	return gameplay.execute("world","journey",{"id":"north_beach"}).ok and gameplay.execute("clock","advance",{"minutes":30}).ok

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var mode := ""
	var path := ""
	var enrolled := true
	for arg in OS.get_cmdline_user_args():
		if arg == "--nonstudent": enrolled = false
		if arg.begins_with("--write="): mode = "write"; path = arg.trim_prefix("--write=")
		if arg.begins_with("--read="): mode = "read"; path = arg.trim_prefix("--read=")
	if mode == "write":
		var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
		config.mode = "sandbox"
		config.difficulty = "hard"
		config.population.count = 8
		config.content.pregnancy = false
		config.sandbox.education = {"enrolled":enrolled,"subjects":["physics","genetics"] if enrolled else []}
		gameplay._pending_configuration = config
		dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
		session.reset_game_time()
		session.reset_character_profile()
		var profile: Dictionary = session.get_character_profile()
		profile.identity.full_name = "Житель песочницы"
		if not session.apply_character_profile_v2(profile) or not gameplay.open_sandbox().ok: _finish(false,mode,"start"); return
		if not gameplay.execute("social","generate",{"id":"newcomer","age":23}).ok: _finish(false,mode,"npc"); return
		# Match normal world generation, which binds stable visual identities.
		gameplay._bind_npc_art()
		var sim = gameplay.simulation
		if bool(sim.state.world.flags.student_enrolled) != enrolled or sim.state.world.flags.subject_computing or bool(sim.state.world.flags.subject_physics) != enrolled: _finish(false,mode,"enrollment"); return
		var npc: Dictionary = sim.state.social.npcs.newcomer
		sim.services.npc_agency._cancel(npc,"snapshot_fixture")
		npc.location = sim.state.world.location
		npc.activity = "rest"
		npc.pinned_until = int(sim.state.clock.total_minutes)+1440
		if not gameplay.execute("social","contact",{"id":"newcomer"}).ok: _finish(false,mode,"contact"); return
		sim.services.npc_relationships._bond("newcomer","player").trust = 30.0
		sim.services.npc_relationships._project("newcomer","player")
		if not gameplay.execute("npc_stories","start",{"id":"newcomer"}).ok: _finish(false,mode,"story"); return
		if not gameplay.execute("npc_stories","choose",{"id":"newcomer","node":"intro","choice":"help"}).ok: _finish(false,mode,"choice"); return
		if not gameplay.execute("world","journey",{"id":"city_park"}).ok: _finish(false,mode,"first_visit"); return
		var variables: Dictionary = _normal(dialogic.VAR.var_storage)
		if not _continue(): _finish(false,mode,"continuation"); return
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: _finish(false,mode,"fixture"); return
		file.store_string(JSON.stringify({"variables":variables,"expected":_normal(sim.export_snapshot())}))
		file.close()
		_finish(sim.state.npc_stories.arcs.newcomer.node == "return_one",mode)
	elif mode == "read":
		var packet: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not packet is Dictionary: _finish(false,mode,"fixture"); return
		dialogic.VAR.var_storage = packet.variables.duplicate(true)
		session._sync_game_time_from_dialogic()
		session._sync_character_profile_from_dialogic()
		if not gameplay.restore_error.is_empty() or not gameplay.is_sandbox() or gameplay.phase != "free_roam": _finish(false,mode,"restore"); return
		if bool(gameplay.configuration.sandbox.education.enrolled) != enrolled or bool(gameplay.simulation.state.world.flags.student_enrolled) != enrolled: _finish(false,mode,"enrollment"); return
		if gameplay.simulation.state.npc_stories.arcs.newcomer.goal.count != 1: _finish(false,mode,"partial_progress"); return
		var ok := _continue()
		ok = ok and _normal(gameplay.simulation.export_snapshot()) == packet.expected
		if not ok: _differences(_normal(gameplay.simulation.export_snapshot()),packet.expected)
		ok = ok and "pregnancy" in gameplay.simulation.state.preferences.disabled_tags and dialogic.current_timeline == null
		_finish(ok,mode)
	else: _finish(false,mode,"arguments")

func _finish(ok: bool, mode: String, stage: String = "complete") -> void:
	print("SANDBOX_SNAPSHOT_RESULT ",JSON.stringify({"mode":mode,"ok":ok,"stage":stage,"audio":AudioServer.get_driver_name()}))
	quit(0 if ok else 1)

func _differences(actual: Variant, expected: Variant, path: String = "snapshot") -> void:
	if actual == expected: return
	if actual is Dictionary and expected is Dictionary:
		for key in actual:
			if expected.has(key): _differences(actual[key],expected[key],path+"."+str(key))
			else: print("SNAPSHOT_DIFFERENCE ",path,".",key," missing expected")
	elif actual is Array and expected is Array and actual.size() == expected.size():
		for i in range(actual.size()): _differences(actual[i],expected[i],path+"["+str(i)+"]")
	else: print("SNAPSHOT_DIFFERENCE ",path," actual=",actual," expected=",expected)
