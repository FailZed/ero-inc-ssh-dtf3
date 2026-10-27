extends "res://tests/gameplay/run.gd"

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	fresh_world()
	preload("res://tests/gameplay/npc_life.gd").new(self).run()
	await preload("res://tests/gameplay/dialogue.gd").new(self).run()
	await preload("res://tests/gameplay/integration_routes.gd").new(self).run()
	print("HEALTH_SOCIAL_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
