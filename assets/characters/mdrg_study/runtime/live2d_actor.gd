extends Node2D
## Runtime adapter for gd_cubism v0.9.1 (Godot 4.3+).
## The native class is instantiated dynamically, so this scene remains readable
## when the optional GDExtension is absent. Unity callbacks are never executed.

signal runtime_error(message: String)
signal model_loaded(imported_model_id: String)
signal motion_event(value: String)
signal motion_finished

@export_file("*.json") var catalog_path: String = ""
@export var model_id: String = ""
@export var fit_to_viewport: bool = true

const FULL_PARAMETER: int = 0
const MANUAL_PROCESS: int = 2
const FORCE_PRIORITY: int = 3

var last_error: String = ""
var baseline_seeded: bool = false
var playback_paused: bool = false
var _model: Node2D
var _entry: Dictionary = {}
var _parameters: Dictionary = {}
var _parts: Dictionary = {}
var _part_overrides: Dictionary = {}
var _initial_snapshot: Dictionary = {}
var _physics_enabled: bool = true
var _pose_enabled: bool = true
var _view_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	if catalog_path.is_empty():
		return
	var catalog: Dictionary = _read_json_object(catalog_path)
	var models: Variant = catalog.get("models", [])
	if not models is Array:
		_report_error("В каталоге отсутствует список models.")
		return
	for value: Variant in models:
		if value is Dictionary:
			var entry: Dictionary = value
			if model_id.is_empty() or str(entry.get("id", "")) == model_id:
				if load_model(entry) and fit_to_viewport:
					var area: Vector2 = get_viewport_rect().size
					position = area * 0.5
					fit_model(area)
				return
	_report_error("Модель не найдена в каталоге: " + model_id)


func _process(delta: float) -> void:
	if not is_model_loaded() or playback_paused:
		return
	for identifier: String in _part_overrides:
		var resource: Object = _parts[identifier]
		resource.call("set_value", float(_part_overrides[identifier]))
	_model.call("advance", maxf(0.0, delta))


func _create_backend() -> Node2D:
	if not ClassDB.class_exists("GDCubismUserModel"):
		return null
	var instance: Object = ClassDB.instantiate("GDCubismUserModel")
	if instance is Node2D:
		return instance as Node2D
	if instance != null:
		instance.free()
	return null


func is_model_loaded() -> bool:
	return is_instance_valid(_model) and not _entry.is_empty()


