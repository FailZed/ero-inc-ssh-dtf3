extends Node2D
## Isolated, clothed GG instance of the retained interaction_model study rig.
## Only actual permanent Cubism morphs and complete everyday outfits are saved.

signal appearance_changed(appearance: Dictionary)
signal load_failed(message: String)

const ACTOR_SCRIPT = preload("res://assets/characters/mdrg_study/runtime/live2d_actor.gd")
const APPEARANCE = preload("res://scripts/characters/protagonist_appearance.gd")
const DESCRIPTOR_PATH := "res://assets/characters/protagonist_gg/gg.json"
const PROFILE_PATH := "res://data/characters/protagonist_live2d.json"
const WARDROBE_SWITCHES: Array[String] = [
	"ParamShirtEnabled", "ParamSkirtEnabled", "ParamHoodieEnabled",
	"ParamPantsEnabled", "ParamDress2Enabled"
]
const SAFE_BASELINE: Dictionary = {
	"ParamBraEnabled": 1.0, "ParamPantiesEnabled": 1.0,
	"ParamShoeLOn": 1.0, "ParamShoeROn": 1.0,
	"ParamSkirtUp": 0.0, "ParamMouthOpen": 0.0,
	"ParamHeart": 0.0, "ParamSaliva": 0.0
}

var last_error: String = ""
var fully_loaded: bool = false
var _actor: Node2D
var _profile: Dictionary = {}
var _shape: Dictionary = {}
var _outfit: String = ""
var _palette: Dictionary = {}
var _frame_size: Vector2 = Vector2.ZERO
var _frame_mode: String = "body"
var _frame_zoom: float = 1.0
var _frame_pan: Vector2 = Vector2.ZERO


func load_gg() -> bool:
	last_error = ""
	fully_loaded = false
	var descriptor: Dictionary = _read_object(DESCRIPTOR_PATH)
	var profile: Dictionary = _read_object(PROFILE_PATH)
	if descriptor.is_empty() or profile.is_empty():
		return _load_fail(last_error)
	if str(descriptor.get("id", "")) != "gg" or str(profile.get("model_id", "")) != "gg":
		return _load_fail("GG descriptor and appearance profile must identify gg.")
	if not _validate_profile(profile):
		return _load_fail(last_error)
	_profile = profile
	if _actor == null:
		_actor = ACTOR_SCRIPT.new() as Node2D
		_actor.name = "GG_Cubism"
		add_child(_actor)
	if not bool(_actor.call("load_model", descriptor)):
		return _load_fail(str(_actor.get("last_error")))
	_shape = _default_shape()
	_outfit = str(_profile.get("default_outfit", ""))
	_palette = (APPEARANCE.normalize_appearance({}).get("palette", {}) as Dictionary).duplicate(true)
	if not _apply_state():
		return _load_fail(last_error)
	if _frame_size != Vector2.ZERO:
		_apply_framing()
	fully_loaded = true
	appearance_changed.emit(get_appearance())
	return true


func is_model_loaded() -> bool:
	return is_instance_valid(_actor) and bool(_actor.call("is_model_loaded"))


func get_actor() -> Node2D:
	return _actor


func get_controls() -> Dictionary:
	return _profile.duplicate(true)


func get_appearance() -> Dictionary:
	return APPEARANCE.normalize_appearance({"shape": _shape, "outfit": _outfit, "palette": _palette})


func apply_appearance(appearance: Dictionary) -> bool:
	if not is_model_loaded():
		return _fail("Load GG before applying appearance.")
	var schema: Variant = appearance.get("schema", 1)
	var model_id: Variant = appearance.get("model_id", "gg")
	if typeof(schema) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(schema)) or float(schema) != 1.0 or typeof(model_id) != TYPE_STRING or model_id != "gg":
		return _fail("Unsupported GG appearance schema or model.")
	var incoming_shape: Variant = appearance.get("shape", {})
	if not incoming_shape is Dictionary:
		return _fail("GG shape must be a dictionary.")
	var proposed: Dictionary = _default_shape()
	for identifier: String in incoming_shape:
		if not proposed.has(identifier):
			return _fail("Unsupported GG shape parameter: " + identifier)
		if typeof(incoming_shape[identifier]) not in [TYPE_INT, TYPE_FLOAT]:
			return _fail("Non-numeric GG shape parameter: " + identifier)
		var numeric: float = float(incoming_shape[identifier])
		if not is_finite(numeric):
			return _fail("Non-finite GG shape parameter: " + identifier)
		var spec: Dictionary = _control(identifier)
		proposed[identifier] = clampf(numeric, float(spec["minimum"]), float(spec["maximum"]))
	var selected: String = str(appearance.get("outfit", _profile.get("default_outfit", "")))
	if _outfit_spec(selected).is_empty():
		return _fail("Unsupported GG outfit: " + selected)
	var incoming_palette: Variant = appearance.get("palette", {})
	if not incoming_palette is Dictionary:
		return _fail("GG palette must be a dictionary.")
	var proposed_palette: Dictionary = (APPEARANCE.normalize_appearance({}).get("palette", {}) as Dictionary).duplicate(true)
	for group_id: String in incoming_palette:
		if not proposed_palette.has(group_id) or _palette_option(group_id, str(incoming_palette[group_id])).is_empty():
			return _fail("Unsupported GG palette option: " + group_id)
		proposed_palette[group_id] = str(incoming_palette[group_id])
	var previous_shape: Dictionary = _shape.duplicate(true)
	var previous_outfit: String = _outfit
	var previous_palette: Dictionary = _palette.duplicate(true)
	_shape = proposed
	_outfit = selected
	_palette = proposed_palette
	if not _apply_state():
		_shape = previous_shape
		_outfit = previous_outfit
		_palette = previous_palette
		_apply_state()
		return false
	appearance_changed.emit(get_appearance())
	return true


