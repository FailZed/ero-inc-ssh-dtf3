extends Control
## A persistent, in-world phone. Browsing apps is read-only; taps invoke real commands.
signal closed
signal screen_requested(id: String)
signal person_requested(id: String)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Social = preload("res://scripts/gameplay/social_presentation.gd")
const Preferences = preload("res://scripts/ui/gameplay/phone_preferences.gd")
var preferences = Preferences.new()
var app := "home"
var contact := ""
var drafts: Dictionary = {}
var _session := ""
var _pending := false
var _error := ""
var _body: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _clock: Label
var _back: Button
var _composer: LineEdit
var _message_scroll: ScrollContainer
var _frame: PanelContainer
var _page: VBoxContainer
var _query := ""
var _bank_amount := 50.0
var _greeting: Dictionary = {}
var _history_limit := 40
var _scroll_request := -1
var _scroll_epoch := 0
var _layout_pending := false
var _saved_scroll := -1
var _saved_follow := true
var _glass: PanelContainer
var _wallpaper: TextureRect
var _wallpaper_material: ShaderMaterial
var _wallpaper_button: Button
var _preview_choice := "city"
var _preview_dimming := 0.22
var _picker: FileDialog

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name = "Phone"
	theme = UI.skin()
	theme.default_font = ThemeDB.fallback_font
	preferences.load_settings()
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.005, 0.01, 0.02, 0.28)
	veil.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: closed.emit())
	add_child(veil)
	_frame = PanelContainer.new()
	_frame.name = "Device"
	_frame.anchor_left = 1.0
	_frame.anchor_right = 1.0
	_frame.anchor_top = 0.5
	_frame.anchor_bottom = 0.5
	_frame.offset_left = -548
	_frame.offset_right = -64
	_frame.offset_top = -456
	_frame.offset_bottom = 456
	var skin := StyleBoxTexture.new()
	skin.texture = preload("res://assets/textures/ui/raster-v1/phone_body.png")
	skin.set_content_margin_all(20)
	_frame.add_theme_stylebox_override("panel",skin)
	add_child(_frame)
	_wallpaper = TextureRect.new()
	_wallpaper.name = "Wallpaper"
	_wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wallpaper.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_wallpaper_material = ShaderMaterial.new()
	_wallpaper_material.shader = preload("res://assets/shaders/phone_wallpaper.gdshader")
	_wallpaper.material = _wallpaper_material
	_frame.add_child(_wallpaper)
	_wallpaper.resized.connect(func(): _wallpaper_material.set_shader_parameter("surface_size",_wallpaper.size))
	_glass = PanelContainer.new()
	var glass_style := UI.style(Color.TRANSPARENT, Color.TRANSPARENT)
	glass_style.set_corner_radius_all(23)
	glass_style.set_content_margin_all(18)
	_glass.add_theme_stylebox_override("panel", glass_style)
	_frame.add_child(_glass)
	_page = UI.column(_glass, 12)
	var status := UI.row(_page)
	_clock = UI.label(status, "", 14)
	var camera := UI.label(status, "●", 14, Color("02070b"))
	camera.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var carrier := UI.label(status, "EINC  ▰", 12, UI.MUTED)
	carrier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var heading := UI.row(_page, 8)
	_back = UI.button(heading, "‹", go_back)
	_back.custom_minimum_size = Vector2(34, 40)
	_back.tooltip_text = "Назад · Esc"
	HUD.quiet_button(_back)
	_title = UI.label(heading, "", 24)
	_wallpaper_button = UI.button(heading,"Обои",_open_app.bind("wallpapers"))
	_wallpaper_button.custom_minimum_size.y = 36
	_wallpaper_button.add_theme_font_size_override("font_size",15)
	_wallpaper_button.tooltip_text = "Сменить фон телефона"
	HUD.quiet_button(_wallpaper_button)
	var close := HUD.dock_button(heading, "Убрать телефон", "P", "close", closed.emit)
	close.custom_minimum_size = Vector2(34, 40)
	_body = UI.column(_page, 12)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var home := UI.button(_page, "━━━━", _go_home)
	home.custom_minimum_size.y = 26
	home.tooltip_text = "Главный экран телефона"
	HUD.quiet_button(home)
	Gameplay.changed.connect(_queue_refresh)
	hide()
	_rebuild()

