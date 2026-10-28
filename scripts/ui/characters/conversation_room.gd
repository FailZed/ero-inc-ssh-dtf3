extends Control
## Scene-first conversation UI: category -> action -> reply -> same category.
signal closed
signal details_requested(id: String)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
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
var _feedback: Label
var _next: Button
var _navigation: Control
var _menu_area: Control
var _submenu: Control
var _submenu_options: VBoxContainer
var _tab_buttons: Dictionary = {}
var _buttons: Array[Button] = []
var _choices: Dictionary = {}
var _tabs: Array = []
var _tab := "dialogue"
var _folder := ""
var _reply_mode := false
var _rendered_turn := -1
var _closing := false
var _external := false
var _capture_path := ""
var _capture_exit := false
var _matrix_overlay: Control
var _animated := true
var _combat_target := "body"
var _combat_move := "jab"
var _combat_power := 1.0
var _combat_turn := -1
var _combat_log_size := -1
const MOVE_NAMES := {"jab":"Джеб","heavy":"Сильный удар","kick":"Удар ногой","feint":"Финт","body_hook":"Хук в корпус","uppercut":"Апперкот","sweep":"Подсечка","disarm":"Обезоружить","slash":"Режущий удар","thrust":"Выпад","bat_precise":"Точный удар","bat_swing":"Размашистый удар"}
const PART_NAMES := {"body":"Корпус","head":"Голова","arms":"Руки","legs":"Ноги"}

func configure_context(context: RefCounted, settings: Dictionary) -> void:
	session = context
	config = settings.duplicate(true)
	_external = true

