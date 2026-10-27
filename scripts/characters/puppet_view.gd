extends Control
## Reusable Live2D presentation. All interaction logic is independent EroInc code.
signal model_loaded(descriptor: Dictionary)
signal load_failed(message: String)
signal interaction_started(id: String)
signal interaction_finished(event: Dictionary)

const Bank = preload("res://scripts/characters/parameter_bank.gd")
const Memory = preload("res://scripts/characters/interaction_memory.gd")
const Clip = preload("res://scripts/characters/motion_clip.gd")

var bank := Bank.new()
var memory := Memory.new()
var clip := Clip.new()
var model: Node2D
var descriptor: Dictionary = {}
var profile: Dictionary = {}
var physics_enabled := true
var gaze_enabled := true
var blink_enabled := true
var debug_zones := false
var toggle_grab := false
var sensitivity := 2.0
var zoom := 1.0
var hovered := ""
var held := ""
var _parameters: Dictionary = {}
var _parts: Dictionary = {}
var _part_defaults: Dictionary = {}
var part_values: Dictionary = {}
var _meshes: Dictionary = {}
var _zone_meshes: Dictionary = {}
var _anchor := Vector2.ZERO
var _last_pointer := Vector2.ZERO
var _grab_values: Dictionary = {}
var _zone: Dictionary = {}
var _clock := 0.0
var _blink_clock := 0.0
var _bounds := Rect2()

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	resized.connect(_fit)
	if not InputMap.has_action("character_release"):
		InputMap.add_action("character_release")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("character_release", key)
	memory.reaction_changed.connect(_react)

func load_character(item: Dictionary, bindings: Dictionary = {}) -> bool:
	var path := str(item.get("model", ""))
	if not ClassDB.class_exists("GDCubismUserModel"):
		load_failed.emit("Live2D доступен в сборке для Windows x64.")
		return false
	if not FileAccess.file_exists(path) or not path.ends_with(".model3.json"):
		load_failed.emit("Не найден файл модели: " + path)
		return false
	if not validate_profile(bindings):
		load_failed.emit("Неверный формат привязок модели.")
		return false
	release_grab(true)
	clip.stop()
	bank.reset()
	_parameters.clear()
	_parts.clear()
	_part_defaults.clear()
	part_values.clear()
	_meshes.clear()
	_zone_meshes.clear()
	if is_instance_valid(model):
		remove_child(model)
		model.free()
	model = null
	descriptor = item.duplicate(true)
	profile = bindings.duplicate(true)
	memory.reset()
	model = ClassDB.instantiate("GDCubismUserModel") as Node2D
	model.set("playback_process_mode", 2)
	add_child(model)
	model.set("assets", path)
	if not model.call("is_initialized"):
		load_failed.emit("Cubism не смог открыть модель.")
		remove_child(model)
		model.free()
		model = null
		return false
	var specs: Array = []
	for parameter: Resource in model.call("get_parameters"):
		var id := str(parameter.get("id"))
		_parameters[id] = parameter
		specs.append({"id":id,"min":parameter.get("minimum_value"),"max":parameter.get("maximum_value"),"default":parameter.get("default_value")})
	bank.configure(specs)
	for part: Resource in model.call("get_part_opacities"):
		var id := str(part.get("id"))
		_parts[id] = part
		part_values[id] = float(part.get("value"))
		_part_defaults[id] = part_values[id]
	_meshes = model.call("get_meshes")
	apply_palette()
	for zone: Dictionary in profile.get("zones", []):
		var matching: Array[String] = []
		for mesh_id: String in _meshes:
			for pattern: String in zone.get("meshes", []):
				if mesh_id.match(pattern):
					matching.append(mesh_id)
					break
		_zone_meshes[str(zone.id)] = matching
	reset_character()
	_fit()
	model_loaded.emit(descriptor)
	return true

func reset_character() -> void:
	release_grab(true)
	clip.stop()
	bank.reset()
	bank.set_targets(profile.get("initial", {}), "wardrobe", 5)
	for id: String in part_values: part_values[id] = clampf(float(profile.get("parts",{}).get(id,_part_defaults[id])),0.0,1.0)
	# Initial wardrobe must be visible on the first rendered frame.
	for id in bank.values: bank.values[id] = bank.target_for(id)
	_apply_parameters(0.016)

func apply_palette() -> void:
	for id: String in _meshes:
		var mesh_node := _meshes[id] as MeshInstance2D
		mesh_node.self_modulate = Color.WHITE
		for entry: Dictionary in profile.get("palette", []):
			for pattern: String in entry.get("meshes", []):
				if id.to_lower().match(pattern.to_lower()):
					mesh_node.self_modulate = Color(str(entry.get("color","ffffff")))

