extends Control
## Scene-first conversation UI: category -> action -> reply -> same category.
signal closed
signal details_requested(id: String)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const Factory = preload("res://scripts/mechanics/conversation_room.gd")
const Actor = preload("res://scripts/characters/conversation_actor.gd")
var session: RefCounted
var config: Dictionary = {}
var puppet: Control
var _text: RichTextLabel
var _options: VBoxContainer
var _speaker: Label
var _clock: Label
var _place: Label
var _stats: Label
var _stats_panel: PanelContainer
var _feedback: Label
var _next: Button
var _navigation: Control
var _menu_panel: PanelContainer
var _category_title: Button
var _menu_area: Control
var _submenu: Control
var _submenu_options: VBoxContainer
var _utility_menu: Control
var _utility_buttons: Array[Button] = []
var _tab_buttons: Dictionary = {}
var _buttons: Array[Button] = []
var _choices: Dictionary = {}
var _tabs: Array = []
var _tab := "dialogue"
var _folder := ""
var _categories_open := false
var _tools_open := false
var _reply_mode := false
var _rendered_turn := -1
var _closing := false
var _external := false
var _capture_path := ""
var _capture_exit := false
var _matrix_overlay: Control
var _detail_overlay: Control
var _animated := true
var _combat_target := "body"
var _combat_move := "jab"
var _combat_power := 1.0
var _combat_turn := -1
var _combat_log_size := -1
var _compact_landscape := false
const MOVE_NAMES := {"jab":"Джеб","heavy":"Сильный удар","kick":"Удар ногой","feint":"Финт","body_hook":"Хук в корпус","uppercut":"Апперкот","sweep":"Подсечка","disarm":"Обезоружить","slash":"Режущий удар","thrust":"Выпад","bat_precise":"Точный удар","bat_swing":"Размашистый удар"}
const PART_NAMES := {"body":"Корпус","head":"Голова","arms":"Руки","legs":"Ноги"}

func configure_context(context: RefCounted, settings: Dictionary) -> void:
	session = context
	config = settings.duplicate(true)
	_external = true

func _ready() -> void:
	var window_size := DisplayServer.window_get_size()
	_compact_landscape = window_size.x > window_size.y and window_size.x <= 1100
	theme = UI.skin()
	theme.set_font_size("font_size","TooltipLabel",22)
	theme.set_stylebox("panel","TooltipPanel",_surface(12))
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	if session == null:
		var room := Factory.create()
		if not room.get("ok",false): return
		config = room.config
		session = room.session
	_build()
	if _animated and not puppet.load_reactions(str(config.reaction_profile)):
		_feedback.text = "Не удалось открыть модель Live2D."
		return
	if not session.active: session.open(str(config.get("channel","face")),str(config.get("initiative","")))
	_render()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-conversation="): _capture_path = argument.trim_prefix("--capture-conversation=")
		if argument == "--capture-exit": _capture_exit = true
	if not _capture_path.is_empty(): _capture.call_deferred()

func _rect(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	add_child(control)

func _surface(padding: int = 12) -> StyleBoxFlat:
	var style := UI.style(Color(0.012,0.029,0.043,0.93),Color(0.48,0.70,0.82,0.82))
	style.set_border_width_all(2)
	style.set_content_margin_all(padding)
	return style

func _clear_surface(padding: int = 0) -> StyleBoxFlat:
	var style := UI.style(Color.TRANSPARENT,Color.TRANSPARENT)
	style.set_border_width_all(0)
	style.set_content_margin_all(padding)
	return style

func _veil(left: float, top: float, right: float, bottom: float, vertical: bool) -> void:
	var gradient := Gradient.new()
	gradient.set_color(0,Color(0.005,0.015,0.025,0.0))
	gradient.set_color(1,Color(0.005,0.015,0.025,0.94))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5,0.0) if vertical else Vector2(0.0,0.5)
	texture.fill_to = Vector2(0.5,1.0) if vertical else Vector2(1.0,0.5)
	var wash := TextureRect.new()
	wash.texture = texture
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect(wash,left,top,right,bottom)

