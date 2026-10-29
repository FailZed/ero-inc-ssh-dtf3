extends Control
signal profile_confirmed(full_name: String, stats: Dictionary)
signal profile_confirmed_v2(profile: Dictionary)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const GG = preload("res://scripts/characters/protagonist_live2d.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
var _layout_root: Control
var _profile: Dictionary = {}
var _labels: Dictionary = {}
var _body: VBoxContainer
var _portrait: GG
var _portrait_frame: Control
var _glass: Control
var _reflection: PanelContainer
var _settings: PanelContainer
var _model_error: Label
var _name: LineEdit
var _points: Label
var _confirm: Button
var _page := 0
var _stat_values := {}
var _stat_buttons := {}
var _budget := 5
var _tabs: HBoxContainer
var _zone := "body"
var _zoom := 1.0
var _pan := Vector2.ZERO
var _head_tilt := 0.0
var _dragging := false
var _model_ready := false
var _undo: Dictionary = {}
var _shape_sliders: Dictionary = {}
var _selection_overlay: Control
var _zone_buttons: Dictionary = {}
var _pick_meshes: Array[MeshInstance2D] = []
var _face_mesh: MeshInstance2D
var _hover_zone := ""
var _press_position := Vector2.ZERO
var _pointer_moved := false
var _touch_index := -1

func _ready() -> void:
	hide()
	theme = UI.skin()
	# A local MSDF font stays sharp when compensating the project canvas scale.
	var mirror_font := theme.default_font.duplicate() as FontFile
	mirror_font.multichannel_signed_distance_field = true
	theme.default_font = mirror_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_root = Control.new()
	_layout_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layout_root)
	UI.background(_layout_root, "res://assets/textures/backgrounds/location_pack_v1/bathroom_night.png", 0.18)
	_reflection = PanelContainer.new()
	_reflection.add_theme_stylebox_override("panel", UI.surface(8))
	_layout_root.add_child(_reflection)
	_glass = Control.new()
	_glass.clip_contents = true
	_glass.mouse_filter = Control.MOUSE_FILTER_PASS
	_reflection.add_child(_glass)
	var tint := ColorRect.new()
	tint.color = Color(0.13, 0.28, 0.36, 0.24)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.add_child(tint)
	_portrait_frame = Control.new()
	_portrait_frame.clip_contents = true
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.add_child(_portrait_frame)
	_place(_portrait_frame, 0.04, 0.20, 0.76, 0.86)
	_portrait = GG.new()
	_portrait.name = "GG_Reflection"
	_portrait_frame.add_child(_portrait)
	var sheen := ColorRect.new()
	sheen.color = Color(0.75, 0.88, 0.94, 0.035)
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.z_index = 999
	_glass.add_child(sheen)
	_glass.gui_input.connect(_glass_input)
	_glass.resized.connect(_refresh_framing)
	_portrait_frame.resized.connect(_refresh_framing)
	_glass.mouse_exited.connect(func(): _hover_zone = ""; _selection_overlay.queue_redraw())
	_selection_overlay = Control.new()
	_selection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_overlay.z_index = 999
	_glass.add_child(_selection_overlay)
	_selection_overlay.draw.connect(_draw_selection)
	var reflection_title := UI.label(_glass, "ГГ  ·  ОТРАЖЕНИЕ", 20)
	_place(reflection_title, 0.04, 0.02, 0.72, 0.10)
	reflection_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reflection_title.z_index = 1000
	var study_note := UI.label(_glass, "Временная женская основа · пол в профиле", 13, UI.MUTED)
	_place(study_note, 0.04, 0.09, 0.74, 0.15)
	study_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	study_note.z_index = 1000
	var gesture_note := UI.label(_glass, "Лицо/тело: нажмите · вид: тяните", 13, UI.MUTED)
	_place(gesture_note, 0.04, 0.14, 0.74, 0.18)
	gesture_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gesture_note.z_index = 1000
	for spec in [["face", "Лицо", 0.20], ["body", "Тело", 0.35], ["", "Обзор", 0.50]]:
		var button := UI.button(_glass, spec[1], _select_zone.bind(spec[0]))
		_place(button, 0.78, spec[2], 0.96, spec[2] + 0.08)
		button.custom_minimum_size.y = 44
		button.z_index = 1000
		button.toggle_mode = true
		_zone_buttons[spec[0]] = button
	var zoom_row := UI.row(_glass, 8)
	_place(zoom_row, 0.04, 0.89, 0.72, 0.97)
	zoom_row.z_index = 1000
	UI.button(zoom_row, "−", _change_zoom.bind(-0.15))
	UI.button(zoom_row, "+", _change_zoom.bind(0.15))
	UI.button(zoom_row, "Сбросить вид", _reset_camera)
	_model_error = UI.label(_glass, "", 18, UI.ORANGE)
	_place(_model_error, 0.04, 0.70, 0.72, 0.86)
	_model_error.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_model_error.z_index = 1000
	_model_error.hide()
	_settings = PanelContainer.new()
	_settings.add_theme_stylebox_override("panel", UI.surface(24))
	_layout_root.add_child(_settings)
	var content := UI.column(_settings, 12)
	UI.label(content, "СОЗДАТЬ ГГ", 30)
	_tabs = UI.row(content)
	_body = UI.scroller(content)
	_points = UI.label(content, "", 20, UI.BLUE)
	_confirm = UI.button(content, "ЭТО Я  →", _confirm_profile)
	_confirm.custom_minimum_size.y = 58
	resized.connect(_layout)
	_layout()
	_build_page()