func choose_preset(group: String, title: String) -> void:
	bank.clear_channel("manual")
	bank.clear_channel("playback")
	if clip.playing: clip.stop()
	var values: Dictionary = profile.get(group, {}).get(title, {})
	if group == "outfits":
		values = profile.get("initial", {}).merged(values, true)
	bank.set_targets(values, group, 20 if group == "poses" else 40)

func _fit() -> void:
	if not is_instance_valid(model): return
	var info: Dictionary = model.call("get_canvas_info")
	var canvas: Vector2 = info.get("size_in_pixels", Vector2.ONE)
	var origin: Vector2 = info.get("origin_in_pixels", Vector2.ZERO)
	var fit_scale := minf(size.x / maxf(canvas.x, 1.0), size.y / maxf(canvas.y, 1.0)) * 0.94 * zoom
	model.scale = Vector2.ONE * fit_scale
	model.position = size * 0.5 - (origin - canvas * 0.5) * fit_scale
	_bounds = Rect2(model.position + (origin-canvas)*fit_scale, canvas*fit_scale)

func set_zoom(value: float) -> void:
	zoom = clampf(value, 0.5, 2.5)
	_fit()

func _process(delta: float) -> void:
	if not is_instance_valid(model): return
	_clock += delta
	memory.advance(delta)
	if clip.playing:
		bank.set_targets(clip.sample(delta), "playback", 200)
		# Recorded values are already smoothed; avoid smoothing them a second time.
		for id: String in bank.values: bank.values[id] = bank.target_for(id)
	else:
		_update_idle(delta)
		bank.advance(delta)
	_apply_parameters(delta)
	clip.record_step(delta, bank.snapshot())
	if debug_zones: queue_redraw()

func _update_idle(delta: float) -> void:
	bank.clear_channel("gaze")
	if gaze_enabled and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		var gaze: Dictionary = profile.get("gaze", {})
		var point := (get_local_mouse_position() / size.max(Vector2.ONE) - Vector2.ONE*0.5) * 2.0
		for id: String in gaze.get("x", []): bank.set_normalized(id, point.x, "gaze", 10)
		for id: String in gaze.get("y", []): bank.set_normalized(id, -point.y, "gaze", 10)
	bank.clear_channel("blink")
	if blink_enabled:
		_blink_clock = fmod(_blink_clock + delta, 4.1)
		if _blink_clock < 0.18:
			bank.set_normalized(str(profile.get("blink", "")), -sin(_blink_clock/0.18*PI), "blink", 50)

func _apply_parameters(delta: float) -> void:
	if not is_instance_valid(model): return
	model.set("physics_evaluate", physics_enabled)
	for id: String in _parameters:
		_parameters[id].set("value", float(bank.values.get(id, 0.0)))
	for id: String in _parts: _parts[id].set("value", float(part_values[id]))
	model.call("advance", minf(delta, 0.1))

func _react(state: String) -> void:
	bank.clear_channel("reaction")
	if state == "comfortable":
		bank.set_target("ParamMouthForm", 0.3, "reaction", 30)
	elif state == "surprised":
		bank.set_target("ParamBrowLY", 0.3, "reaction", 30)
		bank.set_target("ParamBrowRY", 0.3, "reaction", 30)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if toggle_grab and not held.is_empty(): release_grab()
			else: begin_grab(event.position)
		elif not toggle_grab: release_grab()
		accept_event()
	elif event is InputEventMouseMotion:
		if not held.is_empty(): move_grab(event.position)
		else: hovered = str(hit_test(event.position).get("title", ""))
	elif event is InputEventScreenTouch:
		if event.pressed: begin_grab(event.position)
		else: release_grab()
		accept_event()
	elif event is InputEventScreenDrag:
		move_grab(event.position)
		accept_event()