func _build() -> void:
	UI.background(self,str(config.background),0.23)
	_animated = not str(config.get("reaction_profile","")).is_empty()
	var canvas := SubViewportContainer.new()
	canvas.stretch = true
	_rect(canvas,0.08,0.02,0.90,1.0)
	if not _animated:
		canvas.anchor_left = 0.24
		canvas.anchor_right = 0.68
		canvas.anchor_top = 0.12
		canvas.anchor_bottom = 0.82
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.add_child(viewport)
	puppet = Actor.new() if _animated else load("res://scripts/ui/gameplay/resident_preview.gd").new()
	viewport.add_child(puppet)
	puppet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _animated:
		puppet.set_framing(1.42,Vector2(0.0,0.08))
		puppet.speech_progress.connect(func(characters): _text.visible_characters = characters)
		puppet.speech_finished.connect(_finish_line)
	_veil(0.50,0.0,1.0,0.79,false)
	_veil(0.0,0.69,1.0,1.0,true)
	var clock_box := VBoxContainer.new()
	_rect(clock_box,0.025,0.025,0.28,0.12)
	_clock = UI.label(clock_box,"",36 if _compact_landscape else 27)
	_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	_place = UI.label(clock_box,str(config.place),24 if _compact_landscape else 18,UI.MUTED)
	_menu_panel = PanelContainer.new()
	_menu_panel.add_theme_stylebox_override("panel",_clear_surface(4))
	_rect(_menu_panel,0.625,0.12 if _compact_landscape else 0.245,0.985,0.75 if _compact_landscape else 0.735)
	var menu_body := UI.column(_menu_panel,14)
	var menu_heading := UI.row(menu_body,8)
	_category_title = UI.button(menu_heading,"",_toggle_categories)
	_category_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_category_title.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_category_title.expand_icon = true
	_category_title.add_theme_constant_override("icon_max_width",36 if _compact_landscape else 28)
	_category_title.add_theme_font_size_override("font_size",30 if _compact_landscape else 25)
	_category_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_title.custom_minimum_size.y = 82 if _compact_landscape else 54
	_category_title.tooltip_text = "Выбрать тему разговора"
	HUD.quiet_button(_category_title)
	var more_button := UI.button(menu_heading,"",_toggle_tools)
	more_button.icon = HUD.icon("menu")
	more_button.expand_icon = true
	more_button.add_theme_constant_override("icon_max_width",32 if _compact_landscape else 25)
	more_button.tooltip_text = "История и сведения"
	more_button.custom_minimum_size = Vector2(82,82) if _compact_landscape else Vector2(50,54)
	HUD.quiet_button(more_button)
	var close_button := UI.button(menu_heading,"",_close)
	close_button.icon = HUD.icon("close")
	close_button.expand_icon = true
	close_button.add_theme_constant_override("icon_max_width",32 if _compact_landscape else 25)
	close_button.tooltip_text = "Закончить разговор · Esc"
	close_button.custom_minimum_size = Vector2(82,82) if _compact_landscape else Vector2(50,54)
	HUD.quiet_button(close_button)
	_navigation = ScrollContainer.new()
	_navigation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_navigation as ScrollContainer).horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	(_navigation as ScrollContainer).follow_focus = true
	menu_body.add_child(_navigation)
	var categories := UI.column(_navigation,6)
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tab: Dictionary in session.sim.services.npc_dialogue.menu_catalog().get("tabs",[]):
		var button := UI.button(categories,"",_select_tab.bind(str(tab.id)))
		button.icon = load("res://assets/icons/conversation/%s.svg" % str(tab.icon))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width",42 if _compact_landscape else 30)
		button.custom_minimum_size.y = 96 if _compact_landscape else 62
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(tab.title)
		HUD.quiet_button(button)
		var title := UI.label(button,str(tab.title),32 if _compact_landscape else 25,UI.INK)
		title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		title.offset_left = 72 if _compact_landscape else 55
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tab_buttons[str(tab.id)] = button
	_menu_area = ScrollContainer.new()
	_menu_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_area.follow_focus = true
	menu_body.add_child(_menu_area)
	_options = UI.column(_menu_area,8 if _compact_landscape else 6)
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.add_theme_constant_override("separation",8 if _compact_landscape else 6)
	_submenu = ScrollContainer.new()
	_submenu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_submenu.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_submenu.follow_focus = true
	menu_body.add_child(_submenu)
	_submenu_options = UI.column(_submenu,8 if _compact_landscape else 6)
	_submenu_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_submenu_options.add_theme_constant_override("separation",8 if _compact_landscape else 6)
	_submenu.visible = false
	_utility_menu = ScrollContainer.new()
	_utility_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_utility_menu as ScrollContainer).horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_body.add_child(_utility_menu)
	var utilities := UI.column(_utility_menu,8)
	utilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_utility_button(utilities,"journal","История разговора",_show_history)
	_utility_button(utilities,"profile","О собеседнике",_show_details)
	_utility_button(utilities,"health","Матрица отношений",_show_matrix)
	if not _external: _utility_button(utilities,"rest","Начать заново",_restart)
	elif details_requested.has_connections(): _utility_button(utilities,"people","Подарки, встречи и профиль",func(): details_requested.emit(session.npc_id); _close())
	_utility_menu.visible = false
	var speech := PanelContainer.new()
	speech.add_theme_stylebox_override("panel",_clear_surface(6))
	_rect(speech,0.105,0.79,0.97,0.97)
	var body := UI.column(speech,8)
	var speech_heading := UI.row(body,8)
	_speaker = UI.label(speech_heading,str(config.name),34 if _compact_landscape else 27,UI.BLUE)
	_speaker.autowrap_mode = TextServer.AUTOWRAP_OFF
	_speaker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_feedback = UI.label(speech_heading,"",22 if _compact_landscape else 17,UI.MUTED)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_OFF
	_feedback.clip_text = true
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_next = UI.button(speech_heading,"Далее →",_advance)
	_next.custom_minimum_size = Vector2(170,72) if _compact_landscape else Vector2(130,44)
	_next.add_theme_font_size_override("font_size",27 if _compact_landscape else 19)
	HUD.quiet_button(_next)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size",38 if _compact_landscape else 31)
	_text.add_theme_constant_override("line_separation",5)
	_text.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _advance()
	)
	body.add_child(_text)
	_stats_panel = PanelContainer.new()
	_stats_panel.add_theme_stylebox_override("panel",_surface(14))
	_rect(_stats_panel,0.025,0.15,0.25,0.54)
	_stats_panel.visible = false
	_stats = Label.new()
	_stats.add_theme_color_override("font_color",UI.INK)
	_stats.add_theme_font_size_override("font_size",24 if _compact_landscape else 19)
	_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stats_panel.add_child(_stats)

