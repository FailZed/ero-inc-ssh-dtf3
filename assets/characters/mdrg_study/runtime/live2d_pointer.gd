extends RefCounted
## Model-aware Live2D interaction controller for both MeshInstance2D and
## gd_cubism 0.9+ ArrayMesh drawables. Original profile fields still work.

const RIG_DEBUG_OUTFIT := "Без одежды (проверка рига)"
const DEFAULT_CLOTHING_WORDS := [
	"shirt", "skirt", "bra", "pant", "shoe", "hoodie", "dress", "coat",
	"jacket", "sock", "boot", "glove", "underwear", "outfit", "cloth",
	"bikini", "lingerie", "apron", "uniform", "sweater", "vest", "hat",
	"cloak", "corset", "suit", "robe", "stocking", "sleeve", "topwear"
]
const CLOTHING_SWITCH_ENDINGS := ["enabled", "enable", "visible", "visibility", "show", "on", "opacity"]

var actor: Node2D
var model_id: String = ""
var _source_model_id: String = ""
var profile: Dictionary = {}
var zones: Array[Dictionary] = []
var held: Dictionary = {}
var unsupported_parameters: Array[String] = []
var _meshes: Dictionary = {}
var _specs: Dictionary = {}
var _part_specs: Dictionary = {}
var _saved: Dictionary = {}
var _initial_clothing: Dictionary = {}
var _initial_parts: Dictionary = {}
var _mesh_owner: Node2D
var _anchor := Vector2.ZERO
var _last := Vector2.ZERO


func configure(target: Node2D, bindings: Dictionary, target_model_id: String = "") -> void:
	release()
	actor = target
	model_id = target_model_id if not target_model_id.is_empty() else _detect_model_id(target)
	var source_model_id: String = str(target.call("get_source_model_id")) if is_instance_valid(target) and target.has_method("get_source_model_id") else ""
	_source_model_id = source_model_id
	var source: Variant = bindings.get("bindings", bindings)
	var common: Dictionary = source if source is Dictionary else {}
	profile = _resolve_profile(common, model_id, source_model_id)
	zones.clear()
	_specs.clear()
	_part_specs.clear()
	_meshes.clear()
	_initial_clothing.clear()
	_initial_parts.clear()
	unsupported_parameters.clear()
	_mesh_owner = target
	if not is_instance_valid(target):
		return
	var native_model: Node = target.get_node_or_null("Cubism")
	if native_model is Node2D:
		_mesh_owner = native_model as Node2D
	if target.has_method("get_drawable_meshes"):
		var drawable_values: Variant = target.call("get_drawable_meshes")
		if drawable_values is Dictionary:
			# Never share this mutable map with the actor. Reconfiguring used to
			# clear the actor's own mesh registry via _meshes.clear().
			_meshes = drawable_values.duplicate()
	if target.has_method("get_parameter_descriptors"):
		var parameters: Variant = target.call("get_parameter_descriptors")
		if parameters is Array:
			for item: Variant in parameters:
				if item is Dictionary:
					var identifier: String = str(item.get("id", ""))
					if not identifier.is_empty():
						_specs[identifier] = item
	if target.has_method("get_part_descriptors"):
		var parts: Variant = target.call("get_part_descriptors")
		if parts is Array:
			for item: Variant in parts:
				if item is Dictionary:
					var identifier: String = str(item.get("id", ""))
					if not identifier.is_empty():
						_part_specs[identifier] = item
	for identifier: String in _specs:
		if _is_clothing_switch(identifier):
			_initial_clothing[identifier] = _get_current_value(identifier)
	for identifier: String in _part_specs:
		if _is_clothing_name(identifier):
			_initial_parts[identifier] = _get_part_value(identifier)
	var configured_zones: Variant = profile.get("zones", [])
	if configured_zones is Array:
		for item: Variant in configured_zones:
			if item is Dictionary and not bool(item.get("disabled", false)) and _zone_matches_model(item) and _zone_uses_known_parameters(item):
				zones.append(item)
	# Specific eyes, mouth, limb and native HitArea zones must win over the
	# large torso/arm rectangles present in the original five-zone profile.
	zones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0)))


