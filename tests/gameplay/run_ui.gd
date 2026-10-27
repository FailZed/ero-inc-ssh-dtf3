extends "res://tests/gameplay/run.gd"
## Focused UI acceptance. Save-schema migrations are verified by the main suite.

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	fresh_world()
	gameplay.complete_chapter_one()
	await _test_windows()
	await preload("res://tests/gameplay/hud.gd").new(self).run()
	await preload("res://tests/gameplay/ui_redesign.gd").new(self).run()
	await preload("res://tests/gameplay/game_ui.gd").new(self).run()
	await preload("res://tests/gameplay/all_windows.gd").new(self).run()
	await preload("res://tests/gameplay/integration_routes.gd").new(self).run()
	print("GAME_UI_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
