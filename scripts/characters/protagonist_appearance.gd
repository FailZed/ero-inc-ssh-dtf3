extends RefCounted
## Save-safe GG appearance schema. This file has no GUI or native Cubism dependency.

const PROFILE_PATH := "res://data/characters/protagonist_live2d.json"


static func normalize_appearance(value: Variant) -> Dictionary:
	var profile: Dictionary = _profile()
	if profile.is_empty():
		return {}
	var source: Dictionary = value if value is Dictionary else {}
	var shape: Dictionary = {}
	var incoming: Dictionary = source.get("shape", {}) if source.get("shape", {}) is Dictionary else {}
	for group: Variant in profile.get("groups", []):
		for spec: Variant in group.get("controls", []):
			var identifier: String = str(spec["id"])
			var numeric: float = float(spec["default"])
			if typeof(incoming.get(identifier, null)) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(incoming[identifier])):
				numeric = float(incoming[identifier])
			shape[identifier] = clampf(numeric, float(spec["minimum"]), float(spec["maximum"]))
	var outfit: String = str(source.get("outfit", profile.get("default_outfit", "")))
	var allowed: bool = false
	for option: Variant in profile.get("outfits", []):
		if str(option.get("id", "")) == outfit:
			allowed = true
			break
	if not allowed:
		outfit = str(profile.get("default_outfit", ""))
	var palette: Dictionary = {}
	var incoming_palette: Dictionary = source.get("palette", {}) if source.get("palette", {}) is Dictionary else {}
	for group: Variant in profile.get("palette_groups", []):
		var group_id: String = str(group["id"])
		var selection: String = str(incoming_palette.get(group_id, group.get("default", "original")))
		var matched: bool = false
		for option: Variant in group.get("options", []):
			if str(option.get("id", "")) == selection:
				matched = true
				break
		palette[group_id] = selection if matched else str(group.get("default", "original"))
	return {"schema": 1, "model_id": "gg", "shape": shape, "outfit": outfit, "palette": palette}


static func validate_appearance(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if value.size() != 5:
		return false
	for key: Variant in value:
		if key not in ["schema", "model_id", "shape", "outfit", "palette"]:
			return false
	var profile: Dictionary = _profile()
	var schema: Variant = value.get("schema", null)
	if profile.is_empty() or typeof(schema) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(schema)) or float(schema) != 1.0 or typeof(value.get("model_id", null)) != TYPE_STRING or value["model_id"] != "gg":
		return false
	var incoming: Variant = value.get("shape", null)
	if not incoming is Dictionary:
		return false
	var controls: Dictionary = {}
	for group: Variant in profile.get("groups", []):
		for spec: Variant in group.get("controls", []):
			controls[str(spec["id"])] = spec
	if incoming.size() != controls.size():
		return false
	for identifier: String in incoming:
		if not controls.has(identifier) or typeof(incoming[identifier]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		var numeric: float = float(incoming[identifier])
		var spec: Dictionary = controls[identifier]
		if not is_finite(numeric) or numeric < float(spec["minimum"]) or numeric > float(spec["maximum"]):
			return false
	var palette: Variant = value.get("palette", null)
	if not palette is Dictionary or palette.size() != (profile.get("palette_groups", []) as Array).size():
		return false
	for group: Variant in profile.get("palette_groups", []):
		var group_id: String = str(group["id"])
		if not palette.has(group_id):
			return false
		var matched: bool = false
		for option: Variant in group.get("options", []):
			if str(option.get("id", "")) == str(palette[group_id]):
				matched = true
				break
		if not matched:
			return false
	for option: Variant in profile.get("outfits", []):
		if str(option.get("id", "")) == str(value.get("outfit", "")):
			return true
	return false


static func _profile() -> Dictionary:
	if not FileAccess.file_exists(PROFILE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	return parsed if parsed is Dictionary else {}
