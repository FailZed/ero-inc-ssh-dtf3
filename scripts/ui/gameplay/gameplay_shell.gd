extends Control
signal menu_requested
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Portrait = preload("res://scripts/ui/gameplay/resident_preview.gd")
const RoomPlan = preload("res://scripts/ui/gameplay/room_plan.gd")
const ReproductivePanel = preload("res://scripts/ui/gameplay/reproductive_panel.gd")
const MiniGame = preload("res://scripts/ui/gameplay/mini_game.gd")
const Social = preload("res://scripts/gameplay/social_presentation.gd")
const SocialStatus = preload("res://scripts/ui/gameplay/social_status.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const PlayerHUD = preload("res://scripts/ui/gameplay/player_hud.gd")
const ActionPolicy = preload("res://scripts/gameplay/action_policy.gd")
const City = preload("res://scripts/gameplay/city_layout.gd")
const Atmosphere = preload("res://scripts/gameplay/atmosphere.gd")
const CityView = preload("res://scripts/ui/world/city_view.gd")
const Screens = preload("res://scripts/ui/gameplay/screen_catalog.gd")
const ActionQueue = preload("res://scripts/ui/gameplay/action_queue.gd")
const InventoryView = preload("res://scripts/ui/gameplay/inventory_view.gd")
const Phone = preload("res://scripts/ui/gameplay/phone.gd")
const GameScreens = preload("res://scripts/ui/gameplay/game_screens.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const PeopleView = preload("res://scripts/ui/gameplay/people_view.gd")
var _screen_state: Dictionary = {}
var _phone_view: Phone
var _queue: ActionQueue
var _plan_button: Button
var _profile_tab := "attributes"
var _inventory_state := {"query":"", "filter":"all", "selected":"", "sort":0}
var _people_query := ""
var _people_filter := "all"
var _city: CityView
var _indoor_light := ShaderMaterial.new()
var current_panel := "place"
var _panel_history: Array[String] = []
var _npc_risk := false
var selected_npc := ""
var selected_collection := ""
var _gathering_guests: Array[String] = []
var _body: VBoxContainer
var _status: Label
var _toast: Label
var _background: TextureRect
var _title: Label
var _initiative_panel: PanelContainer
var _nav_buttons: Dictionary = {}
var _scroll: ScrollContainer
var _room_item := ""
var _rotated := false
var _refresh_pending := false
var _result_text := ""
var _result_until := 0
var _probe
var _probe_snapshot: Dictionary
var _chrome: MarginContainer
var _main_panel: PanelContainer
var _sections_overlay: Control
var _sections_button: Button
var _close_panel: Button
var _hero: PlayerHUD
var _clock: Label
var _date: Label
var _cash: Label
var _objective: Button
var _wait: Button
var _dock_buttons: Dictionary = {}
var _hud_hint: Button
var _conversation: Control
var _toast_serial := 0
var _phone_badge: Label
var _phone_badge_frame: PanelContainer
var _dock_hint: Label
var _header: HBoxContainer
var _bottom: HBoxContainer

func _ready() -> void:
	theme = UI.skin()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.background(self, "res://assets/textures/backgrounds/location_pack_v1/bedroom_night.png", 0.10)
	_background = get_child(0)
	_indoor_light.shader = preload("res://assets/shaders/city_light.gdshader")
	_background.material = _indoor_light
	_city = CityView.new()
	add_child(_city)
	_city.travel_requested.connect(_city_travel)
	_city.close_requested.connect(open_panel.bind("place"))
	_chrome = UI.inset(self, 36)
	var layout := UI.column(_chrome, 18)
	var header := UI.row(layout, 14)
	_header = header
	var location_panel := PanelContainer.new()
	location_panel.custom_minimum_size.x = 270
	var location_style := HUD.button_style(Color(0.01, 0.025, 0.04, 0.36), Color(0.39, 0.57, 0.68, 0.38))
	location_style.content_margin_left = 16
	location_style.content_margin_right = 20
	location_panel.add_theme_stylebox_override("panel", location_style)
	header.add_child(location_panel)
	var location_info := UI.column(location_panel, 1)
	_status = UI.label(location_info, "", 14, UI.BLUE)
	var moment := UI.row(location_info, 18)
	_clock = UI.label(moment, "", 34, UI.INK)
	_clock.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	_date = UI.label(moment, "", 15, UI.MUTED)
	_date.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_date.custom_minimum_size.x = 210
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(gap)
	_cash = UI.label(header, "", 24)
	_cash.autowrap_mode = TextServer.AUTOWRAP_OFF
	_cash.custom_minimum_size.x = 140
	_cash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cash.size_flags_horizontal = Control.SIZE_SHRINK_END
	_cash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wait = HUD.dock_button(header, "Подождать 15 минут", "", "clock", _act.bind("clock", "advance", {"minutes": 15}))
	_wait.tooltip_text = "Подождать 15 игровых минут. Жители продолжат свои дела."
	_plan_button = HUD.dock_button(header, "План действий", "Q", "journal", _toggle_plan)
	HUD.dock_button(header, "Меню", "Esc", "menu", _request_menu)
	var scene := Control.new()
	scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(scene)
	scene.resized.connect(_fit_scene_panel)
	_objective = UI.button(scene, "", open_panel.bind("journal"))
	_objective.anchor_right = 0.26
	_objective.tooltip_text = "Открыть журнал · J"
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_objective.add_theme_font_size_override("font_size", 18)
	_objective.icon = HUD.icon("journal")
	_objective.expand_icon = true
	_objective.add_theme_constant_override("icon_max_width", 18)
	_objective.add_theme_constant_override("h_separation", 10)
	HUD.quiet_button(_objective)
	_initiative_panel = PanelContainer.new()
	_initiative_panel.anchor_left = 0.43
	_initiative_panel.anchor_right = 1.0
	scene.add_child(_initiative_panel)
	_main_panel = PanelContainer.new()
	scene.add_child(_main_panel)
	var window_layout := UI.row(_main_panel, 28)
	var content := UI.column(window_layout, 12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := UI.row(content)
	_title = UI.label(heading, "", 28)
	var sections_link := UI.button(heading, "МЕНЮ  ·  F1", _toggle_sections)
	sections_link.add_theme_font_size_override("font_size", 14)
	HUD.quiet_button(sections_link)
	_close_panel = UI.button(heading,"Назад · Esc",_back_panel)
	HUD.quiet_button(_close_panel)
	sections_link.set_meta("detail_navigation", true)
	_close_panel.add_theme_font_size_override("font_size", 14)
	_close_panel.tooltip_text = "Закрыть раздел · Esc"
	_body = UI.scroller(content)
	_scroll = _body.get_parent()
	_scroll.follow_focus = true
	_toast = UI.label(self,"",20,UI.ORANGE)
	_toast.anchor_left = 0.28
	_toast.anchor_right = 0.74
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_top = -140
	_toast.offset_bottom = -80
	_toast.add_theme_stylebox_override("normal",UI.style(Color(0.005,0.015,0.025,0.95),Color("577589")))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.max_lines_visible = 2
	_toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast.hide()
	_toast.max_lines_visible = 3
	_toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	var bottom := UI.row(layout, 20)
	_bottom = bottom
	_hero = PlayerHUD.new()
	_hero.pressed.connect(open_panel.bind("health"))
	bottom.add_child(_hero)
	var empty := Control.new()
	empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(empty)
	_queue = ActionQueue.new()
	_queue.execute_requested.connect(_execute_planned)
	bottom.add_child(_queue)
	_queue.layout_changed.connect(func(): _refresh_hud(Gameplay.simulation.state))
	var corner := UI.column(bottom, 8)
	corner.size_flags_vertical = Control.SIZE_SHRINK_END
	# The label has a reserved line: hovering never moves the buttons or scene.
	_dock_hint = UI.label(corner, "", 15, UI.BLUE)
	_dock_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dock_hint.custom_minimum_size.y = 22
	var dock := PanelContainer.new()
	var dock_style := HUD.panel_style()
	dock_style.content_margin_left = 8
	dock_style.content_margin_right = 8
	dock_style.content_margin_top = 6
	dock_style.content_margin_bottom = 6
	dock.add_theme_stylebox_override("panel", dock_style)
	corner.add_child(dock)
	var shortcuts := UI.row(dock, 4)
	for spec in [["map", "Карта", "M"], ["people", "Люди", "R"], ["phone", "Телефон", "P"], ["inventory", "Сумка", "I"], ["journal", "Журнал", "J"]]:
		_dock_buttons[spec[0]] = HUD.dock_button(shortcuts, spec[1], spec[2], spec[0], _toggle_panel.bind(spec[0]))
	_sections_button = HUD.dock_button(shortcuts, "Разделы", "F1", "sections", _toggle_sections)
	_phone_badge_frame = PanelContainer.new()
	_phone_badge_frame.anchor_left = 0.65
	_phone_badge_frame.anchor_right = 0.98
	var badge_style := HUD.panel_style(UI.ORANGE)
	badge_style.set_border_width_all(0)
	badge_style.shadow_size = 0
	badge_style.content_margin_left = 3
	badge_style.content_margin_right = 3
	_phone_badge_frame.add_theme_stylebox_override("panel", badge_style)
	_phone_badge_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_buttons.phone.add_child(_phone_badge_frame)
	_phone_badge = UI.label(_phone_badge_frame, "", 12, Color("0a1821"))
	_phone_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	_phone_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phone_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for button in _dock_buttons.values() + [_sections_button]:
		button.mouse_entered.connect(func(): _dock_hint.text = str(button.get_meta("hud_label")))
		button.focus_entered.connect(func(): _dock_hint.text = str(button.get_meta("hud_label")))
		button.mouse_exited.connect(func(): _dock_hint.text = "")
		button.focus_exited.connect(func(): _dock_hint.text = "")
	_phone_view = Phone.new()
	_phone_view.closed.connect(_back_panel)
	_phone_view.screen_requested.connect(open_panel)
	_phone_view.person_requested.connect(_show_npc_details)
	add_child(_phone_view)
	_build_sections()
	_hud_hint = HUD.dock_button(self, "Показать интерфейс", "H", "eye", _toggle_hud)
	_hud_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud_hint.offset_left = -96
	_hud_hint.offset_right = -36
	_hud_hint.offset_top = 36
	_hud_hint.offset_bottom = 94
	_hud_hint.visible = false
	Gameplay.changed.connect(_queue_refresh)
	Gameplay.notification.connect(_notify)
	Gameplay.panel_requested.connect(open_panel)
	_probe = Gameplay.make_simulation()
	_refresh()

func _queue_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true
	call_deferred("_refresh")

func _notify(text: String) -> void:
	for offer in Gameplay.simulation.services.npc_dialogue.offers():
		if text == str(offer.name) + ": " + str(offer.text): return
	_toast_serial += 1
	var serial := _toast_serial
	_toast.text = text
	_toast.show()
	_toast.tooltip_text = text
	get_tree().create_timer(7).timeout.connect(func():
		if serial == _toast_serial: _toast.text = ""; _toast.hide())

func open_panel(id: String, record_history: bool = true) -> void:
	if is_instance_valid(_queue) and _queue.running: _queue.stop()
	if id == "place": _panel_history.clear()
	elif record_history and current_panel != id:
		if id in _panel_history: _panel_history.resize(_panel_history.find(id))
		else: _panel_history.append(current_panel)
		if _panel_history.size() > 24: _panel_history.pop_front()
	if id != current_panel: _npc_risk = false
	if current_panel == "phone" and id != "phone": _phone_view.suspend()
	current_panel = id
	_sections_overlay.visible = false
	_chrome.visible = true
	_hud_hint.visible = false
	_scroll.scroll_vertical = 0
	_refresh()
	if id == "map" and not _city.markers.is_empty(): _city.markers.values()[0].grab_focus()
	elif id == "phone": _phone_view.focus_default()
	elif id != "place": _focus_screen()
	elif _dock_buttons.has("map"): _dock_buttons.map.grab_focus()

func _toggle_panel(id: String) -> void:
	if current_panel == id: _back_panel()
	else: open_panel(id)

func _back_panel() -> void:
	if current_panel == "npc" and _npc_risk:
		_npc_risk = false
		_refresh()
		return
	open_panel(_panel_history.pop_back() if not _panel_history.is_empty() else "place",false)

func _build_sections() -> void:
	_sections_overlay = Control.new()
	_sections_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_sections_overlay)
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.01, 0.025, 0.04, 0.65)
	_sections_overlay.add_child(veil)
	veil.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _toggle_sections())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sections_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 1040
	panel.add_theme_stylebox_override("panel",UI.surface(30))
	center.add_child(panel)
	var content := UI.column(panel, 14)
	var title := UI.row(content)
	UI.label(title, "Разделы", 32)
	UI.button(title, "ЗАКРЫТЬ  ×", _toggle_sections)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for group in Screens.GROUPS:
		var column := UI.column(grid, 8)
		UI.label(column, group.title, 13, UI.BLUE)
		for spec in group.screens:
			var id: String = spec[0]
			_nav_buttons[id] = UI.button(column, spec[1] + (" · " + spec[3] if not spec[3].is_empty() else ""), open_panel.bind(id))
			_nav_buttons[id].alignment = HORIZONTAL_ALIGNMENT_LEFT
			_nav_buttons[id].add_theme_font_size_override("font_size", 18)
			_nav_buttons[id].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var footer := UI.row(content)
	_nav_buttons.place = UI.button(footer, "К СЦЕНЕ", open_panel.bind("place"))
	UI.button(footer, "ИНТЕРФЕЙС И УПРАВЛЕНИЕ", open_panel.bind("interface"))
	UI.button(content, "Скрыть интерфейс · H", _toggle_hud)
	_sections_overlay.visible = false

