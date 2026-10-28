extends SceneTree
const Fixture = preload("res://tests/gameplay/companion_fixture.gd")

func _initialize() -> void:
	_run.call_deferred()

func normalized(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _run() -> void:
	root.get_node("GameSession").pause_autosave_runtime()
	var mode := ""
	var path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--write="): mode = "write"; path = argument.trim_prefix("--write=")
		if argument.begins_with("--read="): mode = "read"; path = argument.trim_prefix("--read=")
	var fixture = Fixture
	var ok := true
	if mode == "write":
		var sim = fixture.accepted_fixture()
		var packet := {"snapshot":normalized(sim.export_snapshot())}
		var token: int = sim.state.companion.active.token
		ok = sim.command("companion","finish",{"token":token,"zone":"hand_r","duration":1.0}).ok
		packet.expected = normalized(sim.export_snapshot())
		var output := FileAccess.open(path,FileAccess.WRITE)
		ok = ok and output != null
		if output != null: output.store_string(JSON.stringify(packet)); output.close()
	elif mode == "read":
		var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var sim = fixture.fixture()
		ok = sim.restore_snapshot(packet.snapshot).ok
		if ok:
			ok = sim.command("companion","finish",{"token":sim.state.companion.active.token,"zone":"hand_r","duration":1.0}).ok
			ok = ok and normalized(sim.export_snapshot())==packet.expected
	else: ok = false
	print("COMPANION_SNAPSHOT_RESULT ",JSON.stringify({"ok":ok,"mode":mode}))
	quit(0 if ok else 1)
