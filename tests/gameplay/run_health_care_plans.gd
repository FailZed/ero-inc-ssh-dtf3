extends "res://tests/gameplay/run.gd"

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	fresh_world()
	await preload("res://tests/gameplay/health_care_plans.gd").new(self).run()
	print("HEALTH_CARE_PLANS_MAIN_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