func _utility_button(parent: Node, kind: String, title: String, action: Callable) -> void:
	var button := UI.button(parent,title,action)
	button.icon = HUD.icon(kind)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width",44 if _compact_landscape else 30)
	button.add_theme_font_size_override("font_size",32 if _compact_landscape else 25)
	button.custom_minimum_size.y = 96 if _compact_landscape else 62
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = title
	_button_skin(button)
	_utility_buttons.append(button)

func _render() -> void:
	if _closing or session == null: return
	var reply: Dictionary = session.present()
	if reply.is_empty(): return
	var actor: Dictionary = session.actor()
	var bond: Dictionary = session.bond()
	puppet.set_actor(actor)
	_speaker.text = "Результат" if reply.utterance.get("narrated",false) else str(actor.name)
	var minute := int(session.sim.state.clock.minute_of_day)
	_clock.text = "День %d · %02d:%02d" % [int(session.sim.state.clock.day_index)+1,minute/60,minute%60]
	var moods := {"neutral":"Спокойна","happy":"Радость","inspired":"Вдохновение","tired":"Усталость","hungry":"Голод","angry":"Сердится","anxious":"Беспокойство","lonely":"Хочет общения"}
	var stages := {"stranger":"Незнакомые","acquaintance":"Знакомые","friend":"Друзья","close_friend":"Близкие друзья","strained":"Напряжение","partner":"Партнёрство"}
	var full_stats := "Доверие   %d\nСимпатия   %d\nКомфорт   %d\nБлизость   %d\nОбида %d · Страх %d\n%s\nУсталость   %d%%\n%s" % [roundi(float(bond.trust)),roundi(float(bond.affection)),roundi(float(bond.comfort)),roundi(float(bond.closeness)),roundi(float(bond.grievance)),roundi(float(bond.fear)),stages.get(str(bond.stage),"Знакомые"),roundi(float(actor.get("fatigue",0))),moods.get(str(reply.utterance.mood),"Слушает")]
	_stats.text = "%s\nДоверие %d\nСимпатия %d\nКомфорт %d" % [stages.get(str(bond.stage),"Знакомые"),roundi(float(bond.trust)),roundi(float(bond.affection)),roundi(float(bond.comfort))]
	_stats.tooltip_text = full_stats
	var menu: Dictionary = session.sim.services.npc_dialogue.menu(session.npc_id)
	_tabs = menu.get("tabs",[])
	_choices.clear()
	for choice: Dictionary in menu.get("choices",[]): _choices[str(choice.id)] = choice
	if int(reply.turn) != _rendered_turn:
		_rendered_turn = int(reply.turn)
		_text.text = str(reply.utterance.text)
		_text.scroll_to_line(0)
		if _animated: puppet.present_line(str(reply.utterance.text),str(reply.utterance.expression),false,bool(reply.utterance.get("narrated",false)))
		else:
			puppet.set_expression(str(reply.utterance.expression))
			_text.visible_characters = -1
	if session.combat_active(): _build_combat()
	else: _build_menu()
	_sync_phase()

func _select_tab(id: String) -> void:
	_tab = id
	_folder = ""
	_categories_open = false
	_tools_open = false
	_build_menu()

func _toggle_categories() -> void:
	if session.combat_active() or _reply_mode: return
	if _tools_open:
		_tools_open = false
		_build_menu()
		return
	_categories_open = not _categories_open
	_tools_open = false
	if not _categories_open: _build_menu()
	else: _sync_phase()

func _toggle_tools() -> void:
	if session.combat_active() or _reply_mode: return
	_tools_open = not _tools_open
	_categories_open = false
	if not _tools_open: _build_menu()
	else: _sync_phase()