func set_shape(identifier: String, value: float) -> bool:
	var update: Dictionary = get_appearance()
	update["shape"][identifier] = value
	return apply_appearance(update)


func set_outfit(identifier: String) -> bool:
	var update: Dictionary = get_appearance()
	update["outfit"] = identifier
	return apply_appearance(update)


func set_palette(group_id: String, option_id: String) -> bool:
	var update: Dictionary = get_appearance()
	update["palette"][group_id] = option_id
	return apply_appearance(update)


func reset_appearance() -> Dictionary:
	apply_appearance(APPEARANCE.normalize_appearance({}))
	return get_appearance()


func randomize_appearance(seed_value: int) -> Dictionary:
	if not is_model_loaded():
		return get_appearance()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var update: Dictionary = {"schema": 1, "model_id": "gg", "shape": {}, "outfit": ""}
	for group: Variant in _profile.get("groups", []):
		for spec: Variant in group.get("controls", []):
			var minimum: float = float(spec["minimum"])
			var maximum: float = float(spec["maximum"])
			var step: float = float(spec.get("step", 0.05))
			var steps: int = roundi((maximum - minimum) / step)
			update["shape"][str(spec["id"])] = minimum + float(rng.randi_range(0, steps)) * step
	var outfits: Array = _profile.get("outfits", [])
	update["outfit"] = str(outfits[rng.randi_range(0, outfits.size() - 1)]["id"])
	var palette: Dictionary = {}
	for group: Variant in _profile.get("palette_groups", []):
		var options: Array = group.get("options", [])
		palette[str(group["id"])] = str(options[rng.randi_range(0, options.size() - 1)]["id"])
	update["palette"] = palette
	apply_appearance(update)
	return get_appearance()


func fit_model(size: Vector2) -> void:
	set_framing("body", size)


func set_framing(mode: String, size: Vector2, zoom: float = 1.0,
		pan: Vector2 = Vector2.ZERO, head_tilt: float = 0.0) -> void:
	_frame_mode = "face" if mode == "face" else "body"
	_frame_size = size
	_frame_zoom = clampf(zoom, 0.5, 3.0)
	_frame_pan = pan
	_apply_framing()
	if is_model_loaded():
		_actor.call("set_parameter", "ParamHeadZ", clampf(head_tilt, -1.0, 1.0))


func _apply_framing() -> void:
	if not is_model_loaded() or _frame_size.x <= 0.0 or _frame_size.y <= 0.0:
		return
	_actor.call("fit_model", _frame_size)
	# Audited retained source canvas is 4000 px; the highest hair vertex is -1781.
	# Keep that top in the glass on both square and narrow mirrors.
	var base_zoom: float = 3.5 if _frame_mode == "face" else (0.85 if _frame_size.y < 500.0 else 1.0)
	_actor.scale = Vector2.ONE * (base_zoom * _frame_zoom)
	var vertical_offset: float = _frame_size.y * 0.02 if _frame_mode == "body" and _frame_size.y < 500.0 else 0.0
	if _frame_mode == "face":
		var source_fit: float = minf(_frame_size.x / 4000.0, _frame_size.y / 4000.0) * 0.9
		vertical_offset = maxf(_frame_size.y * 0.72, 1782.0 * source_fit * base_zoom * _frame_zoom - _frame_size.y * 0.45)
	_actor.position = _frame_size * 0.5 + _frame_pan + Vector2(0.0, vertical_offset)