func _detect_model_id(target: Node2D) -> String:
	if not is_instance_valid(target):
		return ""
	if target.has_method("get_model_id"):
		return str(target.call("get_model_id"))
	for item: Dictionary in target.get_property_list():
		if str(item.get("name", "")) == "model_id":
			return str(target.get("model_id"))
	return ""


func _resolve_profile(common: Dictionary, identifier: String, source_identifier: String = "") -> Dictionary:
	var resolved: Dictionary = common.duplicate(true)
	resolved.erase("models")
	var models: Variant = common.get("models", {})
	if models is Dictionary:
		for key: String in ["*", source_identifier, identifier]:
			if models.get(key) is Dictionary:
				resolved = _deep_merge(resolved, models[key])
	return resolved


func _deep_merge(base: Dictionary, changes: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key: Variant in changes:
		var value: Variant = changes[key]
		if key == "zones" and result.get(key) is Array and value is Array:
			result[key] = _merge_zones(result[key], value)
		elif result.get(key) is Dictionary and value is Dictionary:
			result[key] = _deep_merge(result[key], value)
		else:
			result[key] = value
	return result


func _merge_zones(base: Array, changes: Array) -> Array:
	var merged: Array = base.duplicate(true)
	for zone: Variant in changes:
		if not zone is Dictionary:
			continue
		var found := false
		for i in range(merged.size()):
			if merged[i] is Dictionary and str(merged[i].get("id", "")) == str(zone.get("id", "")):
				merged[i] = zone
				found = true
				break
		if not found:
			merged.append(zone)
	return merged


func _zone_matches_model(zone: Dictionary) -> bool:
	var identifiers: Variant = zone.get("model_ids", [])
	if identifiers is Array and not identifiers.is_empty():
		return identifiers.has(model_id) or identifiers.has(_source_model_id)
	return true


func _zone_uses_known_parameters(zone: Dictionary) -> bool:
	var patterns: Variant = zone.get("meshes", [])
	if not patterns is Array or patterns.is_empty():
		return false
	for field: String in ["x", "y", "move_x", "move_y"]:
		if _specs.has(str(zone.get(field, ""))):
			return true
	var presses: Variant = zone.get("press", {})
	if presses is Dictionary:
		for identifier: String in presses:
			if _specs.has(identifier):
				return true
	return false


func hit_test(global_point: Vector2) -> Dictionary:
	for zone: Dictionary in zones:
		for identifier: String in _meshes:
			var matches := false
			for pattern: Variant in zone.get("meshes", []):
				if identifier.match(str(pattern)):
					matches = true
					break
			if not matches:
				continue
			var item: Variant = _meshes[identifier]
			var mesh: Mesh
			var origin: Node2D = _mesh_owner
			if item is MeshInstance2D:
				var node: MeshInstance2D = item
				if not is_instance_valid(node) or node.mesh == null:
					continue
				if not identifier.begins_with("HitArea") and (not node.is_visible_in_tree() or node.modulate.a <= 0.001):
					continue
				mesh = node.mesh
				origin = node
			elif item is Mesh:
				mesh = item
			else:
				continue
			if not is_instance_valid(origin) or mesh == null or mesh.get_surface_count() == 0:
				continue
			var point: Vector2 = origin.to_local(global_point)
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size() - 2, 3):
				var a := Vector2(vertices[indices[i]].x, vertices[indices[i]].y)
				var b := Vector2(vertices[indices[i + 1]].x, vertices[indices[i + 1]].y)
				var c := Vector2(vertices[indices[i + 2]].x, vertices[indices[i + 2]].y)
				var area := (b - a).cross(c - a)
				if absf(area) < 0.000001:
					continue
				var u := (b - point).cross(c - point) / area
				var v := (c - point).cross(a - point) / area
				if u >= -0.00001 and v >= -0.00001 and u + v <= 1.00001:
					return zone
	return {}