func _open_folder(title: String) -> void:
	_folder = "" if _folder == title else title
	_categories_open = false
	_tools_open = false
	_build_menu()

func _build_menu() -> void:
	UI.clear(_options)
	UI.clear(_submenu_options)
	_buttons.clear()
	if session.present().get("node") == "initiative":
		_category_title.text = "Разговор"
		_category_title.icon = null
		for choice: Dictionary in session.present().get("choices",[]): _leaf(_options,choice,0)
		_submenu.visible = false
		return
	var active: Dictionary = {}
	for tab: Dictionary in _tabs:
		if str(tab.id) == _tab: active = tab
	_category_title.text = (_folder if not _folder.is_empty() else str(active.get("title","Темы"))) + "  ▾"
	_category_title.icon = _tab_buttons[_tab].icon if _tab_buttons.has(_tab) else null
	for key: String in _tab_buttons:
		_tab_buttons[key].self_modulate = UI.BLUE if key == _tab else Color.WHITE
		var tab_style := HUD.button_style(Color(0.07,0.15,0.21,0.74),UI.BLUE) if key == _tab else HUD.button_style()
		_tab_buttons[key].add_theme_stylebox_override("normal",tab_style)
		(_tab_buttons[key].get_child(0) as Label).add_theme_color_override("font_color",UI.BLUE if key == _tab else UI.INK)
	var number := 0 if _tab == "conflict" else 1
	for item: Dictionary in active.get("items",[]):
		if item.has("choices"):
			var any := false
			for key in item.choices:
				if _choices.has(str(key)): any = true
			if not any: continue
			var title := str(item.title)
			var button := _menu_button(_options,title+"  ›",_open_folder.bind(title))
			button.tooltip_text = "Открыть темы. Время не расходуется."
			if _folder == title:
				var back := _menu_button(_submenu_options,"← К темам",_open_folder.bind(title))
				back.tooltip_text = "Закрыть список тем"
				for key in item.choices:
					if _choices.has(str(key)): _leaf(_submenu_options,_choices[str(key)],0)
		else:
			var key := str(item.get("choice",""))
			if not _choices.has(key): continue
			_leaf(_options,_choices[key],number)
		number += 1
	if session.present().get("node") == "end":
		var reopen := _menu_button(_options,"Поговорить ещё",_reopen)
		reopen.disabled = not session.sim.services.npc_dialogue.availability(session.actor(),session.channel).is_empty() or float(session.actor().health)<=0 or session.sim.services.health.hp("player")<=0
	if _tab in ["intimacy","boundaries"]:
		var space := Control.new()
		space.custom_minimum_size.y = 180
		space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_options.add_child(space)
	if _tab == "questions" and not session.npc_id in session.sim.state.social.contacts:
		_menu_button(_options,"Обменяться контактами",_contact)
	_sync_phase()

func _menu_button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := UI.button(parent,caption,callback)
	button.custom_minimum_size.y = 96 if _compact_landscape else 62
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size",34 if _compact_landscape else 26)
	_button_skin(button)
	_buttons.append(button)
	return button

func _button_skin(button: Button) -> void:
	var normal := HUD.button_style(Color.TRANSPARENT,Color(0.38,0.55,0.64,0.24))
	normal.content_margin_left = 18
	normal.content_margin_right = 12
	var selected := HUD.button_style(Color(0.08,0.18,0.23,0.70),UI.BLUE)
	selected.border_width_left = 3
	selected.content_margin_left = 15
	selected.content_margin_right = 12
	button.add_theme_stylebox_override("normal",normal)
	for state in ["hover","focus","pressed"]: button.add_theme_stylebox_override(state,selected)

func _leaf(parent: Node, choice: Dictionary, number: int) -> void:
	var button := _menu_button(parent,str(choice.text),_choose.bind(str(choice.id),_rendered_turn))
	button.disabled = not str(choice.blocked).is_empty() or session.present().get("node") == "end"
	var lines: Array[String] = [str(choice.text),"Время: %d мин" % int(choice.minutes)]
	if not str(choice.blocked).is_empty(): lines.append(_error(str(choice.blocked)))
	elif float(choice.get("chance",-1))>=0:
		var forecast: Dictionary = choice.get("forecast",{})
		if int(forecast.get("cost",0))>0: lines.append("Стоимость при согласии: %d" % int(forecast.cost))
		if float(forecast.get("fear",0))>0: lines.append("Страх: до +%.1f; попытка оставляет обиду даже при сопротивлении." % float(forecast.fear))
		if forecast.get("combat",false): lines.append("Начнётся пошаговая драка. Итог зависит от ваших действий в бою.")
		else:
			lines.append(("Вероятность исхода: %d%%" if forecast.get("hostile",false) else "Вероятность согласия: %d%%") % roundi(float(choice.chance)*100.0))
			lines.append("Реакция зависит от отношений, настроения и повторений.")
		if forecast.get("hostile",false):
			lines.append("Свидетелей рядом: %d. Возможны сопротивление и ответная драка." % int(forecast.get("witnesses",0)))
			if int(forecast.get("fine",0))>0: lines.append("Штраф: от %d." % int(forecast.fine))
		var impacts: Array[String] = []
		for key: String in forecast.get("changes",{}):
			impacts.append("%s %+.1f" % [_scale_name(key),float(forecast.changes[key])])
		if not impacts.is_empty(): lines.append("При успехе, до ограничений повторения: "+", ".join(impacts))
		if forecast.get("repeat",false): lines.append("Повторение: положительный эффект ограничен.")
	else: lines.append("Ответ зависит от характера, обстоятельств и памяти собеседницы.")
	if number>=0 and number<=9: lines.append("Быстрый выбор: %d" % number)
	button.tooltip_text = "\n".join(lines)
	button.set_meta("dialogue_choice",str(choice.id))