func _input(event: InputEvent) -> void:
	if held.is_empty(): return
	if event.is_action_pressed("character_release"):
		release_grab(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not toggle_grab:
		release_grab()
	elif event is InputEventMouseMotion and not get_global_rect().has_point(event.global_position):
		move_grab(get_local_mouse_position())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		release_grab(true)

func begin_grab(point: Vector2) -> bool:
	var found := hit_test(point)
	if found.is_empty(): return false
	release_grab(true)
	if clip.playing: clip.stop()
	bank.clear_channel("playback")
	bank.clear_channel("manual")
	_zone = found
	held = str(found.id)
	_anchor = point
	_last_pointer = point
	_grab_values = bank.snapshot()
	bank.set_targets(found.get("press", {}), "pointer", 60)
	memory.begin(held)
	interaction_started.emit(held)
	return true

func move_grab(point: Vector2) -> void:
	if held.is_empty(): return
	var movement := (point-_anchor) / maxf(minf(size.x,size.y), 1.0) * sensitivity
	for axis: String in ["x", "y"]:
		var id := str(_zone.get(axis, ""))
		if not bank.has_parameter(id): continue
		var spec: Dictionary = bank.definitions[id]
		var amount := movement.x if axis == "x" else -movement.y
		bank.set_target(id, float(_grab_values[id]) + amount * float(spec.max-spec.min), "pointer", 60)
	var local_motion := (point-_last_pointer) / maxf(minf(size.x,size.y), 1.0) * sensitivity * 30.0
	bank.set_normalized(str(_zone.get("move_x", "")), local_motion.x, "pointer", 60)
	bank.set_normalized(str(_zone.get("move_y", "")), -local_motion.y, "pointer", 60)
	memory.motion(point.distance_to(_last_pointer)/maxf(size.y,1.0))
	_last_pointer = point

func release_grab(cancelled: bool = false) -> void:
	bank.clear_channel("pointer")
	if held.is_empty(): return
	held = ""
	_zone = {}
	interaction_finished.emit(memory.finish(cancelled))

func hit_test(point: Vector2) -> Dictionary:
	if not is_instance_valid(model): return {}
	# Explicit authoring priority: small head/hand regions precede torso regions.
	for zone: Dictionary in profile.get("zones", []):
		var ids: Array = _zone_meshes.get(str(zone.id), [])
		ids.sort_custom(func(a, b): return _mesh_order(a) > _mesh_order(b))
		for id: String in ids:
			var mesh_node := model.get_node_or_null(NodePath(id)) as MeshInstance2D
			if not is_instance_valid(mesh_node): continue
			if not id.begins_with("HitArea") and not mesh_node.visible: continue
			var local := mesh_node.to_local(get_global_transform() * point)
			var mesh := mesh_node.mesh as ArrayMesh
			if mesh.get_surface_count() == 0: continue
			var box := mesh.custom_aabb
			if not Rect2(Vector2(box.position.x,box.position.y),Vector2(box.size.x,box.size.y)).has_point(local): continue
			var arrays := mesh.surface_get_arrays(0)
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size()-2, 3):
				if point_in_triangle(local, _v2(vertices[indices[i]]), _v2(vertices[indices[i+1]]), _v2(vertices[indices[i+2]])):
					return zone
	return {}

func _mesh_order(id: String) -> int:
	var item := model.get_node_or_null(NodePath(id)) as MeshInstance2D
	return item.z_index if is_instance_valid(item) else 0

func _v2(vertex: Variant) -> Vector2:
	return Vector2(vertex.x, vertex.y)

static func point_in_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var area := (b-a).cross(c-a)
	if absf(area) < 0.000001: return false
	var u := (b-point).cross(c-point) / area
	var v := (c-point).cross(a-point) / area
	var w := 1.0-u-v
	return u >= -0.00001 and v >= -0.00001 and w >= -0.00001

static func validate_profile(data: Dictionary) -> bool:
	for key: String in ["initial","parts"]:
		if not data.get(key,{}) is Dictionary: return false
		for value: Variant in data.get(key,{}).values():
			if not (value is int or value is float) or not is_finite(float(value)): return false
	for key: String in ["outfits","expressions","poses"]:
		if not data.get(key,{}) is Dictionary: return false
		for parameters: Variant in data.get(key,{}).values():
			if not parameters is Dictionary: return false
			for value: Variant in parameters.values():
				if not (value is int or value is float) or not is_finite(float(value)): return false
	if not data.get("zones",[]) is Array or not data.get("palette",[]) is Array or not data.get("gaze",{}) is Dictionary: return false
	for entry: Variant in data.get("zones",[]) + data.get("palette",[]):
		if not entry is Dictionary or not entry.get("meshes",[]) is Array: return false
		for pattern: Variant in entry.get("meshes",[]):
			if not pattern is String: return false
	for zone: Dictionary in data.get("zones",[]):
		if str(zone.get("id", "")).is_empty() or not zone.get("press",{}) is Dictionary: return false
	for axis: String in ["x","y"]:
		if not data.get("gaze",{}).get(axis,[]) is Array: return false
	return true

func _draw() -> void:
	if not debug_zones or not is_instance_valid(model): return
	draw_rect(_bounds, Color(0.55,0.77,0.9,0.4), false)
	for id: String in _zone_meshes:
		for mesh_id: String in _zone_meshes[id]:
			var mesh := (_meshes[mesh_id] as MeshInstance2D).mesh as ArrayMesh
			var box := mesh.custom_aabb
			var rect := Rect2(model.position + Vector2(box.position.x,box.position.y)*model.scale, Vector2(box.size.x,box.size.y)*model.scale)
			draw_rect(rect, Color(0.9,0.62,0.38,0.6), false)
