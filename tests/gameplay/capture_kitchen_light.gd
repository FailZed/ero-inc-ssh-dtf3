extends SceneTree
## In-memory render fixture for the kitchen's day and night backgrounds.
var destination := OS.get_environment("EROINC_ARTIFACTS").path_join("captures/kitchen-light") if not OS.get_environment("EROINC_ARTIFACTS").is_empty() else "user://captures/kitchen-light"
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("KITCHEN_CAPTURE_REQUIRES_NATIVE_RENDERER")
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
	gameplay.complete_chapter_one()
	var stage := Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	stage.add_child(shell)
	var sim = gameplay.simulation
	sim.state.world.location = "kitchen"
	var day_start := int(sim.state.clock.total_minutes) - int(sim.state.clock.minute_of_day)
	DirAccess.make_dir_recursive_absolute(destination)
	for hour in [19, 12]:
		sim.state.clock = sim.calendar.snapshot(day_start + hour * 60)
		shell.open_panel("place")
		for frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var expected := "kitchen_night_16x9.png" if hour == 19 else "kitchen_16x9.png"
		if not shell._background.texture.resource_path.ends_with(expected):
			failed = true
			printerr("KITCHEN_TEXTURE_MISMATCH ", hour, " ", shell._background.texture.resource_path)
		var image := root.get_texture().get_image()
		if image.save_png(destination.path_join("kitchen-%02d.png" % hour)) != OK:
			failed = true
			printerr("KITCHEN_CAPTURE_FAILED ", hour)
	print("KITCHEN_LIGHT_RESULT ", JSON.stringify({"failed":failed,"destination":destination}))
	quit(1 if failed else 0)
