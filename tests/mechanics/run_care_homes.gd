extends "res://tests/mechanics/run_adult_health.gd"

func _initialize() -> void:
	preload("res://tests/mechanics/care_homes.gd").new(self).run()
	print("CARE_HOMES_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
