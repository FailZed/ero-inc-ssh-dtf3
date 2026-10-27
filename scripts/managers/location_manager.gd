extends Node

signal location_changed(location_id: String)
signal travel_blocked(location_id: String, reason: String)

const LOCATION_GLOBAL_MAP := "global_map"

const LOCATIONS := {
	"global_map": {
		"title": "Глобальная карта",
		"parent": "",
		"scene_path": "res://locations/global_map.tscn",
	},
	"apartment_hall": {
		"title": "Квартира / Коридор",
		"parent": "global_map",
		"scene_path": "res://locations/apartment/hall.tscn",
	},
	"bathroom": {
		"title": "Ванная комната",
		"parent": "apartment_hall",
		"scene_path": "res://locations/apartment/bathroom.tscn",
	},
	"kitchen": {
		"title": "Кухня",
		"parent": "apartment_hall",
		"scene_path": "res://locations/apartment/kitchen.tscn",
	},
	"bedroom": {
		"title": "Спальня",
		"parent": "apartment_hall",
		"scene_path": "res://locations/apartment/bedroom.tscn",
	},
	"street_exit": {
		"title": "Улица / Выход",
		"parent": "apartment_hall",
		"scene_path": "res://locations/global_map.tscn",
	},
}

var current_location_id := ""
var previous_location_id := ""
var _locations: Dictionary = LOCATIONS.duplicate(true)
var _travel_guard := Callable()


# Add this script as an Autoload named LocationManager in Project Settings.
# In this project it is already registered in project.godot.
func go_to(location_id: String) -> Error:
	var available := can_go_to(location_id)
	if not available.ok:
		travel_blocked.emit(location_id, str(available.error))
		return ERR_UNAVAILABLE
	var location: Dictionary = _locations[location_id]
	var scene_path := str(location.scene_path)
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("LocationManager: failed to open %s (%s): %s" % [location_id, scene_path, error_string(error)])
		return error
	previous_location_id = current_location_id
	current_location_id = location_id
	var travel_minutes := maxi(0, int(location.get("travel_minutes", 0)))
	if travel_minutes > 0:
		GameSession.advance_game_time(travel_minutes)
	location_changed.emit(current_location_id)
	return OK


func can_go_to(location_id: String) -> Dictionary:
	if not _locations.has(location_id):
		return {"ok": false, "error": "unknown_location"}
	var path := str(_locations[location_id].get("scene_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return {"ok": false, "error": "missing_scene"}
	if _travel_guard.is_valid():
		var result: Variant = _travel_guard.call(location_id)
		if not result is Dictionary or not result.get("ok", false):
			return result if result is Dictionary else {"ok": false, "error": "invalid_travel_guard"}
	return {"ok": true}


func register_location(location_id: String, location: Dictionary) -> Error:
	if location_id.is_empty() or _locations.has(location_id):
		return ERR_ALREADY_EXISTS
	var parent := str(location.get("parent", ""))
	if not parent.is_empty() and not _locations.has(parent):
		return ERR_INVALID_PARAMETER
	if not ResourceLoader.exists(str(location.get("scene_path", "")), "PackedScene"):
		return ERR_FILE_NOT_FOUND
	_locations[location_id] = location.duplicate(true)
	return OK


func get_location(location_id: String) -> Dictionary:
	return (_locations.get(location_id, {}) as Dictionary).duplicate(true)


func get_locations() -> Dictionary:
	return _locations.duplicate(true)


func set_travel_guard(guard: Callable) -> void:
	_travel_guard = guard


func go_back() -> void:
	var parent_id := _get_parent_id(current_location_id)
	if parent_id.is_empty():
		push_warning("LocationManager: current location has no parent: %s" % current_location_id)
		return

	go_to(parent_id)


func get_current_location() -> Dictionary:
	if not _locations.has(current_location_id):
		return {}

	return (_locations[current_location_id] as Dictionary).duplicate(true)


func get_parent_location() -> Dictionary:
	var parent_id := _get_parent_id(current_location_id)
	if parent_id.is_empty() or not _locations.has(parent_id):
		return {}

	return (_locations[parent_id] as Dictionary).duplicate(true)


func can_go_back() -> bool:
	return not _get_parent_id(current_location_id).is_empty()


func _get_parent_id(location_id: String) -> String:
	if location_id.is_empty() or not _locations.has(location_id):
		return ""

	return str((_locations[location_id] as Dictionary).get("parent", ""))
