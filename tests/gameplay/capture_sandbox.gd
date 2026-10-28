extends SceneTree
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
var directory := OS.get_environment("EROINC_ARTIFACTS").path_join("captures/sandbox") if not OS.get_environment("EROINC_ARTIFACTS").is_empty() else "user://captures/sandbox"
var capture_failed := false

func _initialize() -> void:
	call_deferred("_run")

func _capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var code := root.get_texture().get_image().save_png(directory.path_join(name+".png"))
	if code != OK: capture_failed = true; printerr("CAPTURE_FAILED ",name)

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	DisplayServer.window_set_size(Vector2i(1366,768))
	var session = root.get_node("GameSession")
	var gameplay = root.get_node("Gameplay")
	session.pause_autosave_runtime()
	var setup = load("res://scenes/ui/WorldSetup.tscn").instantiate()
	setup.configuration.mode = "sandbox"
	setup.configuration.difficulty = "hard"
	setup.configuration.content.pregnancy = false
	setup.configuration.population.count = 8
	root.add_child(setup)
	await _capture("setup-mode")
	setup.page = 1
	setup._show_page()
	await _capture("setup-rules")
	var config: Dictionary = setup.configuration.duplicate(true)
	setup.queue_free()
	gameplay.begin_new_game(config)
	for i in range(12): await process_frame
	session.pause_autosave_runtime()
	var game = current_scene
	await _capture("sandbox-mirror")
	game._character_creation_modal._confirm.pressed.emit()
	for i in range(6): await process_frame
	session.pause_autosave_runtime()
	game._gameplay_shell.open_panel("map")
	await _capture("sandbox-city")
	var sim = gameplay.simulation
	var id: String = sim.state.social.npcs.keys()[0]
	var npc: Dictionary = sim.state.social.npcs[id]
	sim.services.npc_agency._cancel(npc,"visual_fixture")
	npc.location = sim.state.world.location
	npc.activity = "rest"
	npc.pinned_until = int(sim.state.clock.total_minutes)+1440
	sim.command("social","contact",{"id":id})
	sim.services.npc_relationships._bond(id,"player").trust = 30.0
	sim.services.npc_relationships._project(id,"player")
	gameplay.execute("npc_stories","start",{"id":id})
	game._gameplay_shell._open_personal_story(id)
	await _capture("npc-personal-story")
	var layer := CanvasLayer.new()
	layer.layer = 95
	game.add_child(layer)
	var comparison := Control.new()
	comparison.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(comparison)
	comparison.theme = UI.skin()
	var bg := ColorRect.new()
	bg.color = Color("07111c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	comparison.add_child(bg)
	var body := UI.column(UI.inset(comparison,28),12)
	UI.label(body,"Состояния персонажа · временная сборка",28,UI.BLUE)
	var row := UI.row(body,16)
	for state in ["Обычное состояние","Усталость","Травма","Беременность"]:
		var card := UI.card(row)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(card,state,21)
		var actor := Visuals.story_actor("asuka")
		actor.needs = {"energy":100,"hygiene":100,"mood":60}
		actor.injuries = {}
		if state == "Усталость": actor.needs.energy = 10
		if state == "Травма": actor.injuries = {"head":30,"arms":30}
		if state == "Беременность": actor.appearance.pregnancy_stage = 4
		var portrait = load("res://scripts/ui/gameplay/resident_preview.gd").new()
		portrait.wardrobe = "casual"
		portrait.framing = "full"
		portrait.custom_minimum_size = Vector2(260,590)
		portrait.set_actor(actor)
		card.add_child(portrait)
	await _capture("visual-states")
	UI.clear(row)
	for state in ["Обычное состояние","Усталость и гигиена","Травма"]:
		var card := UI.card(row)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(card,state,21)
		var actor := Visuals.story_actor("oliver")
		actor.needs = {"energy":100,"hygiene":100,"mood":60}
		actor.injuries = {}
		if state == "Усталость и гигиена": actor.needs.energy = 10; actor.needs.hygiene = 0
		if state == "Травма": actor.injuries = {"head":30,"arms":30}
		var portrait = load("res://scripts/ui/gameplay/resident_preview.gd").new()
		portrait.wardrobe = "casual"
		portrait.framing = "full"
		portrait.custom_minimum_size = Vector2(260,590)
		portrait.set_actor(actor)
		card.add_child(portrait)
	await _capture("visual-states-male")
	print("SANDBOX_CAPTURE_RESULT ",JSON.stringify({"audio":AudioServer.get_driver_name(),"size":[1366,768],"directory":directory}))
	quit(1 if capture_failed else 0)