func _toggle_sections() -> void:
	if _queue.running: _queue.stop()
	_sections_overlay.visible = not _sections_overlay.visible
	if _sections_overlay.visible: _nav_buttons[current_panel if current_panel != "place" and _nav_buttons.has(current_panel) else "profile"].grab_focus()
	else: _sections_button.grab_focus()

func _toggle_hud() -> void:
	if _queue.running: _queue.stop()
	_sections_overlay.visible = false
	_chrome.visible = not _chrome.visible
	_hud_hint.visible = not _chrome.visible
	if _chrome.visible: _sections_button.grab_focus()

func _refresh_hud(s: Dictionary) -> void:
	var encounter: bool = (not s.encounters.combat.is_empty() and s.encounters.combat.status == "active") or (not s.encounters.game.is_empty() and s.encounters.game.status == "active") or not Gameplay.simulation.services.intimacy.presentation().is_empty()
	_status.text = Names.title(s.world.location).to_upper()
	_clock.text = str(s.clock.time_text)
	_date.text = "%s, %d.%02d" % [["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"][int(s.clock.weekday) - 1], int(s.clock.day), int(s.clock.month_number)]
	_clock.tooltip_text = "%s · %d год\nВремя идёт во время действий" % [s.clock.date_text, int(s.clock.year)]
	_cash.text = "%d ¤" % int(s.economy.cash)
	_hero.present(s.player, Gameplay.simulation.services.needs.condition())
	_hero.visible = current_panel == "place" and not encounter
	_main_panel.visible = not current_panel in ["map", "phone"] or encounter
	_phone_view.visible = current_panel == "phone" and not encounter
	_header.visible = not _phone_view.visible
	_toast.visible = not encounter and not _phone_view.visible and not _toast.text.is_empty()
	_bottom.visible = not _phone_view.visible and not encounter
	var sky := Atmosphere.profile(s.clock,str(s.world.weather))
	_date.text += "\n" + str(sky.label)
	var unread := 0
	for message in s.social.messages:
		if message.incoming and not message.read: unread += 1
	_phone_badge.text = str(unread) if unread > 0 else ""
	_phone_badge_frame.visible = unread > 0
	_dock_buttons.phone.tooltip_text = "Телефон · P" + ("\nНепрочитанных: %d" % unread if unread > 0 else "")
	for id in _dock_buttons:
		_dock_buttons[id].modulate = UI.BLUE if current_panel == id else Color.WHITE
		_dock_buttons[id].add_theme_stylebox_override("normal", HUD.button_style(Color(0.05,0.12,0.18,0.65), UI.BLUE) if current_panel == id else HUD.button_style())
	var quest: Dictionary = s.journal.quests.get("first_steps", {})
	_objective.visible = not encounter and current_panel == "place" and not quest.is_empty() and quest.get("status", "") in ["active", "completed"] and not quest.get("claimed", false)
	_objective.text = "Первые шаги  ·  %d / 2  →" % int(quest.get("objectives", {}).get("practice", 0)) if quest.get("status", "") == "active" else "Первая цель выполнена  →"
	_objective.tooltip_text = "Освоиться в городе: позаниматься самостоятельно два раза\nОткрыть журнал · J"
	var home: bool = current_panel == "place" and not encounter
	_main_panel.anchor_left = 1.0 if home else 0.08
	_main_panel.anchor_right = 1.0 if home else 0.92
	_main_panel.anchor_top = 0.44 if home else 0.0
	_main_panel.anchor_bottom = 1.0
	_main_panel.offset_left = -360 if home else 0
	_main_panel.offset_top = 0
	_main_panel.offset_right = 0
	_main_panel.offset_bottom = 0
	_close_panel.visible = not home and not encounter
	for link in _title.get_parent().get_children():
		if link.has_meta("detail_navigation"): link.visible = not home and not encounter
	_queue.visible = home and not encounter and (_queue.planning or not _queue.entries.is_empty())
	_plan_button.modulate = UI.BLUE if _queue.planning else Color.WHITE
	_plan_button.disabled = encounter
	_title.add_theme_font_size_override("font_size", 14 if home else 34)
	_title.add_theme_color_override("font_color", UI.MUTED if home else UI.INK)
	_body.add_theme_constant_override("separation", 6 if home else 14)
	var scene_style := HUD.panel_style(Color(0.018, 0.045, 0.065, 0.82))
	scene_style.content_margin_left = 16
	scene_style.content_margin_right = 16
	scene_style.content_margin_top = 16
	scene_style.content_margin_bottom = 8
	_main_panel.add_theme_stylebox_override("panel",scene_style if home else UI.surface(24))
	_wait.disabled = encounter

