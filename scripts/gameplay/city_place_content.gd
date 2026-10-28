extends RefCounted
## Read-only city object descriptions. The existing simulation owns all commands.
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const PATH := "res://data/world/city-place-content.json"
const TEXT_FIELDS := ["title_key", "description_key", "inspection_key", "text_key", "label_key", "success_key", "decline_key", "repeat_key", "daily_repeat_key", "open_key", "closed_key"]

static func read_file(path: String = PATH) -> Dictionary:
	if not FileAccess.file_exists(path): return Rules.fail("city_content_missing")
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not decoded is Dictionary: return Rules.fail("city_content_invalid_json")
	return Rules.ok({"content": decoded})

static func catalogue_actions(content: Dictionary) -> Dictionary:
	var patch: Dictionary = content.get("catalogue_patch", {})
	var actions: Dictionary = patch.get("actions", {})
	return actions.duplicate(true)

static func authority_keys(content: Dictionary, location_id: String) -> Array[String]:
	var result: Array[String] = []
	var scene: Dictionary = content.get("scenes", {}).get(location_id, {})
	for object in scene.get("objects", {}).values():
		for option in object.get("choices", {}).values():
			var key := str(option.get("authority_key", ""))
			if not key.is_empty() and not key in result: result.append(key)
		var service_key := str(object.get("service_availability", {}).get("authority_key", ""))
		if not service_key.is_empty() and not service_key in result: result.append(service_key)
	return result

static func validate(content: Dictionary, graph: Dictionary, catalog: Dictionary) -> String:
	if content.get("schema") != 1: return "city_content_schema"
	if not content.get("scenes") is Dictionary or not content.get("small_scenes") is Dictionary: return "city_content_scenes"
	if not content.get("strings") is Dictionary or not content.strings.get("ru") is Dictionary: return "city_content_strings"
	if not content.get("catalogue_patch") is Dictionary or not content.catalogue_patch.get("actions") is Dictionary: return "city_content_action_patch"
	if not graph.get("locations") is Dictionary: return "city_graph_locations"
	var text_error := _text_error(content, content.strings.ru)
	if not text_error.is_empty(): return text_error
	var reaction: Variant = content.get("reaction")
	if not reaction is Dictionary or reaction.get("flag_id") != "city_cafe_notice_sheltered": return "city_content_reaction"
	var actions := catalogue_actions(content)
	if actions.size() != 2 or not actions.has("wp_last_crate") or not actions.has("wp_rain_margin"): return "city_content_actions"
	var flag_effects := 0
	for action_id in actions:
		var action: Variant = actions[action_id]
		if not action is Dictionary: return "city_content_action_shape"
		if not _integer(action.get("minutes"), 1, 30) or action.minutes != 2: return "city_content_action_minutes"
		if not action.get("locations") is Array or action.locations.size() != 1: return "city_content_action_locations"
		if not graph.locations.has(str(action.locations[0])): return "city_content_action_location_unknown"
		if not action.get("costs") is Dictionary or not action.costs.is_empty(): return "city_content_action_costs"
		if not action.get("requirements") is Dictionary: return "city_content_action_requirements"
		if action.get("daily_limit") != 1 or not action.get("effects") is Array: return "city_content_action_limits"
		var hours: Variant = action.get("hours")
		if not hours is Array or hours.size() != 2: return "city_content_action_hours"
		if not _integer(hours[0], 0, 1439) or not _integer(hours[1], 0, 1439): return "city_content_action_hours"
		for effect in action.effects:
			if not effect is Dictionary or effect.get("kind") != "flag" or effect.get("id") != reaction.flag_id or effect.get("value") != true: return "city_content_action_effect"
			if action_id != reaction.action_id: return "city_content_reaction_owner"
			flag_effects += 1
		if catalog.get("actions", {}).has(action_id) and catalog.actions[action_id] != action: return "city_content_action_collision:" + str(action_id)
	if flag_effects != 1: return "city_content_reaction_count"
	var rain_conditions: Variant = actions.wp_rain_margin.get("requirements", {}).get("all")
	if not rain_conditions is Array: return "city_content_reaction_guard"
	if not {"not":{"path":"world.flags.city_cafe_notice_sheltered","value":true}} in rain_conditions: return "city_content_reaction_guard"
	for location_id in content.scenes:
		if not graph.locations.has(str(location_id)): return "city_content_location_unknown:" + str(location_id)
		if not graph.locations[location_id] is Dictionary: return "city_content_graph_location_shape"
		if graph.locations[location_id].get("kind") != "public_exterior": return "city_content_public_scene_required"
		var scene: Variant = content.scenes[location_id]
		if not scene is Dictionary or scene.get("access") != "public_exterior" or not scene.get("objects") is Dictionary: return "city_content_scene_shape"
		for object_id in scene.objects:
			var object: Variant = scene.objects[object_id]
			if not object is Dictionary or not object.get("choices") is Dictionary: return "city_content_object_shape"
			var anchor: Variant = object.get("anchor_uv")
			if not anchor is Array or anchor.size() != 2: return "city_content_anchor"
			for coordinate in anchor:
				if not _number(coordinate) or float(coordinate) < 0.0 or float(coordinate) > 1.0: return "city_content_anchor"
			if not object.get("inspection_variants", []) is Array: return "city_content_inspection_variants"
			for variant in object.get("inspection_variants", []):
				if not variant is Dictionary or not variant.get("requirements") is Dictionary or not variant.get("text_key") is String: return "city_content_inspection_variant"
			for choice_id in object.choices:
				var choice_error := _choice_error(object.choices[choice_id], graph, catalog, actions)
				if not choice_error.is_empty(): return choice_error
	for small_id in content.small_scenes:
		var small: Variant = content.small_scenes[small_id]
		if not small is Dictionary or not actions.has(str(small_id)): return "city_content_small_scene"
		var object := _object(content, str(small.get("location_id", "")), str(small.get("object_id", "")))
		var choice: Dictionary = object.get("choices", {}).get(str(small.get("choice_id", "")), {})
		if choice.get("command", {}).get("args", {}).get("id") != small_id: return "city_content_small_scene_choice"
	var reaction_object := _object(content, str(reaction.get("location_id", "")), str(reaction.get("object_id", "")))
	if reaction_object.is_empty(): return "city_content_reaction_object"
	return ""

