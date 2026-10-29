extends SceneTree

const Simulation = preload("res://scripts/mechanics/simulation.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func fresh(extensions: Dictionary = {}):
	return Simulation.new(42, extensions)

func command(sim, module_id: String, operation: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim.command(module_id, operation, args)
	_check(bool(result.ok), "%s.%s succeeds: %s" % [module_id, operation, str(result.get("error", ""))])
	return result

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	preload("res://tests/mechanics/depth.gd").new(self).run()
	print("MECHANICS_DEPTH_AUDIT ", JSON.stringify({"checks": checks, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