func begin(global_point: Vector2) -> bool:
	release()
	held = hit_test(global_point)
	if held.is_empty():
		return false
	_anchor = global_point
	_last = global_point
	for field: String in ["x", "y", "move_x", "move_y"]:
		_remember(str(held.get(field, "")))
	var presses: Variant = held.get("press", {})
	if presses is Dictionary:
		for identifier: String in presses:
			_remember(identifier)
			if _saved.has(identifier):
				_set_parameter(identifier, float(presses[identifier]))
	return true


func _remember(identifier: String) -> void:
	if not _specs.has(identifier) or _saved.has(identifier):
		return
	var was_held: bool = bool(actor.call("is_parameter_held", identifier)) if actor.has_method("is_parameter_held") else false
	_saved[identifier] = {"value": _get_current_value(identifier), "hold": was_held}


func move(global_point: Vector2, extent: float) -> void:
	if held.is_empty():
		return
	var movement: Vector2 = (global_point - _anchor) / maxf(extent, 1.0) * 2.0
	var speed: Vector2 = (global_point - _last) / maxf(extent, 1.0) * 60.0
	for axis: String in ["x", "y"]:
		var identifier: String = str(held.get(axis, ""))
		if not _saved.has(identifier):
			continue
		var spec: Dictionary = _specs[identifier]
		var amount: float = movement.x if axis == "x" else -movement.y
		_set_parameter(identifier, float(_saved[identifier]["value"]) + amount * (float(spec.get("maximum", 1.0)) - float(spec.get("minimum", 0.0))))
		var motion_id: String = str(held.get("move_" + axis, ""))
		if _specs.has(motion_id):
			var motion_spec: Dictionary = _specs[motion_id]
			var motion_amount: float = clampf(speed.x if axis == "x" else -speed.y, -1.0, 1.0)
			var target: float = lerpf(float(motion_spec.get("default", 0.0)),
				float(motion_spec.get("maximum", 1.0) if motion_amount >= 0.0 else motion_spec.get("minimum", 0.0)), absf(motion_amount))
			_set_parameter(motion_id, target)
	_last = global_point


func release() -> void:
	if is_instance_valid(actor):
		for identifier: String in _saved:
			_set_parameter(identifier, float(_saved[identifier]["value"]))
			if not bool(_saved[identifier]["hold"]) and actor.has_method("release_parameter"):
				actor.call("release_parameter", identifier)
	_saved.clear()
	held.clear()


func _get_current_value(identifier: String) -> float:
	if is_instance_valid(actor) and actor.has_method("get_parameter_value"):
		return float(actor.call("get_parameter_value", identifier))
	return float(_specs.get(identifier, {}).get("value", 0.0))


func _get_part_value(identifier: String) -> float:
	if is_instance_valid(actor) and actor.has_method("get_part_value"):
		return float(actor.call("get_part_value", identifier))
	return float(_part_specs.get(identifier, {}).get("value", 1.0))


func _set_parameter(identifier: String, value: float) -> bool:
	if not is_instance_valid(actor) or not _specs.has(identifier) or not is_finite(value) or not actor.has_method("set_parameter"):
		return false
	var spec: Dictionary = _specs[identifier]
	var low: float = float(spec.get("minimum", -1.0))
	var high: float = float(spec.get("maximum", 1.0))
	var result: Variant = actor.call("set_parameter", identifier, clampf(value, minf(low, high), maxf(low, high)))
	return result != false


func set_known_parameter(identifier: String, value: float) -> bool:
	return _set_parameter(identifier, value)


func available_parameter_ids() -> Array:
	var ids: Array = _specs.keys()
	ids.sort()
	return ids


func get_interaction_zones() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for zone: Dictionary in zones:
		result.append(zone.duplicate(true))
	return result


