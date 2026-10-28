extends SceneTree

const Validator = preload("res://assets/characters/mdrg_study/runtime/live2d_physics_validator.gd")
const Actor = preload("res://assets/characters/mdrg_study/runtime/live2d_actor.gd")
const CATALOG := "res://assets/characters/mdrg_study/catalog.json"
var failed := 0
var passed := 0

func check(ok: bool, title: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + title)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	var everyday: Dictionary = {}
	for entry: Dictionary in catalog.models:
		var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.model3))
		var physics_path: String = str(entry.model3).get_base_dir().path_join(model.FileReferences.Physics).simplify_path()
		check(Validator.validate_file(physics_path).is_empty(), "physics metadata: " + str(entry.id))
		if entry.name == "interaction_model":
			everyday = entry
	check(not everyday.is_empty(), "everyday test model exists")
	if everyday.is_empty():
		quit(1)
		return
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(everyday.model3))
	var physics_path: String = str(everyday.model3).get_base_dir().path_join(model.FileReferences.Physics).simplify_path()
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(physics_path))
	var invalid: Dictionary = valid.duplicate(true)
	invalid.Meta.VertexCount = invalid.Meta.VertexCount
	invalid.Meta.erase("VertexCount")
	check(Validator.validate(invalid).contains("VertexCount"), "legacy wrong field rejected before native load")
	for field: String in ["VertexCount", "TotalInputCount", "TotalOutputCount", "PhysicsSettingCount"]:
		for offset: int in [-1, 1]:
			var broken: Dictionary = valid.duplicate(true)
			broken.Meta[field] += offset
			check(not Validator.validate(broken).is_empty(), "wrong allocation count: " + field + str(offset))
	var broken: Dictionary = valid.duplicate(true)
	broken.PhysicsSettings[0].Output[0].VertexIndex = broken.PhysicsSettings[0].Vertices.size()
	check(not Validator.validate(broken).is_empty(), "out of bounds particle rejected")
	broken = valid.duplicate(true)
	broken.PhysicsSettings[0].Output[0].VertexIndex = 1.5
	check(not Validator.validate(broken).is_empty(), "fractional particle index rejected")
	broken = valid.duplicate(true)
	broken.PhysicsSettings[0].Input[0].Type = "Unknown"
	check(not Validator.validate(broken).is_empty(), "unknown native function type rejected")
	check(not Validator.validate(null).is_empty(), "null rejected")
	var file := FileAccess.open("user://invalid.physics3.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid))
	file.close()
	var invalid_model: Dictionary = model.duplicate(true)
	invalid_model.FileReferences.Physics = "invalid.physics3.json"
	file = FileAccess.open("user://invalid.model3.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid_model))
	file.close()
	var actor := Actor.new()
	root.add_child(actor)
	check(not actor.load_model({"model3": "user://invalid.model3.json"}), "actor rejects malformed physics without crashing")
	check(actor.get_child_count() == 0, "no native object created for invalid physics")
	check(actor.last_error.contains("VertexCount"), "actionable error")
	check(actor.load_model(everyday), "real model loads after rejected data")
	check(actor.get_parameter_descriptors().size() == 106, "native parameters available")
	for frame in range(10):
		await process_frame
	check(actor.load_model(everyday), "native reload remains valid")
	actor.queue_free()
	await process_frame
	print("IMPORTED_BROWSER_RESULT ", JSON.stringify({"passed": passed, "failed": failed}))
	quit(0 if failed == 0 else 1)