func load_model(entry: Dictionary) -> bool:
	last_error = ""
	var pathname: String = str(entry.get("model3", ""))
	if pathname.is_empty() or not FileAccess.file_exists(pathname):
		return _report_error("Не найден файл model3: " + pathname)
	var candidate: Node2D = _create_backend()
	if candidate == null:
		return _report_error("Нужен gd_cubism 0.9.1 или совместимая новая версия для вашей ОС. Установите addons/gd_cubism и перезапустите Godot.")
	var required: Array[String] = [
		"set_assets", "set_load_motions", "set_load_expressions", "csm_get_moc_version",
		"get_parameters", "get_part_opacities", "get_canvas_info", "get_motions",
		"get_expressions", "start_motion", "start_motion_loop", "stop_motion", "start_expression", "stop_expression",
		"set_process_callback", "set_parameter_mode", "set_physics_evaluate", "set_pose_update", "advance"
	]
	for method: String in required:
		if not candidate.has_method(method):
			candidate.free()
			return _report_error("Несовместимый gd_cubism: отсутствует метод " + method)
	_clear_backend()
	_model = candidate
	_model.name = "Cubism"
	_model.call("set_load_motions", true)
	_model.call("set_load_expressions", true)
	_model.call("set_process_callback", MANUAL_PROCESS)
	_model.call("set_parameter_mode", FULL_PARAMETER)
	# Add first: native _ready reloads assets if already assigned.
	add_child(_model)
	_model.call("set_assets", pathname)
	if int(_model.call("csm_get_moc_version")) == 0:
		_clear_backend()
		return _report_error("Cubism Core не загрузил MOC. Проверьте версию SDK, атлас и ошибки в Output: " + pathname)
	var parameter_values: Variant = _model.call("get_parameters")
	var part_values: Variant = _model.call("get_part_opacities")
	if not parameter_values is Array or not part_values is Array:
		_clear_backend()
		return _report_error("gd_cubism вернул неверный список параметров или частей.")
	for resource: Variant in parameter_values:
		if resource is Object and resource.has_method("get_id"):
			_parameters[str(resource.call("get_id"))] = resource
	for resource: Variant in part_values:
		if resource is Object and resource.has_method("get_id"):
			_parts[str(resource.call("get_id"))] = resource
	_entry = entry.duplicate(true)
	model_id = str(entry.get("id", ""))
	if _model.has_signal("motion_event"):
		_model.connect("motion_event", _on_native_motion_event)
	if _model.has_signal("motion_finished"):
		_model.connect("motion_finished", _on_native_motion_finished)
	var snapshot_path: String = str(entry.get("snapshot", ""))
	_initial_snapshot = _read_json_object(snapshot_path) if not snapshot_path.is_empty() else {}
	var model_data: Dictionary = _read_json_object(pathname)
	var references: Dictionary = model_data.get("FileReferences", {})
	_physics_enabled = references.has("Physics")
	_pose_enabled = references.has("Pose")
	set_physics_enabled(_physics_enabled)
	set_pose_enabled(_pose_enabled)
	if not _initial_snapshot.is_empty():
		apply_snapshot(_initial_snapshot)
	else:
		baseline_seeded = false
	if _view_size.x > 0.0 and _view_size.y > 0.0:
		fit_model(_view_size)
	model_loaded.emit(model_id)
	return true


func _clear_backend() -> void:
	_parameters.clear()
	_parts.clear()
	_part_overrides.clear()
	_entry.clear()
	_initial_snapshot.clear()
	baseline_seeded = false
	if is_instance_valid(_model):
		remove_child(_model)
		_model.free()
	_model = null


func _seed_initial_motion() -> bool:
	var seed: Variant = _entry.get("snapshot_motion", {})
	if not seed is Dictionary or not seed.has("group"):
		return false
	var groups: Dictionary = _model.call("get_motions")
	var group: String = str(seed.get("group", ""))
	var index: int = int(seed.get("index", 0))
	if not groups.has(group) or index < 0 or index >= int(groups[group]):
		return false
	_model.call("stop_motion")
	_model.call("stop_expression")
	_release_overrides(false)
	_model.call("set_parameter_mode", FULL_PARAMETER)
	_model.call("set_physics_evaluate", false)
	_model.call("set_pose_update", false)
	# Flush pending GDCubismParameter.changed flags before the seeding motion.
	_model.call("advance", 0.0)
	var handle: Variant = _model.call("start_motion", group, index, FORCE_PRIORITY)
	var valid: bool = _motion_handle_ok(handle)
	if valid:
		# Native order is LoadParameters -> UpdateMotion -> SaveParameters.
		# A zero-fade constant motion seeds the saved state at t=0 without
		# retaining parameter holds that would freeze later animations.
		_model.call("advance", 0.0)
		_model.call("stop_motion")
	_model.call("set_physics_evaluate", _physics_enabled)
	_model.call("set_pose_update", _pose_enabled)
	return valid


func apply_snapshot(snapshot_data: Dictionary) -> bool:
	if not is_model_loaded():
		return _report_error("Сначала загрузите модель.")
	baseline_seeded = false
	if snapshot_data == _initial_snapshot and _seed_initial_motion():
		baseline_seeded = true
		return true
	_model.call("stop_motion")
	_model.call("stop_expression")
	_release_overrides(false)
	var parameters: Variant = snapshot_data.get("effective_parameters", snapshot_data.get("parameters", {}))
	var parts: Variant = snapshot_data.get("effective_parts", snapshot_data.get("parts", {}))
	var success: bool = true
	if parameters is Dictionary:
		for identifier: String in parameters:
			if typeof(parameters[identifier]) in [TYPE_INT, TYPE_FLOAT]:
				success = set_parameter(identifier, float(parameters[identifier])) and success
	if parts is Dictionary:
		for identifier: String in parts:
			if typeof(parts[identifier]) in [TYPE_INT, TYPE_FLOAT]:
				success = set_part_opacity(identifier, float(parts[identifier])) and success
	_model.call("advance", 0.0)
	if snapshot_data == _initial_snapshot:
		_report_error("Исходная поза применена как ручные значения: служебная snapshot motion недоступна. При запуске анимации ручные фиксации снимаются.")
	return success


