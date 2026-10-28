extends Control
## Reusable Live2D presentation. All interaction logic is independent EroInc code.
signal model_loaded(descriptor: Dictionary)
signal load_failed(message: String)
signal interaction_started(id: String)
signal interaction_finished(event: Dictionary)
const Bank = preload("res://scripts/characters/parameter_bank.gd")
const Memory = preload("res://scripts/characters/interaction_memory.gd")
const Clip = preload("res://scripts/characters/motion_clip.gd")
const RIG_DEBUG_LABEL := "Без одежды (проверка рига)"
const CLOTHING_WORDS := ["shirt", "skirt", "bra", "pant", "shoe", "hoodie",
  "dress", "bikini", "sock", "stocking", "coat", "jacket", "boot", "cloth"]
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
var _active_zones: Array[Dictionary] = []
var _physics_output_ids: Dictionary = {}
var _unity_snapshot_parameters: Dictionary = {}
var _unity_snapshot_parts: Dictionary = {}
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
  var path: String = str(item.get("model", item.get("model3", "")))
  if not ClassDB.class_exists("GDCubismUserModel"):
    load_failed.emit("Модуль Live2D не установлен для этой платформы. Выполните настройку проекта с Live2D.")
    return false
  if not FileAccess.file_exists(path) or not path.ends_with(".model3.json"):
    load_failed.emit("Не найден файл модели: " + path)
    return false
  var resolved: Dictionary = resolve_profile_for_model(item, bindings)
  if not validate_profile(resolved):
    load_failed.emit("Неверный формат привязок модели.")
    return false
  var candidate: Object = ClassDB.instantiate("GDCubismUserModel")
  if not candidate is Node2D:
    if candidate != null: candidate.free()
    load_failed.emit("GDCubismUserModel не создал Node2D.")
    return false
  for method: String in ["set_assets", "csm_get_moc_version", "set_process_callback", "set_parameter_mode",
      "get_parameters", "get_part_opacities", "get_meshes", "get_canvas_info", "advance"]:
    if not candidate.has_method(method):
      candidate.free()
      load_failed.emit("Несовместимый gd_cubism: нет метода " + method)
      return false
  # Avoid loading a known-newer MOC into an older native Cubism Core: a bad
  # version combination can crash before GDScript receives a failure code.
  var info_path: String = str(item.get("info", ""))
  if candidate.has_method("csm_get_latest_moc_version") and not info_path.is_empty() and FileAccess.file_exists(info_path):
    var inspection: Variant = JSON.parse_string(FileAccess.get_file_as_string(info_path))
    if inspection is Dictionary and typeof(inspection.get("moc_version")) in [TYPE_INT, TYPE_FLOAT]:
      var available_version: int = int(candidate.call("csm_get_latest_moc_version"))
      var required_version: int = int(inspection["moc_version"])
      if available_version > 0 and required_version > available_version:
        candidate.free()
        load_failed.emit("Модель MOC v%d требует более нового Cubism Core (доступно v%d)." % [required_version, available_version])
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
  _active_zones.clear()
  _physics_output_ids.clear()
  _unity_snapshot_parameters.clear()
  _unity_snapshot_parts.clear()
  if is_instance_valid(model):
    remove_child(model)
    model.free()
  model = null
  descriptor = item.duplicate(true)
  profile = resolved
  memory.reset()
  model = candidate as Node2D
  model.call("set_process_callback", 2) # MANUAL: bank owns interaction timing.
  model.call("set_parameter_mode", 0) # FULL_PARAMETER.
  add_child(model)
  model.call("set_assets", path)
  if int(model.call("csm_get_moc_version")) == 0:
    load_failed.emit("Cubism Core не смог прочитать MOC. Проверьте совместимость Core, MOC и gd_cubism.")
    remove_child(model)
    model.free()
    model = null
    return false
  var specs: Array = []
  for parameter: Variant in model.call("get_parameters"):
    if not parameter is Object: continue
    var id: String = str(parameter.call("get_id")) if parameter.has_method("get_id") else str(parameter.get("id"))
    if id.is_empty(): continue
    _parameters[id] = parameter
    var minimum: float = float(parameter.call("get_minimum_value")) if parameter.has_method("get_minimum_value") else float(parameter.get("minimum_value"))
    var maximum: float = float(parameter.call("get_maximum_value")) if parameter.has_method("get_maximum_value") else float(parameter.get("maximum_value"))
    var base: float = float(parameter.call("get_default_value")) if parameter.has_method("get_default_value") else float(parameter.get("default_value"))
    specs.append({"id":id,"min":minimum,"max":maximum,"default":base})
  bank.configure(specs)
  for part: Variant in model.call("get_part_opacities"):
    if not part is Object: continue
    var id: String = str(part.call("get_id")) if part.has_method("get_id") else str(part.get("id"))
    if id.is_empty(): continue
    _parts[id] = part
    part_values[id] = float(part.call("get_value")) if part.has_method("get_value") else float(part.get("value"))
    _part_defaults[id] = part_values[id]
  _load_unity_snapshot(str(item.get("snapshot", "")))
  var drawn: Variant = model.call("get_meshes")
  _meshes = drawn.duplicate() if drawn is Dictionary else {}
  var physics: Variant = profile.get("unity_inspection", {})
  if physics is Dictionary:
    var settings: Variant = physics.get("physics", {})
    if settings is Dictionary and settings.get("parameter_roles", {}) is Dictionary:
      for name: Variant in settings.get("parameter_roles", {}).get("output_ids", []):
        _physics_output_ids[str(name)] = true
  _build_interaction_zones()
  apply_palette()
  reset_character()
  _fit()
  model_loaded.emit(descriptor)
  return true


