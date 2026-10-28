extends "res://tests/gameplay/run.gd"

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	fresh_world()
	preload("res://tests/gameplay/npc_planner.gd").new(self).run()
	await preload("res://tests/gameplay/remaining.gd").new(self).run()
	print("NPC_PLANNER_MAIN_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
