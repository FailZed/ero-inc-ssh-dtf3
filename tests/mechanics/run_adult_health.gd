extends SceneTree
var checks := 0
var failures: Array[String] = []

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ",description)

func _initialize() -> void:
	preload("res://tests/mechanics/adult_health.gd").new(self).run()
	print("ADULT_HEALTH_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