static func describe(content: Dictionary, location_id: String, context: Dictionary, locale: String = "ru") -> Dictionary:
	var error := _context_error(content, location_id, context, locale)
	if not error.is_empty(): return Rules.fail(error)
	var source: Dictionary = content.scenes[location_id]
	var objects: Array[Dictionary] = []
	for object_id in source.objects:
		var object: Dictionary = source.objects[object_id]
		objects.append({"id":str(object_id), "title":text(content, str(object.title_key), locale), "anchor_uv":object.anchor_uv.duplicate(), "inspection_minutes":0})
	return Rules.ok({"location_id":location_id, "title":text(content, str(source.title_key), locale), "description":text(content, str(source.description_key), locale), "objects":objects})

static func inspect(content: Dictionary, location_id: String, object_id: String, context: Dictionary, locale: String = "ru") -> Dictionary:
	var error := _context_error(content, location_id, context, locale)
	if not error.is_empty(): return Rules.fail(error)
	var object := _object(content, location_id, object_id)
	if object.is_empty(): return Rules.fail("city_content_object_unknown")
	var inspection_key := str(object.inspection_key)
	var repeat_action := str(object.get("daily_repeat_action_id", ""))
	if not repeat_action.is_empty():
		var daily_key := "%s:%d" % [repeat_action, int(Rules.read(context.state, "clock.day_index", 0))]
		if int(Rules.read(context.state, "counters", {}).get(daily_key, 0)) > 0:
			inspection_key = str(object.get("daily_repeat_key", inspection_key))
	for variant in object.get("inspection_variants", []):
		if Rules.check(context.state, variant.get("requirements", {})):
			inspection_key = str(variant.text_key)
			break
	var choices: Array[Dictionary] = []
	for choice_id in object.choices:
		choices.append(_describe_choice(content, str(choice_id), object.choices[choice_id], context, locale))
	return Rules.ok({"location_id":location_id, "object_id":object_id, "title":text(content, str(object.title_key), locale), "text":text(content, inspection_key, locale), "text_key":inspection_key, "inspection_minutes":0, "choices":choices, "service_status":_service_status(content, object, context, locale)})

static func choice(content: Dictionary, location_id: String, object_id: String, choice_id: String, context: Dictionary, locale: String = "ru") -> Dictionary:
	var inspection := inspect(content, location_id, object_id, context, locale)
	if not inspection.ok: return inspection
	for candidate in inspection.data.choices:
		if candidate.id == choice_id:
			if not candidate.available: return Rules.fail(str(candidate.error))
			return Rules.ok(candidate.duplicate(true))
	return Rules.fail("city_content_choice_unknown")

static func text(content: Dictionary, key: String, locale: String = "ru") -> String:
	return str(content.get("strings", {}).get(locale, {}).get(key, ""))

static func result_text(content: Dictionary, action_id: String, locale: String = "ru") -> String:
	var small: Dictionary = content.get("small_scenes", {}).get(action_id, {})
	return text(content, str(small.get("success_key", "")), locale)

