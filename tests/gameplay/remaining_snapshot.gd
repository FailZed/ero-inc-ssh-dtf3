extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _normal(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _run() -> void:
	var mode := ""
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write="): mode = "write"; path = arg.trim_prefix("--write=")
		if arg.begins_with("--read="): mode = "read"; path = arg.trim_prefix("--read=")
	var sim = root.get_node("Gameplay").make_simulation()
	var passed := true
	if mode == "write":
		sim.state.clock = sim.calendar.snapshot(540)
		sim.state.economy.cash = 1000
		sim.state.world.equipment = ["computer"]
		sim.state.player.skills.computing = 150
		passed = sim.command("social", "generate", {"id":"coparent", "age":28}).ok
		var parent: Dictionary = sim.state.social.npcs.coparent
		parent.home = "bedroom"
		parent.location = "bedroom"
		parent.schedule = []
		parent.activity = "rest"
		parent.pinned_until = 0
		parent.needs.energy = 100.0
		sim.state.healthcare.family.append({"parent":"coparent", "partner":"player", "minute":540, "care":20, "status":"dependent"})
		sim.services.family.initialize()
		sim.state.family.members.family_1.needs.hygiene = 20.0
		sim.services.family._autonomy(sim.state.family.members.family_1)
		passed = passed and not sim.state.family.members.family_1.task.is_empty()
		passed = passed and sim.command("digital", "scan", {"id":"training"}).ok
		# Prepare one further real care task so restoration includes unfinished work.
		parent = sim.state.social.npcs.coparent
		parent.activity = "rest"
		parent.pinned_until = 0
		sim.state.family.members.family_1.needs.hygiene = 10.0
		sim.state.family.members.family_1.recent.erase("wash")
		sim.services.family._autonomy(sim.state.family.members.family_1)
		var snapshot: Dictionary = _normal(sim.export_snapshot())
		var args := {"id":"training", "token":sim.state.digital.pending.token}
		passed = passed and sim.command("digital", "resolve", args).ok
		passed = passed and sim.command("clock", "advance", {"minutes":60}).ok
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: passed = false
		else: file.store_string(JSON.stringify({"snapshot":snapshot,"args":args,"expected":_normal(sim.export_snapshot())})); file.close()
	elif mode == "read":
		var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not fixture is Dictionary: passed = false
		else:
			passed = sim.restore_snapshot(fixture.snapshot).ok
			passed = passed and sim.command("digital", "resolve", fixture.args).ok
			passed = passed and sim.command("clock", "advance", {"minutes":60}).ok
			passed = passed and _normal(sim.export_snapshot()) == fixture.expected
	else: passed = false
	print("REMAINING_SNAPSHOT_RESULT ", JSON.stringify({"mode":mode,"ok":passed}))
	quit(0 if passed else 1)
