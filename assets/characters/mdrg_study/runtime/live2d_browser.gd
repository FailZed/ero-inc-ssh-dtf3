extends Control
## A small inspection scene for models imported by unity_to_godot.py.
## The native plugin is accessed by live2d_actor.gd; this UI also opens without it.

const ACTOR_SCRIPT = preload("live2d_actor.gd")
const POINTER_SCRIPT = preload("live2d_pointer.gd")
const RIG_DEBUG_LABEL := "Без одежды (проверка рига)"

@export_file("*.json") var catalog_path: String = "res://live2d_import/catalog.json"

var _catalog: Dictionary = {}
var _models: Array = []
var _current: Dictionary = {}
var _actor: Node2D
var _pointer: RefCounted
var _active_profile: Dictionary = {}
var _model_ready: bool = false
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _panning: bool = false
var _pointer_dragging: bool = false
var _poll_time: float = 0.0

var _model_select: OptionButton
var _motion_select: OptionButton
var _expression_select: OptionButton
var _profile_expression_select: OptionButton
var _profile_pose_select: OptionButton
var _outfit_select: OptionButton
var _motion_button: Button
var _expression_button: Button
var _profile_expression_button: Button
var _profile_pose_button: Button
var _outfit_button: Button
var _reset_button: Button
var _stop_button: Button
var _physics: CheckButton
var _pose: CheckButton
var _zoom_slider: HSlider
var _canvas: Control
var _empty: Label
var _status: Label
var _summary: Label
var _variant_label: Label
var _parameter_list: VBoxContainer
var _part_list: VBoxContainer
var _filter: LineEdit
var _report_dialog: AcceptDialog
var _report_text: TextEdit
var _parameter_sliders: Dictionary = {}
var _part_sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _inspector_rows: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_actor = ACTOR_SCRIPT.new() as Node2D
	_pointer = POINTER_SCRIPT.new()
	# A browser chooses its entry explicitly; do not trigger the actor's scene autoload.
	_actor.set("catalog_path", "")
	_actor.set("model_id", "")
	_actor.connect("runtime_error", _on_runtime_error)
	_actor.connect("model_loaded", _on_model_loaded)
	if _actor.has_signal("motion_event"):
		_actor.connect("motion_event", _on_motion_event)
	_canvas.add_child(_actor)
	_load_catalog()
	set_process(true)


func _process(delta: float) -> void:
	if not _model_ready:
		return
	_poll_time += delta
	if _poll_time < 0.12:
		return
	_poll_time = 0.0
	_sync_live_values()


func _style(background: Color, border: Color = Color.TRANSPARENT, radius: int = 10) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box


