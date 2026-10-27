extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func normal(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func continuation(sim) -> bool:
	while not sim.state.livelihood.pending.is_empty():
		var p: Dictionary = sim.state.livelihood.pending
		var args := {"token":p.token,"round":int(p.round),"elapsed_ms":int(p.elapsed)+300,"choice":int(p.tasks[int(p.round)].answer)}
		if not sim.command("livelihood","input",args).ok: return false
	return true

func run() -> void:
	root.get_node("GameSession").pause_autosave_runtime()
	var mode := ""
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write="): mode = "write"; path = arg.trim_prefix("--write=")
		if arg.begins_with("--read="): mode = "read"; path = arg.trim_prefix("--read=")
	var sim = root.get_node("Gameplay").make_simulation()
	var ok := true
	if mode == "write":
		sim.state.clock = sim.calendar.snapshot(600)
		sim.state.world.location = "riverside_cafe"
		ok = sim.command("livelihood","work",{"id":"cafe_orders"}).ok
		var p: Dictionary = sim.state.livelihood.pending
		if not ok: finish(false,mode); return
		ok = sim.command("livelihood","input",{"token":p.token,"round":0,"action":"ready"}).ok
		ok = ok and sim.command("livelihood","input",{"token":p.token,"round":0,"choice":int(p.tasks[0].answer),"elapsed_ms":300}).ok
		var saved: Dictionary = normal(sim.export_snapshot())
		ok = ok and continuation(sim)
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file == null: ok = false
		else: file.store_string(JSON.stringify({"snapshot":saved,"expected":normal(sim.export_snapshot())})); file.close()
	elif mode == "read":
		var packet: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not packet is Dictionary: finish(false,mode); return
		ok = sim.restore_snapshot(packet.snapshot).ok and int(sim.state.livelihood.pending.round) == 1
		ok = ok and continuation(sim) and normal(sim.export_snapshot()) == packet.expected
	else: ok = false
	finish(ok,mode)

func finish(ok: bool, mode: String) -> void:
	print("LIVELIHOOD_SNAPSHOT_RESULT ",JSON.stringify({"ok":ok,"mode":mode,"audio":AudioServer.get_driver_name()}))
	quit(0 if ok else 1)
