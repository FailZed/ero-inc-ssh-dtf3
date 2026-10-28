extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); printerr("FAIL: ",description)

func _run() -> void:
	var session = root.get_node("GameSession")
	var dialogic = root.get_node("Dialogic")
	var game = root.get_node("Gameplay")
	session.pause_autosave_runtime()
	var sim = preload("res://tests/gameplay/companion_fixture.gd").fixture()
	var invalid: Dictionary = sim.export_snapshot()
	invalid.main_schema = 8
	dialogic.VAR.var_storage.World = {"gameplay":invalid,"time_total_minutes":600}
	const SLOT := "test_incompatible_companion"
	check(dialogic.Save.save(SLOT,false,0) == OK,"create incompatible fixture in isolated user directory")
	var path: String = dialogic.Save.get_slot_path(SLOT).path_join("state.txt")
	var original := FileAccess.get_file_as_bytes(path)
	check(session.request_load_slot(SLOT) == OK,"request load from outside the game scene")
	for i in range(24): await process_frame
	check(current_scene != null and current_scene.scene_file_path == session.MAIN_MENU_SCENE_PATH,"incompatible load returns to menu")
	check(not session.last_load_error.is_empty(),"readable compatibility explanation is retained")
	check(current_scene != null and current_scene.get("feedback_label") != null and current_scene.feedback_label.text == session.last_load_error,"explanation is visible in the menu")
	check(dialogic.current_timeline == null,"failed load never silently starts a new prologue")
	check(game.restore_error == "unsupported_main_schema","underlying incompatibility is preserved")
	check(session.perform_autosave() == ERR_INVALID_DATA,"autosave refuses invalid world")
	check(FileAccess.get_file_as_bytes(path) == original,"failed load leaves saved file byte-for-byte intact")
	check(dialogic.Save.delete_slot(SLOT) == OK,"remove only the test fixture")
	print("SAVE_COMPATIBILITY_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
