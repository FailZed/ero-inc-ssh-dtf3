extends Control
## Scene-anchored actions. A marker opens a menu only when its object has choices.
signal action_chosen(action: Dictionary, minutes: int)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const LAYOUT_PATH := "res://data/ui/location_interactions.json"
const GROUP_ORDER := ["door", "bed", "sink", "shower", "toilet", "stove", "pantry", "desk", "study", "market", "estate", "hobby", "clean", "person", "other"]
static var _locations: Dictionary = {}
var _groups: Dictionary = {}
var _markers: Dictionary = {}
var _menu: PanelContainer
var _open_group := ""
var _selected_index := 0
var _sleep_minutes := 480
var _location := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _locations.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if data is Dictionary: _locations = data.get("locations", {})
	resized.connect(_layout_markers)

func present(actions: Array, location: String) -> void:
	_location = location
	_groups.clear()
	_markers.clear()
	_open_group = ""
	_menu = null
	UI.clear(self)
	for action in actions:
		var key := _group_for(action)
		if not _groups.has(key): _groups[key] = []
		_groups[key].append(action)
	for key in GROUP_ORDER:
		if not _groups.has(key): continue
		var choices: Array = _groups[key]
		var button := Button.new()
		button.text = _marker_title(key, choices)
		button.icon = HUD.icon("marker")
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 36)
		button.add_theme_constant_override("h_separation", 8)
		button.add_theme_font_size_override("font_size", roundi(18 * UI.text_scale))
		button.add_theme_color_override("font_color", UI.INK)
		button.custom_minimum_size = Vector2(158, 56)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var normal := UI.style(Color.TRANSPARENT, Color.TRANSPARENT)
		normal.set_border_width_all(0)
		normal.set_content_margin_all(2)
		var active := UI.style(Color(0.03, 0.09, 0.14, 0.60), UI.BLUE)
		active.set_border_width_all(0)
		active.border_width_bottom = 1
		active.set_content_margin_all(2)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", active)
		button.add_theme_stylebox_override("pressed", active)
		button.add_theme_stylebox_override("focus", active)
		button.tooltip_text = "Выбрать действие" if choices.size() == 1 else "Показать действия: %d" % choices.size()
		button.pressed.connect(_activate_group.bind(key))
		if choices.size() > 1: button.mouse_entered.connect(_open_menu.bind(key))
		add_child(button)
		_markers[key] = button
	_layout_markers()

func _group_for(action: Dictionary) -> String:
	var kind := str(action.get("kind", "other"))
	if kind in ["bed", "rest"]: return "bed"
	if kind == "desk": return "desk"
	if kind == "leisure": return "hobby"
	if kind == "clean": return "clean"
	if kind == "thirst": return "sink"
	if kind == "hygiene": return "shower"
	if kind == "toilet": return "toilet"
	if kind == "cook": return "stove"
	if kind == "inventory": return "pantry"
	if kind == "study": return "study"
	if kind == "market": return "market"
	if kind == "estate": return "estate"
	if kind in ["arrow", "map", "home"]: return "door"
	if kind == "profile": return "person"
	return "other"

func _marker_title(key: String, choices: Array) -> String:
	if key == "bed": return "Поспать"
	if key == "door": return str(choices[0].caption).replace("  →", "") if _location == "bedroom" or choices.size() == 1 else "Переходы"
	if key == "desk": return "Работа"
	if key == "sink": return "Вода"
	if key == "shower": return "Душ"
	if key == "toilet": return "Туалет"
	if key == "stove": return "Готовить"
	if key == "pantry": return "Сумка"
	if key == "study": return "Занятия"
	if key == "market": return "Магазины"
	if key == "estate": return "Жильё"
	if key == "hobby": return "Хобби"
	if key == "clean": return "Уборка"
	if key == "person": return "Люди"
	return "Действия"

func _layout_markers() -> void:
	if size.x <= 0 or size.y <= 0: return
	var location_points: Dictionary = _locations.get(_location, {}).get("marker_points", {})
	var generic_index := 0
	for key in GROUP_ORDER:
		if not _markers.has(key): continue
		var marker: Button = _markers[key]
		var point: Vector2
		var coordinates: Variant = location_points.get(key, [])
		if coordinates is Array and coordinates.size() == 2:
			point = Vector2(clampf(float(coordinates[0]), 0.0, 1.0), clampf(float(coordinates[1]), 0.0, 1.0))
		else:
			point = Vector2(0.78, 0.18 + generic_index * 0.10)
			generic_index += 1
		var right_side := point.x > 0.65
		marker.position = Vector2(size.x * point.x - (158 if right_side else 0), size.y * point.y - 28)
		marker.size = Vector2(158, 56)
		marker.alignment = HORIZONTAL_ALIGNMENT_RIGHT if right_side else HORIZONTAL_ALIGNMENT_LEFT
	if is_instance_valid(_menu): _position_menu()

