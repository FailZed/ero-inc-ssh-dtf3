extends SceneTree
## End-to-end gate: paused story starts and story saves cannot enter gameplay.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	var session = root.get_node("GameSession")
	var gameplay = root.get_node("Gameplay")
	var dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var story: Dictionary = preload("res://scripts/mechanics/setup_config.gd").defaults()
	story.mode = "story"
	var before: Dictionary = gameplay.simulation.export_snapshot()
	check(gameplay.begin_new_game(story) == ERR_UNAVAILABLE and gameplay.simulation.export_snapshot() == before,
		"story API cannot start a new game or alter sandbox state")
	check(session.start_new_game() == OK, "legacy direct start reaches the mode gate")
	for i in range(16): await process_frame
	check(current_scene != null and current_scene.scene_file_path == session.MAIN_MENU_SCENE_PATH and dialogic.current_timeline == null,
		"direct start returns to menu without launching the prologue")
	session.pause_autosave_runtime()
	var world: Dictionary = {
		"gameplay_setup": story,
		"gameplay": before,
		"gameplay_phase": "story",
		"time_total_minutes": 480,
	}
	dialogic.VAR.var_storage.World = world
	const SLOT := "test_story_mode_paused"
	check(dialogic.Save.save(SLOT, false, 0) == OK, "create a story save in the disposable test directory")
	var path: String = dialogic.Save.get_slot_path(SLOT).path_join("state.txt")
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check(session.request_load_slot(SLOT) == OK, "story save is found by the load menu")
	for i in range(24): await process_frame
	check(current_scene != null and current_scene.scene_file_path == session.MAIN_MENU_SCENE_PATH,
		"story save returns to main menu while story mode is paused")
	check(session.last_load_error == session.localize("feedback.story_unavailable"),
		"menu explains that story mode is temporarily unavailable")
	check(dialogic.current_timeline == null, "story timeline never starts")
	check(FileAccess.get_file_as_bytes(path) == original, "blocked story save stays byte-for-byte unchanged")
	check(dialogic.Save.delete_slot(SLOT) == OK, "remove only the disposable test save")
	print("STORY_MODE_DISABLED_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