func reset_pose() -> bool:
	if not is_model_loaded():
		return false
	if not _initial_snapshot.is_empty():
		return apply_snapshot(_initial_snapshot)
	_model.call("stop_motion")
	_model.call("stop_expression")
	_release_overrides(false)
	for resource: Object in _parameters.values():
		resource.call("reset")
	_model.call("advance", 0.0)
	return true


func set_parameter(identifier: String, value: float) -> bool:
	if not _parameters.has(identifier) or not is_finite(value):
		return _report_error("Недоступен параметр или неверное значение: " + identifier)
	var resource: Object = _parameters[identifier]
	var minimum: float = float(resource.call("get_minimum_value"))
	var maximum: float = float(resource.call("get_maximum_value"))
	resource.call("set_value", clampf(value, minimum, maximum))
	resource.call("set_hold", true)
	return true


func set_part_opacity(identifier: String, value: float) -> bool:
	if not _parts.has(identifier) or not is_finite(value):
		return _report_error("Недоступна часть или неверное значение: " + identifier)
	var resource: Object = _parts[identifier]
	var opacity: float = clampf(value, 0.0, 1.0)
	resource.call("set_value", opacity)
	_part_overrides[identifier] = opacity
	return true


func release_parameter(identifier: String) -> void:
	if _parameters.has(identifier):
		var resource: Object = _parameters[identifier]
		resource.call("set_hold", false)


func release_part_opacity(identifier: String) -> void:
	_part_overrides.erase(identifier)


func _release_overrides(flush: bool = true) -> void:
	for resource: Object in _parameters.values():
		resource.call("set_hold", false)
	_part_overrides.clear()
	if flush and is_model_loaded():
		_model.call("advance", 0.0)


func play_motion(group: String, index: int, priority: int = FORCE_PRIORITY) -> bool:
	if not is_model_loaded():
		return _report_error("Сначала загрузите модель.")
	var groups: Dictionary = _model.call("get_motions")
	if not groups.has(group) or index < 0 or index >= int(groups[group]):
		return _report_error("Анимация не найдена: %s / %d" % [group, index])
	_release_overrides()
	_model.call("set_parameter_mode", FULL_PARAMETER)
	playback_paused = false
	var should_loop: bool = false
	for record: Variant in _entry.get("motions", []):
		if record is Dictionary and str(record.get("group", "")) == group and int(record.get("index", -1)) == index:
			should_loop = bool(record.get("loop", false))
			break
	# gd_cubism.start_motion() hardcodes loop=false. Preserve each
	# original motion's Meta.Loop through start_motion_loop() instead.
	var handle: Variant = _model.call("start_motion_loop", group, index, clampi(priority, 0, 3), should_loop, true)
	if not _motion_handle_ok(handle):
		return _report_error("Cubism отклонил запуск анимации: " + group)
	return true


func play_expression(expression_name: String) -> bool:
	if not is_model_loaded():
		return _report_error("Сначала загрузите модель.")
	var expressions: Array = _model.call("get_expressions")
	if not expressions.has(expression_name):
		return _report_error("Выражение не найдено: " + expression_name)
	_release_overrides()
	_model.call("start_expression", expression_name)
	playback_paused = false
	return true


func stop_motion() -> void:
	if is_model_loaded():
		_model.call("stop_motion")


func stop_expression() -> void:
	if is_model_loaded():
		_model.call("stop_expression")