static func resolve_profile_for_model(item: Dictionary, common: Dictionary) -> Dictionary:
  var source: Variant = common.get("bindings", common)
  if not source is Dictionary: return {}
  var data: Dictionary = source.duplicate(true)
  var overrides: Variant = data.get("models", {})
  data.erase("models")
  if overrides is Dictionary:
    var source_id: String = str(item.get("source_id", ""))
    var item_id: String = str(item.get("id", ""))
    if source_id.is_empty() and not overrides.has(item_id) and not item_id.is_empty():
      # Legacy study_catalog.json uses a shorter ID than its exported MOC.
      # Match a single source variant only; never guess between two variants.
      var candidates: Array[String] = []
      for key: String in overrides:
        if key.begins_with(item_id + "__"):
          candidates.append(key)
      if candidates.size() == 1: source_id = candidates[0]
    for key: String in ["*", source_id, item_id]:
      if overrides.get(key) is Dictionary:
        data = _merge_profile(data, overrides[key])
  return data


static func _merge_profile(base: Dictionary, changes: Dictionary) -> Dictionary:
  var result: Dictionary = base.duplicate(true)
  for name: Variant in changes:
    var value: Variant = changes[name]
    if name == "zones" and value is Array and result.get(name) is Array:
      var merged: Array = result[name].duplicate(true)
      for zone: Variant in value:
        if not zone is Dictionary: continue
        var existing := -1
        for i in range(merged.size()):
          if merged[i] is Dictionary and str(merged[i].get("id", "")) == str(zone.get("id", "")):
            existing = i
            break
        if existing >= 0: merged[existing] = zone
        else: merged.append(zone)
      result[name] = merged
    elif value is Dictionary and result.get(name) is Dictionary:
      result[name] = _merge_profile(result[name], value)
    else:
      result[name] = value
  return result


func _build_interaction_zones() -> void:
  _active_zones.clear()
  _zone_meshes.clear()
  for value: Variant in profile.get("zones", []):
    if not value is Dictionary: continue
    var zone: Dictionary = value
    if bool(zone.get("disabled", false)): continue
    var scopes: Variant = zone.get("model_ids", [])
    if scopes is Array and not scopes.is_empty():
      if not scopes.has(str(descriptor.get("id", ""))) and not scopes.has(str(descriptor.get("source_id", ""))):
        continue
    var controls := false
    for field: String in ["x", "y", "move_x", "move_y"]:
      if bank.has_parameter(str(zone.get(field, ""))): controls = true
    var presses: Variant = zone.get("press", {})
    if presses is Dictionary:
      for id: String in presses:
        if bank.has_parameter(id): controls = true
    if not controls: continue
    var matching: Array[String] = []
    for mesh_id: String in _meshes:
      for pattern: Variant in zone.get("meshes", []):
        if mesh_id.match(str(pattern)):
          matching.append(mesh_id)
          break
    if matching.is_empty(): continue
    _zone_meshes[str(zone.get("id", ""))] = matching
    _active_zones.append(zone)
  _active_zones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
    return int(a.get("priority", 0)) > int(b.get("priority", 0)))