func _refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree(): return
	var focus := _remember_focus()
	UI.clear(_body)
	var s: Dictionary = Gameplay.simulation.state
	_probe_snapshot = Gameplay.simulation.export_snapshot()
	_refresh_hud(s)
	for id in _nav_buttons: _nav_buttons[id].modulate = UI.BLUE if id == current_panel or (id == "people" and current_panel in ["npc", "gathering"]) else Color.WHITE
	var backgrounds := {"bedroom":"bedroom_night", "apartment_hall":"hallway_night", "bathroom":"bathroom_night", "kitchen":"bedroom_morning", "global_map":"home_street_dusk", "training_center":"home_street_day"}
	_background.texture = load("res://assets/textures/backgrounds/campus_v1/courtyard.tres" if s.world.location == "training_center" else "res://assets/textures/locations/apartment/kitchen_16x9.png" if s.world.location == "kitchen" else "res://assets/textures/backgrounds/location_pack_v1/%s.png" % backgrounds.get(str(s.world.location), "home_street_day"))
	_city.visible = current_panel == "map" or not City.point(str(s.world.location)).is_empty()
	if _city.visible: _city.present(Gameplay.simulation,current_panel == "map")
	var sky := Atmosphere.profile(s.clock,str(s.world.weather),true)
	_indoor_light.set_shader_parameter("brightness",float(sky.brightness)*float({"morning":0.94,"day":1.12,"sunset":0.88,"night":0.72}[sky.period]))
	_indoor_light.set_shader_parameter("saturation",sky.saturation)
	_indoor_light.set_shader_parameter("light_tint",Color("e8efff") if sky.period == "night" else Color("ffe2bc") if sky.period == "sunset" else Color.WHITE)
	_initiative_panel.visible = false
	if ReproductivePanel.encounter(self, _body):
		_title.text = "Личный разговор"
		_restore_focus(focus)
		return
	if _active_encounter():
		_restore_focus(focus)
		return
	_refresh_initiative()
	match current_panel:
		"place": _place()
		"map": _map()
		"profile": _profile()
		"inventory": _inventory()
		"phone": _phone()
		"people": _people()
		"gathering": _gathering()
		"npc": _npc()
		"journal": _journal()
		"activities": _activities()
		"work": _work()
		"club": _club()
		"home": _home()
		"health": _health()
		"interface": _interface()
		"family":
			GameScreens.family(self, _body)
		"digital": _digital()
		"collection":
			_heading("Коллекция воспоминаний")
			var viewer := preload("res://scripts/ui/gameplay/collection_view.gd").new()
			viewer.selected_id = selected_collection
			viewer.entry_selected.connect(func(id): selected_collection = id)
			viewer.custom_minimum_size.y = 420
			_body.add_child(viewer)
	if _body.get_child_count() == 0 and current_panel != "phone": UI.label(_body, "Пока здесь тихо.", 22, UI.MUTED)
	_restore_focus(focus)
	_fit_scene_panel.call_deferred()

