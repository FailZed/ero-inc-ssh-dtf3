extends SceneTree

const BASE := "res://assets/characters/male_cubism/runtime"

var passed := 0
var failed := 0


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	check(ClassDB.class_exists("GDCubismUserModel"), "Cubism native class exists")
	for form: String in ["lean", "medium", "full"]:
		var path := BASE.path_join(form).path_join(form + "-layered-pilot.model3.json")
		var model: Node2D = ClassDB.instantiate("GDCubismUserModel") as Node2D
		root.add_child(model)
		model.call("set_process_callback", 2)
		model.call("set_parameter_mode", 0)
		model.call("set_assets", path)
		check(int(model.call("csm_get_moc_version")) == 5, form + " layered MOC v5 loads")
		var meshes: Dictionary = model.call("get_meshes")
		check(meshes.size() == 10, form + " has ten ArtMeshes")
		var found_torso := false
		for param: Variant in model.call("get_parameters"):
			if str(param.call("get_id")) == "ParamTorsoWidth":
				found_torso = true
				check(is_equal_approx(float(param.call("get_minimum_value")), -1.0), "torso minimum")
				check(is_equal_approx(float(param.call("get_default_value")), 0.0), "torso default")
				check(is_equal_approx(float(param.call("get_maximum_value")), 1.0), "torso maximum")
		check(found_torso, form + " has torso width parameter")
		print("MALE_LAYERED_MODEL ", JSON.stringify({
			"form": form,
			"meshes": meshes.size(),
			"parameters": (model.call("get_parameters") as Array).size(),
			"torso_width": found_torso,
		}))
		model.queue_free()
		await process_frame
	print("MALE_LAYERED_RESULT ", JSON.stringify({"passed": passed, "failed": failed}))
	quit(0 if failed == 0 else 1)