func _finish_line() -> void:
	if not _closing: _sync_phase()

func _speaking() -> bool:
	return _animated and puppet.speaking

func _finish_speech() -> void:
	if _speaking(): puppet.finish_speech()

func _cancel_speech() -> void:
	if _animated: puppet.cancel_speech()

func _build_combat() -> void:
	UI.clear(_options)
	UI.clear(_submenu_options)
	_buttons.clear()
	_folder = ""
	_categories_open = false
	_tools_open = false
	_category_title.text = "Столкновение"
	_reply_mode = false
	_finish_speech()
	var combat: Dictionary = session.combat()
	var defending: bool = combat.phase == "defence"
	_stats.text = "ВЫ · здоровье %d\nВыносливость %d\n\n%s · здоровье %d\nВыносливость %d\nХод %d · %d ОД\nОтвет противника · %d ОД" % [roundi(float(combat.player_hp)),roundi(float(combat.stamina.player)),str(session.actor().name),roundi(float(combat.npc_hp)),roundi(float(combat.stamina.npc)),int(combat.turn),int(combat.ap),int(combat.npc_ap)]
	UI.label(_options,"ВЫБЕРИТЕ ЗАЩИТУ" if defending else "ВАШ УДАР · %d ОД" % int(combat.ap),23,UI.ORANGE)
	UI.label(_options,"Прикройте зону и подтвердите один ответ противника." if defending else "Выберите приём, цель и усилие, затем подтвердите удар.",16,UI.MUTED)
	var revision := int(combat.revision)
	var targets := OptionButton.new()
	targets.set_meta("combat_target",true)
	for part: String in PART_NAMES:
		targets.add_item(("Прикрыть: " if defending else "Цель: ")+str(PART_NAMES[part]))
		targets.set_item_metadata(targets.item_count-1,part)
		if part == _combat_target: targets.select(targets.item_count-1)
	targets.item_selected.connect(func(index): _combat_target = str(targets.get_item_metadata(index)); _render())
	_options.add_child(targets)
	if defending:
		var caption := "Подтвердить защиту → ответ противника"
		if combat.statuses.player.has("knockdown"): caption = "Переждать ответ на земле"
		var confirm := _menu_button(_options,caption,_fight.bind({"action":"guard","part":_combat_target,"revision":revision}))
		confirm.set_meta("combat_defence",true)
	else:
		var efforts := OptionButton.new()
		efforts.set_meta("combat_power",true)
		for power: float in [0.5,0.75,1.0,1.25,1.5]:
			efforts.add_item("Усилие: %d%%" % roundi(power*100))
			efforts.set_item_metadata(efforts.item_count-1,power)
			if is_equal_approx(power,_combat_power): efforts.select(efforts.item_count-1)
		efforts.item_selected.connect(func(index): _combat_power = float(efforts.get_item_metadata(index)); _render())
		_options.add_child(efforts)
		var moves := OptionButton.new()
		moves.set_meta("combat_move_picker",true)
		for id: String in session.sim.catalog.combat_moves:
			if not session.sim.services.combat.forecast(id,_combat_target,"player",_combat_power).ok: continue
			moves.add_item(str(MOVE_NAMES.get(id,id)))
			moves.set_item_metadata(moves.item_count-1,id)
			if id == _combat_move: moves.select(moves.item_count-1)
		if moves.item_count>0:
			_combat_move = str(moves.get_item_metadata(moves.selected))
		moves.item_selected.connect(func(index): _combat_move = str(moves.get_item_metadata(index)); _render())
		_options.add_child(moves)
		var forecast: Dictionary = session.sim.services.combat.forecast(_combat_move,_combat_target,"player",_combat_power)
		if forecast.ok:
			UI.label(_options,"%s → %s\n%d ОД · попадание %d%%\nУрон ≈ %.1f · выносливость %.1f\nКрит %d%% · нокдаун %d%%" % [MOVE_NAMES.get(_combat_move,_combat_move),PART_NAMES[_combat_target],int(forecast.data.ap),roundi(float(forecast.data.accuracy)*100),float(forecast.data.damage),float(forecast.data.stamina),roundi(float(forecast.data.critical)*100),roundi(float(forecast.data.knockdown)*100)],18)
			var confirm := _menu_button(_options,"Подтвердить удар",_fight.bind({"action":"attack","move":_combat_move,"part":_combat_target,"power":_combat_power,"revision":revision}))
			confirm.disabled = int(combat.ap)<int(forecast.data.ap) or float(combat.stamina.player)<float(forecast.data.stamina)
			confirm.set_meta("combat_move",_combat_move)
			confirm.set_meta("combat_confirm",true)
		for action: String in ["recover","intimidate","escape","end_turn"]:
			var caption: String = {"recover":"Перевести дух","intimidate":"Остановить драку · 4 ОД","escape":"Попытаться уйти","end_turn":"Передать ход → защита"}[action]
			var button := _menu_button(_options,caption,_fight.bind({"action":action,"revision":revision}))
			button.disabled = action == "intimidate" and int(combat.ap)<4
			button.set_meta("combat_action",action)
		var stances := OptionButton.new()
		for id: String in ["balanced","defensive","aggressive"]:
			stances.add_item(str({"balanced":"Обычная стойка","defensive":"Защитная стойка","aggressive":"Агрессивная стойка"}[id])+" · 1 ОД")
			stances.set_item_metadata(stances.item_count-1,id)
			if combat.stances.player == id: stances.select(stances.item_count-1)
		stances.disabled = int(combat.ap)<1
		stances.item_selected.connect(func(index): _fight({"action":"stance","id":str(stances.get_item_metadata(index)),"revision":revision}))
		_options.add_child(stances)
	if int(combat.turn) != _combat_turn or combat.log.size() != _combat_log_size:
		_combat_turn = int(combat.turn)
		_combat_log_size = combat.log.size()
		var lines: Array[String] = []
		if combat.log.is_empty(): lines.append(str(session.present().utterance.text))
		for entry: Dictionary in combat.log.slice(-3):
			var who := "Вы" if entry.actor == "player" else str(session.actor().name)
			if entry.has("move"):
				lines.append("%s: %s — %s" % [who,MOVE_NAMES.get(str(entry.move),str(entry.move)),"урон %d" % roundi(float(entry.damage)) if entry.hit else "промах"])
			else: lines.append("%s: %s" % [who,"поднимается" if entry.get("action","") == "stand_up" else "ожидает" if entry.get("action","") == "wait" else "переводит дух"])
		_text.text = "\n".join(lines)
	_text.visible_characters = -1