func _focus_screen() -> void:
	for button in _body.find_children("*","Button",true,false):
		if not button.disabled and button.get_meta("initial_focus",false): button.grab_focus(); return
	for button in _body.find_children("*","Button",true,false):
		if not button.disabled: button.grab_focus(); return
	_close_panel.grab_focus()

func _remember_focus() -> Dictionary:
	var control := get_viewport().gui_get_focus_owner()
	if control == null or not _body.is_ancestor_of(control): return {}
	for key in ["input_id","item_id","profile_tab","screen_tab","gameplay_action","person_id","room_item"]:
		if control.has_meta(key): return {"key":key,"value":control.get_meta(key),"caret":control.caret_column if control is LineEdit else -1}
	return {}

func _restore_focus(focus: Dictionary) -> void:
	if focus.is_empty(): return
	for control in _body.find_children("*","Control",true,false):
		if not control.has_meta(str(focus.key)) or control.get_meta(str(focus.key)) != focus.value: continue
		if control is BaseButton and control.disabled: continue
		control.grab_focus()
		if control is LineEdit and int(focus.caret) >= 0: control.caret_column = mini(int(focus.caret),control.text.length())
		return
	_focus_screen()

func _fit_scene_panel() -> void:
	if _main_panel == null or current_panel != "place": return
	var encounters: Dictionary = Gameplay.simulation.state.encounters
	if (not encounters.combat.is_empty() and encounters.combat.status == "active") or (not encounters.game.is_empty() and encounters.game.status == "active"): return
	if not Gameplay.simulation.services.intimacy.presentation().is_empty(): return
	var available := _main_panel.get_parent_control().size.y
	if available <= 0: return
	var desired := _body.get_combined_minimum_size().y + _title.get_combined_minimum_size().y + 48
	_main_panel.anchor_top = 1.0
	_main_panel.offset_top = -minf(desired, available * 0.78)

func _refresh_initiative() -> void:
	UI.clear(_initiative_panel)
	if current_panel != "place": return
	var offers: Array = Gameplay.simulation.services.npc_dialogue.offers()
	if offers.is_empty(): return
	_initiative_panel.visible = true
	var offer: Dictionary = offers[0]
	var content := UI.column(_initiative_panel, 8)
	UI.label(content, str(offer.name) + (" пишет" if offer.channel == "message" else " обращается к вам"), 21, UI.BLUE)
	var line := UI.label(content, str(offer.text), 20)
	line.max_lines_visible = 1
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.tooltip_text = str(offer.text)
	var row := UI.row(content)
	UI.button(row, "ОТВЕТИТЬ", _open_conversation.bind(str(offer.id), "message" if offer.channel == "message" else "free", str(offer.initiative)))
	UI.button(row, "СЕЙЧАС НЕ МОГУ", _act.bind("npc_dialogue", "decline", {"id": offer.id, "initiative": offer.initiative}))

func _heading(title: String, description: String = "") -> void:
	_title.text = title
	if not description.is_empty(): UI.label(_body, description, 21, UI.MUTED)

func _offer(parent: Node, title: String, detail: String, module_id: String, operation: String, args: Dictionary = {}, unavailable: String = "", verify: bool = true, embedded: bool = false) -> Button:
	embedded = embedded or (parent is VBoxContainer and parent.get_parent() is PanelContainer and parent != _body)
	var caution := ""
	var study_conflict := false
	if verify and unavailable.is_empty() and _probe != null:
		var restored: Dictionary = _probe.restore_snapshot(_probe_snapshot)
		if not restored.ok: unavailable = Names.error(str(restored.error))
		var preview: Dictionary = _probe.command(module_id,operation,args)
		if not preview.ok:
			unavailable = Names.error(str(preview.error))
			if preview.error == "work_conflicts_study":
				var override := args.duplicate(true)
				override.skip_classes = true
				var permitted: Dictionary = _probe.command(module_id,operation,override)
				study_conflict = permitted.ok
				if not permitted.ok: unavailable = Names.error(str(permitted.error))
		else: caution = _commitment_hint(int(_probe.state.clock.total_minutes))
	var card := UI.column(parent,10) if embedded else W.panel(parent, 18)
	if not embedded:
		var heading := UI.row(card,12)
		W.icon(heading,{"actions":"energy" if args.get("id","") == "exercise" else "journal","activities":"energy","character":"rest","needs":"rest","world":"map","inventory":"inventory","housing":"home","social":"people","social_rules":"people","npc_agency":"chat","npc_relationships":"chat","health":"health","reproduction":"health","economy":"wallet","careers":"desk","events":"journal","family":"home","digital":"desk","organizations":"people"}.get(module_id,"journal"),28)
		UI.label(heading, title, 23)
	if not detail.is_empty(): UI.label(card, detail, 17, UI.MUTED)
	if not caution.is_empty(): UI.label(card, caution, 18, UI.ORANGE)
	if not unavailable.is_empty(): UI.label(card,unavailable,18,UI.ORANGE)
	var button := W.primary(card, {"sleep":"Поспать", "rest":"Отдохнуть", "practice":"Заниматься", "project":"Работать", "buy":"Купить", "treat":"Пройти лечение", "begin":"Предложить", "perform":"Начать"}.get(operation, "Продолжить"), _act.bind(module_id, operation, args))
	button.set_meta("gameplay_action", {"module":module_id, "operation":operation, "args":args.duplicate(true)})
	button.tooltip_text = unavailable if not unavailable.is_empty() else detail
	button.disabled = not unavailable.is_empty() and not study_conflict
	button.set_meta("study_conflict",study_conflict)
	return button

