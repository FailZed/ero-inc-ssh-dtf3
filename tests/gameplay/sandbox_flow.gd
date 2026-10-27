extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL: ",text)

func _run() -> void:
	var gameplay = root.get_node("Gameplay")
	var session = root.get_node("GameSession")
	var dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.mode = "sandbox"
	config.difficulty = "hard"
	config.population.count = 8
	config.content.pregnancy = false
	check(gameplay.begin_new_game(config) == OK, "new game API accepts real sandbox start")
	for i in range(12): await process_frame
	session.pause_autosave_runtime()
	var game = current_scene
	check(game != null and game.has_method("_on_gameplay_phase_changed"), "sandbox loads actual game scene")
	if game != null:
		check(game._character_creation_modal.visible, "actual game scene opens the mirror before sandbox")
		check(dialogic.current_timeline == null, "sandbox never starts prologue timeline")
		check(not game._gameplay_shell.visible, "city stays hidden until mirror confirmation")
		game._character_creation_modal._confirm.pressed.emit()
		for i in range(6): await process_frame
		session.pause_autosave_runtime()
		check(gameplay.phase == "free_roam" and game._gameplay_shell.visible, "real mirror button opens sandbox city")
		check(dialogic.current_timeline == null and not game._guided_exploration.visible, "sandbox has no timeline or authored exploration guide")
		check(gameplay.simulation.state.journal.quests.is_empty(), "sandbox does not add opening plot quest")
		check(gameplay.simulation.state.social.npcs.size() == 8, "sandbox respects configured population")
		var stored: Dictionary = dialogic.VAR.var_storage.World.duplicate(true)
		gameplay._on_time_reset(session.get_game_time_snapshot())
		for i in range(3): await process_frame
		check(gameplay.is_sandbox() and gameplay.phase == "free_roam" and dialogic.current_timeline == null, "restoring saved World preserves story-free sandbox")
		check(stored.gameplay.state.npc_stories == gameplay.simulation.state.npc_stories, "sandbox restores optional NPC chains")
	print("SANDBOX_FLOW_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
