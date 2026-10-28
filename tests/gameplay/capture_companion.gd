extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.get_node("GameSession").pause_autosave_runtime()
	DisplayServer.window_set_size(Vector2i(1366,768))
	var game = root.get_node("Gameplay")
	game.simulation = preload("res://tests/gameplay/companion_fixture.gd").accepted_fixture()
	game.phase = "free_roam"
	var window = load("res://scripts/ui/gameplay/companion_window.gd").new()
	window.npc_id = "friend"
	root.add_child(window)
	for i in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("EROINC_ARTIFACTS").path_join("captures/companion")
	DirAccess.make_dir_recursive_absolute(directory)
	var code := root.get_texture().get_image().save_png(directory.path_join("accepted.png"))
	window._complete_keyboard()
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image().save_png(directory.path_join("completed.png"))
	var ok: bool = code == OK and after == OK and game.simulation.state.companion.active.is_empty()
	window._close_moment()
	await process_frame
	print("COMPANION_NATIVE_RESULT ",JSON.stringify({"ok":ok}))
	quit(0 if ok else 1)