func _commitment_hint(ending: int) -> String:
	if ending <= int(_probe_snapshot.state.clock.total_minutes): return ""
	var parts: Array[String] = []
	for entry in ActionPolicy.commitments(_probe_snapshot.state, ending):
		if entry.kind == "appointment": parts.append("встреча — " + Names.actor_name(Gameplay.simulation, str(entry.id)))
		else: parts.append("срок: " + Names.title(str(entry.id)))
	return "На это время запланировано: " + "; ".join(parts) if not parts.is_empty() else ""

func _act(module_id: String, operation: String, args: Dictionary = {}) -> void:
	if _queue.running: _queue.stop()
	var before: Dictionary = Gameplay.simulation.state
	var minute := int(before.clock.total_minutes)
	var cash := int(before.economy.cash)
	var absences := int(before.world.education.absences)
	var target := str(args.get("npc", args.get("id", "")))
	var previous_bond: Dictionary = Social.bond(Gameplay.simulation, target) if before.social.npcs.has(target) else {}
	var result := Gameplay.execute(module_id, operation, args)
	if result.ok:
		var s: Dictionary = Gameplay.simulation.state
		var delta := int(s.economy.cash) - cash
		var spent := int(s.clock.total_minutes) - minute
		var message := "Готово"
		if result.data.get("accepted") is bool: message = Social.response(str(args.get("action", operation)), bool(result.data.accepted))
		if result.data.get("description") is String: message = str(result.data.description)
		if result.data.get("crafted") is bool: message = "Блюдо готово" if result.data.crafted else "Блюдо не получилось. Практика поможет в следующий раз"
		if result.data.get("success") is bool: message = "Удалось" if result.data.success else "Не удалось. Последствия записаны в журнале"
		if spent > 0: message += " · %d мин" % spent
		if delta != 0: message += " · %+d ¤" % delta
		if int(s.world.education.absences) > absences: message += " · пропущено занятий: %d" % (int(s.world.education.absences)-absences)
		if not previous_bond.is_empty():
			var changes := Social.change_summary(previous_bond, Social.bond(Gameplay.simulation, target))
			if not changes.is_empty(): message += "\n" + changes
		_notify(message)
		_refresh()
	else:
		_notify(Names.error(str(result.get("error", "Действие сейчас недоступно"))))
		if result.get("error","") == "work_conflicts_study": _confirm_work_skip(module_id,operation,args)

func _confirm_work_skip(module_id: String, operation: String, args: Dictionary) -> void:
	var sim = Gameplay.simulation
	var duration := ActionPolicy.duration(sim,module_id,operation,args)
	var window = load("res://scripts/ui/gameplay/work_schedule_window.gd").new()
	window.conflicts = preload("res://scripts/mechanics/work_schedule.gd").conflicts(sim,str(sim.state.world.location),duration)
	var accepted := args.duplicate(true)
	accepted.skip_classes = true
	window.confirmed.connect(func(): _act(module_id,operation,accepted))
	add_child(window)

func _execute_planned(command: Dictionary) -> void:
	if get_tree().paused or not is_visible_in_tree() or is_instance_valid(_conversation) or current_panel != "place" or _wait.disabled:
		_queue.stop("План остановлен: завершите текущую сцену.")
		return
	var module_id := str(command.module)
	var operation := str(command.operation)
	var args: Dictionary = command.args
	var restored: Dictionary = _probe.restore_snapshot(Gameplay.simulation.export_snapshot())
	if not restored.ok:
		_queue.resolve(false, "Не удалось проверить действие.")
		return
	var forecast: Dictionary = _probe.command(module_id, operation, args)
	if not forecast.ok:
		_queue.resolve(false, Names.error(str(forecast.error)))
		return
	var before := int(Gameplay.simulation.state.clock.total_minutes)
	var ending := int(_probe.state.clock.total_minutes)
	if not ActionPolicy.commitments(Gameplay.simulation.state, ending).is_empty() and ending > before:
		_queue.resolve(false, "На это время есть встреча или срок. Выполните действие вручную.")
		return
	var result: Dictionary = Gameplay.execute(module_id, operation, args)
	_queue.resolve(bool(result.ok), Names.error(str(result.get("error", ""))))
	if result.ok:
		_notify(str(command.title) + " · выполнено")
		_refresh()
		if _wait.disabled: _queue.stop("План остановлен: началось событие.")

func _context_action(callback: Callable, caption: String) -> void:
	var bound: Array = callback.get_bound_arguments()
	if callback.get_method() == "_act" and bound.size() == 3 and (_queue.planning or Input.is_key_pressed(KEY_SHIFT)):
		_queue.enqueue({"title":caption.replace("\n", " "), "module":str(bound[0]), "operation":str(bound[1]), "args":bound[2]})
		return
	callback.call()

func _place() -> void:
	var sim = Gameplay.simulation
	var s: Dictionary = sim.state
	_heading("ДОСТУПНО ЗДЕСЬ")
	if sim.services.has("livelihood") and not s.livelihood.pending.is_empty(): UI.button(_body,"ПРОДОЛЖИТЬ РАБОЧУЮ МИНИ-ИГРУ",_open_livelihood)
	match str(s.world.location):
		"bedroom":
			_context_button("Поспать · 8 часов", _act.bind("needs", "sleep", {"minutes":480}), "Выспаться. За это время город продолжит жить.", "bed")
			_context_button("Отдохнуть · 1 час", _act.bind("character", "rest", {"minutes":60}), "", "rest")
			if float(s.player.needs.rested) < 70.0: _context_button("Вздремнуть · 30 мин", _act.bind("needs", "nap"), "Короткий сон в кровати", "bed")
			_context_button("Сесть за работу", open_panel.bind("work"), "", "desk")
			_context_button("Заняться хобби · 30 мин", _act.bind("needs", "leisure"), "Восстановить потребность в досуге", "leisure")
		"bathroom":
			_context_button("Принять душ · 15 мин", _act.bind("world", "shower"), "", "hygiene")
			_context_button("Сходить в туалет · 5 мин", _act.bind("needs", "toilet"), "", "toilet")
			_context_button("Выпить воды · 2 мин", _act.bind("needs", "drink"), "", "thirst")
		"kitchen":
			_context_button("Выпить воды · 2 мин", _act.bind("needs", "drink"), "", "thirst")
			for id in sim.catalog.recipes: _context_button("%s · %d мин" % [Names.title(id), sim.catalog.recipes[id].get("minutes",20)], _act.bind("inventory", "craft", {"id":id}), "Нужны плита и ингредиенты")
			_context_button("Поесть из сумки  →", open_panel.bind("inventory"))
		"global_map":
			_context_button("Магазины и городские дела  →", open_panel.bind("work"))
			_context_button("Прогуляться для себя · 30 мин", _act.bind("needs", "leisure"), "Восстановить потребность в досуге", "leisure")
		"training_center": _context_button("Расписание и секции  →", open_panel.bind("activities"))
		"real_estate_agency": _context_button("Аренда и покупка жилья  →", open_panel.bind("home"), "Двухэтажный дом, пентхаус и помощь с социальным жильём")
		"north_shops": _context_button("Местные магазины  →", open_panel.bind("work"))
		"riverside_cafe", "city_park", "south_promenade", "north_beach":
			_context_button("Отдохнуть здесь · 30 мин", _act.bind("needs","leisure"),"Провести время в городе", "leisure")
	if str(s.world.location) == City.home(s) and not s.housing.residence.is_empty():
		_context_button("Войти домой · 1 мин",_act.bind("world","travel",{"id":"apartment_hall"}),"","home")
	if s.world.location in ["bedroom", "kitchen", "bathroom", "apartment_hall"]:
		_context_button("Навести порядок · 30 мин", _act.bind("world", "clean"), "Выносливость −5 · чистота +40", "clean")
		for room in Gameplay.simulation.services.world.routes_for(str(s.world.location)):
			_context_button(("Выйти из дома" if room == City.home(s) or room == "global_map" else Names.title(room)) + "  →",_act.bind("world","travel",{"id":room}))
	_context_button("На карту  →", open_panel.bind("map"), "Выбрать место назначения · M", "map")
	var nearby: Array = []
	for id in s.social.npcs:
		if s.social.npcs[id].location == s.world.location: nearby.append(str(id))
	if not nearby.is_empty():
		UI.label(_body, "РЯДОМ · %d" % nearby.size(), 19, UI.BLUE)
		nearby.sort()
		for id in nearby.slice(0, 3):
			var npc: Dictionary = s.social.npcs[id]
			_context_button("%s\n%s" % [npc.name, Names.title(npc.activity)], _open_npc.bind(id), "Поговорить с " + str(npc.name), "profile")
		if nearby.size() > 3: _context_button("Все люди и отношения  →", open_panel.bind("people"))

