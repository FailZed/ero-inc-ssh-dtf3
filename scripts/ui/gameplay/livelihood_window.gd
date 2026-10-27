extends Control
signal closed
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const WorkNames = preload("res://scripts/gameplay/livelihood_presentation.gd")
const WorkWindow = preload("res://scripts/ui/gameplay/game_window.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const Art = preload("res://scripts/ui/gameplay/item_art.gd")
var page := "jobs"
var _body: VBoxContainer
var _status: Label
var _clock: Label
var _focus: Control
var _epoch := 0
var _offset := 0
var _refresh_queued := false
var _auto_timeout := false
var _live_token := ""
var _paused := false
var _previewing := false
var _duration := 0
var _window: Control
var _selected_job := ""
var _skill_filter := "all"
var _skip_classes := false
var _round_clock: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.skin()
	_window = WorkWindow.new()
	_window.title = "Работа и своя жизнь"
	_window.subtitle = "Подработка, личные цели и обустройство дома"
	_window.back_requested.connect(_back)
	add_child(_window)
	_status = _window.status
	_body = _window.body
	Gameplay.changed.connect(_queue_refresh)
	_refresh()

func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	call_deferred("_refresh")

func _refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree(): return
	_window.begin_update()
	_window.set_tabs({"jobs":"Работа","orders":"Заказы","goals":"Мои цели","home":"Уют дома"},page,func(id): page = id; _refresh())
	_clock = null
	_round_clock = null
	_focus = null
	_auto_timeout = false
	var s: Dictionary = Gameplay.simulation.state.livelihood
	if not s.pending.is_empty():
		_window.tabs.hide()
		_window._close.text = "Пауза · Esc"
		_game(s.pending)
		_window.end_update()
		return
	_live_token = ""
	_window._close.text = "Назад · Esc"
	_paused = false
	_previewing = false
	var streak := int(s.streak) if int(Gameplay.simulation.state.clock.day_index)-int(s.streak_day) <= 1 else 0
	UI.label(_body,"Наличные %d ¤ · заработано здесь %d ¤ · серия рабочих дней %d / 7" % [Gameplay.simulation.state.economy.cash,s.totals.earnings,streak],21,UI.BLUE)
	match page:
		"jobs": _jobs()
		"orders": _orders()
		"goals": _goals()
		"home": _home()
	_window.end_update()

func _jobs() -> void:
	var service = Gameplay.simulation.services.livelihood
	UI.label(_body,"Выберите работу слева. За качество в мини-игре можно получить премию.",18,UI.MUTED)
	var filter := OptionButton.new()
	var skills: Array = ["all"]+Gameplay.simulation.catalog.skills.keys()
	filter.add_item("Все навыки · %d работы" % service.rules().jobs.size())
	for skill in skills.slice(1): filter.add_item(Names.title(str(skill)))
	filter.select(skills.find(_skill_filter))
	filter.set_meta("focus_id","job_skill_filter")
	filter.item_selected.connect(func(index): _skill_filter = str(skills[index]); _refresh())
	_body.add_child(filter)
	var columns := UI.row(_body,32)
	var index := UI.scroller(columns)
	index.get_parent().custom_minimum_size = Vector2(360,450)
	index.get_parent().size_flags_horizontal = Control.SIZE_FILL
	var detail := UI.column(columns,12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var matching: Array = []
	var selected_entry: Button
	for id in service.rules().jobs:
		if _skill_filter == "all" or service.rules().jobs[id].skill == _skill_filter: matching.append(id)
	if matching.is_empty():
		W.empty(detail,"desk","Подработок пока нет","Выберите другое направление.")
		return
	if not _selected_job in matching: _selected_job = str(matching[0])
	for id in service.rules().jobs:
		if not id in matching: continue
		var entry := UI.button(index,str(service.rules().jobs[id].title),func(): _selected_job = id; _skip_classes = false; _refresh())
		entry.set_meta("job_id",id)
		entry.set_meta("focus_id",id)
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == _selected_job:
			entry.modulate = UI.BLUE
			selected_entry = entry
	for id in service.rules().jobs:
		if id != _selected_job: continue
		var job: Dictionary = service.rules().jobs[id]
		var card := detail
		W.illustration(card,Art.texture("desk"),72)
		var progress: Dictionary = service.career(id)
		UI.label(card,job.title,27,UI.BLUE)
		UI.label(card,job.description,20)
		UI.label(card,"%s · ступень %d / 5" % [WorkNames.CAREERS[job.career],progress.level],18,UI.MUTED)
		UI.label(card,"Навык: %s · уровень %d / 10 · для входа: %d" % [Names.title(str(job.skill)),progress.skill,job.min_skill],18,UI.BLUE)
		if int(progress.level) < 5:
			UI.label(card,"Следующая ступень: навык %d. Повышение только через навык." % progress.next_skill if progress.automatic else "Следующая ступень: навык %d и опыт %d / %d. Хорошая мини-игра ускоряет рост после достижения нужного навыка." % [progress.next_skill,progress.xp,progress.next_xp],18,UI.MUTED)
		else: UI.label(card,"Максимальная ступень этой работы",18,UI.BLUE)
		var pay_text := "оплата %d ¤" % service.wage(id,0.65) if job.kind == "shift" else "оплата %d–%d ¤" % [service.wage(id,0.0),service.wage(id,1.0)]
		UI.label(card,"%s · %02d:00–%02d:00 · %d мин · силы −%d · %s" % [Names.title(job.location),int(job.hours[0])/60,int(job.hours[1])/60,job.minutes,ceili(float(job.energy)*Gameplay.simulation.multiplier("resource_cost")),pay_text],18,UI.MUTED)
		if float(job.risk) > 0: UI.label(card,"Нелегально · риск задержания %.0f%% · штраф %d ¤ · расход на вход %d ¤" % [service.risk(id)*100,int(job.fine),int(job.get("fee",0))],19,UI.ORANGE)
		var conflicts: Array = service.study_conflicts(id)
		if not conflicts.is_empty():
			for lesson in conflicts:
				UI.label(card,"Занятие: %s · %02d:%02d–%02d:%02d · дорога до кампуса %d мин" % [Names.title(str(lesson.id)),int(lesson.start)%1440/60,int(lesson.start)%60,int(lesson.end)%1440/60,int(lesson.end)%60,lesson.commute],18,UI.ORANGE)
			var skip := CheckBox.new()
			skip.text = "Выйти на смену, пропустив занятия"
			skip.button_pressed = _skip_classes
			skip.set_meta("focus_id","skip_classes")
			skip.toggled.connect(func(value): _skip_classes = value; _refresh())
			card.add_child(skip)
			UI.label(card,"Пропуски снижают успеваемость и могут привести к предупреждению или отчислению.",17,UI.MUTED)
		else: _skip_classes = false
		var reason: String = service.blocked(id,_skip_classes)
		if not reason.is_empty(): UI.label(card,Names.error(reason),18,UI.MUTED)
		if not preload("res://scripts/gameplay/action_policy.gd").commitments(Gameplay.simulation.state,int(Gameplay.simulation.state.clock.total_minutes)+int(job.minutes)).is_empty():
			UI.label(card,"Во время смены наступит срок или встреча. Проверьте свои обязательства.",18,UI.ORANGE)
		var row := UI.row(card)
		UI.button(row,"СМЕНА · %d ¤" % service.wage(id,0.65 if job.kind == "shift" else 0.55),_act.bind("work",{"id":id,"interactive":false,"skip_classes":_skip_classes})).disabled = not reason.is_empty()
		if job.kind != "shift": UI.button(row,"РАБОТАТЬ С МИНИ-ИГРОЙ",_act.bind("work",{"id":id,"interactive":true,"skip_classes":_skip_classes})).disabled = not reason.is_empty()
		if job.location != Gameplay.simulation.state.world.location: UI.button(row,"К РАБОЧЕМУ МЕСТУ",_travel.bind(job.location))
	call_deferred("_reveal_job",index.get_parent(),selected_entry)

func _reveal_job(scroll: ScrollContainer, entry: Button) -> void:
	if is_instance_valid(scroll) and is_instance_valid(entry) and scroll.is_ancestor_of(entry): scroll.ensure_control_visible(entry)

func _orders() -> void:
	var sim = Gameplay.simulation
	UI.label(_body,"Три предложения обновляются с новым днём. До двух заказов одновременно; передача у северных магазинов до 23:00. Нужны настоящие предметы из сумки.",20,UI.MUTED)
	var grid := W.grid(_body,3)
	for offer in sim.services.livelihood.board():
		var card := W.panel(grid)
		W.illustration(card,Art.texture(str(offer.item),sim.catalog.items.get(offer.item,{})),100)
		UI.label(card,offer.title,26,UI.BLUE)
		UI.label(card,"%s × %d · оплата %d ¤" % [Names.title(offer.item),offer.quantity,offer.pay],20)
		if not sim.state.livelihood.orders.has(offer.id): UI.button(card,"ВЗЯТЬ ЗАКАЗ",_act.bind("take_order",{"id":offer.id}))
		else: UI.label(card,{"active":"Уже в работе","completed":"Выполнен","expired":"Срок истёк"}[str(sim.state.livelihood.orders[offer.id].status)],18,UI.MUTED)
	for id in sim.state.livelihood.orders:
		var order: Dictionary = sim.state.livelihood.orders[id]
		if order.status != "active": continue
		var card := UI.card(_body)
		UI.label(card,"В работе: "+str(order.title),24,UI.BLUE)
		UI.label(card,"В сумке %d / %d · осталось %d мин · %d ¤" % [sim.state.inventory.items.get(order.item,0),order.quantity,int(order.deadline)-int(sim.state.clock.total_minutes),order.pay],20)
		UI.button(card,"ПЕРЕДАТЬ · 15 МИН",_act.bind("deliver",{"id":id}))
	UI.button(_body,"К СЕВЕРНЫМ МАГАЗИНАМ",_travel.bind("north_shops"))

func _goals() -> void:
	var service = Gameplay.simulation.services.livelihood
	UI.label(_body,"Добровольные цели открытого мира. Награда за каждую выдаётся один раз; поступки считаются с первого выбора цели.",20,UI.MUTED)
	var grid := W.grid(_body,2)
	for id in service.rules().aspirations:
		var spec: Dictionary = service.rules().aspirations[id]
		var view: Dictionary = service.goal_view(id)
		var card := W.panel(grid)
		UI.label(card,spec.title,26,UI.BLUE)
		UI.label(card,spec.description+" Награда: %d опыта." % spec.xp,20)
		if view.claimed: UI.label(card,"Достигнуто",20,UI.BLUE)
		elif view.chosen:
			UI.label(card,"Выполнено: %d / %d" % [view.count,view.required],20)
			UI.button(card,"ПОЛУЧИТЬ НАГРАДУ",_act.bind("claim_goal",{"id":id})).disabled = not view.ready
		else: UI.button(card,"ВЫБРАТЬ ЦЕЛЬ",_act.bind("choose_goal",{"id":id}))

func _home() -> void:
	var service = Gameplay.simulation.services.livelihood
	UI.label(_body,"Улучшения принадлежат текущему жилью и остаются в нём после переезда. Установка: 30 минут дома.",20,UI.MUTED)
	var grid := W.grid(_body,2)
	for id in service.rules().upgrades:
		var spec: Dictionary = service.rules().upgrades[id]
		var level: int = service.home_level(id)
		var card := W.panel(grid)
		UI.label(card,"%s · %d / %d" % [spec.title,level,spec.max_level],26,UI.BLUE)
		UI.label(card,spec.description,20)
		if level < int(spec.max_level):
			var price := int(spec.price)*(level+1)
			var buy := UI.button(card,"УЛУЧШИТЬ · %d ¤" % price,_act.bind("upgrade",{"id":id}))
			buy.disabled = not Gameplay.simulation.state.world.location in ["bedroom","bathroom","kitchen","apartment_hall"] or int(Gameplay.simulation.state.economy.cash) < price
			if buy.disabled: buy.tooltip_text = "Нужно находиться дома и иметь %d ¤." % price

func _game(p: Dictionary) -> void:
	var spec: Dictionary = Gameplay.simulation.services.livelihood.rules().jobs[p.id]
	_duration = int(p.assistance.duration_ms)
	var elapsed := _elapsed()
	if p.token != _live_token:
		_status.text = ""
		_paused = false
		elapsed = int(p.elapsed)
	elif _previewing and not p.preview: elapsed = int(p.elapsed)
	_offset = maxi(int(p.elapsed),elapsed)
	_epoch = Time.get_ticks_msec()
	_live_token = str(p.token)
	_previewing = bool(p.preview)
	UI.label(_body,spec.title,32,UI.BLUE)
	UI.label(_body,"Смена учтена. Выполните задание, чтобы получить премию за качество.",20,UI.MUTED)
	UI.label(_body,"Готово %d / %d · верно %d" % [p.round,p.assistance.rounds,p.correct],24)
	UI.label(_body,"%s · помощь навыков %.0f%% · время %.0f с" % [Names.title(str(p.assistance.skill)),float(p.assistance.help)*100,_duration/1000.0],18,UI.BLUE)
	if _paused:
		UI.label(_body,"Пауза · время испытания остановлено",26,UI.BLUE)
		UI.button(_body,"ПРОДОЛЖИТЬ",_toggle_pause)
		UI.button(_body,"СОХРАНЕНИЕ И МЕНЮ",func():
			if get_parent().has_signal("menu_requested"): get_parent().emit_signal("menu_requested"))
		return
	if p.preview:
		var words: Array[String] = []
		for task in p.tasks: words.append(str(spec.choices[int(task.answer)]))
		UI.label(_body,"Запомните порядок:\n"+" → ".join(words),28,UI.ORANGE)
		UI.button(_body,"ЗАПОМНИЛ · НАЧАТЬ",func(): _work_input({"action":"ready"}))
	else:
		_clock = UI.label(_body,"",22,UI.ORANGE)
		var task: Dictionary = p.tasks[int(p.round)]
		if spec.kind == "focus":
			UI.label(_body,"Нажмите рядом с отметкой %.0f%%. Допуск: %.0f%% в обе стороны." % [float(task.target)*100,float(p.assistance.window)*100],25)
			_focus = preload("res://scripts/ui/gameplay/work_timing_meter.gd").new()
			_focus.target = float(task.target)
			_focus.tolerance = float(p.assistance.window)
			_focus.custom_minimum_size.y = 38
			_body.add_child(_focus)
			UI.button(_body,"ПОЙМАТЬ РИТМ",func(): _work_input({}))
		elif spec.kind == "reasoning":
			UI.label(_body,str(task.prompt),27,UI.ORANGE)
			if int(task.excluded) >= 0: UI.label(_body,"Навык помог исключить один неверный вариант. Выберите из оставшихся.",18,UI.MUTED)
			for index in range(task.options.size()):
				if index != int(task.excluded): _choice(_body,str(task.options[index]),index)
		elif spec.kind == "comparison":
			UI.label(_body,str(spec.comparison_prompt),24,UI.ORANGE)
			_round_clock = UI.label(_body,"",19,UI.MUTED)
			var row := UI.row(_body,32)
			for side in ["reference","candidate"]:
				var box := UI.column(row,12)
				UI.label(box,"Контроль" if side == "reference" else "Выберите различие",20,UI.BLUE)
				var grid := W.grid(box,3)
				for index in range(9):
					var caption := "%d  %s" % [index+1,["○","△","□","◇"][int(task[side][index])]]
					if side == "candidate":
						var cell := _choice(grid,caption,index)
						cell.custom_minimum_size = Vector2(100,72)
						cell.add_theme_font_size_override("font_size",roundi(30*UI.text_scale))
					else:
						var cell := UI.label(grid,caption,30,UI.BLUE)
						cell.custom_minimum_size = Vector2(100,72)
						cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif spec.kind == "sequence":
			UI.label(_body,str(task.prompt),27,UI.ORANGE)
			var chosen: Array[String] = []
			for index in p.selection: chosen.append(str(task.options[int(index)]))
			UI.label(_body,"Выбрано: "+(" → ".join(chosen) if not chosen.is_empty() else "пока ничего"),20,UI.BLUE)
			for index in range(task.options.size()):
				var choice := _choice(_body,str(task.options[index]),index)
				choice.disabled = index in p.selection
			if not p.selection.is_empty(): UI.button(_body,"ОТМЕНИТЬ ПОСЛЕДНИЙ ЭТАП",func(): _work_input({"action":"undo"}))
		else:
			var choices: Array = spec.choices
			UI.label(_body,"На посылке: "+str(choices[int(task.answer)]) if spec.kind == "sorting" else "Что было в позиции %d?" % (int(p.round)+1),28,UI.ORANGE)
			if spec.kind == "sorting": _round_clock = UI.label(_body,"",19,UI.MUTED)
			var row := UI.row(_body)
			for i in range(choices.size()): _choice(row,str(choices[i]),i)
	UI.button(_body,"ПАУЗА · ESC",_toggle_pause)
	UI.button(_body,"ПРЕРВАТЬ · ПОНИЖЕННАЯ ОПЛАТА",func(): _act("cancel",{"token":p.token}))

func _choice(parent: Node, caption: String, index: int) -> Button:
	var result := UI.button(parent,caption,func(): _work_input({"choice":index}))
	result.set_meta("work_choice",index)
	return result

func _elapsed() -> int:
	if _paused or _previewing: return _offset
	return _offset+int(Time.get_ticks_msec())-_epoch

func _toggle_pause() -> void:
	_offset = _elapsed()
	_epoch = Time.get_ticks_msec()
	_paused = not _paused
	_refresh()

func _process(_delta: float) -> void:
	if not is_instance_valid(_clock): return
	var elapsed := _elapsed()
	_clock.text = "Осталось %.1f с" % maxf(0,(_duration-elapsed)/1000.0)
	if is_instance_valid(_round_clock):
		var p: Dictionary = Gameplay.simulation.state.livelihood.pending
		if not p.is_empty(): _round_clock.text = "На текущий ответ: %.1f с" % maxf(0,(int(p.assistance.round_ms)-elapsed+int(p.last))/1000.0)
	if is_instance_valid(_focus):
		_focus.value = fposmod(elapsed/1500.0,1.0)
		_focus.queue_redraw()
	if elapsed >= _duration and not _auto_timeout:
		_auto_timeout = true
		call_deferred("_work_input",{})

func _work_input(extra: Dictionary) -> void:
	var p: Dictionary = Gameplay.simulation.state.livelihood.pending
	if p.is_empty(): return
	var args := {"token":p.token,"round":int(p.round),"elapsed_ms":_elapsed()}
	args.merge(extra,true)
	_act("input",args)

func _act(operation: String, args: Dictionary) -> void:
	var result: Dictionary = Gameplay.execute("livelihood",operation,args)
	_status.text = "Оплата: %d ¤%s" % [result.data.pay," · задержание, назначен штраф" if result.data.get("caught",false) else ""] if result.ok and result.data.has("pay") else "" if result.ok else Names.error(str(result.error))
	if result.ok and result.data.has("correct"): _status.text = "Верно" if result.data.correct else "Ошибка · премия за качество ниже"
	if result.ok and result.data.get("accelerated",false): _status.text += " · ускоренный карьерный рост"
	if result.ok and int(result.data.get("missed_classes",0)) > 0: _status.text += " · пропущено занятий: %d" % int(result.data.missed_classes)
	if result.ok and not str(result.data.get("feedback","")).is_empty(): _status.text += " · "+str(result.data.feedback)
	_window.notice(_status.text)

func _travel(id: String) -> void:
	var result: Dictionary = Gameplay.execute("world","journey",{"id":id})
	_status.text = "" if result.ok else Names.error(str(result.error))

func _close() -> void:
	if not Gameplay.simulation.state.livelihood.pending.is_empty(): _window.notice(Names.error("finish_work_session")); return
	closed.emit()
	queue_free()

func _back() -> void:
	if not Gameplay.simulation.state.livelihood.pending.is_empty(): _toggle_pause()
	else: _close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not Gameplay.simulation.state.livelihood.pending.is_empty(): _toggle_pause()
		else: _close()