func _ready() -> void:
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
	var style := UI.style(Color(0.025,0.055,0.085,0.90),Color("45657c"))
	style.set_border_width_all(1)
	style.set_content_margin_all(padding)
	return style

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
	var clock_box := VBoxContainer.new()
	_rect(clock_box,0.025,0.025,0.28,0.12)
	_clock = UI.label(clock_box,"",27)
	_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	_place = UI.label(clock_box,str(config.place),18,UI.MUTED)
	var navigation := PanelContainer.new()
	navigation.add_theme_stylebox_override("panel",_surface(6))
	_rect(navigation,0.64,0.025,0.985,0.09)
	_navigation = navigation
	var bar := UI.row(navigation,3)
	for tab: Dictionary in session.sim.services.npc_dialogue.menu_catalog().get("tabs",[]):
		var button := UI.button(bar,"",_select_tab.bind(str(tab.id)))
		button.icon = load("res://assets/icons/conversation/%s.svg" % str(tab.icon))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",34)
		button.custom_minimum_size = Vector2(48,44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(tab.title)
		_tab_buttons[str(tab.id)] = button
	var close_button := UI.button(bar,"×",_close)
	close_button.tooltip_text = "Закончить разговор · Esc"
	close_button.custom_minimum_size = Vector2(42,40)
	_menu_area = Control.new()
	_rect(_menu_area,0.71,0.125,0.985,0.715)
	_options = UI.scroller(_menu_area)
	# scroller() returns its VBox; the ScrollContainer itself fills the area.
	(_options.get_parent() as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options.add_theme_constant_override("separation",6)
	var sub := PanelContainer.new()
	sub.add_theme_stylebox_override("panel",_surface(10))
	_rect(sub,0.49,0.125,0.705,0.60)
	_submenu = sub
	_submenu_options = UI.scroller(sub)
	_submenu_options.add_theme_constant_override("separation",6)
	_submenu.visible = false
	var speech := PanelContainer.new()
	speech.add_theme_stylebox_override("panel",_surface(20))
	_rect(speech,0.165,0.755,0.815,0.957)
	var body := UI.column(speech,6)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size",28)
	_text.add_theme_constant_override("line_separation",5)
	_text.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _advance()
	)
	body.add_child(_text)
	var footer := UI.row(body,6)
	_feedback = UI.label(footer,"",17,UI.MUTED)
	_next = UI.button(footer,"Далее →",_advance)
	_next.custom_minimum_size.y = 30
	_next.add_theme_font_size_override("font_size",19)
	var name_plate := PanelContainer.new()
	name_plate.add_theme_stylebox_override("panel",_surface(8))
	_rect(name_plate,0.185,0.716,0.40,0.76)
	_speaker = UI.label(name_plate,str(config.name),24,UI.BLUE)
	_speaker.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stats = Label.new()
	_stats.add_theme_color_override("font_color",UI.INK)
	_stats.add_theme_font_size_override("font_size",19)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_rect(_stats,0.83,0.76,0.985,0.955)
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation",4)
	_rect(tools,0.115,0.67,0.155,0.97)
	_tool(tools,"≡","История разговора",_show_history)
	_tool(tools,"i","О собеседнике",_show_details)
	_tool(tools,"↔","Матрица отношений",_show_matrix)
	if not _external: _tool(tools,"↺","Начать заново",_restart)
	elif details_requested.has_connections(): _tool(tools,"…","Подарки, встречи и профиль",func(): details_requested.emit(session.npc_id); _close())
	_tool(tools,"×","Закончить разговор",_close)

func _tool(parent: Node, title: String, hint: String, action: Callable) -> void:
	var button := UI.button(parent,title,action)
	button.custom_minimum_size = Vector2(32,30)
	button.tooltip_text = hint
	button.add_theme_font_size_override("font_size",22)

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
	_stats.text = "Доверие   %d\nСимпатия   %d\nКомфорт   %d\nБлизость   %d\nОбида %d · Страх %d\n%s\nУсталость   %d%%\n%s" % [roundi(float(bond.trust)),roundi(float(bond.affection)),roundi(float(bond.comfort)),roundi(float(bond.closeness)),roundi(float(bond.grievance)),roundi(float(bond.fear)),stages.get(str(bond.stage),"Знакомые"),roundi(float(actor.get("fatigue",0))),moods.get(str(reply.utterance.mood),"Слушает")]
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
	_build_menu()

func _open_folder(title: String) -> void:
	_folder = "" if _folder == title else title
	_build_menu()

func _build_menu() -> void:
	UI.clear(_options)
	UI.clear(_submenu_options)
	_buttons.clear()
	if session.present().get("node") == "initiative":
		for choice: Dictionary in session.present().get("choices",[]): _leaf(_options,choice,0)
		_submenu.visible = false
		return
	var active: Dictionary = {}
	for tab: Dictionary in _tabs:
		if str(tab.id) == _tab: active = tab
	for key: String in _tab_buttons:
		_tab_buttons[key].self_modulate = UI.BLUE if key == _tab else Color.WHITE
	var number := 0 if _tab == "conflict" else 1
	for item: Dictionary in active.get("items",[]):
		if item.has("choices"):
			var any := false
			for key in item.choices:
				if _choices.has(str(key)): any = true
			if not any: continue
			var title := str(item.title)
			var button := _menu_button(_options,"%d. %s  ‹" % [number,title],_open_folder.bind(title))
			button.tooltip_text = "Открыть темы. Время не расходуется."
			if _folder == title:
				UI.label(_submenu_options,title,21,UI.BLUE)
				for key in item.choices:
					if _choices.has(str(key)): _leaf(_submenu_options,_choices[str(key)],0)
				var back := _menu_button(_submenu_options,"Назад  →",_open_folder.bind(title))
				back.tooltip_text = "Закрыть список тем"
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
	_submenu.visible = not _folder.is_empty() and _submenu_options.get_child_count()>0 and not _reply_mode

func _menu_button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := UI.button(parent,caption,callback)
	button.custom_minimum_size.y = 40
	button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size",24)
	button.add_theme_stylebox_override("normal",_surface(7))
	button.add_theme_stylebox_override("hover",UI.style(Color("25475e"),UI.BLUE))
	button.add_theme_stylebox_override("focus",UI.style(Color("25475e"),UI.BLUE))
	_buttons.append(button)
	return button

func _leaf(parent: Node, choice: Dictionary, number: int) -> void:
	var prefix := "%d. " % number if number>0 or _tab == "conflict" and parent == _options else ""
	var button := _menu_button(parent,prefix+str(choice.text),_choose.bind(str(choice.id),_rendered_turn))
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
	_navigation.visible = not fighting and not _reply_mode and session.present().get("node") != "initiative"
	_menu_area.visible = fighting or not _reply_mode
	_submenu.visible = not fighting and not _reply_mode and not _folder.is_empty() and _submenu_options.get_child_count()>0
	_next.text = "Показать целиком" if _speaking() else ("К действиям →" if _reply_mode else "✓")
	_next.visible = not fighting and (_speaking() or _reply_mode)
	if not _reply_mode and not _speaking(): _focus_first()

func _focus_first() -> void:
	if _submenu.visible:
		for child: Node in _submenu_options.get_children():
			if child is Button and not child.disabled:
				UI.restore_focus.call_deferred(weakref(child))
				return
	for button: Button in _buttons:
		if not button.disabled:
			UI.restore_focus.call_deferred(weakref(button))
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
	add_child(_matrix_overlay)
	_matrix_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.01,0.025,0.04,0.78)
	_matrix_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_surface(24))
	_matrix_overlay.add_child(panel)
	panel.anchor_left = 0.23
	panel.anchor_right = 0.77
	panel.anchor_top = 0.13
	panel.anchor_bottom = 0.90
	var body := UI.column(panel,10)
	UI.label(body,"Матрица отношений",30,UI.INK)
	UI.label(body,str(config.name)+" → Вы · чувства и границы собеседника",20,UI.MUTED)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",18)
	grid.add_theme_constant_override("v_separation",9)
	body.add_child(grid)
	for row: Dictionary in matrix.rows:
		var label := UI.label(grid,_scale_name(str(row.id)),23,UI.INK)
		label.custom_minimum_size.x = 285
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(140,20)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.min_value = 0
		bar.max_value = 100
		bar.value = absf(float(row.value))
		bar.tooltip_text = "Диапазон: %d … %d. Ноль — нейтральное значение." % [int(row.minimum),int(row.maximum)]
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background",UI.style(Color("0b1823"),Color("345064")))
		bar.add_theme_stylebox_override("fill",UI.style(Color("a67550") if row.id in ["grievance","fear"] or float(row.value)<0 else Color("457c9b"),Color.TRANSPARENT))
		grid.add_child(bar)
		UI.label(grid,"%+.1f" % float(row.value),23,UI.BLUE)
	var consent := "Есть согласие на отношения" if matrix.consent else "Согласия на отношения нет"
	UI.label(body,consent+(" · Вред признан" if matrix.acknowledged else ""),20,UI.MUTED)
	UI.label(body,"Дневной прирост: осталось %.1f · Личный долг: %d
Дней надёжного поведения после извинения: %d" % [float(matrix.gain_remaining),int(matrix.loan),matrix.repair_days.size()],20,UI.MUTED)
	var close := UI.button(body,"Закрыть · Esc",_close_matrix)
	close.custom_minimum_size.y = 40
	close.grab_focus()

func _close_matrix() -> void:
	if is_instance_valid(_matrix_overlay): _matrix_overlay.queue_free()
	_matrix_overlay = null
	_focus_first()

func _show_text(title: String, text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.ok_button_text = "Закрыть"
	dialog.exclusive = true
	var content := RichTextLabel.new()
	content.text = text
	content.custom_minimum_size = Vector2(560,340)
	content.add_theme_font_size_override("normal_font_size",20)
	dialog.add_child(content)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(640,430))

func _unhandled_input(event: InputEvent) -> void:
	if _closing or not is_instance_valid(puppet): return
	if is_instance_valid(_matrix_overlay):
		if event.is_action_pressed("ui_cancel"): _close_matrix()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if session.combat_active():
			_feedback.text = "Чтобы выйти из драки, выбери «Попытаться уйти»."
			return
		if not _folder.is_empty() and not _reply_mode:
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