func _context_button(caption: String, callback: Callable, hint: String = "", kind: String = "arrow") -> Button:
	var button := UI.button(_body, "", _context_action.bind(callback, caption))
	button.custom_minimum_size.y = 54 if not "\n" in caption else 64
	HUD.quiet_button(button)
	button.tooltip_text = hint if not hint.is_empty() else caption
	var bound: Array = callback.get_bound_arguments()
	if callback.get_method() == "_act" and bound.size() == 3:
		var minutes := ActionPolicy.duration(Gameplay.simulation, str(bound[0]), str(bound[1]), bound[2])
		var caution := _commitment_hint(int(Gameplay.simulation.state.clock.total_minutes) + minutes) if minutes > 0 else ""
		if not caution.is_empty(): button.tooltip_text += "\n" + caution
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 8)
	button.add_child(margin)
	var row := UI.row(margin, 14)
	var glyph := TextureRect.new()
	glyph.texture = HUD.icon(kind)
	glyph.custom_minimum_size = Vector2(22, 22)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.modulate = UI.BLUE
	row.add_child(glyph)
	var parts := caption.replace("  →", "").split(" · ", true, 1)
	var label := UI.label(row, parts[0], 18)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var trailing := UI.label(row, parts[1] if parts.size() > 1 else "›", 14, UI.MUTED)
	trailing.autowrap_mode = TextServer.AUTOWRAP_OFF
	trailing.size_flags_horizontal = Control.SIZE_SHRINK_END
	trailing.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ignore_pointer(margin)
	return button

func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_pointer(child)

func _map() -> void:
	_heading("Карта города", "Выберите метку на карте и подтвердите переход.")

func _city_travel(id: String) -> void:
	var result := Gameplay.execute("world","journey",{"id":id})
	if result.ok:
		_notify("%s · %d мин в пути" % [Names.title(id),int(result.data.minutes)])
		open_panel("place")
	else:
		_notify(Names.error(str(result.error)))
		_refresh()

func _profile() -> void:
	var sim = Gameplay.simulation
	var s: Dictionary = sim.state
	_heading(str(s.player.name))
	UI.button(_body,"ПРАКТИКА И ПОЛЕЗНЫЕ ПРИВЫЧКИ",_open_growth).set_meta("growth_entry","skills")
	GameScreens._compact_links(_body)
	var columns := UI.row(_body, 54)
	var identity := UI.column(columns, 14)
	identity.custom_minimum_size.x = 350
	var runtime_portrait := Portrait.new()
	runtime_portrait.custom_minimum_size = Vector2(330, 410)
	runtime_portrait.set_actor(preload("res://scripts/portraits/character_visuals.gd").player_actor(GameSession.get_character_profile(), s.player))
	identity.add_child(runtime_portrait)
	UI.label(identity, "Уровень %d  ·  опыт %d" % [s.player.level, s.player.xp], 18, UI.MUTED)
	UI.button(identity, "СУМКА  ·  I", open_panel.bind("inventory"))
	for slot in s.inventory.equipped:
		UI.button(identity, "Снять: " + Names.title(s.inventory.equipped[slot]), _act.bind("inventory", "unequip", {"slot":slot}))
	var detail := UI.column(columns, 22)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tabs := UI.row(detail, 14)
	for id in {"attributes":"Характеристики", "skills":"Навыки", "perks":"Особенности"}:
		var caption: String = {"attributes":"Характеристики", "skills":"Навыки", "perks":"Особенности"}[id]
		var tab := UI.button(tabs, caption, _select_profile_tab.bind(id))
		tab.set_meta("profile_tab", id)
		HUD.quiet_button(tab)
		if id == _profile_tab:
			tab.add_theme_stylebox_override("normal", HUD.button_style(Color.TRANSPARENT, UI.BLUE))
			tab.modulate = UI.BLUE
	match _profile_tab:
		"attributes":
			if s.player.points > 0: UI.label(detail, "%d свободных очков" % s.player.points, 18, UI.MUTED)
			var stats := W.grid(detail, 2)
			for id in s.player.stats:
				var tile := W.panel(stats, 14)
				var row := UI.row(tile, 12)
				UI.label(row, Names.title(id), 22)
				var effective: float = sim.services.character.effective_stat(str(id))
				var value := UI.label(row, "%d" % s.player.stats[id] if is_equal_approx(effective, float(s.player.stats[id])) else "%d  (%.1f)" % [s.player.stats[id], effective], 24, UI.INK)
				value.size_flags_horizontal = Control.SIZE_SHRINK_END
				value.autowrap_mode = TextServer.AUTOWRAP_OFF
				value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				var button := UI.button(row, "+", _act.bind("character", "allocate", {"stat":id}))
				button.custom_minimum_size = Vector2(42, 42)
				button.tooltip_text = "Повысить «%s» за одно очко" % Names.title(id)
				button.disabled = s.player.points <= 0 or s.player.stats[id] >= 100
		"skills":
			UI.label(detail,"Самые развитые навыки",23,UI.BLUE)
			var skills := W.grid(detail, 2)
			var ranked: Array = sim.catalog.skills.keys()
			ranked.sort_custom(func(a,b): return int(s.player.skills.get(a,0)) > int(s.player.skills.get(b,0)))
			for id in ranked.slice(0,8):
				var tile := W.panel(skills, 14)
				var row := UI.row(tile)
				UI.label(row, Names.title(id), 21, UI.MUTED)
				var value := UI.label(row,"ур. %d · %d" % [sim.services.growth.level(id),int(s.player.skills.get(id,0))],23)
				value.size_flags_horizontal = Control.SIZE_SHRINK_END
				value.autowrap_mode = TextServer.AUTOWRAP_OFF
			W.primary(detail,"Все навыки и практика",_open_growth)
		"perks":
			for id in s.player.perks: UI.label(detail, Names.title(id), 22, UI.BLUE)
			for id in sim.catalog.perks:
				if not id in s.player.perks: _offer(detail, Names.title(id), "%d очков" % sim.catalog.perks[id].get("cost", 1), "character", "perk", {"id":id})
	for id in sim.catalog.outfits:
		var owned := true
		for item in sim.catalog.outfits[id].items:
			if int(s.inventory.items.get(item,0)) < 1: owned = false
		if owned: _offer(_body,"Надеть комплект: " + {"casual":"На каждый день","work":"Рабочий комплект","training":"Спортивный комплект"}.get(id,Names.title(id)),"Вещи должны находиться в сумке","appearance","outfit",{"id":id})

