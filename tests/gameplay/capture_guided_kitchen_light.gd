extends SceneTree
## Renders the authored kitchen route in a disposable story world.
var destination := OS.get_environment("EROINC_ARTIFACTS").path_join("captures/guided-kitchen-light") if not OS.get_environment("EROINC_ARTIFACTS").is_empty() else "user://captures/guided-kitchen-light"
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GUIDED_KITCHEN_CAPTURE_REQUIRES_NATIVE_RENDERER")
		quit(2)
		return
	var session = root.get_node("GameSession")
	var gameplay = root.get_node("Gameplay")
	session.pause_autosave_runtime()
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count = 8
	gameplay._pending_configuration = config
	session.reset_game_time()
	session.reset_character_profile()
	var guide = load("res://scripts/ui/gameplay/guided_exploration.gd").new()
	root.add_child(guide)
	DirAccess.make_dir_recursive_absolute(destination)
	for setting in [{"stage":"night", "month":8, "day":31, "hour":3, "minute":20, "file":"guided-kitchen-03.png", "expected":"kitchen_night_16x9.png"}, {"stage":"morning_dress", "month":9, "day":1, "hour":11, "minute":0, "file":"guided-kitchen-11.png", "expected":"kitchen_16x9.png"}]:
		gameplay.set_story_date(setting.month, setting.day, setting.hour, setting.minute)
		gameplay.begin_guide(setting.stage)
		if not gameplay.guided_travel("apartment_hall").ok or not gameplay.guided_travel("kitchen").ok:
			failed = true
			printerr("GUIDED_KITCHEN_ROUTE_FAILED ", setting.stage)
		guide.refresh()
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		if not guide._background.texture.resource_path.ends_with(setting.expected):
			failed = true
			printerr("GUIDED_KITCHEN_TEXTURE_MISMATCH ", setting.stage, " ", guide._background.texture.resource_path)
		if root.get_texture().get_image().save_png(destination.path_join(setting.file)) != OK:
			failed = true
			printerr("GUIDED_KITCHEN_CAPTURE_FAILED ", setting.stage)
	print("GUIDED_KITCHEN_LIGHT_RESULT ", JSON.stringify({"failed":failed,"destination":destination}))
	quit(1 if failed else 0)
