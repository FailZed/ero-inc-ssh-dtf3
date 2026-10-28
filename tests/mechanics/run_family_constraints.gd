extends "res://tests/mechanics/run_adult_health.gd"

func _initialize() -> void:
	preload("res://tests/mechanics/family.gd").new(self)._care_constraints()
	print("FAMILY_CONSTRAINTS_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
