extends SceneTree
## Narrow headless check of GG save contract and the real retained Cubism backend.

const VIEW = preload("res://scripts/characters/protagonist_live2d.gd")
const APPEARANCE = preload("res://scripts/characters/protagonist_appearance.gd")

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append(label)
		printerr("FAIL: ", label)


func _run() -> void:
	var default_state: Dictionary = APPEARANCE.normalize_appearance({})
	check(APPEARANCE.validate_appearance(default_state), "normalized default is valid without loading native model")
	check(default_state.get("outfit") == "hoodie_pants", "default is fully clothed")
	var malformed: Dictionary = APPEARANCE.normalize_appearance({"shape": {"ParamAssSize": 7.0, "Bad": 2.0}, "outfit": "nude"})
	check(APPEARANCE.validate_appearance(malformed) and is_equal_approx(float(malformed["shape"]["ParamAssSize"]), 1.0) and malformed["outfit"] == "hoodie_pants", "normalizer clamps and rejects unsupported customization")
	check(not APPEARANCE.validate_appearance({"schema": 1, "model_id": "gg", "shape": {"Bad": 0.0}, "outfit": "nude"}), "validator rejects unsupported customization")
	var invalid_schema: Dictionary = default_state.duplicate(true)
	invalid_schema["schema"] = 1.5
	check(not APPEARANCE.validate_appearance(invalid_schema), "validator rejects fractional schema 1.5")
	check(ClassDB.class_exists("GDCubismUserModel"), "native Cubism backend registered")
	var view: Node2D = VIEW.new()
	root.add_child(view)
	check(bool(view.call("load_gg")), "GG descriptor loads retained native MOC")
	if not bool(view.call("is_model_loaded")):
		_finish(view)
		return
	check(bool(view.get("fully_loaded")), "fully loaded state set")
	var actor: Node2D = view.call("get_actor")
	check(str(actor.call("get_model_id")) == "gg", "GG has separate instance ID")
	check(str(actor.call("get_source_model_id")) == "interaction_model__714017f09d7b7c24_21238", "retained study provenance is preserved")
	var native: Node2D = actor.get("_model")
	check(int(native.call("csm_get_moc_version")) > 0, "real Cubism MOC parsed")
	check((native.call("get_motions") as Dictionary).is_empty(), "GG descriptor has no study motions")
	var state: Dictionary = view.call("get_appearance")
	check(APPEARANCE.validate_appearance(state), "view provides save-safe appearance")
	check(is_equal_approx(float(actor.call("get_parameter_value", "ParamHoodieEnabled")), 1.0) and is_equal_approx(float(actor.call("get_parameter_value", "ParamPantsEnabled")), 1.0), "default hoodie and pants applied to real model")
	var change: Dictionary = state.duplicate(true)
	change["shape"]["ParamAssSize"] = 0.8
	change["shape"]["ParamThighSize"] = -0.5
	change["outfit"] = "shirt_skirt"
	check(bool(view.call("apply_appearance", change)), "shape and outfit apply")
	check(is_equal_approx(float(actor.call("get_parameter_value", "ParamAssSize")), 0.8) and is_equal_approx(float(actor.call("get_parameter_value", "ParamThighSize")), -0.5), "native shape values changed")
	check(is_equal_approx(float(actor.call("get_parameter_value", "ParamShirtEnabled")), 1.0) and is_equal_approx(float(actor.call("get_parameter_value", "ParamSkirtEnabled")), 1.0) and is_zero_approx(float(actor.call("get_parameter_value", "ParamHoodieEnabled"))), "native outfit switches changed")
	view.call("set_framing", "face", Vector2(640.0, 760.0), 1.15, Vector2(8.0, -12.0), 0.35)
	check(actor.scale.x > 2.0 and is_equal_approx(float(actor.call("get_parameter_value", "ParamHeadZ")), 0.35), "face framing and head tilt affect only preview")
	for frame: int in range(20):
		await process_frame
	check(is_equal_approx(float(actor.call("get_parameter_value", "ParamAssSize")), 0.8) and is_equal_approx(float(actor.call("get_parameter_value", "ParamShirtEnabled")), 1.0), "appearance remains after native frames")
	check((view.call("get_appearance") as Dictionary) == change, "framing does not enter saved appearance")
	var meshes: Dictionary = actor.call("get_drawable_meshes")
	var hair_mesh: MeshInstance2D = meshes.get("ModdableHairFront") as MeshInstance2D
	var visible_hair_mesh: MeshInstance2D = meshes.get("H0_Front_Bang") as MeshInstance2D
	var iris_mesh: MeshInstance2D = meshes.get("Iris1L") as MeshInstance2D
	var skin_mesh: MeshInstance2D = meshes.get("SkinFace") as MeshInstance2D
	check(is_instance_valid(hair_mesh) and is_instance_valid(visible_hair_mesh) and is_instance_valid(iris_mesh) and is_instance_valid(skin_mesh), "native backend exposes visible hair, iris and skin drawables")
	check(bool(view.call("set_palette", "hair", "copper")) and bool(view.call("set_palette", "eyes", "sea")) and bool(view.call("set_palette", "skin", "peach")), "palette choices apply to GG instance")
	check(hair_mesh.self_modulate == Color("e2aa86") and visible_hair_mesh.self_modulate == Color("e2aa86") and iris_mesh.self_modulate == Color("a9d2bd") and skin_mesh.self_modulate == Color("ffe1d6"), "visible Live2D drawable nodes receive selected colors")
	for frame: int in range(10):
		await process_frame
	check(visible_hair_mesh.self_modulate == Color("e2aa86") and iris_mesh.self_modulate == Color("a9d2bd") and skin_mesh.self_modulate == Color("ffe1d6"), "visible drawable colors persist across native frames")
	var encoded: String = JSON.stringify(view.call("get_appearance"))
	var decoded: Variant = JSON.parse_string(encoded)
	check(APPEARANCE.validate_appearance(decoded), "appearance survives JSON round trip")
	var second: Node2D = VIEW.new()
	root.add_child(second)
	check(bool(second.call("load_gg")), "second GG instance loads")
	check(is_zero_approx(float((second.call("get_actor") as Node2D).call("get_parameter_value", "ParamAssSize"))), "GG instances do not share shape state")
	var second_meshes: Dictionary = (second.call("get_actor") as Node2D).call("get_drawable_meshes")
	check((second_meshes.get("ModdableHairFront") as MeshInstance2D).self_modulate == Color.WHITE, "GG instances do not share drawable tint")
	check(bool(second.call("apply_appearance", decoded)) and (second.call("get_appearance") as Dictionary) == APPEARANCE.normalize_appearance(decoded), "JSON appearance restores on a fresh native GG instance")
	check((second_meshes.get("H0_Front_Bang") as MeshInstance2D).self_modulate == Color("e2aa86"), "restored hair tint reaches visible drawable")
	var randomized: Dictionary = view.call("randomize_appearance", 123456)
	check(APPEARANCE.validate_appearance(randomized), "randomize uses only valid controls and outfits")
	check((view.call("randomize_appearance", 123456) as Dictionary) == randomized, "randomize is seeded and deterministic")
	check((view.call("reset_appearance") as Dictionary) == default_state, "reset restores clothed defaults")
	check(is_equal_approx(float(actor.call("get_parameter_value", "ParamHoodieEnabled")), 1.0), "reset reapplies native wardrobe")
	second.queue_free()
	_finish(view)


func _finish(view: Node2D) -> void:
	view.queue_free()
	await process_frame
	print("PROTAGONIST_LIVE2D_RESULT ", JSON.stringify({"passed": passed, "failed": failed, "failures": failures}))
	quit(1 if failed > 0 else 0)