func _choose_screen(value: String, key: String) -> void:
	_screen_state[key] = value
	_scroll.scroll_vertical = 0
	_refresh()
	for button in _body.find_children("*", "Button", true, false):
		if button.get_meta("screen_tab", "") == value:
			button.grab_focus()
			return

func _select_profile_tab(id: String) -> void:
	_profile_tab = id
	_refresh()
	for button in _body.find_children("*", "Button", true, false):
		if button.get_meta("profile_tab", "") == id: button.grab_focus(); break

func _inventory() -> void:
	_heading("Сумка")
	var inventory := InventoryView.new()
	inventory.sim = Gameplay.simulation
	inventory.view_state = _inventory_state
	inventory.action_requested.connect(_act)
	_body.add_child(inventory)

func _open_npc(id: String) -> void:
	selected_npc = id
	var npc: Dictionary = Gameplay.simulation.state.social.npcs[id]
	if npc.location != Gameplay.simulation.state.world.location:
		open_panel("npc")
		return
	_open_conversation(id, "free")

func _open_conversation(id: String, channel: String, initiative: String = "") -> void:
	if channel == "message":
		selected_npc = id
		open_panel("phone")
		_phone_view.open_thread(id, initiative)
		return
	if is_instance_valid(_conversation): return
	selected_npc = id
	var conversation := preload("res://scripts/ui/gameplay/conversation_window.gd").new()
	_conversation = conversation
	conversation.configure(id,channel,_background.texture.resource_path,initiative)
	conversation.menu_requested.connect(_request_menu)
	conversation.details_requested.connect(func(_id): open_panel("npc"))
	conversation.closed.connect(func():
		_conversation = null
		if current_panel != "place": _close_panel.grab_focus()
		else: _dock_buttons.people.grab_focus())
	add_child(conversation)

func _phone() -> void:
	_title.text = "Телефон"
	_phone_view.present()

func _npc() -> void:
	if _npc_risk: _risk_view(selected_npc)
	else: GameScreens.person(self,_body)

func _open_personal_story(id: String) -> void:
	var window = load("res://scripts/ui/gameplay/personal_story_window.gd").new()
	window.npc_id = id
	add_child(window)

func _people() -> void:
	_heading("Люди")
	var view := PeopleView.new()
	view.owner_ui = self
	_body.add_child(view)

func _gathering() -> void:
	var sim = Gameplay.simulation
	_heading("Время вместе", "Общий вечер помогает отдохнуть и познакомить знакомых между собой.")
	UI.button(_body, "←  К ЛЮДЯМ И ОТНОШЕНИЯМ", open_panel.bind("people"))
	var nearby: Array[String] = []
	for id in sim.state.social.npcs:
		if sim.state.social.npcs[id].location == sim.state.world.location: nearby.append(str(id))
	_gathering_guests.assign(_gathering_guests.filter(func(id): return id in nearby))
	var card := UI.card(_body)
	UI.label(card, "Кого позвать", 24, UI.BLUE)
	UI.label(card, "90 мин · 2–6 гостей рядом · по обеду на гостя · выносливость −10. Участники знакомятся друг с другом.", 18, UI.MUTED)
	if nearby.is_empty():
		UI.label(card, "Сначала найдите компанию или пригласите знакомых к себе через телефон.", 18, UI.MUTED)
	for id in nearby:
		var available: Dictionary = sim.services.social_rules.guest_availability(id)
		var selected := id in _gathering_guests
		var choice := UI.button(card, ("✓  " if selected else "+  ") + str(sim.state.social.npcs[id].name), _toggle_gathering_guest.bind(id))
		choice.set_meta("gathering_guest", id)
		choice.disabled = not selected and (not available.ok or _gathering_guests.size() >= 6)
		if not available.ok: choice.tooltip_text = Names.error(str(available.error))
	var button := _offer(card, "Встреча · выбрано %d" % _gathering_guests.size(), "Обедов в сумке: %d" % int(sim.state.inventory.items.get("meal", 0)), "social_rules", "gathering", {"candidates":_gathering_guests.duplicate()})
	if not button.disabled: button.text = "ПРОВЕСТИ ВСТРЕЧУ · 90 МИН"

func _toggle_gathering_guest(id: String) -> void:
	if id in _gathering_guests: _gathering_guests.erase(id)
	elif _gathering_guests.size() < 6: _gathering_guests.append(id)
	_refresh()
	for button in _body.find_children("*", "Button", true, false):
		if button.get_meta("gathering_guest", "") == id: button.grab_focus(); break

func _show_npc_details(id: String) -> void:
	selected_npc = id
	open_panel("npc")

func _family_plan(id: String) -> void:
	var result := Gameplay.plan_family(id)
	if result.ok: _notify("Открыт разговор о времени наедине и семейных намерениях."); _refresh()
	else: _notify(Names.error(str(result.error)))

func _risk_actions(id: String) -> void:
	selected_npc = id
	_npc_risk = true
	_refresh()

func _risk_view(id: String) -> void:
	_heading("На грани конфликта","Драка и кража могут привести к травмам, недоверию и штрафам.")
	_offer(_body,"Начать драку","Риск травм для обоих участников","combat","start",{"npc":id})
	_offer(_body,"Попытаться украсть деньги","10 мин · свидетели снижают шансы","security","steal",{"npc":id})
	_offer(_body,"Попытаться проникнуть в жильё","Нужна отмычка и присутствие у дома цели","security","begin_burglary",{"npc":id})
	UI.button(_body,"Назад к человеку",_back_panel)