func set_physics_enabled(enabled: bool) -> void:
	_physics_enabled = enabled
	if is_model_loaded():
		_model.call("set_physics_evaluate", enabled)


func set_pose_enabled(enabled: bool) -> void:
	_pose_enabled = enabled
	if is_model_loaded():
		_model.call("set_pose_update", enabled)


func get_parameter_value(identifier: String) -> float:
	if not _parameters.has(identifier):
		return 0.0
	var resource: Object = _parameters[identifier]
	return float(resource.call("get_value"))


func get_model_id() -> String:
	return model_id


func get_source_model_id() -> String:
	return str(_entry.get("source_id", ""))


func is_parameter_held(identifier: String) -> bool:
	if not _parameters.has(identifier):
		return false
	var resource: Object = _parameters[identifier]
	return bool(resource.call("get_hold")) if resource.has_method("get_hold") else false


func get_drawable_meshes() -> Dictionary:
	## Accept both legacy MeshInstance2D consumers and gd_cubism 0.9+
	## get_meshes() dictionary of deformed ArrayMesh resources.
	if not is_model_loaded() or not _model.has_method("get_meshes"):
		return {}
	var native_meshes: Variant = _model.call("get_meshes")
	if not native_meshes is Dictionary:
		return {}
	var result: Dictionary = {}
	for identifier: String in native_meshes:
		var node: Node = _model.find_child(identifier, true, false)
		result[identifier] = node if node is MeshInstance2D and str(node.name) == identifier else native_meshes[identifier]
	return result


func get_part_value(identifier: String) -> float:
	if not _parts.has(identifier):
		return 0.0
	var resource: Object = _parts[identifier]
	return float(resource.call("get_value"))


func get_parameter_descriptors() -> Array:
	var result: Array = []
	for identifier: String in _parameters:
		var resource: Object = _parameters[identifier]
		result.append({"id": identifier, "minimum": float(resource.call("get_minimum_value")),
			"maximum": float(resource.call("get_maximum_value")), "default": float(resource.call("get_default_value")),
			"value": float(resource.call("get_value"))})
	return result


func get_part_descriptors() -> Array:
	var result: Array = []
	for identifier: String in _parts:
		var resource: Object = _parts[identifier]
		result.append({"id": identifier, "value": float(resource.call("get_value"))})
	return result


func fit_model(size: Vector2) -> void:
	_view_size = size
	if not is_model_loaded() or size.x <= 0.0 or size.y <= 0.0:
		return
	var canvas: Dictionary = _model.call("get_canvas_info")
	var dimensions: Vector2 = canvas.get("size_in_pixels", Vector2.ZERO)
	if dimensions.x <= 0.0 or dimensions.y <= 0.0:
		return
	var origin: Vector2 = canvas.get("origin_in_pixels", dimensions * 0.5)
	var factor: float = minf(size.x / dimensions.x, size.y / dimensions.y) * 0.9
	_model.scale = Vector2(factor, factor)
	# Renderer v0.9.1 maps (x,y) Core units to (x*ppu,-y*ppu).
	_model.position = Vector2(origin.x - dimensions.x * 0.5, dimensions.y * 0.5 - origin.y) * factor


func _read_json_object(pathname: String) -> Dictionary:
	if pathname.is_empty() or not FileAccess.file_exists(pathname):
		_report_error("Не найден JSON-файл: " + pathname)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pathname))
	if not parsed is Dictionary:
		_report_error("Ожидался JSON-объект: " + pathname)
		return {}
	return parsed


func _motion_handle_ok(handle: Variant) -> bool:
	return handle is Object and handle.has_method("get_error") and int(handle.call("get_error")) == OK


func _report_error(message: String) -> bool:
	last_error = message
	runtime_error.emit(message)
	push_warning(message)
	return false


func _on_native_motion_event(value: String) -> void:
	# Inform the host game. Never call a method named by imported Unity data.
	motion_event.emit(value)


func _on_native_motion_finished() -> void:
	motion_finished.emit()
