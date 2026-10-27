extends SceneTree
## Focused portrait checks, without changing save slots or running other UI suites.
var checks := 0
var failures: Array[String] = []
var gameplay

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ",description)

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	preload("res://tests/gameplay/portraits.gd").run(self)
	preload("res://tests/gameplay/pregnancy_visuals.gd").run(self)
	print("PREGNANCY_VISUALS_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