func get_effective_profile() -> Dictionary:
	return profile.duplicate(true)


func _apply_parameters(values: Dictionary) -> bool:
	var applied := false
	for identifier: String in values:
		if not _specs.has(identifier):
			if not unsupported_parameters.has(identifier):
				unsupported_parameters.append(identifier)
			continue
		var value: Variant = values[identifier]
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and _set_parameter(identifier, float(value)):
			applied = true
	return applied


func apply_preset(category: String, title: String) -> bool:
	if category == "outfits":
		return apply_outfit(title)
	var presets: Variant = profile.get(category, {})
	if not presets is Dictionary or not presets.get(title) is Dictionary:
		return false
	if (presets[title] as Dictionary).is_empty():
		if is_instance_valid(actor) and actor.has_method("reset_pose"):
			release()
			return actor.call("reset_pose") != false
		return false
	return _apply_parameters(presets[title])


func _is_clothing_name(identifier: String) -> bool:
	var lower: String = identifier.to_lower()
	var config: Variant = profile.get("rig_debug", {})
	var words: Variant = config.get("clothing_words", DEFAULT_CLOTHING_WORDS) if config is Dictionary else DEFAULT_CLOTHING_WORDS
	for word: Variant in words:
		if lower.contains(str(word).to_lower()):
			return true
	return false


func _is_clothing_switch(identifier: String) -> bool:
	if not _is_clothing_name(identifier):
		return false
	var lower: String = identifier.to_lower()
	for ending: String in CLOTHING_SWITCH_ENDINGS:
		if lower.ends_with(ending):
			return true
	return false


func can_test_without_clothes() -> bool:
	for identifier: String in _specs:
		if _is_clothing_switch(identifier):
			return true
	for identifier: String in _part_specs:
		if _is_clothing_name(identifier):
			return true
	var config: Variant = profile.get("rig_debug", {})
	if config is Dictionary:
		for identifier: String in config.get("disable_parameters", {}):
			if _specs.has(identifier):
				return true
		for identifier: String in config.get("disable_parts", {}):
			if _part_specs.has(identifier):
				return true
	return false


func _apply_parts(values: Dictionary) -> bool:
	if not is_instance_valid(actor) or not actor.has_method("set_part_opacity"):
		return false
	var applied := false
	for identifier: String in values:
		if _part_specs.has(identifier):
			var outcome: Variant = actor.call("set_part_opacity", identifier, clampf(float(values[identifier]), 0.0, 1.0))
			applied = (outcome != false) or applied
	return applied


func apply_outfit(title: String) -> bool:
	var outfits: Variant = profile.get("outfits", {})
	if not outfits is Dictionary or (not outfits.has(title) and title != RIG_DEBUG_OUTFIT):
		return false
	var values: Dictionary = _initial_clothing.duplicate(true)
	var initial: Variant = profile.get("initial", {})
	if initial is Dictionary:
		values.merge(initial, true)
	var selected: Variant = outfits.get(title, {})
	if selected is Dictionary:
		values.merge(selected, true)
	var part_values: Dictionary = _initial_parts.duplicate(true)
	if title == RIG_DEBUG_OUTFIT:
		var config: Variant = profile.get("rig_debug", {})
		var off_value: float = float(config.get("off_value", 0.0)) if config is Dictionary else 0.0
		for identifier: String in _specs:
			if _is_clothing_switch(identifier):
				values[identifier] = off_value
		for identifier: String in _part_specs:
			if _is_clothing_name(identifier):
				part_values[identifier] = 0.0
		if config is Dictionary:
			if config.get("disable_parameters") is Dictionary:
				values.merge(config["disable_parameters"], true)
			if config.get("disable_parts") is Dictionary:
				part_values.merge(config["disable_parts"], true)
		if not can_test_without_clothes():
			return false
	var parameters_applied: bool = _apply_parameters(values)
	var parts_applied: bool = _apply_parts(part_values)
	return parameters_applied or parts_applied