func _fight(args: Dictionary) -> void:
	var result: Dictionary = session.fight(args)
	if not result.get("ok",false):
		_feedback.text = _error(str(result.get("error","")))
		return
	_reply_mode = not session.combat_active()
	_feedback.text = "Драка продолжается" if session.combat_active() else "Драка окончена"
	_render()

func _sync_phase() -> void:
	var fighting: bool = session.combat_active()
	var browsing: bool = not fighting and not _reply_mode and session.present().get("node") != "initiative"
	var submenu_open: bool = browsing and not _categories_open and not _tools_open and not _folder.is_empty() and _submenu_options.get_child_count()>0
	_menu_panel.visible = fighting or not _reply_mode
	_stats_panel.visible = fighting
	_navigation.visible = browsing and _categories_open
	_utility_menu.visible = browsing and _tools_open
	_menu_area.visible = (fighting or not _reply_mode) and not submenu_open and not _navigation.visible and not _utility_menu.visible
	_submenu.visible = submenu_open
	if _navigation.visible:
		_category_title.text = "Темы разговора  ▴"
		_category_title.icon = null
	elif _utility_menu.visible:
		_category_title.text = "← Разговор"
		_category_title.icon = null
	_category_title.disabled = fighting or not browsing
	_next.text = "Показать целиком" if _speaking() else ("К действиям →" if _reply_mode else "✓")
	_next.visible = not fighting and (_speaking() or _reply_mode)
	if not _reply_mode and not _speaking(): _focus_first()

func _focus_first() -> void:
	if _navigation.visible:
		if _tab_buttons.has(_tab): UI.restore_focus.call_deferred(weakref(_tab_buttons[_tab]))
		return
	if _utility_menu.visible:
		if not _utility_buttons.is_empty(): UI.restore_focus.call_deferred(weakref(_utility_buttons[0]))
		return
	if _submenu.visible:
		for child: Node in _submenu_options.get_children():
			if child is Button and not child.disabled:
				UI.restore_focus.call_deferred(weakref(child))
				_submenu.set_deferred("scroll_vertical",0)
				return
	for button: Button in _buttons:
		if not button.disabled:
			UI.restore_focus.call_deferred(weakref(button))
			_menu_area.set_deferred("scroll_vertical",0)
			break

