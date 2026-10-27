extends SceneTree
## Native renderer captures in a controlled fixture; never opens a user's save slot.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy":
		printerr("Captures require disabled audio output.")
		quit(2)
		return
	var directory := "E:/GoDot/.research/school-0.981/remaining-2026-10-27/captures"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(directory)
	var gameplay = root.get_node("Gameplay")
	var session = root.get_node("GameSession")
	var dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count = 8
	gameplay._pending_configuration = config
	dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	session.reset_character_profile()
	gameplay.complete_chapter_one()
	var sim = gameplay.simulation
	sim.state.economy.cash = 1200
	sim.state.world.location = "bedroom"
	sim.state.world.equipment = ["computer", "stove"]
	sim.state.player.skills.computing = 150
	sim.state.healthcare.family.append({"parent":"asuka","partner":"player","minute":sim.state.clock.total_minutes,"care":40,"status":"dependent"})
	sim.services.family.initialize()
	sim.state.family.members.family_1.name = "Мира"
	sim.state.family.members.family_1.needs.food = 35.0
	sim.state.family.members.family_1.needs.attention = 45.0
	sim.command("character", "gain_xp", {"amount":100})
	sim.command("events", "claim_achievement", {"id":"first_level"})
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	root.add_child(shell)
	await process_frame
	DisplayServer.window_set_size(Vector2i(1366,768))
	await process_frame
	for panel in ["family", "digital", "collection"]:
		shell.open_panel(panel)
		if not await _capture(directory.path_join(panel + ".png")): quit(1); return
	for button in shell._body.find_children("*", "Button", true, false):
		if button.text == "ПОСМОТРЕТЬ": button.pressed.emit(); break
	if not await _capture(directory.path_join("collection-open.png")): quit(1); return
	shell.hide()
	var menu = load("res://scenes/mainMenu/main_menu.tscn").instantiate()
	menu.menu_context = 1
	root.add_child(menu)
	menu.open_action(&"gallery")
	if not await _capture(directory.path_join("menu-collection.png")): quit(1); return
	print("REMAINING_CAPTURE_RESULT ", JSON.stringify({"audio":AudioServer.get_driver_name(),"directory":directory,"size":[1366,768]}))
	quit(0)

func _capture(path: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image().save_png(path) == OK