func _journal() -> void:
	UI.button(_body,"МОИ ЖИЗНЕННЫЕ ЦЕЛИ",_open_livelihood.bind("goals"))
	GameScreens.journal(self, _body)

func _activities() -> void:
	GameScreens.activities(self, _body)

func _work() -> void:
	UI.button(_body,"РАБОТА, ЗАКАЗЫ И СВОИ ЦЕЛИ",_open_livelihood).set_meta("livelihood_entry","jobs")
	GameScreens.work(self, _body)

func _open_livelihood(page: String = "jobs") -> void:
	var window = load("res://scripts/ui/gameplay/livelihood_window.gd").new()
	window.page = page
	add_child(window)

func _digital() -> void:
	GameScreens.digital(self, _body)

func _club() -> void:
	GameScreens.club(self, _body)

func _club_election(id: String, group: Dictionary) -> void:
	var candidates: Array = group.members.keys()
	if candidates.size() >= 2:
		if group.election.is_empty() or group.election.status != "active": UI.button(_body,"НАЗНАЧИТЬ ВЫБОРЫ",_act.bind("institutions","election",{"id":id,"candidates":candidates}))
		else:
			UI.label(_body,"Выборы руководителя",25,UI.BLUE)
			UI.label(_body, "Участники проголосуют сами, когда будут свободны. Подано голосов: %d / %d." % [group.election.votes.size(), group.members.size()], 19, UI.MUTED)
			_offer(_body, "Провести голосование", "30 мин · личный выбор каждого участника", "institutions", "hold_vote", {"id":id})
	if not group.election.is_empty() and group.election.status == "completed":
		UI.label(_body, "Руководитель: " + Names.actor_name(Gameplay.simulation, str(group.election.winner)), 22, UI.BLUE)

func _home() -> void:
	UI.button(_body,"УЛУЧШЕНИЯ ДЛЯ УЮТА И РАБОТЫ",_open_livelihood.bind("home"))
	GameScreens.home(self, _body)

func _health() -> void:
	UI.button(_body,"МОИ ПОТРЕБНОСТИ И ПРИВЫЧКИ",_open_growth.bind("needs"))
	GameScreens.health(self, _body)

func _open_growth(page: String = "skills") -> void:
	var window = load("res://scripts/ui/gameplay/growth_window.gd").new()
	window.page = page
	add_child(window)

func _active_encounter() -> bool:
	var sim = Gameplay.simulation
	var combat: Dictionary = sim.state.encounters.combat
	if not combat.is_empty() and combat.status == "active":
		GameScreens.combat(self, _body)
		return true
	var game: Dictionary = sim.state.encounters.game
	if not game.is_empty() and game.status == "active":
		_heading({"blackjack":"Двадцать одно","timing":"Поймать ритм","reaction":"Реакция","guess":"Угадать число","lockpick":"Учебный замок","strength":"Проверка силы","pushups":"Отжимания"}[str(game.type)],"Завершите испытание или откройте меню, чтобы сделать паузу.")
		var window := MiniGame.new()
		window.custom_minimum_size.y = 500
		_body.add_child(window)
		return true
	return false

func _at_home() -> bool:
	return Gameplay.simulation.state.world.location in ["bedroom","kitchen","bathroom","apartment_hall"]

func _interface() -> void:
	UI.button(_body,"НАСТРОИТЬ ПОТРЕБНОСТИ ПЕРСОНАЖА",_open_growth.bind("needs"))
	GameScreens._compact_links(_body)
	_heading("Интерфейс и управление", "Понятные действия, предсказуемое время, свободный обзор")
	var card := UI.card(_body)
	UI.label(card, "Размер текста", 25)
	UI.label(card, "Применяется к игровым окнам, диалогам и подсказкам. Настройка хранится отдельно от сохранений.", 18, UI.MUTED)
	var options := UI.row(card)
	for scale in [0.9, 1.0, 1.1, 1.25]:
		var button := UI.button(options, "%d %%" % roundi(scale * 100), func():
			UI.set_text_scale(scale)
			theme = UI.skin()
			UI.apply_text_scale(self)
			_refresh())
		if is_equal_approx(UI.text_scale, scale): button.add_theme_stylebox_override("normal", UI.style(Color("193246"), UI.BLUE))
	var columns := UI.row(_body, 22)
	var controls := UI.card(columns)
	UI.label(controls, "Всегда под рукой", 25)
	for line in ["I · сумка     C · персонаж", "J · журнал     M · карта города", "R · люди     P · телефон", "F1 · все разделы     H · скрыть HUD", "Q · план действий", "Esc · закрыть верхнее окно, затем меню", "Tab / стрелки · навигация", "Enter / пробел · выбрать действие"]:
		UI.label(controls, line, 18, UI.MUTED)
	var planning := UI.card(columns)
	UI.label(planning, "Планируйте свой день", 25)
	UI.label(planning, "Включите «План действий» и выберите занятия по месту. Или удерживайте Shift при выборе. В плане помещается до шести действий.", 19, UI.MUTED)
	UI.label(planning, "▶ начинает выполнение, пауза останавливает его между действиями. × убирает действие. Недоступное действие, встреча или новое событие останавливают план.", 19, UI.MUTED)
	UI.label(planning, "Время идёт только при выполнении действий. Просмотр окон и составление плана его не расходуют.", 19, UI.BLUE)

func _request_menu() -> void:
	_queue.stop()
	menu_requested.emit()

func _toggle_plan() -> void:
	if current_panel != "place": open_panel("place")
	_queue.planning = not _queue.planning
	_queue.refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or is_instance_valid(_conversation): return
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		if _queue.running: _queue.stop()
		get_viewport().set_input_as_handled()
		if _sections_overlay.visible: _toggle_sections()
		elif current_panel == "phone": _phone_view.go_back()
		elif not _chrome.visible: _toggle_hud()
		elif current_panel != "place": _back_panel()
		else: _request_menu()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit: return
		if _wait.disabled: return
		if event.keycode == KEY_H:
			get_viewport().set_input_as_handled()
			_toggle_hud()
			return
		if not _chrome.visible:
			return
		if event.keycode == KEY_F1:
			get_viewport().set_input_as_handled()
			_toggle_sections()
			return
		if event.keycode == KEY_Q:
			get_viewport().set_input_as_handled()
			_toggle_plan()
			return
		var keys := {KEY_I:"inventory",KEY_C:"profile",KEY_J:"journal",KEY_M:"map",KEY_P:"phone",KEY_R:"people"}
		if keys.has(event.keycode):
			get_viewport().set_input_as_handled()
			_toggle_panel(keys[event.keycode])