func _advance() -> void:
	if _speaking(): _finish_speech()
	elif _reply_mode:
		_reply_mode = false
		_sync_phase()
		_focus_first()

func _choose(id: String, turn: int) -> void:
	if _closing: return
	_finish_speech()
	var before: Dictionary = session.bond()
	var minute := int(session.sim.state.clock.total_minutes)
	var result: Dictionary = session.choose(id,turn,session.present().get("node") != "initiative")
	if not result.get("ok",false):
		_feedback.text = _error(str(result.get("error","")))
		return
	_reply_mode = not session.combat_active()
	_render()
	var changes: Array[String] = []
	var after: Dictionary = session.bond()
	for key: String in ["trust","affection","comfort"]:
		var delta := float(after.get(key,0.0))-float(before.get(key,0.0))
		if absf(delta)>0.05: changes.append("%s %+.1f" % [{"trust":"Доверие","affection":"Симпатия","comfort":"Комфорт"}[key],delta])
	var elapsed := int(session.sim.state.clock.total_minutes)-minute
	if elapsed>0: changes.append("%d мин" % elapsed)
	if int(result.get("data",{}).get("outcome",{}).get("money",0))>0: changes.append("Деньги: %d" % int(result.data.outcome.money))
	_feedback.text = " · ".join(changes)

func _contact() -> void:
	var result: Dictionary = session.command("social","contact",{"id":session.npc_id})
	_feedback.text = "Вы обменялись контактами." if result.get("ok",false) else _error(str(result.get("error","")))
	_build_menu()

func _reopen() -> void:
	session.open()
	_reply_mode = false
	_render()

func _restart() -> void:
	if _external: return
	if session.combat_active(): _feedback.text = _error("finish_active_combat"); return
	_cancel_speech()
	session.close()
	var room := Factory.create()
	if not room.get("ok",false): return
	session = room.session
	_rendered_turn = -1
	_reply_mode = false
	_folder = ""
	if _animated: puppet.reset_character()
	session.open()
	_render()
	_feedback.text = "Новый разговор."

func _error(code: String) -> String:
	return str(config.get("errors",{}).get(code,"Сейчас это действие недоступно."))

func _show_history() -> void:
	var lines: Array[String] = []
	for entry: Dictionary in session.transcript: lines.append(("Вы" if entry.speaker == "player" else str(config.name))+": "+str(entry.text))
	_show_text("История разговора","\n\n".join(lines))

func _show_details() -> void:
	_show_text("О собеседнике",str(session.sim.services.social_rules.describe(session.npc_id)))

func _scale_name(key: String) -> String:
	return str({"trust":"Доверие","affection":"Симпатия","respect":"Уважение","comfort":"Комфорт","closeness":"Привязанность","interest":"Романтический интерес","grievance":"Обида","fear":"Страх","care_balance":"Баланс помощи"}.get(key,key))

