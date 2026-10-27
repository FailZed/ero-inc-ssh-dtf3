extends SceneTree
## Run this file by absolute path with --main-pack; the shipped pack excludes tests.
var checks := 0
var failed: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed.append(label); printerr("FAIL: ",label)
func _run() -> void:
	var game = root.get_node("Gameplay")
	var session = root.get_node("GameSession")
	session.pause_autosave_runtime()
	var setup = load("res://scripts/mechanics/setup_config.gd")
	var config: Dictionary = setup.defaults()
	config.population.count = 8
	game._pending_configuration = config
	session.reset_game_time()
	session.reset_character_profile()
	game.complete_chapter_one()
	check(game.simulation.configuration_error.is_empty(),"packed main catalog validates")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/city-river-v2.json"))
	check(data is Dictionary and data.get("locations",[]).size() == 15,"raw city geography is included in the exported pack")
	if data is Dictionary:
		for path in data.get("period_textures",{}).values(): check(load(str(path)) is Texture2D,"packed city lighting texture loads: " + str(path))
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	root.add_child(shell)
	shell.open_panel("map")
	await process_frame
	check(shell._city.markers.size() == 15,"packed main HUD instantiates its travel markers")
	shell._city.select("north_beach")
	shell._city._go()
	check(game.simulation.state.world.location == "north_beach" and shell.current_panel == "place","packed map actually enters a north-bank location")
	check(game.execute("world","journey",{"id":"bedroom"}).ok,"packed city returns through the home entrance")
	print("PACKED_CITY_RESULT ",JSON.stringify({"checks":checks,"failed":failed.size(),"failures":failed}))
	quit(0 if failed.is_empty() else 1)