func _place(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0

func _layout() -> void:
	if not is_instance_valid(_reflection) or not is_instance_valid(_settings): return
	# The project stretches a 1920px canvas. Keep this modal's controls legible
	# when the actual window is smaller, without changing the game's viewport.
	var viewport_scale: float = get_viewport().get_final_transform().get_scale().x
	var compensation: float = 1.0 / minf(1.0, maxf(viewport_scale, 0.1))
	_layout_root.scale = Vector2.ONE * compensation
	_layout_root.size = size / compensation
	var available: Vector2 = _layout_root.size
	if available.x < available.y * 1.15:
		_place(_reflection, 0.04, 0.025, 0.96, 0.46)
		_place(_settings, 0.04, 0.49, 0.96, 0.975)
	else:
		_place(_reflection, 0.035, 0.05, 0.565, 0.95)
		_place(_settings, 0.59, 0.05, 0.965, 0.95)
	_refresh_framing.call_deferred()

func _refresh_framing() -> void:
	if _model_ready and is_instance_valid(_portrait) and is_instance_valid(_portrait_frame):
		var face := _zone == "face"
		_place(_portrait_frame, 0.04, 0.20, 0.76, 0.72 if face else 0.86)
		var framing_size := Vector2(_portrait_frame.size.x, _glass.size.y * 0.66) if face else _portrait_frame.size
		var body_zoom := 1.25 if not face and _glass.size.y < 500.0 else 1.0
		_portrait.set_framing("face" if face else "body", framing_size, _zoom * body_zoom, _pan, _head_tilt)
	if is_instance_valid(_selection_overlay): _selection_overlay.queue_redraw()

func _select_zone(zone: String) -> void:
	_page = 0
	_zone = zone
	_hover_zone = ""
	_dragging = false
	_reset_camera()
	_build_page()

func _change_zoom(amount: float) -> void:
	_zoom = clampf(_zoom + amount, 0.75, 1.75)
	_refresh_framing()

func _reset_camera() -> void:
	_dragging = false
	_touch_index = -1
	_zoom = 1.0
	_pan = Vector2.ZERO
	_head_tilt = 0.0
	_refresh_framing()

func _glass_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer(event.position)
		_glass.accept_event()
	elif event is InputEventMouseMotion:
		if _dragging and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_pointer(event.position, event.relative)
		else:
			_dragging = false
			_hover_zone = _pick_zone(event.position)
			_glass.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _hover_zone.is_empty() else Control.CURSOR_ARROW
			_selection_overlay.queue_redraw()
	elif event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_begin_pointer(event.position)
		elif not event.pressed and event.index == _touch_index:
			_end_pointer(event.position)
			_touch_index = -1
		_glass.accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_move_pointer(event.position, event.relative)
		_glass.accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_change_zoom(0.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1)
		_glass.accept_event()

func _begin_pointer(point: Vector2) -> void:
	_dragging = true
	_pointer_moved = false
	_press_position = point

func _move_pointer(point: Vector2, delta: Vector2) -> void:
	if not _dragging: return
	if not _pointer_moved and point.distance_to(_press_position) < 6.0: return
	if not _pointer_moved: delta = point - _press_position
	_pointer_moved = true
	_hover_zone = ""
	_pan = (_pan + delta).clamp(-_glass.size * 0.3, _glass.size * 0.3)
	_refresh_framing()

func _end_pointer(point: Vector2) -> void:
	var clicked := _dragging and not _pointer_moved and point.distance_to(_press_position) < 6.0
	_dragging = false
	if clicked:
		var selected := _pick_zone(point)
		if not selected.is_empty(): _select_zone(selected)

func _cache_pick_meshes() -> void:
	_pick_meshes.clear()
	_face_mesh = null
	var meshes: Dictionary = _portrait.get_actor().get_drawable_meshes()
	for id in meshes:
		var node: Variant = meshes[id]
		if node is MeshInstance2D:
			_pick_meshes.append(node)
			if id == "SkinFace": _face_mesh = node

func _mesh_points(node: MeshInstance2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	if not is_instance_valid(node) or not node.is_visible_in_tree() or node.modulate.a * node.self_modulate.a < 0.05 or node.mesh == null or node.mesh.get_surface_count() == 0: return points
	var transform := _glass.get_global_transform().affine_inverse() * node.get_global_transform()
	for vertex in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		points.append(transform * Vector2(vertex.x, vertex.y))
	return points

func _points_rect(points: PackedVector2Array) -> Rect2:
	if points.is_empty(): return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	return bounds

func _face_bottom() -> float:
	var face := _points_rect(_mesh_points(_face_mesh))
	return face.end.y

func _pick_zone(point: Vector2) -> String:
	if not _model_ready or not _portrait_frame.get_rect().has_point(point): return ""
	# Hit the current deformed triangles, so blank glass and gaps are not buttons.
	for node in _pick_meshes:
		var points := _mesh_points(node)
		if points.is_empty() or not _points_rect(points).has_point(point): continue
		var indices: PackedInt32Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		for index in range(0, indices.size() - 2, 3):
			var triangle := PackedVector2Array([points[indices[index]], points[indices[index + 1]], points[indices[index + 2]]])
			if Geometry2D.is_point_in_polygon(point, triangle):
				return "face" if point.y <= _face_bottom() else "body"
	return ""

func _draw_selection() -> void:
	if not _model_ready: return
	if _glass.size.x <= 6.0 or _glass.size.y <= 4.0: return
	var selected := _hover_zone if not _hover_zone.is_empty() else _zone
	if selected.is_empty(): return
	var face_bottom := _face_bottom()
	var bounds := Rect2()
	var found := false
	for node in _pick_meshes:
		for point in _mesh_points(node):
			if (selected == "face") != (point.y <= face_bottom): continue
			bounds = bounds.expand(point) if found else Rect2(point, Vector2.ZERO)
			found = true
	if not found: return
	# Match the visible clipped portrait; the border must not cross captions or controls.
	var selection_area := _portrait_frame.get_rect().grow(-3.0)
	bounds = bounds.grow(6.0).intersection(selection_area)
	if not bounds.has_area(): return
	_selection_overlay.draw_rect(bounds, Color(UI.BLUE, 0.035), true)
	_selection_overlay.draw_rect(bounds, Color(UI.BLUE, 0.85), false, 1.5)

func open_with_profile(profile: Dictionary, stat_labels: Dictionary, _texts: Dictionary, _appearance_options: Dictionary) -> void:
	_profile = profile.duplicate(true)
	_labels = stat_labels.duplicate(true)
	_budget = Gameplay.creation_budget()
	_profile.rules.bonus_points = _budget
	_profile.rules.min_stat = 5
	if str(_profile.identity.full_name).is_empty(): _profile.identity.full_name = GameSession.get_default_character_full_name()
	_page = 0
	_zone = "body"
	_reset_camera()
	_undo.clear()
	_model_ready = _portrait.is_model_loaded() or _portrait.load_gg()
	if _model_ready: _cache_pick_meshes()
	_model_error.text = "Не удалось открыть Live2D-модель ГГ: " + str(_portrait.last_error) if not _model_ready else ""
	_model_error.visible = not _model_ready
	if _model_ready:
		var appearance: Dictionary = _profile.appearance.get("live2d", _portrait.get_appearance())
		if not _portrait.apply_appearance(appearance):
			_model_ready = false
			_model_error.text = "Не удалось применить внешность ГГ: " + str(_portrait.last_error)
			_model_error.show()
		else: _profile.appearance["live2d"] = _portrait.get_appearance()
	_build_page()
	show()
	_refresh_framing.call_deferred()
	UI.focus_loop(self)
	_confirm.grab_focus()

func _build_page() -> void:
	for zone in _zone_buttons: _zone_buttons[zone].set_pressed_no_signal(zone == _zone)
	UI.clear(_body)
	UI.clear(_tabs)
	W.tabs(_tabs,{"look":"Внешность","character":"Имя и характер"},"look" if _page == 0 else "character",func(id): _select_page(0 if id == "look" else 1))
	_stat_values.clear()
	_stat_buttons.clear()
	_shape_sliders.clear()
	if _page == 0:
		_build_appearance()
	else:
		UI.label(_body, "Как меня зовут", 26, UI.BLUE)
		_name = LineEdit.new()
		_name.text = str(_profile.identity.full_name)
		_name.max_length = 48
		_name.custom_minimum_size.y = 52
		_name.text_changed.connect(func(v): _profile.identity.full_name = v; _refresh())
		_body.add_child(_name)
		var gender_row := UI.row(_body, 10)
		UI.label(gender_row, "Пол персонажа", 19, UI.MUTED)
		var gender := OptionButton.new()
		gender.custom_minimum_size = Vector2(150, 48)
		gender.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gender_row.add_child(gender)
		for spec in [["male", "Мужской"], ["female", "Женский"]]:
			gender.add_item(spec[1])
			gender.set_item_metadata(gender.item_count - 1, spec[0])
			if str(_profile.appearance.gender) == spec[0]: gender.select(gender.item_count - 1)
		gender.item_selected.connect(func(index): _set_gender(str(gender.get_item_metadata(index))))
		UI.label(_body, "Live2D-отражение пока использует временную женскую основу независимо от выбора пола.", 16, UI.MUTED)
		UI.label(_body, "С чего начинается мой путь", 26, UI.BLUE)
		for id in GameSession.CHARACTER_STAT_KEYS:
			var row := UI.row(_body)
			UI.label(row, str(_labels.get(id, id)), 20)
			var minus := UI.button(row, "−", _change_stat.bind(id, -1))
			_stat_values[id] = UI.label(row, "", 24, UI.BLUE)
			(_stat_values[id] as Label).custom_minimum_size.x = 40
			(_stat_values[id] as Label).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			var plus := UI.button(row, "+", _change_stat.bind(id, 1))
			_stat_buttons[id] = [minus, plus]
		UI.label(_body, "Очки можно оставить на потом. Развивать навыки и остальные качества вы сможете в городе.", 18, UI.MUTED)
	_refresh()
	if visible: UI.focus_loop(self)

func _select_page(page: int) -> void:
	_page = page
	_build_page()

func _build_appearance() -> void:
	UI.label(_body, "Отражение", 26, UI.BLUE)
	if _zone.is_empty():
		UI.label(_body, "Выберите лицо или тело на зеркале. Изменения сразу видны в отражении.", 19, UI.MUTED)
		return
	UI.label(_body, "Лицо · крупный план" if _zone == "face" else "Тело · фигура и одежда", 22)
	if _zone == "face":
		UI.label(_body, "Приблизьте и поверните отражение. Форма лица и причёска этой Live2D-модели пока не меняются; цвета можно выбрать ниже.", 18, UI.MUTED)
		UI.label(_body, "Наклон головы · только просмотр", 18, UI.MUTED)
		var tilt := HSlider.new()
		tilt.min_value = -1.0
		tilt.max_value = 1.0
		tilt.step = 0.05
		tilt.value = _head_tilt
		tilt.custom_minimum_size.y = 44
		_body.add_child(tilt)
		tilt.value_changed.connect(func(value): _head_tilt = value; _refresh_framing())
		_build_palette(["skin", "hair", "eyes"])
		_appearance_actions()
		return
	if not _model_ready:
		UI.label(_body, "Параметры появятся после загрузки модели.", 18, UI.ORANGE)
		return
	var controls: Dictionary = _portrait.get_controls()
	for group in controls.get("groups", []):
		if str(group.get("id", "")) != "body": continue
		UI.label(_body, str(group.get("title", "Телосложение")), 20, UI.MUTED)
		for spec in group.get("controls", []):
			var id := str(spec.id)
			var row := UI.row(_body, 10)
			UI.label(row, str(spec.title), 18)
			var slider := HSlider.new()
			slider.min_value = float(spec.minimum)
			slider.max_value = float(spec.maximum)
			slider.step = float(spec.get("step", 0.05))
			slider.value = float(_profile.appearance.live2d.shape.get(id, spec.default))
			slider.custom_minimum_size = Vector2(120, 40)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(slider)
			slider.value_changed.connect(_set_shape.bind(id))
			_shape_sliders[id] = slider
	var outfit_row: BoxContainer = UI.column(_body, 4) if _settings.size.x < 600.0 else UI.row(_body, 10)
	UI.label(outfit_row, "Одежда", 18)
	var outfit := OptionButton.new()
	outfit.custom_minimum_size = Vector2(160, 44)
	outfit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outfit_row.add_child(outfit)
	for spec in controls.get("outfits", []):
		outfit.add_item(str(spec.title))
		outfit.set_item_metadata(outfit.item_count - 1, str(spec.id))
		if str(spec.id) == str(_profile.appearance.live2d.outfit): outfit.select(outfit.item_count - 1)
	outfit.item_selected.connect(func(index): _set_outfit(str(outfit.get_item_metadata(index))))
	_build_palette(["skin", "top", "bottom"])
	_appearance_actions()

func _appearance_actions() -> void:
	var actions: BoxContainer = UI.column(_body, 8) if _settings.size.x < 600.0 else UI.row(_body, 8)
	var undo := UI.button(actions, "Отменить изменение", _undo_appearance)
	undo.disabled = _undo.is_empty()
	UI.button(actions, "Сбросить", _reset_appearance)
	UI.button(actions, "Случайно", _randomize_appearance)
	UI.label(_body, "Доступны только изменения, которые действительно поддерживает эта модель.", 16, UI.MUTED)

func _build_palette(allowed: Array) -> void:
	if not _model_ready: return
	var controls: Dictionary = _portrait.get_controls()
	UI.label(_body, "Цвета", 20, UI.MUTED)
	for group in controls.get("palette_groups", []):
		var group_id := str(group.get("id", ""))
		if not group_id in allowed: continue
		var row := UI.row(_body, 10)
		UI.label(row, str(group.get("title", group_id)), 18)
		var selector := OptionButton.new()
		selector.custom_minimum_size = Vector2(150, 44)
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(selector)
		for option in group.get("options", []):
			selector.add_item(str(option.title))
			selector.set_item_metadata(selector.item_count - 1, str(option.id))
			if str(option.id) == str(_profile.appearance.live2d.palette.get(group_id, group.default)):
				selector.select(selector.item_count - 1)
		selector.item_selected.connect(_palette_selected.bind(group_id, selector))

func _palette_selected(index: int, group_id: String, selector: OptionButton) -> void:
	_set_palette(group_id, str(selector.get_item_metadata(index)))

func _current_live2d() -> Dictionary:
	return _profile.appearance.get("live2d", {}).duplicate(true)

func _set_gender(value: String) -> void:
	if value not in ["male", "female"] or str(_profile.appearance.gender) == value: return
	_profile.appearance.gender = value
	_profile.appearance.genital_type = "penis" if value == "male" else "vulva"
	_profile.appearance.genital_size = "average" if value == "male" else "full"

func _set_shape(value: float, id: String) -> void:
	if not _model_ready: return
	var previous := _current_live2d()
	var update := previous.duplicate(true)
	update.shape[id] = value
	if _portrait.apply_appearance(update):
		_undo = previous
		_profile.appearance["live2d"] = _portrait.get_appearance()
		_refresh_undo_button()
		_selection_overlay.queue_redraw()

func _set_outfit(id: String) -> void:
	if not _model_ready: return
	var previous := _current_live2d()
	var update := previous.duplicate(true)
	update.outfit = id
	if _portrait.apply_appearance(update):
		_undo = previous
		_profile.appearance["live2d"] = _portrait.get_appearance()
		_refresh_undo_button()
		_selection_overlay.queue_redraw()

func _set_palette(group_id: String, option_id: String) -> void:
	if not _model_ready: return
	var previous := _current_live2d()
	var update := previous.duplicate(true)
	update.palette[group_id] = option_id
	if _portrait.apply_appearance(update):
		_undo = previous
		_profile.appearance["live2d"] = _portrait.get_appearance()
		_refresh_undo_button()
		_selection_overlay.queue_redraw()

func _reset_appearance() -> void:
	if not _model_ready: return
	_undo = _current_live2d()
	_profile.appearance["live2d"] = _portrait.reset_appearance()
	_build_page()

func _randomize_appearance() -> void:
	if not _model_ready: return
	_undo = _current_live2d()
	_profile.appearance["live2d"] = _portrait.randomize_appearance(Time.get_ticks_usec())
	_build_page()

func _undo_appearance() -> void:
	if _undo.is_empty() or not _model_ready: return
	if _portrait.apply_appearance(_undo):
		_profile.appearance["live2d"] = _portrait.get_appearance()
		_undo.clear()
		_build_page()

func _refresh_undo_button() -> void:
	for button in _body.find_children("*", "Button", true, false):
		if button.text == "Отменить изменение": button.disabled = _undo.is_empty()

func _remaining() -> int:
	var spent := 0
	for id in GameSession.CHARACTER_STAT_KEYS: spent += int(_profile.stats[id]) - 5
	return _budget - spent

func _change_stat(id: String, amount: int) -> void:
	var next := int(_profile.stats[id]) + amount
	if next < 5 or next > 30 or (amount > 0 and _remaining() <= 0): return
	_profile.stats[id] = next
	_refresh()

func _refresh() -> void:
	if _profile.is_empty():
		_confirm.disabled = true
		return
	_points.text = "Очков осталось: %d" % _remaining()
	for id in _stat_values:
		_stat_values[id].text = str(_profile.stats[id])
		_stat_buttons[id][0].disabled = int(_profile.stats[id]) <= 5
		_stat_buttons[id][1].disabled = _remaining() <= 0 or int(_profile.stats[id]) >= 30
	_confirm.disabled = not _model_ready or str(_profile.identity.full_name).strip_edges().is_empty() or _remaining() < 0

func _confirm_profile() -> void:
	if _confirm.disabled: return
	_profile.identity.full_name = str(_profile.identity.full_name).strip_edges()
	profile_confirmed.emit(_profile.identity.full_name, _profile.stats.duplicate(true))
	profile_confirmed_v2.emit(_profile.duplicate(true))

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _dragging:
			_dragging = false
		elif _page == 1:
			_page = 0
			_zone = ""
			_build_page()
			_refresh_framing()
		elif not _zone.is_empty():
			_select_zone("")
