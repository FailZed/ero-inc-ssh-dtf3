extends Control
signal closed

const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Puppet = preload("res://scripts/characters/puppet_view.gd")
const PROFILE_PATH := "res://data/characters/interaction_profile.json"
const IMPORT_CATALOG_PATH := "res://assets/characters/mdrg_study/catalog.json"
const IMPORT_PROFILE_PATH := "res://assets/characters/mdrg_study/interaction_profile.json"
const RIG_DEBUG_LABEL := "Без одежды (проверка рига)"
const SAVE_DIR := "user://character_workshop"

var puppet: Control
var models: Array = []
var model_picker: OptionButton
var parameter_list: VBoxContainer
var search: LineEdit
var status: Label
var details: Label
var transport: Label
var preset_list: VBoxContainer
var palette_list: VBoxContainer
var part_list: VBoxContainer
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var rows: Dictionary = {}
var file_dialog: FileDialog
var file_action := ""
var _status_left := 0.0
var _sync_clock := 0.0
var _capture_path := ""
var _close_after_capture := false
var _sidebar: Control
var _inspector: Control
var settings_controls: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.skin()
	models = _load_available_models()
	_build_ui()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): _capture_path = argument.trim_prefix("--capture=")
		if argument == "--capture-exit": _close_after_capture = true
	if not models.is_empty(): _select_model(0)
	resized.connect(_responsive)
	_responsive.call_deferred()
	if not _capture_path.is_empty(): _capture.call_deferred()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("07121e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column := UI.column(UI.inset(self, 20), 12)
	var header := UI.row(column)
	UI.label(header, "Мастерская персонажей", 26)
	UI.button(header, "Закрыть", _close)
	var body := UI.row(column, 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sidebar = _panel(body, 260)
	var left := UI.scroller(_sidebar)
	UI.label(left, "МОДЕЛЬ", 15, UI.BLUE)
	model_picker = OptionButton.new()
	model_picker.custom_minimum_size.y = 44
	model_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for item: Dictionary in models: model_picker.add_item(str(item.title))
	model_picker.item_selected.connect(_select_model)
	left.add_child(model_picker)
	details = UI.label(left, "", 15, UI.MUTED)
	preset_list = UI.column(left, 8)
	UI.button(left, "Открыть модель…", func(): _open_file("model"))
	UI.button(left, "Сбросить позу", func(): puppet.reset_character(); _rebuild_parameters(); _rebuild_presets())
	UI.button(left, "Без одежды · тест рига", func():
		if puppet.profile.get("outfits", {}).has(RIG_DEBUG_LABEL):
			puppet.choose_preset("outfits", RIG_DEBUG_LABEL)
			_message("Режим проверки рига включён. Сброс позы вернёт одежду.")
		else:
			_message("Для этой модели нет переключателей одежды."))
	var stage_column := UI.column(body, 8)
	stage_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stage := _panel(stage_column, 100)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	puppet = Puppet.new()
	puppet.custom_minimum_size = Vector2(100, 180)
	puppet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	puppet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(puppet)
	puppet.load_failed.connect(_message)
	puppet.interaction_finished.connect(func(event): _message("%s · %.1f с" % [event.get("interaction",""),event.get("duration",0.0)]))
	UI.label(stage_column, "Перетаскивай глаза, уши, рот, руки, ноги, корпус или хвост. Esc — отпустить.", 16, UI.MUTED)
	var zoom_row := UI.row(stage_column)
	UI.label(zoom_row, "Масштаб", 16)
	var zoom_slider := _slider(zoom_row, 0.5, 2.5, 1.0)
	zoom_slider.value_changed.connect(func(value): puppet.set_zoom(value))
	var bar := UI.row(stage_column, 6)
	UI.button(bar, "● Запись", _record)
	UI.button(bar, "▶", _play).tooltip_text = "Воспроизвести запись"
	UI.button(bar, "■", _stop).tooltip_text = "Остановить запись / воспроизведение"
	_check(bar, "Цикл", false, func(value): puppet.clip.loop = value)
	transport = UI.label(stage_column, "Запись параметров · 30 кадров/с", 15, UI.MUTED)
	_inspector = _panel(body, 350)
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.add_child(tabs)
	var params := VBoxContainer.new()
	params.name = "Параметры"
	tabs.add_child(params)
	search = LineEdit.new()
	search.placeholder_text = "Поиск по имени параметра"
	search.text_changed.connect(_filter_parameters)
	params.add_child(search)
	UI.button(params, "Снять ручные изменения", func(): puppet.bank.clear_channel("manual"))
	parameter_list = UI.scroller(params)
	var parts := VBoxContainer.new()
	parts.name = "Слои"
	tabs.add_child(parts)
	UI.label(parts,"Непрозрачность групп модели",16,UI.MUTED)
	part_list = UI.scroller(parts)
	var controls := VBoxContainer.new()
	controls.name = "Настройки"
	tabs.add_child(controls)
	var settings := UI.scroller(controls)
	settings_controls.physics_enabled = _check(settings, "Физика модели", true, func(value): puppet.physics_enabled = value)
	settings_controls.gaze_enabled = _check(settings, "Взгляд на курсор", true, func(value): puppet.gaze_enabled = value)
	settings_controls.blink_enabled = _check(settings, "Моргание", true, func(value): puppet.blink_enabled = value)
	settings_controls.debug_zones = _check(settings, "Зоны захвата", false, func(value): puppet.debug_zones = value; puppet.queue_redraw())
	settings_controls.toggle_grab = _check(settings, "Захват по щелчку", false, func(value): puppet.release_grab(true); puppet.toggle_grab = value)
	UI.label(settings, "Чувствительность", 16)
	settings_controls.sensitivity = _slider(settings, 0.3, 4.0, 2.0)
	settings_controls.sensitivity.value_changed.connect(func(value): puppet.sensitivity = value)
	UI.label(settings, "Сглаживание, секунды", 16)
	settings_controls.smoothing = _slider(settings, 0.01, 0.8, 0.12)
	settings_controls.smoothing.value_changed.connect(func(value): puppet.bank.smoothing = value)
	var smoothing := OptionButton.new()
	for title: String in ["Плавное", "Линейное", "Пружина"]: smoothing.add_item(title)
	smoothing.item_selected.connect(func(index): puppet.bank.mode = ["smooth","linear","spring"][index])
	settings_controls.mode = smoothing
	settings.add_child(smoothing)
	UI.label(settings, "ПАЛИТРА", 15, UI.BLUE)
	palette_list = UI.column(settings, 4)
	UI.label(settings, "ПРОФИЛЬ И ДВИЖЕНИЕ", 15, UI.BLUE)
	UI.button(settings, "Сохранить профиль…", func(): _open_file("save_profile"))
	UI.button(settings, "Загрузить профиль…", func(): _open_file("load_profile"))
	UI.button(settings, "Сохранить движение…", func(): _open_file("save_clip"))
	UI.button(settings, "Загрузить движение…", func(): _open_file("load_clip"))
	UI.label(settings, "Профиль содержит привязки зон, позы, одежду и текущие значения. Их можно редактировать в JSON и загрузить обратно.", 16, UI.MUTED)
	status = UI.label(column, "Учебные модели MDRG · собственная система управления EroInc", 16, UI.MUTED)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = false
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)

func _panel(parent: Node, width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel",UI.surface(16))
	parent.add_child(panel)
	return panel

func _slider(parent: Node, minimum: float, maximum: float, initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = maxf((maximum-minimum)/1000.0,0.0001)
	slider.value = initial
	slider.custom_minimum_size = Vector2(90,28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slider)
	return slider

func _check(parent: Node, title: String, initial: bool, action: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = title
	check.button_pressed = initial
	check.toggled.connect(action)
	parent.add_child(check)
	return check

func _load_available_models() -> Array:
	var results: Array = []
	var known: Dictionary = {}
	var legacy: Variant = _read_json("res://data/characters/study_catalog.json").get("models", [])
	if legacy is Array:
		for value: Variant in legacy:
			if value is Dictionary and value.get("id") is String:
				var key: String = str(value["id"])
				if not key.is_empty() and not known.has(key):
					known[key] = true
					results.append(value)
	var imported: Variant = _read_json(IMPORT_CATALOG_PATH).get("models", [])
	if imported is Array:
		for value: Variant in imported:
			if not value is Dictionary: continue
			var key: String = str(value.get("id", ""))
			var pathname: String = str(value.get("model3", ""))
			if key.is_empty() or pathname.is_empty() or known.has(key): continue
			known[key] = true
			results.append({"id": key, "source_id": str(value.get("source_id", "")),
				"title": str(value.get("name", key)), "model": pathname,
				"snapshot": str(value.get("snapshot", "")),
				"info": str(value.get("info", "")), "study_asset": false,
				"imported": true})
	return results


func _profile_for_item(item: Dictionary) -> Dictionary:
	if bool(item.get("imported", false)) or str(item.get("id", "")) == "interaction_model":
		var imported: Dictionary = _read_json(IMPORT_PROFILE_PATH)
		if not imported.is_empty(): return imported
	return _read_json(PROFILE_PATH)


func _select_model(index: int) -> void:
	if index < 0 or index >= models.size(): return
	var item: Dictionary = models[index]
	var bindings: Dictionary = _profile_for_item(item)
	if puppet.load_character(item, bindings):
		model_picker.select(index)
		_rebuild_parameters()
		_rebuild_presets()
		details.text = "%s\n%d параметров · %d сеток\n%d активных зон касания" % [item.id,
			puppet.bank.definitions.size(), puppet.model.call("get_meshes").size(), puppet.get_active_zone_count()]

func _rebuild_parameters() -> void:
	UI.clear(parameter_list)
	sliders.clear()
	rows.clear()
	value_labels.clear()
	UI.clear(part_list)
	for id: String in puppet.part_values:
		var part_row := UI.column(part_list,2)
		UI.label(part_row,id,15)
		_slider(part_row,0.0,1.0,float(puppet.part_values[id])).value_changed.connect(func(value): puppet.part_values[id] = value)
	for id: String in puppet.bank.definitions:
		var spec: Dictionary = puppet.bank.definitions[id]
		var row := UI.column(parameter_list, 2)
		row.tooltip_text = "Диапазон: %.3f … %.3f; исходное: %.3f" % [spec.min,spec.max,spec.default]
		var heading := UI.row(row, 4)
		var title := UI.label(heading, id.trim_prefix("Param"), 15)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		var value_label := UI.label(heading, "", 14, UI.BLUE)
		value_label.custom_minimum_size.x = 50
		value_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		var slider := _slider(row, spec.min, spec.max, puppet.bank.values[id])
		slider.value_changed.connect(func(value):
			if puppet.clip.playing: puppet.clip.stop()
			puppet.bank.clear_channel("playback")
			puppet.bank.set_target(id, value)
		)
		sliders[id] = slider
		value_labels[id] = value_label
		rows[id] = row
	_filter_parameters(search.text)

func _filter_parameters(query: String) -> void:
	for id: String in rows: rows[id].visible = query.is_empty() or id.to_lower().contains(query.to_lower())

func _rebuild_presets() -> void:
	UI.clear(preset_list)
	UI.clear(palette_list)
	for entry: Dictionary in puppet.profile.get("palette", []):
		var row := UI.row(palette_list)
		UI.label(row, str(entry.get("title","Цвет")), 16)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(64,32)
		picker.color = Color(str(entry.get("color","ffffff")))
		picker.edit_alpha = false
		picker.color_changed.connect(func(color): entry.color = color.to_html(false); puppet.apply_palette())
		row.add_child(picker)
	for group: String in ["outfits", "expressions", "poses"]:
		var choices: Dictionary = puppet.profile.get(group, {})
		if choices.is_empty(): continue
		UI.label(preset_list, {"outfits":"ОДЕЖДА","expressions":"ВЫРАЖЕНИЕ","poses":"ПОЗА"}[group], 15, UI.BLUE)
		var picker := OptionButton.new()
		for title: String in choices: picker.add_item(title)
		picker.item_selected.connect(func(index): puppet.choose_preset(group,picker.get_item_text(index)))
		preset_list.add_child(picker)

func _process(delta: float) -> void:
	_sync_clock -= delta
	_status_left -= delta
	if _sync_clock > 0.0 or not is_instance_valid(puppet): return
	_sync_clock = 0.1
	for id: String in sliders:
		var slider: HSlider = sliders[id]
		if not slider.has_focus(): slider.set_value_no_signal(float(puppet.bank.values.get(id,0.0)))
		value_labels[id].text = "%.2f" % float(puppet.bank.values.get(id,0.0))
	transport.text = "%s · %.1f с · %d кадров" % ["Запись" if puppet.clip.recording else ("Воспроизведение" if puppet.clip.playing else "Остановлено"),puppet.clip.time,puppet.clip.frames.size()]
	if _status_left <= 0.0:
		status.text = "Захват: %s · Реакция: %s · История: %d" % [puppet.held if not puppet.held.is_empty() else puppet.hovered,puppet.memory.state,puppet.memory.history.size()]

func _record() -> void:
	puppet.bank.clear_channel("playback")
	puppet.clip.start_recording(str(puppet.descriptor.get("id","")))
	_message("Запись началась. Двигай модель; ■ — закончить.")

func _play() -> void:
	puppet.release_grab(true)
	if not puppet.clip.play(puppet.clip.loop): _message("Сначала запиши движение или загрузи файл.")

func _stop() -> void:
	puppet.clip.stop()
	puppet.bank.clear_channel("playback")

func _open_file(action: String) -> void:
	file_action = action
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action.begins_with("save") else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.model3.json ; Live2D model"]) if action == "model" else PackedStringArray(["*.json ; JSON"])
	file_dialog.current_dir = ProjectSettings.globalize_path(SAVE_DIR)
	file_dialog.current_file = "motion.json" if action == "save_clip" else ("profile.json" if action == "save_profile" else "")
	file_dialog.popup_centered_ratio(0.75)

func _file_selected(path: String) -> void:
	match file_action:
		"model":
			var item := {"id":path.get_file().trim_suffix(".model3.json"),"title":path.get_file(),"model":path,"study_asset":false}
			if puppet.load_character(item, _profile_for_item(item)):
				models.append(item)
				model_picker.add_item(item.title)
				model_picker.select(models.size()-1)
				_rebuild_parameters()
				_rebuild_presets()
				details.text = "Внешняя модель\n" + item.id
		"save_profile":
			_write_json(path, {"schema":1,"model":puppet.descriptor,"bindings":puppet.profile,"values":puppet.bank.snapshot(),"parts":puppet.part_values,"settings":_settings_snapshot()})
		"load_profile":
			var data := _read_json(path)
			if data.get("schema") != 1 or not data.get("model") is Dictionary or not data.get("bindings") is Dictionary or not data.get("values") is Dictionary:
				_message("Неверный формат профиля.")
				return
			if not data.get("settings",{}) is Dictionary or not Puppet.validate_profile(data.bindings) or not Puppet.validate_profile({"initial":data["values"],"parts":data.get("parts",{})}):
				_message("Неверные значения или привязки профиля.")
				return
			if puppet.load_character(data.model, data.bindings):
				puppet.bank.restore(data["values"])
				for id: String in data.get("parts",{}):
					if puppet.part_values.has(id): puppet.part_values[id] = clampf(float(data.parts[id]),0.0,1.0)
				var settings: Dictionary = data.get("settings", {})
				for key: String in ["physics_enabled","gaze_enabled","blink_enabled","debug_zones","toggle_grab"]:
					if settings.get(key) is bool: puppet.set(key,settings[key])
				puppet.bank.smoothing = clampf(float(settings.get("smoothing",0.12)),0.01,0.8)
				puppet.bank.mode = str(settings.get("mode","smooth"))
				puppet.sensitivity = clampf(float(settings.get("sensitivity",2)),0.3,4)
				for key: String in settings_controls:
					var control: Control = settings_controls[key]
					if control is CheckBox: control.set_pressed_no_signal(bool(puppet.get(key)))
					elif control is HSlider: control.set_value_no_signal(puppet.bank.smoothing if key == "smoothing" else puppet.sensitivity)
				settings_controls.mode.select(maxi(0,["smooth","linear","spring"].find(puppet.bank.mode)))
				_rebuild_parameters()
				_rebuild_presets()
				details.text = "Профиль: " + path.get_file()
		"save_clip":
			if puppet.clip.frames.size() < 2: _message("Нет записанного движения.")
			else: _write_json(path, puppet.clip.serialize())
		"load_clip":
			var data := _read_json(path)
			if data.get("model", "") != puppet.descriptor.get("id", ""):
				_message("Это движение записано для другой модели.")
			elif not puppet.clip.load_clip(data): _message("Неверный формат движения.")
			else: _message("Движение загружено. Нажми ▶.")

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _settings_snapshot() -> Dictionary:
	var result := {"smoothing":puppet.bank.smoothing,"mode":puppet.bank.mode,"sensitivity":puppet.sensitivity}
	for key: String in ["physics_enabled","gaze_enabled","blink_enabled","debug_zones","toggle_grab"]: result[key] = puppet.get(key)
	return result

func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_message("Не удалось записать файл: " + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	_message("Сохранено: " + path.get_file())

func _message(text: String) -> void:
	if is_instance_valid(status): status.text = text
	_status_left = 4.0

func _responsive() -> void:
	_sidebar.custom_minimum_size.x = 230 if size.x < 1400 else 270
	_inspector.custom_minimum_size.x = 310 if size.x < 1400 else 370

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	puppet.release_grab(true)
	closed.emit()
	if get_tree().current_scene == self: get_tree().quit()
	else: queue_free()

func _capture() -> void:
	for frame in range(12): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(_capture_path)
	var metrics := {"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_video_adapter_name(),"model":puppet.descriptor.get("id",""),"godot_static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"texture_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED),"video_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)}
	_write_json(_capture_path.trim_suffix(".png")+".metrics.json",metrics)
	print("WORKSHOP_CAPTURE ", _capture_path, " error=", error)
	if _close_after_capture: get_tree().quit(error)
