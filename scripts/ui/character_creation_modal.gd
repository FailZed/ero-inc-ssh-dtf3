extends Control
signal profile_confirmed(full_name: String, stats: Dictionary)
signal profile_confirmed_v2(profile: Dictionary)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Preview = preload("res://scripts/ui/gameplay/layered_preview.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
var _profile: Dictionary = {}
var _options: Dictionary = {}
var _labels: Dictionary = {}
var _body: VBoxContainer
var _portrait: Control
var _name: LineEdit
var _points: Label
var _confirm: Button
var _page := 0
var _stat_values := {}
var _stat_buttons := {}
var _budget := 5
var _tabs: HBoxContainer

func _ready() -> void:
	hide()
	theme = UI.skin()
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.background(self, "res://assets/textures/backgrounds/location_pack_v1/bathroom_night.png", 0.05)
	var reflection := PanelContainer.new()
	reflection.add_theme_stylebox_override("panel", UI.style(Color(0.08,0.13,0.16,0.84),Color("879091")))
	reflection.anchor_left = 0.155
	reflection.anchor_right = 0.261
	reflection.anchor_top = 0.10
	reflection.anchor_bottom = 0.368
	reflection.clip_contents = true
	add_child(reflection)
	_portrait = Preview.new()
	reflection.add_child(_portrait)
	var glass := ColorRect.new()
	glass.color = Color(0.35,0.53,0.64,0.12)
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reflection.add_child(glass)
	var caption := PanelContainer.new()
	caption.anchor_left = 0.06
	caption.anchor_right = 0.48
	caption.anchor_top = 0.76
	caption.anchor_bottom = 0.90
	add_child(caption)
	var left := UI.column(caption, 6)
	UI.label(left, "ЗНАКОМОЕ ОТРАЖЕНИЕ", 28)
	UI.label(left, "23 года · Эллизия\nАльтерра ждёт. Осталось узнать себя.", 21, UI.MUTED)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UI.surface(26))
	panel.anchor_left = 0.55
	panel.anchor_right = 0.96
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.94
	add_child(panel)
	var content := UI.column(panel, 18)
	UI.label(content, "ЭТО Я", 42)
	_tabs = UI.row(content)
	_body = UI.scroller(content)
	_points = UI.label(content, "", 20, UI.BLUE)
	_confirm = UI.button(content, "ЭТО Я  →", _confirm_profile)

func open_with_profile(profile: Dictionary, stat_labels: Dictionary, _texts: Dictionary, appearance_options: Dictionary) -> void:
	_profile = profile.duplicate(true)
	_labels = stat_labels.duplicate(true)
	_options = appearance_options.duplicate(true)
	_budget = Gameplay.creation_budget()
	_profile.rules.bonus_points = _budget
	_profile.rules.min_stat = 5
	_profile.appearance.gender = "male"
	_profile.appearance.censorship_enabled = true
	if str(_profile.identity.full_name).is_empty(): _profile.identity.full_name = GameSession.get_default_character_full_name()
	_page = 0
	_build_page()
	show()
	_confirm.grab_focus()

func _build_page() -> void:
	UI.clear(_body)
	UI.clear(_tabs)
	W.tabs(_tabs,{"look":"Внешность","character":"Характер"},"look" if _page == 0 else "character",func(id): _page = 0 if id == "look" else 1; _build_page())
	_stat_values.clear()
	_stat_buttons.clear()
	if _page == 0:
		UI.label(_body, "Как я выгляжу", 26, UI.BLUE)
		for id in ["body_type", "face_id", "hair_style", "hair_color"]:
			var row := UI.row(_body)
			UI.label(row, str(_options.get(id, {}).get("label", id)), 20, UI.MUTED)
			var select := OptionButton.new()
			select.custom_minimum_size = Vector2(210, 48)
			row.add_child(select)
			for option in _options.get(id, {}).get("options", []):
				select.add_item(str(option.label))
				select.set_item_metadata(select.item_count - 1, option.id)
				if option.id == _profile.appearance.get(id, ""): select.select(select.item_count - 1)
			select.item_selected.connect(func(i): _profile.appearance[id] = select.get_item_metadata(i); _refresh())
		UI.label(_body, "Отражение меняется вместе с выбором. Одежду можно будет сменить дома.", 19, UI.MUTED)
	else:
		UI.label(_body, "Как меня зовут", 26, UI.BLUE)
		_name = LineEdit.new()
		_name.text = str(_profile.identity.full_name)
		_name.max_length = 48
		_name.custom_minimum_size.y = 52
		_name.text_changed.connect(func(v): _profile.identity.full_name = v; _refresh())
		_body.add_child(_name)
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
	_points.text = "Очков осталось: %d" % _remaining()
	for id in _stat_values:
		_stat_values[id].text = str(_profile.stats[id])
		_stat_buttons[id][0].disabled = int(_profile.stats[id]) <= 5
		_stat_buttons[id][1].disabled = _remaining() <= 0 or int(_profile.stats[id]) >= 30
	_portrait.set_appearance(_profile.appearance)
	_confirm.disabled = str(_profile.identity.full_name).strip_edges().is_empty() or _remaining() < 0

func _confirm_profile() -> void:
	if _confirm.disabled: return
	_profile.identity.full_name = str(_profile.identity.full_name).strip_edges()
	profile_confirmed.emit(_profile.identity.full_name, _profile.stats.duplicate(true))
	profile_confirmed_v2.emit(_profile.duplicate(true))

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_page = 1 - _page
		_build_page()