func _apply_state() -> bool:
	if not is_model_loaded():
		return _fail("GG native model is not loaded.")
	var success: bool = true
	for identifier: String in SAFE_BASELINE:
		success = bool(_actor.call("set_parameter", identifier, float(SAFE_BASELINE[identifier]))) and success
	var outfit_spec: Dictionary = _outfit_spec(_outfit)
	for identifier: String in WARDROBE_SWITCHES:
		success = bool(_actor.call("set_parameter", identifier, float(outfit_spec.get("parameters", {}).get(identifier, 0.0)))) and success
	for identifier: String in _shape:
		success = bool(_actor.call("set_parameter", identifier, float(_shape[identifier]))) and success
	if not success:
		return _fail("GG rig rejected a configured appearance parameter.")
	return _apply_palette()


func _apply_palette() -> bool:
	var meshes: Dictionary = _actor.call("get_drawable_meshes")
	for group: Variant in _profile.get("palette_groups", []):
		var group_id: String = str(group["id"])
		var option: Dictionary = _palette_option(group_id, str(_palette.get(group_id, "")))
		if option.is_empty():
			return _fail("GG palette option is missing: " + group_id)
		var tint: Color = Color(str(option["color"]))
		var matching_nodes: int = 0
		for identifier: String in meshes:
			var node: MeshInstance2D = meshes[identifier] as MeshInstance2D
			if not is_instance_valid(node):
				continue
			for pattern: Variant in group.get("meshes", []):
				if identifier.to_lower().match(str(pattern).to_lower()):
					node.self_modulate = tint
					matching_nodes += 1
					break
		if matching_nodes == 0:
			return _fail("GG native backend exposes no drawable nodes for palette: " + group_id)
	return true


func _default_shape() -> Dictionary:
	var result: Dictionary = {}
	for group: Variant in _profile.get("groups", []):
		for spec: Variant in group.get("controls", []):
			result[str(spec["id"])] = float(spec["default"])
	return result


func _control(identifier: String) -> Dictionary:
	for group: Variant in _profile.get("groups", []):
		for spec: Variant in group.get("controls", []):
			if str(spec.get("id", "")) == identifier:
				return spec
	return {}


func _outfit_spec(identifier: String) -> Dictionary:
	for spec: Variant in _profile.get("outfits", []):
		if str(spec.get("id", "")) == identifier:
			return spec
	return {}


func _palette_option(group_id: String, option_id: String) -> Dictionary:
	for group: Variant in _profile.get("palette_groups", []):
		if str(group.get("id", "")) == group_id:
			for option: Variant in group.get("options", []):
				if str(option.get("id", "")) == option_id:
					return option
	return {}


func _validate_profile(profile: Dictionary) -> bool:
	if not profile.get("groups", null) is Array or not profile.get("outfits", null) is Array:
		return _fail("GG profile is missing controls or outfits.")
	if (profile["outfits"] as Array).is_empty():
		return _fail("GG profile has no safe outfit.")
	var seen: Dictionary = {}
	for group: Variant in profile["groups"]:
		if not group is Dictionary or not group.get("controls", null) is Array:
			return _fail("Malformed GG control group.")
		for spec: Variant in group["controls"]:
			if not spec is Dictionary:
				return _fail("Malformed GG shape control.")
			var identifier: String = str(spec.get("id", ""))
			if identifier.is_empty() or seen.has(identifier) or float(spec.get("minimum", 0.0)) >= float(spec.get("maximum", 0.0)):
				return _fail("Invalid GG shape control: " + identifier)
			seen[identifier] = true
	for outfit: Variant in profile["outfits"]:
		if not outfit is Dictionary or not outfit.get("parameters", null) is Dictionary:
			return _fail("Malformed GG outfit.")
		var switches: Dictionary = outfit["parameters"]
		var top: bool = float(switches.get("ParamShirtEnabled", 0.0)) > 0.5 or float(switches.get("ParamHoodieEnabled", 0.0)) > 0.5 or float(switches.get("ParamDress2Enabled", 0.0)) > 0.5
		var bottom: bool = float(switches.get("ParamSkirtEnabled", 0.0)) > 0.5 or float(switches.get("ParamPantsEnabled", 0.0)) > 0.5 or float(switches.get("ParamDress2Enabled", 0.0)) > 0.5
		if not top or not bottom:
			return _fail("GG outfit must cover upper and lower body.")
	if not profile.get("palette_groups", null) is Array:
		return _fail("GG profile is missing palette groups.")
	for group: Variant in profile["palette_groups"]:
		if not group is Dictionary or not group.get("meshes", null) is Array or not group.get("options", null) is Array or (group["options"] as Array).is_empty():
			return _fail("Malformed GG palette group.")
	return true


func _read_object(pathname: String) -> Dictionary:
	if not FileAccess.file_exists(pathname):
		_fail("Missing GG file: " + pathname)
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(pathname))
	if not value is Dictionary:
		_fail("Invalid GG JSON: " + pathname)
		return {}
	return value


func _fail(message: String) -> bool:
	last_error = message
	push_warning(message)
	return false


func _load_fail(message: String) -> bool:
	_fail(message)
	load_failed.emit(message)
	return false