func present() -> void:
	show()
	_rebuild()

func open_calendar() -> void:
	_open_app("calendar")

func focus_default() -> void:
	if app == "chat" and is_instance_valid(_composer): _composer.grab_focus()
	else:
		for button in _body.find_children("*", "Button", true, false):
			if button.visible and not button.disabled: button.grab_focus(); return
		_back.grab_focus()

func _queue_refresh() -> void:
	if _pending or not visible: return
	_pending = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_pending = false
	if not is_inside_tree(): return
	theme = UI.skin()
	theme.default_font = ThemeDB.fallback_font
	var restore_caret := -1
	var old_scroll := _saved_scroll
	var following := _saved_follow
	if is_instance_valid(_message_scroll) and app == "chat" and not _layout_pending:
		old_scroll = _message_scroll.scroll_vertical
		var bar := _message_scroll.get_v_scroll_bar()
		following = float(old_scroll) >= bar.max_value-bar.page-24
	_message_scroll = null
	var previous := get_viewport().gui_get_focus_owner()
	var focus_key := str(previous.get_meta("phone_focus","")) if previous != null else ""
	var saved_caret: int = previous.caret_column if previous is LineEdit else -1
	if is_instance_valid(_composer) and _composer.has_focus(): restore_caret = _composer.caret_column
	_composer = null
	UI.clear(_body)
	_clock.text = str(Gameplay.simulation.state.clock.time_text)
	_title.text = {"home":"", "messages":"Сообщения", "contacts":"Контакты", "calendar":"Календарь", "chat":"", "person":"Контакт", "meeting":"Новая встреча", "bank":"Банк", "wallpapers":"Обои"}.get(app, "")
	_back.visible = app != "home"
	_wallpaper_button.visible = app == "home"
	_apply_wallpaper()
	match app:
		"home": _home()
		"messages", "contacts": _contacts()
		"chat": _chat()
		"person": _person()
		"calendar": _calendar()
		"meeting": _meeting()
		"bank": _bank()
		"wallpapers": _wallpapers()
	_scroll_epoch += 1
	if app == "chat" and is_instance_valid(_message_scroll):
		_saved_scroll = 0 if _scroll_request == 0 else 100000 if _scroll_request == 1 or old_scroll < 0 or following else old_scroll
		_saved_follow = _saved_scroll == 100000
		_layout_pending = true
		_settle_chat_scroll.call_deferred(_scroll_epoch,_saved_scroll)
	else:
		_layout_pending = false
		_saved_scroll = -1
		_saved_follow = true
	_scroll_request = -1
	if not _error.is_empty(): UI.label(_body, _error, 15, UI.ORANGE).max_lines_visible = 3
	if restore_caret >= 0 and is_instance_valid(_composer):
		_composer.grab_focus()
		_composer.caret_column = mini(restore_caret, _composer.text.length())
	elif not focus_key.is_empty():
		for control in _body.find_children("*","Control",true,false):
			if control.get_meta("phone_focus","") == focus_key:
				control.grab_focus()
				if control is LineEdit and saved_caret >= 0: control.caret_column = mini(saved_caret,control.text.length())
				break

func _settle_chat_scroll(epoch: int, position: int) -> void:
	await get_tree().process_frame
	if epoch != _scroll_epoch or not is_instance_valid(_message_scroll): return
	_message_scroll.scroll_vertical = position
	await get_tree().process_frame
	if epoch != _scroll_epoch or not is_instance_valid(_message_scroll): return
	_saved_scroll = _message_scroll.scroll_vertical
	_layout_pending = false

func _apply_wallpaper() -> void:
	_wallpaper.texture = preferences.texture()
	_wallpaper.visible = app == "home" and _wallpaper.texture != null
	_wallpaper_material.set_shader_parameter("dimming",preferences.dimming)
	# Other apps use the phone's dark screen so long messages remain readable.
	var surface := _glass.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	surface.bg_color = Color.TRANSPARENT if app == "home" else Color("0e1b27")
	_glass.add_theme_stylebox_override("panel",surface)