static func _describe_choice(content: Dictionary, choice_id: String, source: Dictionary, context: Dictionary, locale: String) -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result.id = choice_id
	result.label = text(content, str(source.label_key), locale)
	result.available = false
	result.error = "city_content_authority_missing"
	result.minutes = 0
	if source.time_source == "catalogue_action":
		result.minutes = int(catalogue_actions(content).get(str(source.command.args.id), {}).get("minutes", 0))
	var authority: Variant = context.get("availability", {}).get(str(source.authority_key))
	if not authority is Dictionary or not authority.get("ok") is bool: return result
	if not authority.ok:
		result.error = str(authority.get("error", "city_content_unavailable"))
		if result.error == "action_requirements" and source.get("command", {}).get("args", {}).get("id") == "wp_rain_margin":
			if Rules.read(context.state, "world.flags.city_cafe_notice_sheltered") == true: result.error = "city_notice_already_sheltered"
			elif Rules.read(context.state, "world.weather") != "rain": result.error = "city_rain_required"
		return result
	if source.time_source != "none":
		if not authority.get("data") is Dictionary:
			result.error = "city_content_duration_missing"
			return result
		var minutes: Variant = authority.data.get("minutes")
		if not _integer(minutes, 0, 43200):
			result.error = "city_content_duration_missing"
			return result
		result.minutes = int(minutes)
	if source.time_source == "catalogue_action":
		var definition: Dictionary = catalogue_actions(content).get(str(source.command.args.id), {})
		if definition.is_empty() or not Rules.check(context.state, definition.get("requirements", {})):
			result.error = "action_requirements"
			return result
		if result.minutes != int(definition.minutes):
			result.error = "city_content_duration_mismatch"
			return result
	result.available = true
	result.error = ""
	return result

static func _service_status(content: Dictionary, object: Dictionary, context: Dictionary, locale: String) -> Dictionary:
	var service: Dictionary = object.get("service_availability", {})
	if service.is_empty(): return {}
	var authority: Variant = context.get("availability", {}).get(str(service.authority_key))
	var available: bool = authority is Dictionary and authority.get("ok") == true
	var error := "city_content_authority_missing"
	if authority is Dictionary: error = str(authority.get("error", ""))
	return {"title":text(content, str(service.title_key), locale), "available":available, "text":text(content, str(service.open_key if available else service.closed_key), locale), "error":error}

static func _context_error(content: Dictionary, location_id: String, context: Dictionary, locale: String) -> String:
	if not content.get("scenes", {}).has(location_id): return "city_content_scene_unknown"
	if not content.get("strings", {}).has(locale): return "city_content_locale_missing"
	if context.get("phase") != "free_roam": return "story_locked"
	if not context.get("state") is Dictionary: return "city_content_state_missing"
	if Rules.read(context.state, "world.location") != location_id: return "wrong_location"
	if not context.get("access") is Dictionary: return "city_content_access_missing"
	if context.has("availability") and not context.availability is Dictionary: return "city_content_authority_invalid"
	var access: Variant = context.get("access", {}).get(location_id)
	if not access is Dictionary or not access.get("ok") is bool: return "city_content_access_missing"
	if not access.ok: return str(access.get("error", "city_content_access_denied"))
	return ""

static func _object(content: Dictionary, location_id: String, object_id: String) -> Dictionary:
	var scene: Dictionary = content.get("scenes", {}).get(location_id, {})
	return scene.get("objects", {}).get(object_id, {})

static func _choice_error(choice_data: Variant, graph: Dictionary, catalog: Dictionary, actions: Dictionary) -> String:
	if not choice_data is Dictionary: return "city_content_choice_shape"
	var item: Dictionary = choice_data
	if not item.get("authority_key") is String or str(item.authority_key).is_empty(): return "city_content_choice_authority"
	if not item.get("time_source") is String: return "city_content_choice_timing"
	if not item.get("confirmation") is bool: return "city_content_choice_confirmation"
	if item.get("kind") == "catalogue":
		if item.get("group") != "shops" or not catalog.get("shops", {}).has(str(item.get("id", ""))): return "city_content_shop_unknown"
		return "" if item.time_source == "none" and not item.confirmation else "city_content_shop_timing"
	if item.get("kind") != "command" or not item.get("command") is Dictionary or not item.confirmation: return "city_content_command_shape"
	var command: Dictionary = item.command
	if not command.get("args") is Dictionary: return "city_content_command_args"
	var id := str(command.args.get("id", ""))
	if command.get("module") == "world" and command.get("operation") == "journey":
		if not graph.locations.has(id) or item.time_source != "availability": return "city_content_destination_unknown"
		return ""
	if command.get("module") == "actions" and command.get("operation") == "perform":
		if not actions.has(id) or item.time_source != "catalogue_action": return "city_content_action_unknown"
		return ""
	return "city_content_command_not_allowed"

static func _text_error(value: Variant, strings: Dictionary) -> String:
	if value is Dictionary:
		for key in value:
			if key in TEXT_FIELDS:
				if not value[key] is String or not strings.has(value[key]) or not strings[value[key]] is String or str(strings[value[key]]).is_empty(): return "city_content_text_missing:" + str(value[key])
			else:
				var error := _text_error(value[key], strings)
				if not error.is_empty(): return error
	elif value is Array:
		for entry in value:
			var error := _text_error(entry, strings)
			if not error.is_empty(): return error
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high
