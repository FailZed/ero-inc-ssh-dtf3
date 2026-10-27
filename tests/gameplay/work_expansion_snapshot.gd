extends SceneTree
const Driver = preload("res://tests/gameplay/work_driver.gd")

func _initialize() -> void:
	call_deferred("run")

func normalized(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func run() -> void:
	root.get_node("GameSession").pause_autosave_runtime()
	var mode := ""
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write="): mode = "write"; path = arg.trim_prefix("--write=")
		if arg.begins_with("--read="): mode = "read"; path = arg.trim_prefix("--read=")
	var ok := AudioServer.get_driver_name() == "Dummy"
	var packets: Array = []
	if mode == "write":
		for id in ["tutor","lab_assistant","music_arranger"]:
			var sim = root.get_node("Gameplay").make_simulation()
			var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
			sim.state.world.location = job.location
			sim.state.clock = sim.calendar.snapshot(900)
			ok = ok and sim.command("livelihood","work",{"id":id}).ok
			ok = ok and sim.command("livelihood","input",Driver.answer(sim)).ok
			var saved := normalized(sim.export_snapshot())
			ok = ok and Driver.finish(sim)
			packets.append({"id":id,"snapshot":saved,"expected":normalized(sim.export_snapshot())})
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: ok = false
		else: file.store_string(JSON.stringify(packets)); file.close()
	elif mode == "read":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Array or parsed.size() != 3: ok = false
		else:
			packets = parsed
			for packet in packets:
				var sim = root.get_node("Gameplay").make_simulation()
				ok = ok and sim.restore_snapshot(packet.snapshot).ok
				ok = ok and Driver.finish(sim) and normalized(sim.export_snapshot()) == packet.expected
	else: ok = false
	print("WORK_EXPANSION_SNAPSHOT_RESULT ",JSON.stringify({"ok":ok,"mode":mode,"tasks":packets.size(),"audio":AudioServer.get_driver_name()}))
	quit(0 if ok else 1)