func get_active_zone_count() -> int:
  return _active_zones.size()


func _load_unity_snapshot(path: String) -> void:
  _unity_snapshot_parameters.clear()
  _unity_snapshot_parts.clear()
  if path.is_empty() or not FileAccess.file_exists(path): return
  var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
  if not data is Dictionary: return
  var parameters: Variant = data.get("effective_parameters", data.get("parameters", {}))
  if parameters is Dictionary:
    for id: String in parameters:
      if bank.has_parameter(id) and typeof(parameters[id]) in [TYPE_INT, TYPE_FLOAT]:
        var spec: Dictionary = bank.definitions[id]
        _unity_snapshot_parameters[id] = clampf(float(parameters[id]), float(spec.min), float(spec.max))
  var parts: Variant = data.get("effective_parts", data.get("parts", {}))
  if parts is Dictionary:
    for id: String in parts:
      if _parts.has(id) and typeof(parts[id]) in [TYPE_INT, TYPE_FLOAT]:
        _unity_snapshot_parts[id] = clampf(float(parts[id]), 0.0, 1.0)

func reset_character() -> void:
  release_grab(true)
  clip.stop()
  bank.reset()
  bank.set_targets(_supported_parameters(profile.get("initial", {})), "wardrobe", 5)
  # Each Unity instance can share a MOC yet preserve a distinct saved pose.
  bank.set_targets(_supported_parameters(_unity_snapshot_parameters), "unity_snapshot", 10)
  for id: String in part_values:
    part_values[id] = clampf(float(_unity_snapshot_parts.get(id, profile.get("parts", {}).get(id, _part_defaults[id]))),0.0,1.0)
  # Initial wardrobe must be visible on the first rendered frame.
  for id in bank.values: bank.values[id] = bank.target_for(id)
  _apply_parameters(0.016)

func apply_palette() -> void:
  for id: String in _meshes:
    # GDCubismUserModel.get_meshes() normally returns ArrayMesh resources,
    # not children named after drawables. Palette changes are only supported
    # where the backend actually exposes an individual MeshInstance2D.
    var mesh_node: MeshInstance2D = _meshes[id] as MeshInstance2D
    if not is_instance_valid(mesh_node): continue
    mesh_node.self_modulate = Color.WHITE
    for entry: Dictionary in profile.get("palette", []):
      for pattern: String in entry.get("meshes", []):
        if id.to_lower().match(pattern.to_lower()):
          mesh_node.self_modulate = Color(str(entry.get("color","ffffff")))

func choose_preset(group: String, title: String) -> void:
  var presets: Variant = profile.get(group, {})
  if not presets is Dictionary or not presets.get(title) is Dictionary: return
  bank.clear_channel("manual")
  bank.clear_channel("playback")
  if clip.playing: clip.stop()
  var values: Dictionary = presets[title].duplicate(true)
  if values.is_empty() and group != "outfits":
    reset_character()
    return
  if group == "outfits":
    var original: Variant = profile.get("initial", {})
    if original is Dictionary: values = original.merged(values, true)
    for id: String in _parts:
      part_values[id] = clampf(float(profile.get("parts", {}).get(id, _part_defaults[id])), 0.0, 1.0)
    if title == RIG_DEBUG_LABEL:
      var diagnostics: Variant = profile.get("rig_debug", {})
      var off: float = float(diagnostics.get("off_value", 0.0)) if diagnostics is Dictionary else 0.0
      for id: String in bank.definitions:
        if _is_clothes_switch(id): values[id] = off
      if diagnostics is Dictionary:
        if diagnostics.get("disable_parameters", {}) is Dictionary:
          values.merge(diagnostics["disable_parameters"], true)
        if diagnostics.get("disable_parts", {}) is Dictionary:
          for id: String in diagnostics["disable_parts"]:
            if part_values.has(id): part_values[id] = clampf(float(diagnostics["disable_parts"][id]), 0.0, 1.0)
  bank.set_targets(_supported_parameters(values), group, 20 if group == "poses" else 40)


func _is_clothes_switch(identifier: String) -> bool:
  var lower := identifier.to_lower()
  if not (lower.ends_with("enabled") or lower.ends_with("enable") or
      lower.ends_with("on") or lower.ends_with("visible") or lower.ends_with("show")):
    return false
  for word: String in CLOTHING_WORDS:
    if lower.contains(word): return true
  return false


