extends SceneTree
## Save schema must work even in a project without the optional native addon.

const APPEARANCE = preload("res://scripts/characters/protagonist_appearance.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: Array[String] = []
	var state: Dictionary = APPEARANCE.normalize_appearance({})
	if not APPEARANCE.validate_appearance(state):
		failures.append("canonical default invalid")
	if state.get("model_id") != "gg" or state.get("outfit") != "hoodie_pants":
		failures.append("wrong canonical identity or wardrobe")
	var fractional: Dictionary = state.duplicate(true)
	fractional["schema"] = 1.5
	if APPEARANCE.validate_appearance(fractional):
		failures.append("schema 1.5 accepted")
	var extra: Dictionary = state.duplicate(true)
	extra["legacy"] = true
	if APPEARANCE.validate_appearance(extra):
		failures.append("extra field accepted")
	var unknown: Dictionary = state.duplicate(true)
	unknown["palette"]["hair"] = "missing"
	if APPEARANCE.validate_appearance(unknown):
		failures.append("unknown swatch accepted")
	var out_of_range: Dictionary = state.duplicate(true)
	out_of_range["shape"]["ParamAssSize"] = 1.5
	if APPEARANCE.validate_appearance(out_of_range):
		failures.append("out of range shape accepted")
	var decoded: Variant = JSON.parse_string(JSON.stringify(state))
	if not APPEARANCE.validate_appearance(decoded):
		failures.append("JSON round trip invalid")
	print("PROTAGONIST_APPEARANCE_RESULT ", JSON.stringify({"failed": failures.size(), "failures": failures, "native_available": ClassDB.class_exists("GDCubismUserModel")}))
	quit(1 if not failures.is_empty() else 0)