func _wallpapers() -> void:
	var list := UI.scroller(_body)
	var grid := W.grid(list,2)
	var ids: Array = Preferences.WALLPAPERS.keys()
	if FileAccess.file_exists(preferences.data_dir.path_join("custom.png")): ids.append("custom")
	for id in ids:
		var cell := UI.column(grid,4)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := UI.button(cell,"",func(): _preview_choice = id; _rebuild())
		button.set_meta("wallpaper_id",id)
		button.set_meta("phone_focus","wallpaper:"+str(id))
		button.custom_minimum_size = Vector2(164,158)
		var edge := UI.style(Color("0c1721"),UI.BLUE if id == _preview_choice else Color("405969"))
		edge.set_border_width_all(2 if id == _preview_choice else 1)
		button.add_theme_stylebox_override("normal",edge)
		var thumbnail := TextureRect.new()
		thumbnail.texture = preferences.texture(id)
		thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		thumbnail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		thumbnail.offset_left = 4; thumbnail.offset_top = 4
		thumbnail.offset_right = -4; thumbnail.offset_bottom = -4
		thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumbnail.modulate = Color(1.0-_preview_dimming,1.0-_preview_dimming,1.0-_preview_dimming)
		button.add_child(thumbnail)
		var caption := "Своё изображение" if id == "custom" else str(Preferences.WALLPAPERS[id].title)
		UI.label(cell,("✓ " if id == _preview_choice else "")+caption,14,UI.BLUE if id == _preview_choice else UI.INK)
	var row := UI.row(list)
	UI.label(row,"Затемнение",16,UI.MUTED)
	var slider := HSlider.new()
	slider.min_value = 0.0; slider.max_value = 0.7; slider.step = 0.05
	slider.value = _preview_dimming
	slider.custom_minimum_size = Vector2(160,40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "Затемнить изображение для читаемости часов и значков"
	row.add_child(slider)
	slider.value_changed.connect(func(value):
		_preview_dimming = value
		for item in grid.find_children("*","TextureRect",true,false): item.modulate = Color(1.0-value,1.0-value,1.0-value))
	UI.button(list,"Своё изображение…",_pick_wallpaper)
	UI.label(list,"PNG, JPG или WebP. Изображение будет обрезано по форме экрана.",13,UI.MUTED)
	W.primary(_body,"Установить",_install_wallpaper)

func _install_wallpaper() -> void:
	var old_dimming: float = preferences.dimming
	preferences.dimming = _preview_dimming
	var result: Error = preferences.choose(_preview_choice)
	if result != OK:
		preferences.dimming = old_dimming
		_error = "Не удалось сохранить фон телефона."
	else:
		app = "home"
		_error = ""
	_rebuild()
	focus_default()

func _pick_wallpaper() -> void:
	if is_instance_valid(_picker): _picker.queue_free()
	_picker = FileDialog.new()
	_picker.title = "Фон телефона"
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_picker.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp; Изображения"])
	_picker.use_native_dialog = true
	_picker.file_selected.connect(_import_wallpaper)
	add_child(_picker)
	_picker.popup_centered_ratio(0.7)

func _import_wallpaper(path: String) -> void:
	var result: Error = preferences.import_image(path)
	if result == OK:
		_preview_choice = "custom"
		app = "home"
		_error = ""
	else: _error = "Не удалось открыть изображение. Выберите PNG, JPG или WebP."
	_rebuild()
	focus_default()

func _home() -> void:
	var clock := UI.label(_body, str(Gameplay.simulation.state.clock.time_text), 68, UI.INK)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var now: Dictionary = Gameplay.simulation.state.clock
	UI.label(_body, "%d %s" % [now.day,["января","февраля","марта","апреля","мая","июня","июля","августа","сентября","октября","ноября","декабря"][int(now.month_number)-1]], 18, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var space := Control.new()
	space.custom_minimum_size.y = 26
	_body.add_child(space)
	var apps := W.grid(_body, 3)
	apps.add_theme_constant_override("v_separation",24)
	var unread := _unread()
	for spec in [["messages","Сообщения"], ["contacts","Контакты"], ["calendar","Встречи"], ["bank","Банк"], ["map","Город"], ["journal","Заметки"]]:
		var item := UI.column(apps, 6)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := UI.button(item, "", _open_app.bind(spec[0]))
		button.custom_minimum_size = Vector2(94, 88)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.icon = load("res://assets/textures/ui/raster-v1/app_"+str(spec[0])+".png")
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width",80)
		# Native transparent hit areas; artwork is a circular Android-style icon.
		for state in ["normal","hover","pressed","focus"]:
			var style := UI.style(Color(0.70,0.84,1.0,0.12) if state == "hover" else Color(0.70,0.84,1.0,0.22) if state == "pressed" else Color.TRANSPARENT,UI.BLUE if state == "focus" else Color.TRANSPARENT)
			style.set_content_margin_all(3)
			style.set_corner_radius_all(44)
			style.set_border_width_all(2 if state == "focus" else 0)
			button.add_theme_stylebox_override(state,style)
		button.add_theme_color_override("icon_normal_color",Color.WHITE)
		button.add_theme_color_override("icon_hover_color",Color.WHITE)
		button.add_theme_color_override("icon_focus_color",Color.WHITE)
		button.add_theme_color_override("icon_pressed_color",Color.WHITE)
		button.set_meta("phone_app",spec[0])
		button.tooltip_text = spec[1]
		var caption := UI.label(item,spec[1],14,Color("f0f4f8"))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_color_override("font_shadow_color",Color(0,0,0,0.85))
		caption.add_theme_constant_override("shadow_offset_y",1)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if spec[0] == "messages" and unread > 0:
			var badge := Label.new()
			badge.text = str(mini(unread,99)) + ("+" if unread > 99 else "")
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge.add_theme_font_size_override("font_size",13)
			badge.add_theme_color_override("font_color",Color.WHITE)
			var dot := UI.style(Color("c7563f"),Color("12222e"))
			dot.set_corner_radius_all(14)
			dot.set_content_margin_all(3)
			dot.set_border_width_all(2)
			badge.add_theme_stylebox_override("normal",dot)
			button.add_child(badge)
			badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			badge.offset_left = -31
			badge.offset_right = -5
			badge.offset_top = 3
			badge.offset_bottom = 29
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var upcoming := _upcoming()
	if not upcoming.is_empty():
		var note := W.panel(_body, 14, Color("172c3b"))
		UI.label(note, "Ближайшая встреча", 14, UI.BLUE)
		var date: Dictionary = Gameplay.simulation.calendar.snapshot(int(upcoming.minute))
		UI.label(note, "%s · %s" % [Names.actor_name(Gameplay.simulation, upcoming.npc), date.time_text], 19)
		UI.label(note, Names.title(upcoming.location), 15, UI.MUTED)
		UI.button(note, "Посмотреть", _open_app.bind("calendar"))

func _open_app(id: String) -> void:
	_error = ""
	if id in ["map", "journal"]: screen_requested.emit(id); return
	_end_session()
	app = id
	if id == "wallpapers":
		_preview_choice = preferences.selected
		_preview_dimming = preferences.dimming
	_query = ""
	_rebuild()
	focus_default()

func _contacts() -> void:
	var search := LineEdit.new()
	search.placeholder_text = "Поиск…"
	search.set_meta("phone_focus","search")
	search.text = _query
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 42
	_body.add_child(search)
	var list := UI.scroller(_body)
	search.text_changed.connect(func(value): _query = value; _contact_rows(list))
	_contact_rows(list)

func _contact_rows(list: VBoxContainer) -> void:
	UI.clear(list)
	var social: Dictionary = Gameplay.simulation.state.social
	var ids: Array = social.contacts.duplicate()
	if app == "messages": ids.sort_custom(func(a,b): return _last_minute(str(a)) > _last_minute(str(b)))
	else: ids.sort_custom(func(a,b): return str(social.npcs[a].name).naturalnocasecmp_to(str(social.npcs[b].name)) < 0)
	for id in ids:
		var person: Dictionary = social.npcs[id]
		if not _query.is_empty() and not str(person.name).to_lower().contains(_query.to_lower()): continue
		var button := UI.button(list, "", open_thread.bind(str(id)) if app == "messages" else open_person.bind(str(id)))
		button.custom_minimum_size.y = 86
		button.set_meta("phone_contact", id)
		button.set_meta("phone_focus","contact:"+str(id))
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_right", 8)
		button.add_child(margin)
		var row := UI.row(margin, 12)
		W.avatar(row, str(person.name), 42)
		var text := UI.column(row, 3)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.label(text, str(person.name), 18)
		var last := _last_message(str(id))
		var preview := UI.label(text, str(last.get("text", "Начать переписку")) if app == "messages" else str(Social.bond(Gameplay.simulation, str(id)).status_text), 14, UI.MUTED)
		preview.max_lines_visible = 1
		preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if _unread(str(id)) > 0: UI.label(row, "●", 14, UI.BLUE).size_flags_horizontal = Control.SIZE_SHRINK_END
		W.ignore_pointer(margin)
	if list.get_child_count() == 0: W.empty(list, "people", "Контактов пока нет" if ids.is_empty() else "Никого не найдено", "Знакомства появятся здесь после обмена контактами." if ids.is_empty() else "Попробуйте другое имя.")

func open_person(id: String) -> void:
	_end_session()
	contact = id
	app = "person"
	_error = ""
	_rebuild()
	focus_default()

func _person() -> void:
	var person: Dictionary = Gameplay.simulation.state.social.npcs[contact]
	W.avatar(_body, str(person.name), 84)
	UI.label(_body, str(person.name), 28)
	UI.label(_body, str(Social.bond(Gameplay.simulation, contact).status_text), 17, UI.BLUE)
	W.primary(_body, "Написать сообщение", open_thread.bind(contact))
	UI.button(_body, "Позвонить · 5 мин", _call)
	UI.button(_body, "Договориться о встрече", func(): app = "meeting"; _rebuild())
	UI.button(_body, "О человеке", func(): person_requested.emit(contact))

func open_thread(id: String, initiative: String = "") -> void:
	if _session != id: _end_session()
	if contact != id: _history_limit = 40
	contact = id
	app = "chat"
	_error = ""
	_scroll_request = 1
	if _unread(id) > 0: Gameplay.execute("social", "read", {"id":id})
	if not initiative.is_empty(): _begin_topics(initiative)
	_rebuild()
	focus_default()

func _chat() -> void:
	if not Gameplay.simulation.state.social.npcs.has(contact): app = "messages"; _contacts(); return
	_title.text = str(Gameplay.simulation.state.social.npcs[contact].name)
	if is_visible_in_tree() and _unread(contact) > 0: Gameplay.execute("social","read",{"id":contact})
	var thread := UI.scroller(_body)
	thread.add_theme_constant_override("separation", 10)
	_message_scroll = thread.get_parent()
	_message_scroll.follow_focus = false
	var messages: Array = []
	for message in Gameplay.simulation.state.social.messages:
		if message.npc == contact: messages.append(message)
	if messages.size() > _history_limit:
		UI.button(thread,"Ранние сообщения",func(): _history_limit += 40; _scroll_request = 0; _rebuild())
	var show_greeting := not _greeting.is_empty() and not messages.any(func(message): return message.incoming and str(message.text) == str(_greeting.text))
	var greeted := false
	for message in messages.slice(-_history_limit):
		if show_greeting and not greeted and int(message.id) >= int(_greeting.next_message):
			_bubble(thread,str(_greeting.text),true,int(_greeting.minute))
			greeted = true
		_bubble(thread, str(message.text), bool(message.incoming), int(message.minute))
	if show_greeting and not greeted: _bubble(thread,str(_greeting.text),true,int(_greeting.minute))
	_random_event_choices(thread)
	var dialogue: Dictionary = Gameplay.simulation.services.npc_dialogue.present(contact) if _session == contact else {}
	if messages.is_empty() and dialogue.is_empty(): W.empty(thread, "chat", "Начните разговор", "Можно написать своё сообщение или выбрать тему ниже.")
	var active: bool = not dialogue.is_empty() and dialogue.get("node","end") != "end" and int(Gameplay.simulation.state.social.npcs[contact].mind.dialogue.expires) > int(Gameplay.simulation.state.clock.total_minutes)
	if active:
		var choices := UI.scroller(_body)
		choices.get_parent().size_flags_vertical = Control.SIZE_FILL
		choices.get_parent().custom_minimum_size.y = 148
		for choice in dialogue.choices:
			if choice.id == "leave": continue
			var minutes := int(choice.minutes)
			var button := UI.button(choices, str(choice.text) + (" · %d мин" % minutes if minutes > 0 else ""), _choose.bind(str(choice.id), int(dialogue.turn)))
			button.add_theme_font_size_override("font_size", roundi(15 * UI.text_scale))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size.y = 42
			button.set_meta("phone_focus","choice:"+str(choice.id))
			button.disabled = not str(choice.blocked).is_empty()
			button.tooltip_text = Names.error(str(choice.blocked)) if button.disabled else ""
	else: UI.button(_body, "Выбрать тему разговора", _begin_topics)
	var composer := UI.row(_body, 6)
	_composer = LineEdit.new()
	_composer.placeholder_text = "Сообщение…"
	_composer.text = str(drafts.get(contact, ""))
	_composer.max_length = 400
	_composer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_composer.custom_minimum_size.y = 46
	_composer.text_changed.connect(func(value): drafts[contact] = value)
	_composer.text_submitted.connect(func(_value): _send())
	composer.add_child(_composer)
	var send := UI.button(composer, "↑", _send)
	send.tooltip_text = "Отправить сообщение · Enter"
	send.custom_minimum_size = Vector2(42, 46)
	send.set_meta("phone_send", true)

func _bubble(parent: Node, text: String, incoming: bool, minute: int) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 0 if incoming else 38)
	margin.add_theme_constant_override("margin_right", 38 if incoming else 0)
	parent.add_child(margin)
	var body := W.panel(margin, 12, Color("203645") if incoming else Color("35566a"))
	var bubble_style := UI.style(Color("203645") if incoming else Color("35566a"),Color.TRANSPARENT)
	bubble_style.set_corner_radius_all(16)
	bubble_style.set_content_margin_all(12)
	body.get_parent().add_theme_stylebox_override("panel",bubble_style)
	UI.label(body, text, 18)
	var time: Dictionary = Gameplay.simulation.calendar.snapshot(minute)
	var label := UI.label(body, str(time.time_text), 11, UI.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _send() -> void:
	var text := str(drafts.get(contact, "")).strip_edges()
	if text.is_empty(): return
	var result := Gameplay.execute("social", "message", {"id":contact, "text":text})
	if result.ok: drafts[contact] = ""
	else: _error = Names.error(str(result.error))
	if result.ok: _error = ""
	_scroll_request = 1
	_rebuild()
	if is_instance_valid(_composer): _composer.grab_focus()

func _random_event_choices(parent: Node) -> void:
	for offer: Dictionary in Gameplay.simulation.services.events.random_offers(contact):
		var card := W.panel(parent,10)
		var content := preload("res://scripts/ui/gameplay/random_event_offer.gd").new()
		card.add_child(content)
		content.setup(offer,_choose_random_event)

func _choose_random_event(instance: String, choice: String) -> void:
	var result := Gameplay.execute("events","random_choose",{"id":instance,"choice":choice})
	_error = "" if result.ok else "Ситуация уже изменилась. Проверьте сообщение или вернитесь позже."
	_scroll_request = 1
	_rebuild()

func _begin_topics(initiative: String = "") -> void:
	var result := Gameplay.execute("npc_dialogue", "open", {"id":contact, "channel":"message", "initiative":initiative})
	if result.ok:
		_session = contact
		_error = ""
		_greeting = {"text":str(result.data.utterance.text),"minute":int(Gameplay.simulation.state.clock.total_minutes),"next_message":int(Gameplay.simulation.state.social.next_message_id)}
	else: _error = Names.error(str(result.error))
	_scroll_request = 1
	_rebuild()

func _choose(id: String, turn: int) -> void:
	var result := Gameplay.execute("npc_dialogue", "choose", {"id":contact, "choice":id, "turn":turn})
	_error = ""
	if not result.ok: _error = Names.error(str(result.error))
	elif _unread(contact) > 0: Gameplay.execute("social", "read", {"id":contact})
	_scroll_request = 1
	_rebuild()

func _call() -> void:
	var result := Gameplay.execute("social", "call", {"id":contact, "text":"Как проходит твой день?"})
	_error = "Звонок завершён · 5 мин" if result.ok else Names.error(str(result.error))
	_rebuild()

func _calendar() -> void:
	var list := UI.scroller(_body)
	var count := 0
	for meeting in Gameplay.simulation.state.social.appointments:
		if meeting.status != "pending": continue
		count += 1
		var day: Dictionary = Gameplay.simulation.calendar.snapshot(int(meeting.minute))
		var note := W.panel(list, 16)
		UI.label(note, "%s  ·  %s" % [day.date_text, day.time_text], 18, UI.BLUE)
		UI.label(note, Names.actor_name(Gameplay.simulation, str(meeting.npc)), 22)
		UI.label(note, Names.title(str(meeting.location)), 16, UI.MUTED)
		UI.button(note, "Показать на карте", func(): screen_requested.emit("map"))
	if count == 0: W.empty(list, "clock", "Пока нет планов", "Выберите контакт и предложите встречу.")
	UI.button(_body, "Выбрать, с кем встретиться", _open_app.bind("contacts"))

func _meeting() -> void:
	UI.label(_body, Names.actor_name(Gameplay.simulation, contact), 27)
	UI.label(_body, "Когда?", 18, UI.MUTED)
	var delay := OptionButton.new()
	for minutes in [60, 120, 180, 1440]:
		delay.add_item({60:"Через час",120:"Через два часа",180:"Через три часа",1440:"Завтра в это же время"}[minutes])
		delay.set_item_metadata(delay.item_count - 1, minutes)
	_body.add_child(delay)
	UI.label(_body, "Где?", 18, UI.MUTED)
	var place := OptionButton.new()
	for id in ["south_trade_street", "riverside_cafe_front", "city_park", "south_promenade"]:
		place.add_item(Names.title(id))
		place.set_item_metadata(place.item_count - 1, id)
	_body.add_child(place)
	W.primary(_body, "Предложить встречу", func():
		var result := Gameplay.execute("social", "appointment", {"id":contact, "minute":int(Gameplay.simulation.state.clock.total_minutes) + int(delay.get_item_metadata(delay.selected)), "location":str(place.get_item_metadata(place.selected))})
		if result.ok: app = "calendar"
		else: _error = Names.error(str(result.error))
		_rebuild())

func _bank() -> void:
	var economy: Dictionary = Gameplay.simulation.state.economy
	UI.label(_body, "На счёте", 16, UI.MUTED)
	UI.label(_body, "%d ¤" % economy.bank, 46)
	UI.label(_body, "С собой %d ¤   ·   долг %d ¤" % [economy.cash, economy.debt], 16, UI.MUTED)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 10000
	amount.value = _bank_amount
	amount.value_changed.connect(func(value): _bank_amount = value)
	amount.custom_minimum_size.y = 48
	_body.add_child(amount)
	amount.get_line_edit().set_meta("phone_focus","bank_amount")
	for id in ["deposit", "withdraw", "borrow", "repay"]:
		var button := UI.button(_body, {"deposit":"Внести на счёт", "withdraw":"Снять наличные", "borrow":"Взять кредит", "repay":"Погасить долг"}[id], func():
			var result := Gameplay.execute("economy", id, {"amount":int(amount.value)})
			_error = "" if result.ok else Names.error(str(result.error))
			_rebuild())
		button.set_meta("phone_focus","bank:"+id)
	UI.label(_body, "По понедельникам: вклад +1 %, кредит +5 %. Лимит кредита — 1 000 ¤.", 14, UI.MUTED)

func _upcoming() -> Dictionary:
	var result: Dictionary = {}
	for meeting in Gameplay.simulation.state.social.appointments:
		if meeting.status == "pending" and (result.is_empty() or int(meeting.minute) < int(result.minute)): result = meeting
	return result

func _unread(id: String = "") -> int:
	var result := 0
	for message in Gameplay.simulation.state.social.messages:
		if message.incoming and not message.read and (id.is_empty() or message.npc == id): result += 1
	return result

func _last_message(id: String) -> Dictionary:
	for index in range(Gameplay.simulation.state.social.messages.size() - 1, -1, -1):
		var message: Dictionary = Gameplay.simulation.state.social.messages[index]
		if message.npc == id: return message
	return {}

func _last_minute(id: String) -> int:
	return int(_last_message(id).get("minute", -1))

func go_back() -> void:
	_error = ""
	if app == "home": closed.emit(); return
	if app == "chat":
		_end_session()
		app = "messages"
	elif app in ["person", "meeting"]: app = "contacts"
	else: app = "home"
	_rebuild()
	focus_default()

func _go_home() -> void:
	_end_session()
	app = "home"
	_error = ""
	_rebuild()
	focus_default()

func _end_session() -> void:
	if not _session.is_empty() and Gameplay.simulation.state.social.npcs.has(_session):
		Gameplay.execute("npc_dialogue", "close", {"id":_session})
	_session = ""
	_greeting = {}

func suspend() -> void:
	_end_session()
	hide()