func _supported_parameters(values: Variant) -> Dictionary:
  var supported: Dictionary = {}
  if not values is Dictionary: return supported
  for id: String in values:
    if bank.has_parameter(id) and typeof(values[id]) in [TYPE_FLOAT, TYPE_INT]:
      supported[id] = values[id]
  return supported

func _fit() -> void:
  if not is_instance_valid(model) or not model.has_method("get_canvas_info"): return
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
  if not is_instance_valid(model) or not model.has_method("advance"): return
  if model.has_method("set_physics_evaluate"):
    model.call("set_physics_evaluate", physics_enabled)
  for id: String in _parameters:
    if physics_enabled and _physics_output_ids.has(id): continue
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


func _refresh_meshes() -> void:
  # Native Cubism may replace deformation meshes after advance(). Keep hit
  # testing aligned with the currently displayed pose, not the load frame.
  if not is_instance_valid(model) or not model.has_method("get_meshes"): return
  var latest: Variant = model.call("get_meshes")
  if latest is Dictionary and not latest.is_empty():
    _meshes = latest.duplicate()


func hit_test(point: Vector2) -> Dictionary:
  if not is_instance_valid(model): return {}
  _refresh_meshes()
  # Source-scoped priority puts small mouth/eye/hand regions ahead of the
  # broad original arm and torso zones.
  for zone: Dictionary in _active_zones:
    var ids: Array = _zone_meshes.get(str(zone.get("id", "")), [])
    for id: String in ids:
      var value: Variant = _meshes.get(id)
      var owner: Node2D = model
      var mesh: Mesh = null
      if value is MeshInstance2D:
        var instance: MeshInstance2D = value
        if not is_instance_valid(instance) or instance.mesh == null: continue
        if not id.begins_with("HitArea") and (not instance.is_visible_in_tree() or instance.modulate.a <= 0.001):
          continue
        owner = instance
        mesh = instance.mesh
      elif value is Mesh:
        mesh = value
      if mesh == null or mesh.get_surface_count() == 0: continue
      var local: Vector2 = owner.to_local(get_global_transform() * point)
      var arrays: Array = mesh.surface_get_arrays(0)
      var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
      var indices: Variant = arrays[Mesh.ARRAY_INDEX]
      if not vertices is PackedVector2Array and not vertices is PackedVector3Array: continue
      if indices is PackedInt32Array and not indices.is_empty():
        for i in range(0, indices.size() - 2, 3):
          if point_in_triangle(local, _v2(vertices[indices[i]]), _v2(vertices[indices[i+1]]), _v2(vertices[indices[i+2]])):
            return zone
      else:
        for i in range(0, vertices.size() - 2, 3):
          if point_in_triangle(local, _v2(vertices[i]), _v2(vertices[i + 1]), _v2(vertices[i + 2])):
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
  _refresh_meshes()
  draw_rect(_bounds, Color(0.55,0.77,0.9,0.4), false)
  var drawn: Dictionary = {}
  for zone: Dictionary in _active_zones:
    for mesh_id: String in _zone_meshes.get(str(zone.get("id", "")), []):
      if drawn.has(mesh_id): continue
      drawn[mesh_id] = true
      var value: Variant = _meshes.get(mesh_id)
      var owner: Node2D = model
      var mesh: Mesh = null
      if value is MeshInstance2D:
        var instance: MeshInstance2D = value
        if not is_instance_valid(instance) or instance.mesh == null: continue
        owner = instance
        mesh = instance.mesh
      elif value is Mesh:
        mesh = value
      if mesh == null or mesh.get_surface_count() == 0: continue
      var arrays: Array = mesh.surface_get_arrays(0)
      var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
      if not vertices is PackedVector2Array and not vertices is PackedVector3Array: continue
      if vertices.is_empty(): continue
      var minimum: Vector2 = _v2(vertices[0])
      var maximum: Vector2 = minimum
      for vertex: Variant in vertices:
        var p: Vector2 = _v2(vertex)
        minimum = minimum.min(p)
        maximum = maximum.max(p)
      var first: Vector2 = get_global_transform().affine_inverse() * owner.to_global(minimum)
      var last: Vector2 = get_global_transform().affine_inverse() * owner.to_global(maximum)
      var rectangle: Rect2 = Rect2(first, last - first).abs()
      draw_rect(rectangle, Color(0.9, 0.62, 0.38, 0.48), false, 1.0)