func _show_matrix() -> void:
	if is_instance_valid(_matrix_overlay): return
	var matrix: Dictionary = session.sim.services.npc_relationships.matrix(session.npc_id,"player")
	_matrix_overlay = Control.new()
	_matrix_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_matrix_overlay)
	_matrix_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.005,0.013,0.024,0.80)
	_matrix_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_surface(20))
	_matrix_overlay.add_child(panel)
	panel.anchor_left = 0.10
	panel.anchor_right = 0.90
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92 if _compact_landscape else 0.70
	var body := UI.column(panel,12)
	var heading := UI.row(body,12)
	UI.label(heading,"Матрица отношений",38 if _compact_landscape else 32,UI.INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := UI.button(heading,"×",_close_matrix)
	close.custom_minimum_size = Vector2(66,58) if _compact_landscape else Vector2(48,44)
	close.add_theme_font_size_override("font_size",34 if _compact_landscape else 26)
	close.tooltip_text = "Закрыть · Esc"
	var rows := UI.scroller(body)
	rows.add_theme_constant_override("separation",12)
	UI.label(rows,str(config.name)+" → Вы · чувства и границы собеседника",27 if _compact_landscape else 20,UI.MUTED)
	for row: Dictionary in matrix.rows:
		var line := UI.row(rows,16)
		var label := UI.label(line,_scale_name(str(row.id)),30 if _compact_landscape else 23,UI.INK)
		label.custom_minimum_size.x = 300
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(300,28)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.min_value = 0
		bar.max_value = 100
		bar.value = absf(float(row.value))
		bar.tooltip_text = "Диапазон: %d … %d. Ноль — нейтральное значение." % [int(row.minimum),int(row.maximum)]
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background",UI.style(Color("0b1823"),Color("345064")))
		bar.add_theme_stylebox_override("fill",UI.style(Color("a67550") if row.id in ["grievance","fear"] or float(row.value)<0 else Color("457c9b"),Color.TRANSPARENT))
		line.add_child(bar)
		var value := UI.label(line,"%+.1f" % float(row.value),28 if _compact_landscape else 23,UI.BLUE)
		value.custom_minimum_size.x = 90
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var consent := "Есть согласие на отношения" if matrix.consent else "Согласия на отношения нет"
	UI.label(rows,consent+(" · Вред признан" if matrix.acknowledged else ""),27 if _compact_landscape else 20,UI.MUTED)
	UI.label(rows,"Дневной прирост: осталось %.1f · Личный долг: %d\nДней надёжного поведения после извинения: %d" % [float(matrix.gain_remaining),int(matrix.loan),matrix.repair_days.size()],27 if _compact_landscape else 20,UI.MUTED)
	close.grab_focus()

func _close_matrix() -> void:
	if is_instance_valid(_matrix_overlay): _matrix_overlay.queue_free()
	_matrix_overlay = null
	_focus_first()

func _show_text(title: String, text: String) -> void:
	if is_instance_valid(_detail_overlay): _detail_overlay.queue_free()
	_detail_overlay = Control.new()
	_detail_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_detail_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_detail_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.005,0.013,0.024,0.80)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_surface(24))
	var brief := text.length() < 360 and text.count("\n") < 5
	panel.anchor_left = 0.12
	panel.anchor_right = 0.88
	panel.anchor_top = 0.19 if brief else 0.12
	panel.anchor_bottom = 0.55 if brief else 0.88
	_detail_overlay.add_child(panel)
	var body := UI.column(panel,16)
	var heading := UI.row(body,12)
	UI.label(heading,title,38 if _compact_landscape else 32,UI.INK).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := UI.button(heading,"×",_close_detail)
	close.custom_minimum_size = Vector2(70,64) if _compact_landscape else Vector2(50,48)
	close.add_theme_font_size_override("font_size",36 if _compact_landscape else 28)
	close.tooltip_text = "Закрыть · Esc"
	var content := RichTextLabel.new()
	content.bbcode_enabled = false
	content.text = text if not text.is_empty() else "Пока записей нет."
	content.scroll_active = true
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_font_size_override("normal_font_size",30 if _compact_landscape else 24)
	content.add_theme_color_override("default_color",UI.INK)
	content.add_theme_constant_override("line_separation",8)
	body.add_child(content)
	close.grab_focus()

func _close_detail() -> void:
	if is_instance_valid(_detail_overlay): _detail_overlay.queue_free()
	_detail_overlay = null
	_focus_first()

func _unhandled_input(event: InputEvent) -> void:
	if _closing or not is_instance_valid(puppet): return
	if is_instance_valid(_detail_overlay):
		if event.is_action_pressed("ui_cancel"): _close_detail()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_matrix_overlay):
		if event.is_action_pressed("ui_cancel"): _close_matrix()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if session.combat_active():
			_feedback.text = "Чтобы выйти из драки, выбери «Попытаться уйти»."
			return
		if _categories_open or _tools_open:
			_categories_open = false
			_tools_open = false
			_build_menu()
		elif not _folder.is_empty() and not _reply_mode:
			_folder = ""
			_build_menu()
		elif _reply_mode:
			_finish_speech()
			_advance()
		else: _close()
	elif event.is_action_pressed("ui_accept") or event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if _speaking() or _reply_mode:
			_advance()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and not _reply_mode:
		if event.keycode>=KEY_0 and event.keycode<=KEY_9 and not session.combat_active():
			var first := KEY_0 if _tab == "conflict" and not _submenu.visible else KEY_1
			var index := int(event.keycode-first)
			var parent: Node = _submenu_options if _submenu.visible else _options
			var choices: Array = parent.get_children().filter(func(child): return child is Button)
			if index>=0 and index<choices.size() and not choices[index].disabled:
				choices[index].pressed.emit()
				get_viewport().set_input_as_handled()

func _close() -> void:
	if _closing: return
	if session != null and session.combat_active(): _feedback.text = _error("finish_active_combat"); return
	_closing = true
	if session != null: session.close()
	if is_instance_valid(puppet):
		_cancel_speech()
		if _animated: puppet.release_grab(true)
	closed.emit()
	if get_tree().current_scene == self: get_tree().quit()
	else: queue_free()

func _exit_tree() -> void:
	if session != null: session.close()

func _capture() -> void:
	for frame in range(18): await get_tree().process_frame
	_finish_speech()
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(_capture_path)
	print("CONVERSATION_CAPTURE ",_capture_path," error=",error)
	if _capture_exit: get_tree().quit(error)
