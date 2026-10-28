extends RefCounted
## Data and actor-aware access queries only. No Simulation, pathfinder or world mutation.
## Single current-city source; no fallback to a prior city map exists here.
const PATH := "res://data/world/city-graph.json"
const SCHEMA := 1
const KINDS := ["public_exterior", "private_room", "private_residence", "service_interior"]
const POLICY_KINDS := ["public", "residence", "private_home", "service"]
const ROUTE_KINDS := ["walk", "entry", "private_entry", "interior"]


static func load_graph(path: String = PATH) -> Dictionary:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return {"ok": false, "error": "city_graph_unreadable", "path": path}
	var parser := JSON.new()
	var parse_error := parser.parse(source.get_as_text())
	source.close()
	if parse_error != OK:
		return {"ok": false, "error": "city_graph_json", "line": parser.get_error_line(), "details": parser.get_error_message()}
	if not parser.data is Dictionary:
		return {"ok": false, "error": "city_graph_object_required"}
	var graph: Dictionary = parser.data
	var errors := validation_errors(graph)
	if not errors.is_empty():
		return {"ok": false, "error": "city_graph_invalid", "details": errors}
	return {"ok": true, "data": graph}


static func validation_errors(graph: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if graph.get("schema") != SCHEMA:
		errors.append("schema")
	if graph.get("epoch") != "present_ellizia":
		errors.append("epoch")
	for group in ["map", "districts", "buildings", "locations", "access_policies", "services", "activation", "home_units", "resident_home_templates"]:
		if not graph.get(group) is Dictionary:
			errors.append(group + ":object_required")
	for group in ["routes", "dependencies", "story_bindings"]:
		if not graph.get(group) is Array:
			errors.append(group + ":array_required")
	if not errors.is_empty():
		return errors
	var locations: Dictionary = graph.locations
	var policies: Dictionary = graph.access_policies
	var buildings: Dictionary = graph.buildings
	var services: Dictionary = graph.services
	if locations.is_empty():
		errors.append("locations:empty")
	if not _position(graph.map.get("reference_size_px"), false):
		errors.append("map:reference_size_px")
	for raw_id in policies:
		var id := str(raw_id)
		var entry: Variant = policies[raw_id]
		if not _id(id) or not entry is Dictionary:
			errors.append("policy:" + id)
			continue
		var kind := str(entry.get("kind", ""))
		if not kind in POLICY_KINDS:
			errors.append("policy_kind:" + id)
		if kind in ["residence", "private_home"] and str(entry.get("owner_actor_id", "")).is_empty():
			errors.append("policy_owner:" + id)
		if kind == "residence" and str(entry.get("residence_property_id", "")).is_empty():
			errors.append("policy_property:" + id)
		if kind == "service" and not services.has(str(entry.get("service_id", ""))):
			errors.append("policy_service:" + id)
		for field in ["allow_invitation", "allow_story_entry", "allow_duty_entry", "allow_urgent_entry", "require_activity"]:
			if entry.has(field) and not entry[field] is bool:
				errors.append("policy_flag:" + id + ":" + field)
	for raw_id in locations:
		var id := str(raw_id)
		var entry: Variant = locations[raw_id]
		if not _id(id) or id in ["global_map", "training_center", "street_exit"] or id.begins_with("fb_") or id.begins_with("frame_") or not entry is Dictionary:
			errors.append("location:" + id)
			continue
		if entry.get("id") != id or not entry.get("title") is String or str(entry.title).is_empty():
			errors.append("location_identity:" + id)
		if not str(entry.get("kind", "")) in KINDS:
			errors.append("location_kind:" + id)
		if not graph.districts.has(str(entry.get("district_id", ""))):
			errors.append("location_district:" + id)
		var policy_id := str(entry.get("access_policy_id", ""))
		if not policies.has(policy_id):
			errors.append("location_policy:" + id)
		var building_id := str(entry.get("building_id", ""))
		if not building_id.is_empty() and not buildings.has(building_id):
			errors.append("location_building:" + id)
		if entry.has("hours") or entry.has("weekdays"):
			errors.append("location_hours_belong_to_service:" + id)
		var map_entry: Variant = entry.get("map")
		if not map_entry is Dictionary:
			errors.append("location_map:" + id)
		elif not _position(map_entry.get("position_uv"), true) or not map_entry.get("marker") is bool:
			errors.append("location_map_position:" + id)
		elif map_entry.get("offscreen", false) and map_entry.marker:
			errors.append("offscreen_marker:" + id)
		if policies.get(policy_id) is Dictionary:
			var policy: Dictionary = policies[policy_id]
			if entry.get("kind") == "public_exterior" and policy.get("kind") != "public":
				errors.append("public_frontage_policy:" + id)
			if entry.get("kind") == "private_room" and policy.get("kind") != "residence":
				errors.append("private_room_policy:" + id)
			if entry.get("kind") == "private_residence" and (policy.get("kind") != "private_home" or entry.get("owner_actor_id") != policy.get("owner_actor_id")):
				errors.append("private_owner_policy:" + id)
			if entry.get("kind") == "service_interior" and policy.get("kind") != "service":
				errors.append("service_interior_policy:" + id)
	for raw_id in buildings:
		var id := str(raw_id)
		var entry: Variant = buildings[raw_id]
		if not _id(id) or not entry is Dictionary:
			errors.append("building:" + id)
			continue
		if entry.get("id") != id or not entry.get("location_ids") is Array or not locations.has(str(entry.get("entry_location_id", ""))):
			errors.append("building_members:" + id)
			continue
		for member in entry.location_ids:
			if not locations.get(member) is Dictionary or locations[member].get("building_id") != id:
				errors.append("building_member:" + id + ":" + str(member))
		if not entry.entry_location_id in entry.location_ids:
			errors.append("building_entry:" + id)
	for raw_id in services:
		var id := str(raw_id)
		var entry: Variant = services[raw_id]
		if not _id(id) or not entry is Dictionary:
			errors.append("service:" + id)
			continue
		var location_id := str(entry.get("location_id", ""))
		if entry.get("id") != id or not locations.get(location_id) is Dictionary:
			errors.append("service_location:" + id)
			continue
		if not _hours(entry.get("hours")) or not _weekdays(entry.get("weekdays")):
			errors.append("service_hours:" + id)
		if not entry.get("urgent_entry") is bool:
			errors.append("service_urgent_flag:" + id)
		var frontage: Variant = locations.get(str(entry.get("public_frontage_location_id", "")))
		if not frontage is Dictionary or frontage.get("kind") != "public_exterior":
			errors.append("service_public_frontage:" + id)
		var policy: Variant = policies.get(str(locations[location_id].get("access_policy_id", "")))
		if not policy is Dictionary or policy.get("kind") != "service" or policy.get("service_id") != id:
			errors.append("service_entry_policy:" + id)
	var arcs := {}
	for raw_edge in graph.routes:
		if not raw_edge is Dictionary:
			errors.append("route:object_required")
			continue
		var edge: Dictionary = raw_edge
		var from_id := str(edge.get("from_id", ""))
		var to_id := str(edge.get("to_id", ""))
		if from_id == to_id or not locations.has(from_id) or not locations.has(to_id):
			errors.append("route_endpoint:" + from_id + ":" + to_id)
		if not _whole(edge.get("minutes")) or float(edge.get("minutes", 0)) <= 0.0 or not _whole(edge.get("cost")) or float(edge.get("cost", -1)) < 0.0 or not edge.get("bidirectional") is bool:
			errors.append("route_values:" + from_id + ":" + to_id)
		if edge.get("access_at") != "destination_actor_policy":
			errors.append("route_access:" + from_id + ":" + to_id)
		if not str(edge.get("kind", "")) in ROUTE_KINDS:
			errors.append("route_kind:" + from_id + ":" + to_id)
		var pairs := [[from_id, to_id]]
		if edge.get("bidirectional", false):
			pairs.append([to_id, from_id])
		for pair in pairs:
			var key := str(pair[0]) + ">" + str(pair[1])
			if arcs.has(key):
				errors.append("duplicate_route:" + key)
			arcs[key] = true
	var private_owners := {}
	for id in locations:
		var entry: Variant = locations[id]
		if not entry is Dictionary or entry.get("kind") != "private_residence":
			continue
		var owner := str(entry.get("owner_actor_id", ""))
		if private_owners.has(owner):
			errors.append("duplicate_private_home_owner:" + owner)
		private_owners[owner] = id
	for property_id in graph.home_units:
		var unit: Variant = graph.home_units[property_id]
		if not unit is Dictionary or unit.get("property_id") != property_id or not unit.get("room_ids") is Dictionary:
			errors.append("home_unit:" + str(property_id))
			continue
		var frontage := str(unit.get("frontage_id", ""))
		if not locations.get(frontage) is Dictionary or locations[frontage].get("kind") != "public_exterior":
			errors.append("home_frontage:" + str(property_id))
		for room_kind in ["hall", "bedroom", "bathroom", "kitchen"]:
			if not unit.room_ids.has(room_kind):
				errors.append("home_missing_room:" + str(property_id) + ":" + room_kind)
		for room_kind in unit.room_ids:
			var id := str(unit.room_ids[room_kind])
			var room: Variant = locations.get(id)
			if not room is Dictionary or room.get("kind") != "private_room" or room.get("residence_property_id") != property_id or room.get("room_kind") != room_kind:
				errors.append("home_room:" + str(property_id) + ":" + id)
				continue
			var policy: Variant = policies.get(str(room.get("access_policy_id", "")))
			if not policy is Dictionary or policy.get("residence_property_id") != property_id:
				errors.append("home_room_policy:" + id)
		if not arcs.has(frontage + ">" + str(unit.room_ids.get("hall", ""))):
			errors.append("home_entry_route:" + str(property_id))
	for template_id in graph.resident_home_templates:
		var template: Variant = graph.resident_home_templates[template_id]
		if not template is Dictionary or not _id(str(template_id)):
			errors.append("resident_home_template:" + str(template_id))
			continue
		var frontage: Variant = locations.get(str(template.get("frontage_id", "")))
		if not frontage is Dictionary or frontage.get("kind") != "public_exterior" or not graph.districts.has(str(template.get("district_id", ""))):
			errors.append("resident_home_template_frontage:" + str(template_id))
		if not _whole(template.get("minutes")) or float(template.get("minutes", 0)) <= 0.0:
			errors.append("resident_home_template_minutes:" + str(template_id))
		if not _whole(template.get("cost")) or float(template.get("cost", -1)) < 0.0:
			errors.append("resident_home_template_cost:" + str(template_id))
		for field in ["location_prefix", "policy_suffix", "building_suffix"]:
			if not template.get(field) is String or str(template[field]).is_empty():
				errors.append("resident_home_template_name:" + str(template_id) + ":" + field)
	var dependency_ids := {}
	for raw_dependency in graph.dependencies:
		if not raw_dependency is Dictionary:
			errors.append("dependency:object_required")
			continue
		var dependency: Dictionary = raw_dependency
		var id := str(dependency.get("id", ""))
		if not _id(id) or dependency_ids.has(id) or not dependency.get("status") in ["pending", "resolved"]:
			errors.append("dependency_identity:" + id)
		dependency_ids[id] = true
		for field in ["required_location_ids", "required_building_ids"]:
			if dependency.has(field) and not _id_list(dependency[field]):
				errors.append("dependency_ids:" + id + ":" + field)
	if not graph.activation.get("ready_for_main_world") is bool or not _id_list(graph.activation.get("blocking_dependency_ids")):
		errors.append("activation_fields")
	else:
		for id in graph.activation.blocking_dependency_ids:
			if not dependency_ids.has(id):
				errors.append("activation_dependency:" + str(id))
	for raw_binding in graph.story_bindings:
		if not raw_binding is Dictionary:
			errors.append("story_binding:object_required")
			continue
		var binding: Dictionary = raw_binding
		var id := str(binding.get("id", ""))
		var status := str(binding.get("status", ""))
		if not _id(id) or status.is_empty():
			errors.append("story_binding_identity:" + id)
		if binding.has("dependency_id") and not dependency_ids.has(str(binding.dependency_id)):
			errors.append("story_binding_dependency:" + id)
		if status.begins_with("mapped"):
			var targets: Array = []
			var building_target := str(binding.get("target_building_id", ""))
			if binding.has("target_location_id"):
				targets.append(binding.target_location_id)
			if binding.has("target_location_ids") and binding.target_location_ids is Array:
				targets.append_array(binding.target_location_ids)
			if targets.is_empty() and building_target.is_empty():
				errors.append("story_binding_target:" + id)
			if not building_target.is_empty() and not buildings.has(building_target):
				errors.append("story_binding_building:" + id)
			for target in targets:
				if not locations.has(target):
					errors.append("story_binding_location:" + id + ":" + str(target))
	errors.append_array(_capability_errors(graph))
	return errors


static func activation_errors(graph: Dictionary) -> PackedStringArray:
	## Validate the complete current-city switch and its explicit technical dependencies.
	var errors := validation_errors(graph)
	if not errors.is_empty():
		return errors
	if graph.activation.get("ready_for_main_world") != true:
		errors.append("main_world_not_ready")
	var dependencies := {}
	for raw_entry in graph.dependencies:
		if not raw_entry is Dictionary:
			errors.append("dependency:object_required")
			continue
		var entry: Dictionary = raw_entry
		var id := str(entry.get("id", ""))
		dependencies[id] = entry
		for location_id in entry.get("required_location_ids", []):
			if not graph.locations.has(location_id):
				errors.append("dependency_location:" + id + ":" + str(location_id))
		for building_id in entry.get("required_building_ids", []):
			if not graph.buildings.has(building_id):
				errors.append("dependency_building:" + id + ":" + str(building_id))
	for id in graph.activation.get("blocking_dependency_ids", []):
		if not dependencies.get(id) is Dictionary or dependencies[id].get("status") != "resolved":
			errors.append("pending_dependency:" + str(id))
	return errors


static func location(graph: Dictionary, id: String) -> Dictionary:
	var entry: Variant = graph.get("locations", {}).get(id)
	return entry.duplicate(true) if entry is Dictionary else {}


static func home_unit(graph: Dictionary, property_id: String) -> Dictionary:
	var unit: Variant = graph.get("home_units", {}).get(property_id)
	return unit.duplicate(true) if unit is Dictionary else {}


static func home_frontage(graph: Dictionary, property_id: String) -> String:
	return str(home_unit(graph, property_id).get("frontage_id", ""))


static func home_room(graph: Dictionary, property_id: String, room_kind: String) -> String:
	var rooms: Variant = home_unit(graph, property_id).get("room_ids")
	if not rooms is Dictionary:
		return ""
	var id: Variant = rooms.get(room_kind)
	return id if id is String else ""


static func private_home_for_actor(graph: Dictionary, actor_id: String) -> String:
	for id in graph.get("locations", {}):
		var entry: Dictionary = graph.locations[id]
		if entry.kind == "private_residence" and entry.get("owner_actor_id") == actor_id:
			return str(id)
	return ""


static func resident_home_records(graph: Dictionary, actor_id: String, template_id: String = "default") -> Dictionary:
	## Pure factory. Caller installs these records in the SAME catalog before generating the NPC.
	if not _id(actor_id) or actor_id == "player":
		return {"ok": false, "error": "city_resident_id_invalid"}
	var existing := private_home_for_actor(graph, actor_id)
	if not existing.is_empty():
		return {"ok": false, "error": "city_resident_home_exists", "location_id": existing}
	var template: Variant = graph.get("resident_home_templates", {}).get(template_id)
	if not template is Dictionary:
		return {"ok": false, "error": "city_resident_home_template_unknown"}
	var id := str(template.location_prefix) + actor_id
	var building_id := id + str(template.building_suffix)
	var policy_id := id + str(template.policy_suffix)
	if not _id(id) or not _id(building_id) or not _id(policy_id) or graph.locations.has(id) or graph.buildings.has(building_id) or graph.access_policies.has(policy_id):
		return {"ok": false, "error": "city_resident_home_collision"}
	var frontage := str(template.frontage_id)
	var place := location(graph, frontage)
	if place.is_empty() or place.kind != "public_exterior":
		return {"ok": false, "error": "city_resident_frontage_missing"}
	var map_entry: Dictionary = place.map.duplicate(true)
	map_entry.marker = false
	map_entry.offscreen = true
	var home := {"id": id, "title": "Жильё жителя", "kind": "private_residence",
		"district_id": str(template.district_id), "building_id": building_id,
		"access_policy_id": policy_id, "owner_actor_id": actor_id, "map": map_entry}
	var building := {"id": building_id, "title": "Жилой адрес", "entry_location_id": id,
		"location_ids": [id], "above_ground_floors": null, "architecture_status": "offscreen_private_unit"}
	var policy := {"kind": "private_home", "owner_actor_id": actor_id, "allow_invitation": true}
	var route := {"from_id": frontage, "to_id": id, "minutes": int(template.minutes),
		"cost": int(template.cost), "bidirectional": true, "kind": "private_entry",
		"access_at": "destination_actor_policy", "time_status": "authored_residence_template"}
	return {"ok": true, "data": {"location": home, "building": building,
		"policy_id": policy_id, "access_policy": policy, "route": route}}


static func catalog_locations(graph: Dictionary) -> Dictionary:
	## Projection only. Applying it to Simulation requires activation_errors() to be empty.
	var result: Dictionary = graph.locations.duplicate(true)
	for id in result:
		result[id].routes = {}
	for edge in graph.routes:
		result[edge.from_id].routes[edge.to_id] = {"minutes": int(edge.minutes), "cost": int(edge.cost)}
		if edge.bidirectional:
			result[edge.to_id].routes[edge.from_id] = {"minutes": int(edge.minutes), "cost": int(edge.cost)}
	return result


static func service_open(graph: Dictionary, id: String, minute_of_day: int, weekday: int) -> bool:
	if minute_of_day < 0 or minute_of_day >= 1440 or weekday < 1 or weekday > 7:
		return false
	var service: Variant = graph.get("services", {}).get(id)
	if not service is Dictionary or not _hours(service.get("hours")) or not _weekdays(service.get("weekdays")):
		return false
	var starts := int(service.hours[0])
	var ends := int(service.hours[1])
	var opening_day := weekday
	if starts > ends and minute_of_day < ends:
		opening_day = 7 if weekday == 1 else weekday - 1
	var valid_day := false
	for day in service.weekdays:
		if int(day) == opening_day:
			valid_day = true
	if not valid_day:
		return false
	if starts == ends:
		return true
	return minute_of_day >= starts and minute_of_day < ends if starts < ends else minute_of_day >= starts or minute_of_day < ends


static func can_enter(graph: Dictionary, id: String, actor: Dictionary, minute_of_day: int, weekday: int, check_hours: bool = true) -> Dictionary:
	## actor comes from current Simulation state, never directly from UI request arguments.
	var entry := location(graph, id)
	if entry.is_empty():
		return {"ok": false, "error": "unknown_city_location"}
	if not actor.get("id") is String or str(actor.id).is_empty():
		return {"ok": false, "error": "city_actor_required"}
	var policy: Variant = graph.get("access_policies", {}).get(str(entry.access_policy_id))
	if not policy is Dictionary:
		return {"ok": false, "error": "city_access_policy_missing"}
	var kind := str(policy.kind)
	if kind == "public":
		return {"ok": true}
	if kind in ["residence", "private_home"]:
		var owner: bool = actor.id == policy.owner_actor_id
		if kind == "residence":
			var occupancy: bool = actor.get("residence_id", "") == policy.residence_property_id
			var story_entry: bool = policy.get("allow_story_entry", false) and _actor_has(actor, "story_location_ids", id)
			owner = owner and (occupancy or story_entry)
		if owner or (policy.get("allow_invitation", false) and _actor_has(actor, "invited_location_ids", id)):
			return {"ok": true}
		return {"ok": false, "error": "city_private_access_required"}
	if kind == "service":
		if minute_of_day < 0 or minute_of_day >= 1440 or weekday < 1 or weekday > 7:
			return {"ok": false, "error": "city_clock_required"}
		if policy.get("allow_story_entry", false) and actor.id == "player" and _actor_has(actor, "story_location_ids", id):
			return {"ok": true}
		if policy.get("allow_duty_entry", false) and _actor_has(actor, "duty_location_ids", id):
			return {"ok": true}
		var service: Dictionary = graph.services[policy.service_id]
		if policy.get("allow_urgent_entry", false) and service.get("urgent_entry", false) and _actor_has(actor, "urgent_location_ids", id):
			return {"ok": true}
		if policy.get("require_activity", false) and not _actor_has(actor, "activity_location_ids", id):
			return {"ok": false, "error": "city_activity_access_required"}
		if not check_hours or service_open(graph, str(policy.service_id), minute_of_day, weekday):
			return {"ok": true}
		return {"ok": false, "error": "city_service_closed"}
	return {"ok": false, "error": "city_access_policy_invalid"}


static func _actor_has(actor: Dictionary, field: String, id: String) -> bool:
	var ids: Variant = actor.get(field)
	return ids is Array and id in ids


static func _capability_errors(graph: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var bindings: Variant = graph.get("capability_bindings")
	if not bindings is Dictionary:
		errors.append("capability_bindings:object_required")
		return errors
	for group in ["jobs", "shops", "lessons", "sports", "skill_practice"]:
		if not bindings.get(group) is Dictionary:
			errors.append("capability_bindings:" + group)
	if not errors.is_empty():
		return errors
	for id in bindings.jobs:
		var entry: Variant = bindings.jobs[id]
		if not entry is Dictionary:
			errors.append("job_binding:" + str(id))
			continue
		if entry.get("scope") == "fixed_location":
			if not graph.locations.has(str(entry.get("target_location_id", ""))):
				errors.append("job_location:" + str(id))
		elif entry.get("scope") == "actor_home":
			for property_id in graph.home_units:
				if home_room(graph, str(property_id), str(entry.get("player_room_kind", ""))).is_empty():
					errors.append("job_home_room:" + str(id) + ":" + str(property_id))
		else:
			errors.append("job_binding_scope:" + str(id))
	for group in ["lessons", "sports"]:
		for id in bindings[group]:
			if not graph.locations.has(str(bindings[group][id])):
				errors.append("activity_location:" + group + ":" + str(id))
	for id in bindings.shops:
		var entry: Variant = bindings.shops[id]
		if not entry is Dictionary or not graph.locations.has(str(entry.get("target_location_id", ""))) or not graph.locations.has(str(entry.get("frontage_location_id", ""))):
			errors.append("shop_binding:" + str(id))
	for id in bindings.skill_practice:
		var entry: Variant = bindings.skill_practice[id]
		if not entry is Dictionary or not _id_list(entry.get("fixed_location_ids")) or not _id_list(entry.get("actor_home_room_kinds")):
			errors.append("skill_binding:" + str(id))
			continue
		for location_id in entry.fixed_location_ids:
			if not graph.locations.has(location_id):
				errors.append("skill_location:" + str(id) + ":" + str(location_id))
		for room_kind in entry.actor_home_room_kinds:
			for property_id in graph.home_units:
				if home_room(graph, str(property_id), str(room_kind)).is_empty():
					errors.append("skill_home_room:" + str(id) + ":" + str(room_kind))
	return errors


static func _id(value: String) -> bool:
	if value.is_empty() or value != value.to_lower() or not value.is_valid_identifier():
		return false
	for index in range(value.length()):
		if not value[index] in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return false
	return true


static func _id_list(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen := {}
	for id in value:
		if not id is String or not _id(id) or seen.has(id):
			return false
		seen[id] = true
	return true


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func _position(value: Variant, normalized: bool) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
		if normalized and (float(number) < 0.0 or float(number) > 1.0):
			return false
		if not normalized and (not _whole(number) or float(number) <= 0.0):
			return false
	return true


static func _hours(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0]) and _whole(value[1]) and int(value[0]) >= 0 and int(value[0]) < 1440 and int(value[1]) >= 0 and int(value[1]) < 1440


static func _weekdays(value: Variant) -> bool:
	if not value is Array or value.is_empty():
		return false
	var seen := {}
	for day in value:
		if not _whole(day) or int(day) < 1 or int(day) > 7 or seen.has(int(day)):
			return false
		seen[int(day)] = true
	return true