func _activate_group(key: String) -> void:
	var choices: Array = _groups[key]
	if choices.size() == 1 and not bool(choices[0].get("sleep", false)):
		action_chosen.emit(choices[0], -1)
	else:
		_open_menu(key)

func _open_menu(key: String) -> void:
	if _open_group == key and is_instance_valid(_menu): return
	_open_group = key
	_selected_index = 0
	_render_menu()

func _render_menu() -> void:
	if is_instance_valid(_menu):
		remove_child(_menu)
		_menu.queue_free()
	_menu = PanelContainer.new()
	_menu.custom_minimum_size.x = 336
	_menu.add_theme_stylebox_override("panel", HUD.hud_surface(Color(0.012, 0.035, 0.06, 0.96)))
	add_child(_menu)
	var body := UI.column(_menu, 7)
	UI.label(body, "ДЕЙСТВИЯ", 14, UI.BLUE)
	var choices: Array = _groups[_open_group]
	var choices_scroll := ScrollContainer.new()
	choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices_scroll.follow_focus = true
	choices_scroll.custom_minimum_size.y = minf(choices.size() * 59.0, maxf(120.0, size.y - (260.0 if bool(choices[_selected_index].get("sleep", false)) else 150.0)))
	body.add_child(choices_scroll)
	var choice_list := UI.column(choices_scroll, 7)
	choice_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_button: Button
	for index in choices.size():
		var action: Dictionary = choices[index]
		var title := str(action.caption).replace("  →", "").replace("\n", " · ")
		if bool(action.get("sleep", false)): title = "Поспать"
		var button := UI.button(choice_list, title, _select_action.bind(index))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = HUD.icon(str(action.get("kind", "arrow")))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		button.add_theme_font_size_override("font_size", 17)
		button.custom_minimum_size.y = 52
		button.tooltip_text = str(action.get("hint", title))
		HUD.quiet_button(button)
		if index == _selected_index:
			button.add_theme_stylebox_override("normal", HUD.shortcut_style(true))
			selected_button = button
	var selected: Dictionary = choices[_selected_index]
	if bool(selected.get("sleep", false)):
		UI.label(body, "Длительность сна", 16, UI.MUTED)
		var duration := UI.label(body, _duration_text(_sleep_minutes), 21, UI.INK)
		duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var slider := HSlider.new()
		slider.min_value = 60
		slider.max_value = 720
		slider.step = 30
		slider.value = _sleep_minutes
		slider.custom_minimum_size = Vector2(280, 44)
		slider.value_changed.connect(func(value): _sleep_minutes = roundi(value); duration.text = _duration_text(_sleep_minutes))
		body.add_child(slider)
		var scale := UI.row(body)
		UI.label(scale, "1 ч", 14, UI.MUTED)
		var max_label := UI.label(scale, "12 ч", 14, UI.MUTED)
		max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var commit := UI.button(body, "Поспать" if bool(selected.get("sleep", false)) else "Выбрать", _execute_selected)
	commit.add_theme_stylebox_override("normal", HUD.shortcut_style(true))
	commit.add_theme_stylebox_override("hover", HUD.shortcut_style(true, true))
	commit.custom_minimum_size.y = 52
	_position_menu()
	if is_instance_valid(selected_button): selected_button.grab_focus()

func _select_action(index: int) -> void:
	_selected_index = index
	_render_menu()

func _execute_selected() -> void:
	var action: Dictionary = _groups[_open_group][_selected_index]
	close_menu()
	action_chosen.emit(action, _sleep_minutes if bool(action.get("sleep", false)) else -1)

func _position_menu() -> void:
	if not is_instance_valid(_menu) or not _markers.has(_open_group): return
	var marker: Button = _markers[_open_group]
	_menu.reset_size()
	var desired := _menu.get_combined_minimum_size()
	_menu.size = desired
	var x := marker.position.x + marker.size.x + 8
	if x + desired.x > size.x - 20: x = marker.position.x - desired.x - 8
	x = clampf(x, 16.0, maxf(16.0, size.x - desired.x - 16.0))
	var y := marker.position.y - 4
	y = clampf(y, 20.0, maxf(20.0, size.y - desired.y - 20.0))
	_menu.position = Vector2(x, y)

func _duration_text(minutes: int) -> String:
	return "%d ч" % (minutes / 60) if minutes % 60 == 0 else "%d ч 30 мин" % (minutes / 60)

func close_menu() -> void:
	_open_group = ""
	if is_instance_valid(_menu):
		remove_child(_menu)
		_menu.queue_free()
	_menu = null

func menu_is_open() -> bool:
	return not _open_group.is_empty()

func _unhandled_input(event: InputEvent) -> void:
	if _open_group.is_empty(): return
	if event is InputEventMouseButton and event.pressed and not _menu.get_global_rect().has_point(event.global_position):
		for marker in _markers.values():
			if marker.get_global_rect().has_point(event.global_position): return
		close_menu()
	if event is InputEventScreenTouch and event.pressed and not _menu.get_global_rect().has_point(event.position): close_menu()