func _label(text: String, font_size: int = 14, color: Color = Color("d8dfe9")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 35
	button.pressed.connect(callback)
	return button


func _section(text: String, parent: VBoxContainer) -> void:
	var label := _label(text, 12, Color("8798ad"))
	label.add_theme_constant_override("outline_size", 0)
	parent.add_child(label)


func _selector(parent: VBoxContainer) -> OptionButton:
	var select := OptionButton.new()
	select.custom_minimum_size.y = 36
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.fit_to_longest_item = false
	select.clip_text = true
	parent.add_child(select)
	return select


func _scroll_list(parent: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


func _build_ui() -> void:
	var theme_value := Theme.new()
	theme_value.default_font_size = 14
	theme_value.set_color("font_color", "Label", Color("d8dfe9"))
	theme_value.set_color("font_color", "Button", Color("e5edf7"))
	theme_value.set_color("font_disabled_color", "Button", Color("64748b"))
	theme_value.set_stylebox("normal", "Button", _style(Color("1e2b3d"), Color("30415a"), 6))
	theme_value.set_stylebox("hover", "Button", _style(Color("2b3c54"), Color("75a9ef"), 6))
	theme_value.set_stylebox("pressed", "Button", _style(Color("203d61"), Color("78b2ff"), 6))
	theme_value.set_stylebox("disabled", "Button", _style(Color("172130"), Color("243247"), 6))
	theme_value.set_stylebox("normal", "LineEdit", _style(Color("121c2a"), Color("30415a"), 6))
	theme_value.set_color("font_color", "LineEdit", Color("e5edf7"))
	theme_value.set_color("font_placeholder_color", "LineEdit", Color("7c8ca3"))
	theme = theme_value
	var background := ColorRect.new()
	background.color = Color("0c1320")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 15)
	root.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	heading.add_child(_label("Live2D · Модели и варианты", 23, Color("f0f5fc")))
	_summary = _label("Загрузка каталога…", 13, Color("92a3b9"))
	heading.add_child(_summary)
	header.add_child(_button("Отчёт импорта", _show_report))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 240
	left_panel.add_theme_stylebox_override("panel", _style(Color("141f2e"), Color("27354b")))
	columns.add_child(left_panel)
	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(left_scroll)
	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 10)
	left_scroll.add_child(actions)
	_section("МОДЕЛЬ / ВАРИАНТ", actions)
	_model_select = _selector(actions)
	_model_select.item_selected.connect(_select_model)
	_variant_label = _label("", 11, Color("8c9eb6"))
	_variant_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_variant_label.custom_minimum_size.y = 40
	actions.add_child(_variant_label)
	actions.add_child(HSeparator.new())
	_section("АНИМАЦИЯ", actions)
	_motion_select = _selector(actions)
	_motion_button = _button("Воспроизвести", _play_motion)
	actions.add_child(_motion_button)
	_stop_button = _button("Остановить анимацию", _stop_motion)
	actions.add_child(_stop_button)
	_section("ВЫРАЖЕНИЕ", actions)
	_expression_select = _selector(actions)
	_expression_button = _button("Применить выражение", _play_expression)
	actions.add_child(_expression_button)
	_section("ЭМОЦИИ ПРОФИЛЯ", actions)
	_profile_expression_select = _selector(actions)
	_profile_expression_button = _button("Применить эмоцию", _apply_profile_expression)
	actions.add_child(_profile_expression_button)
	_section("ПОЗЫ ПРОФИЛЯ", actions)
	_profile_pose_select = _selector(actions)
	_profile_pose_button = _button("Применить позу", _apply_profile_pose)
	actions.add_child(_profile_pose_button)
	_section("ОДЕЖДА / ТЕСТ РИГА", actions)
	_outfit_select = _selector(actions)
	_outfit_button = _button("Применить набор", _apply_outfit_preset)
	actions.add_child(_outfit_button)
	_reset_button = _button("Исходная поза", _reset_pose)
	actions.add_child(_reset_button)
	actions.add_child(HSeparator.new())
	_physics = CheckButton.new()
	_physics.text = "Физика"
	_physics.toggled.connect(_toggle_physics)
	actions.add_child(_physics)
	_pose = CheckButton.new()
	_pose.text = "Группы видимости Pose"
	_pose.toggled.connect(_toggle_pose)
	actions.add_child(_pose)
	var note := _label("Изменяйте параметры справа. «Исходная поза» возвращает сохранённое состояние варианта.", 12, Color("91a2b8"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(note)
	var stage_panel := PanelContainer.new()
	stage_panel.add_theme_stylebox_override("panel", _style(Color("101925"), Color("2a3a51")))
	stage_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_panel.custom_minimum_size.x = 200
	columns.add_child(stage_panel)
	var stage_layout := VBoxContainer.new()
	stage_layout.add_theme_constant_override("separation", 10)
	stage_panel.add_child(stage_layout)
	_canvas = Control.new()
	_canvas.name = "ModelCanvas"
	_canvas.clip_contents = true
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.tooltip_text = "Колесо: масштаб. Средняя кнопка: перемещение. Левая кнопка: взаимодействие с моделью."
	_canvas.gui_input.connect(_canvas_input)
	_canvas.resized.connect(_fit_view)
	stage_layout.add_child(_canvas)
	_empty = _label("Выберите модель", 17, Color("91a4be"))
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_empty)
	var view_controls := HBoxContainer.new()
	view_controls.add_theme_constant_override("separation", 10)
	stage_layout.add_child(view_controls)
	view_controls.add_child(_label("Масштаб", 12, Color("9dafc7")))
	_zoom_slider = HSlider.new()
	_zoom_slider.min_value = 0.2
	_zoom_slider.max_value = 3.0
	_zoom_slider.step = 0.02
	_zoom_slider.value = 1.0
	_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zoom_slider.value_changed.connect(_set_zoom)
	view_controls.add_child(_zoom_slider)
	view_controls.add_child(_button("По размеру", _reset_view))
	var inspector_panel := PanelContainer.new()
	inspector_panel.custom_minimum_size.x = 285
	inspector_panel.add_theme_stylebox_override("panel", _style(Color("141f2e"), Color("27354b")))
	columns.add_child(inspector_panel)
	var inspector := VBoxContainer.new()
	inspector.add_theme_constant_override("separation", 12)
	inspector_panel.add_child(inspector)
	_section("ПАРАМЕТРЫ И ЧАСТИ", inspector)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Поиск по ID…"
	_filter.text_changed.connect(_filter_rows)
	inspector.add_child(_filter)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.add_child(tabs)
	_parameter_list = _scroll_list(tabs, "Параметры")
	_part_list = _scroll_list(tabs, "Части")
	_status = _label("", 13, Color("91a2b8"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 38
	root.add_child(_status)
	_report_dialog = AcceptDialog.new()
	_report_dialog.title = "Отчёт импорта"
	_report_dialog.min_size = Vector2i(680, 440)
	_report_dialog.ok_button_text = "Закрыть"
	_report_text = TextEdit.new()
	_report_text.editable = false
	_report_text.custom_minimum_size = Vector2(650, 400)
	_report_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_report_dialog.add_child(_report_text)
	add_child(_report_dialog)
	_set_controls_enabled(false)


func _read_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if parser.data is Dictionary:
		return parser.data as Dictionary
	return {}


func _load_catalog() -> void:
	_catalog = _read_dictionary(catalog_path)
	var entries: Variant = _catalog.get("models", [])
	_models = entries if entries is Array else []
	_model_select.clear()
	for index in range(_models.size()):
		if not _models[index] is Dictionary:
			_model_select.add_item("Некорректная запись %d" % index)
			_model_select.set_item_disabled(index, true)
			continue
		var entry: Dictionary = _models[index]
		var identifier: String = str(entry.get("id", index))
		var display_name: String = str(entry.get("name", identifier))
		_model_select.add_item("%s · %s" % [display_name, identifier.right(8)])
		_model_select.set_item_tooltip(index, identifier)
	_summary.text = "В каталоге: %d. Данные анимаций и варианты сохраняются раздельно." % _models.size()
	if _models.is_empty():
		_empty.text = "В каталоге нет готовых моделей.\nПроверьте отчёт импорта."
		_model_select.disabled = true
		_set_status("Каталог пуст или недоступен: %s" % catalog_path, true)
		return
	for index in range(_models.size()):
		if _models[index] is Dictionary:
			_model_select.select(index)
			_select_model(index)
			return


func _select_model(index: int) -> void:
	if index < 0 or index >= _models.size() or not _models[index] is Dictionary:
		return
	_current = _models[index] as Dictionary
	_model_ready = false
	_pointer_dragging = false
	if _pointer != null:
		_pointer.call("release")
	_set_controls_enabled(false)
	_empty.show()
	_empty.text = "Загрузка модели…"
	_variant_label.text = str(_current.get("id", ""))
	_reset_view()
	_fill_asset_selectors()
	_profile_expression_select.clear()
	_profile_pose_select.clear()
	_outfit_select.clear()
	_build_inspector(false)
	_set_status("Открываю %s…" % str(_current.get("name", _current.get("id", "модель"))))
	var loaded: bool = bool(_actor.call("load_model", _current))
	if not loaded:
		_empty.text = "Модель пока не отображается.\nПричина указана внизу окна."


func _fill_asset_selectors() -> void:
	_motion_select.clear()
	_expression_select.clear()
	var motions: Variant = _current.get("motions", [])
	if motions is Array:
		for motion in motions:
			if not motion is Dictionary:
				continue
			var name_value: String = str(motion.get("name", str(motion.get("file", "")).get_file()))
			if name_value.is_empty():
				name_value = "Анимация %d" % int(motion.get("index", 0))
			name_value = str(motion.get("group", "Imported")) + " / " + name_value
			if not bool(motion.get("complete", false)):
				name_value += " [частично]"
			_motion_select.add_item(name_value)
			_motion_select.set_item_metadata(_motion_select.item_count - 1, motion)
	if _motion_select.item_count == 0:
		_motion_select.add_item("Нет подключённых анимаций")
	var expressions: Variant = _current.get("expressions", [])
	if expressions is Array:
		for expression in expressions:
			if not expression is Dictionary:
				continue
			_expression_select.add_item(str(expression.get("name", "Выражение")))
			_expression_select.set_item_metadata(_expression_select.item_count - 1, expression)
	if _expression_select.item_count == 0:
		_expression_select.add_item("Нет подключённых выражений")


func _on_model_loaded(identifier: String) -> void:
	if identifier != str(_current.get("id", "")):
		return
	_model_ready = true
	var shared_path: String = str(_catalog.get("interaction_profile", ""))
	if shared_path.is_empty():
		shared_path = str(_current.get("workshop_profile", ""))
	_active_profile = _read_dictionary(shared_path)
	_pointer.call("configure", _actor, _active_profile, str(_current.get("id", "")))
	_fill_profile_presets()
	_fill_outfit_selector()
	_empty.hide()
	_build_inspector(true)
	_set_controls_enabled(true)
	var model_data := _read_dictionary(str(_current.get("model3", "")))
	var references: Dictionary = model_data.get("FileReferences", {}) as Dictionary
	_physics.set_pressed_no_signal(references.has("Physics"))
	_pose.set_pressed_no_signal(references.has("Pose"))
	_physics.disabled = not references.has("Physics")
	_pose.disabled = not references.has("Pose")
	_actor.call("set_physics_enabled", _physics.button_pressed)
	_actor.call("set_pose_enabled", _pose.button_pressed)
	_fit_view.call_deferred()
	var zones: Array = _pointer.call("get_interaction_zones")
	_set_status("Открыт вариант «%s». Настроено зон касания: %d. Перетаскивайте части модели мышью." % [
		str(_current.get("name", identifier)), zones.size()])


func _on_runtime_error(message: String) -> void:
	_set_status(message, true)
	if not _model_ready:
		_empty.text = "Отображение модели недоступно.\n" + message
		_empty.show()


func _on_motion_event(value: String) -> void:
	_set_status("Событие анимации: " + value)


func _set_status(message: String, error: bool = false) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", Color("ffb29d") if error else Color("9fb1c8"))


func _set_controls_enabled(enabled: bool) -> void:
	var has_motion: bool = _motion_select.item_count > 0 and _motion_select.get_item_metadata(0) is Dictionary
	var has_expression: bool = _expression_select.item_count > 0 and _expression_select.get_item_metadata(0) is Dictionary
	_motion_select.disabled = not enabled or not has_motion
	_motion_button.disabled = not enabled or not has_motion
	_stop_button.disabled = not enabled
	_expression_select.disabled = not enabled or not has_expression
	_expression_button.disabled = not enabled or not has_expression
	var has_profile_expressions: bool = _profile_expression_select.item_count > 0 and _profile_expression_select.get_item_metadata(0) is String
	_profile_expression_select.disabled = not enabled or not has_profile_expressions
	_profile_expression_button.disabled = not enabled or not has_profile_expressions
	var has_profile_poses: bool = _profile_pose_select.item_count > 0 and _profile_pose_select.get_item_metadata(0) is String
	_profile_pose_select.disabled = not enabled or not has_profile_poses
	_profile_pose_button.disabled = not enabled or not has_profile_poses
	var has_outfits: bool = _outfit_select.item_count > 0 and _outfit_select.get_item_metadata(0) is String
	_outfit_select.disabled = not enabled or not has_outfits
	_outfit_button.disabled = not enabled or not has_outfits
	_reset_button.disabled = not enabled
	_physics.disabled = not enabled
	_pose.disabled = not enabled


func _play_motion() -> void:
	if not _model_ready or _motion_select.selected < 0:
		return
	var value: Variant = _motion_select.get_item_metadata(_motion_select.selected)
	if not value is Dictionary:
		return
	var motion: Dictionary = value
	var accepted: bool = bool(_actor.call("play_motion", str(motion.get("group", "Imported")), int(motion.get("index", 0)), 3))
	if accepted:
		var note: String = "Анимация запущена."
		if not bool(motion.get("complete", false)):
			note += " Конвертация частичная: ограничения перечислены в отчёте."
		_set_status(note)


func _stop_motion() -> void:
	if _model_ready:
		_actor.call("stop_motion")
		_set_status("Анимация остановлена.")


func _play_expression() -> void:
	if not _model_ready or _expression_select.selected < 0:
		return
	var value: Variant = _expression_select.get_item_metadata(_expression_select.selected)
	if value is Dictionary:
		var accepted: bool = bool(_actor.call("play_expression", str(value.get("name", ""))))
		if accepted:
			_set_status("Применено выражение: " + str(value.get("name", "")))


func _reset_pose() -> void:
	if not _model_ready:
		return
	_actor.call("reset_pose")
	_pointer.call("configure", _actor, _active_profile, str(_current.get("id", "")))
	_sync_live_values()
	_set_status("Восстановлено сохранённое состояние варианта.")


func _fill_profile_presets() -> void:
	var effective: Dictionary = _pointer.call("get_effective_profile")
	for record: Dictionary in [
		{"selector": _profile_expression_select, "category": "expressions"},
		{"selector": _profile_pose_select, "category": "poses"},
	]:
		var selector: OptionButton = record["selector"]
		selector.clear()
		var presets: Variant = effective.get(str(record["category"]), {})
		if presets is Dictionary:
			var names: Array = presets.keys()
			names.sort()
			for name: Variant in names:
				if presets[name] is Dictionary:
					selector.add_item(str(name))
					selector.set_item_metadata(selector.item_count - 1, str(name))
		if selector.item_count == 0:
			selector.add_item("Нет настроенных пресетов")
		else:
			selector.select(0)


func _apply_profile_expression() -> void:
	_apply_profile_preset("expressions", _profile_expression_select)


func _apply_profile_pose() -> void:
	_apply_profile_preset("poses", _profile_pose_select)


func _apply_profile_preset(category: String, selector: OptionButton) -> void:
	if not _model_ready or selector.selected < 0:
		return
	var title: Variant = selector.get_item_metadata(selector.selected)
	if not title is String:
		return
	if bool(_pointer.call("apply_preset", category, title)):
		_sync_live_values()
		_set_status("Применён пресет %s: %s" % [category, title])
	else:
		_set_status("Пресет не подходит к параметрам модели: " + str(title), true)


func _fill_outfit_selector() -> void:
	_outfit_select.clear()
	var effective: Dictionary = _pointer.call("get_effective_profile")
	var presets: Variant = effective.get("outfits", {})
	if presets is Dictionary:
		var names: Array = presets.keys()
		names.sort()
		for title: Variant in names:
			if str(title) != RIG_DEBUG_LABEL:
				_outfit_select.add_item(str(title))
				_outfit_select.set_item_metadata(_outfit_select.item_count - 1, str(title))
	if bool(_pointer.call("can_test_without_clothes")):
		_outfit_select.add_item(RIG_DEBUG_LABEL)
		_outfit_select.set_item_metadata(_outfit_select.item_count - 1, RIG_DEBUG_LABEL)
	if _outfit_select.item_count == 0:
		_outfit_select.add_item("Нет доступных переключателей одежды")
	else:
		_outfit_select.select(0)


func _apply_outfit_preset() -> void:
	if not _model_ready or _outfit_select.selected < 0:
		return
	var title: Variant = _outfit_select.get_item_metadata(_outfit_select.selected)
	if not title is String:
		return
	if bool(_pointer.call("apply_outfit", title)):
		_sync_live_values()
		_set_status("Режим применён: " + str(title))
	else:
		_set_status("Набор недоступен для этой модели: " + str(title), true)


func _toggle_physics(enabled: bool) -> void:
	if _model_ready:
		_actor.call("set_physics_enabled", enabled)


func _toggle_pose(enabled: bool) -> void:
	if _model_ready:
		_actor.call("set_pose_enabled", enabled)


func _build_inspector(native_ready: bool) -> void:
	for list in [_parameter_list, _part_list]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	_parameter_sliders.clear()
	_part_sliders.clear()
	_value_labels.clear()
	_inspector_rows.clear()
	var info := _read_dictionary(str(_current.get("info", "")))
	var snapshot := _read_dictionary(str(_current.get("snapshot", "")))
	var parameters: Array = []
	var parts: Array = []
	if native_ready:
		var native_parameters: Variant = _actor.call("get_parameter_descriptors")
		var native_parts: Variant = _actor.call("get_part_descriptors")
		if native_parameters is Array:
			parameters = native_parameters
		if native_parts is Array:
			parts = native_parts
	if parameters.is_empty() and info.get("parameters") is Array:
		parameters = info["parameters"]
	if parts.is_empty() and info.get("parts") is Array:
		parts = info["parts"]
	var saved_parameters: Dictionary = snapshot.get("effective_parameters", {}) as Dictionary
	var saved_parts: Dictionary = snapshot.get("effective_parts", {}) as Dictionary
	for record in parameters:
		if record is Dictionary:
			_add_parameter_row(record, saved_parameters, false, native_ready)
	for record in parts:
		if record is Dictionary:
			_add_parameter_row(record, saved_parts, true, native_ready)
	if _parameter_sliders.is_empty():
		_parameter_list.add_child(_label("Нет доступных параметров", 13, Color("8fa1ba")))
	if _part_sliders.is_empty():
		_part_list.add_child(_label("Нет доступных частей", 13, Color("8fa1ba")))
	_filter_rows(_filter.text)


func _add_parameter_row(record: Dictionary, saved: Dictionary, is_part: bool, enabled: bool) -> void:
	var identifier: String = str(record.get("id", ""))
	if identifier.is_empty():
		return
	var map: Dictionary = _part_sliders if is_part else _parameter_sliders
	if map.has(identifier):
		return
	var minimum: float = 0.0 if is_part else float(record.get("minimum", 0.0))
	var maximum: float = 1.0 if is_part else float(record.get("maximum", 1.0))
	if not is_finite(minimum) or not is_finite(maximum) or maximum < minimum:
		return
	var default: float = float(record.get("opacity", 1.0)) if is_part else float(record.get("default", 0.0))
	var current_value: float = float(record.get("value", saved.get(identifier, default)))
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var title_row := HBoxContainer.new()
	row.add_child(title_row)
	var name_label := _label(identifier, 12)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = identifier
	title_row.add_child(name_label)
	var value_label := _label(String.num(current_value, 3), 12, Color("8fbfff"))
	value_label.custom_minimum_size.x = 48
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = maxf((maximum - minimum) / 1000.0, 0.0001)
	slider.value = current_value
	slider.editable = enabled and maximum > minimum
	slider.tooltip_text = "%s: %s … %s" % [identifier, String.num(minimum, 3), String.num(maximum, 3)]
	row.add_child(slider)
	if is_part:
		slider.value_changed.connect(_on_part_changed.bind(identifier, value_label))
		_part_list.add_child(row)
	else:
		slider.value_changed.connect(_on_parameter_changed.bind(identifier, value_label))
		_parameter_list.add_child(row)
	map[identifier] = slider
	_value_labels[("part:" if is_part else "parameter:") + identifier] = value_label
	_inspector_rows.append({"id": identifier, "row": row})


func _on_parameter_changed(value: float, identifier: String, label: Label) -> void:
	label.text = String.num(value, 3)
	if _model_ready:
		_actor.call("set_parameter", identifier, value)


func _on_part_changed(value: float, identifier: String, label: Label) -> void:
	label.text = String.num(value, 3)
	if _model_ready:
		_actor.call("set_part_opacity", identifier, value)


func _sync_live_values() -> void:
	for identifier in _parameter_sliders:
		var slider: HSlider = _parameter_sliders[identifier]
		if slider.has_focus() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			continue
		var value: float = float(_actor.call("get_parameter_value", identifier))
		if is_finite(value):
			slider.set_value_no_signal(value)
			(_value_labels["parameter:" + identifier] as Label).text = String.num(value, 3)
	for identifier in _part_sliders:
		var slider: HSlider = _part_sliders[identifier]
		if slider.has_focus() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			continue
		var value: float = float(_actor.call("get_part_value", identifier))
		if is_finite(value):
			slider.set_value_no_signal(value)
			(_value_labels["part:" + identifier] as Label).text = String.num(value, 3)


func _filter_rows(text: String) -> void:
	var query: String = text.strip_edges().to_lower()
	for record in _inspector_rows:
		(record["row"] as Control).visible = query.is_empty() or str(record["id"]).to_lower().contains(query)


func _set_zoom(value: float) -> void:
	_zoom = value
	_fit_view()


func _reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	if is_instance_valid(_zoom_slider):
		_zoom_slider.set_value_no_signal(1.0)
	_fit_view()


func _fit_view() -> void:
	if not is_instance_valid(_actor) or not is_instance_valid(_canvas):
		return
	_actor.position = _canvas.size * 0.5 + _pan
	_actor.scale = Vector2.ONE * _zoom
	if _model_ready and _canvas.size.x > 1.0 and _canvas.size.y > 1.0:
		_actor.call("fit_model", _canvas.size * 0.92)


func _canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _model_ready:
				_pointer_dragging = bool(_pointer.call("begin", event.global_position))
			elif not event.pressed and _pointer_dragging:
				_pointer.call("release")
				_pointer_dragging = false
			if _pointer_dragging:
				_canvas.accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			_canvas.accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor: float = 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			_zoom = clampf(_zoom * factor, 0.2, 3.0)
			_zoom_slider.set_value_no_signal(_zoom)
			_fit_view()
			_canvas.accept_event()
	elif event is InputEventMouseMotion:
		if _pointer_dragging:
			_pointer.call("move", event.global_position, maxf(_canvas.size.x, _canvas.size.y))
			_canvas.accept_event()
		elif _panning:
			_pan += event.relative
			_fit_view()
			_canvas.accept_event()


func _show_report() -> void:
	var path: String = str(_catalog.get("report", catalog_path.get_base_dir().path_join("import_report.json")))
	if FileAccess.file_exists(path):
		_report_text.text = FileAccess.get_file_as_string(path)
	else:
		_report_text.text = "Отчёт недоступен: " + path + "\n\n" + _status.text
	_report_dialog.popup_centered(Vector2i(850, 580))
