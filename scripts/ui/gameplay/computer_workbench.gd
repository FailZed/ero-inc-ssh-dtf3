extends RefCounted
## Player-facing entry to the staged computer careers in the sandbox.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")

static func _tab(owner: Control, parent: Node, key: String, options: Dictionary, fallback: String) -> String:
	var selected := str(owner._screen_state.get(key, fallback))
	if not options.has(selected): selected = fallback
	W.tabs(parent, options, selected, owner._choose_screen.bind(key))
	return selected

static func _button(owner: Control, parent: Node, label: String, operation: String, args: Dictionary = {}) -> void:
	UI.button(parent, label, owner._act.bind("computer", operation, args))

static func render(owner: Control, parent: Node) -> void:
	var sim = Gameplay.simulation
	var view: Dictionary = sim.services.computer.inspect()
	var selected := _tab(owner, parent, "computer_tab", {"orders":"Заказы", "practice":"Развитие", "operations":"Операции", "broadcast":"Эфиры"}, "orders")
	if not str(view.blocked).is_empty():
		UI.label(parent, {"missing_computer":"Нужен компьютер в комнате.", "computer_desk_required":"Рабочее место доступно дома у компьютера.", "no_current_home":"Сначала нужно жильё для рабочего места."}.get(str(view.blocked), "Рабочее место сейчас недоступно."), 18, UI.ORANGE)
	if selected == "orders": _orders(owner, parent, view)
	elif selected == "practice": _practice(owner, parent, view)
	elif selected == "operations": _operations(owner, parent, view, sim)
	else: _broadcast(owner, parent, view)

static func _orders(owner: Control, parent: Node, view: Dictionary) -> void:
	UI.label(parent, "Заказы с этапами и сроком", 21, UI.BLUE)
	for project in view.projects:
		if str(project.status) != "active": continue
		var card := W.panel(parent)
		UI.label(card, str(project.label), 23)
		var stage: String = {"design":"Замысел", "build":"Реализация", "test":"Проверка", "delivery":"Сдача"}.get(str(project.stage), str(project.stage))
		UI.label(card, "%s · качество %d/100 · замечания %d · осталось %d мин" % [stage, roundi(float(project.quality)), int(project.bugs), int(project.remaining_minutes)], 17, UI.BLUE)
		if int(project.step) < 3:
			for choice_id in project.choices:
				var choice: Dictionary = project.choices[choice_id]
				_button(owner, card, "%s · %d мин · качество %+d · замечания %+d" % [str(choice.label), int(choice.minutes), int(choice.quality), int(choice.bugs)], "project_step", {"id":project.id, "step":project.stage, "choice":choice_id})
		else:
			if bool(project.ready): _button(owner, card, "Сдать клиенту · около %d €$" % int(project.estimated_pay), "deliver_project", {"id":project.id})
			elif bool(project.can_revise): _button(owner, card, "Исправить замечания · 30 мин", "revise_project", {"id":project.id})
			else: UI.label(card, "Заказ не готов к сдаче.", 17, UI.ORANGE)
		UI.label(card, str(project.brief), 17, UI.MUTED)
		_button(owner, card, "Отказаться от заказа", "abandon_project", {"id":project.id})
	var cards := W.grid(parent, 2)
	for offer in view.board:
		if bool(offer.accepted): continue
		var card := W.panel(cards)
		UI.label(card, str(offer.label), 22)
		UI.label(card, "Оплата от %d €$ · срок %d ч · навык %d" % [int(offer.pay), floori(float(offer.deadline) / 60.0), int(offer.skill)], 16, UI.BLUE)
		if bool(offer.locked): UI.label(card, "Пока не хватает навыка", 16, UI.ORANGE)
		else: _button(owner, card, "Взять заказ", "take_project", {"id":offer.id})
		UI.label(card, str(offer.brief), 17, UI.MUTED)
	if cards.get_child_count() == 0: W.empty(parent, "desk", "Новых заказов сегодня нет", "Доска обновится завтра.")
	if not view.portfolio.is_empty(): UI.label(parent, "В портфолио: %d работ" % view.portfolio.size(), 17, UI.MUTED)

static func _practice(owner: Control, parent: Node, view: Dictionary) -> void:
	var tracks := W.grid(parent, 3)
	for track in view.tracks:
		var card := W.panel(tracks)
		UI.label(card, str(track.label), 21)
		UI.label(card, "Уровень %d · опыт %d" % [int(track.level), int(track.xp)], 17, UI.BLUE)
		if int(track.next_level_xp) > 0: UI.label(card, "Следующий уровень: %d" % int(track.next_level_xp), 16, UI.MUTED)
		if not str(track.specialization).is_empty(): UI.label(card, "Специализация: " + str(view.specializations[track.specialization].label), 16, UI.MUTED)
	UI.label(parent, "Практика · один раз в день для каждого направления", 20, UI.BLUE)
	var lessons := W.grid(parent, 2)
	for id in view.lessons:
		var lesson: Dictionary = view.lessons[id]
		var card := W.panel(lessons)
		UI.label(card, str(lesson.label), 19)
		UI.label(card, "30 мин · профессиональный опыт +12", 16, UI.MUTED)
		if bool(lesson.available): _button(owner, card, "Практиковаться", "lesson", {"id":id})
		else: UI.label(card, "Сегодня уже выполнено", 16, UI.MUTED)
	UI.label(parent, "Оборудование и направления", 20, UI.BLUE)
	var upgrades := W.grid(parent, 2)
	for upgrade in view.upgrades:
		var card := W.panel(upgrades)
		UI.label(card, str(upgrade.label) + " · %d/%d" % [int(upgrade.level), int(upgrade.max_level)], 19)
		UI.label(card, str(upgrade.description), 16, UI.MUTED)
		if int(upgrade.level) < int(upgrade.max_level): _button(owner, card, "Улучшить · %d €$" % int(upgrade.price), "upgrade", {"id":upgrade.id})
	for id in view.specializations:
		var spec: Dictionary = view.specializations[id]
		var card := W.panel(upgrades)
		UI.label(card, str(spec.label), 19)
		UI.label(card, str(spec.description), 16, UI.MUTED)
		_button(owner, card, "Выбрать направление", "specialize", {"id":id})

static func _operations(owner: Control, parent: Node, view: Dictionary, sim) -> void:
	UI.label(parent, "Три этапа подготовки и итоговый подход", 20, UI.BLUE)
	if not view.hack.is_empty():
		var session: Dictionary = view.hack
		var card := W.panel(parent)
		UI.label(card, "Этап %d/3 · подготовка %d · давление %d" % [int(session.step)+1, int(session.intel), int(session.pressure)], 20)
		UI.label(card, str(session.scenario.text), 18, UI.MUTED)
		var approach := _tab(owner, card, "computer_approach", {"careful":"Осторожно", "balanced":"Сбалансированно", "fast":"Быстро"}, "balanced") if int(session.step) == 2 else "balanced"
		if int(session.step) == 2:
			var preview: Dictionary = sim.services.digital.preview(str(session.id), approach)
			if preview.ok: UI.label(card, "Итог: %d мин · шанс около %d%% · награда до %d €$" % [int(preview.data.minutes), roundi(float(preview.data.chance)*100), int(preview.data.reward)], 16, UI.BLUE)
		for choice_id in session.choices:
			var choice: Dictionary = session.choices[choice_id]
			_button(owner, card, "%s · %d мин" % [str(choice.label), int(choice.minutes)], "hack_step", {"token":session.token, "step":session.step, "choice":choice_id, "approach":approach})
		_button(owner, card, "Остановить операцию", "hack_abort", {"token":session.token})
		return
	if bool(view.busy):
		UI.label(parent, "Сначала завершите текущую компьютерную задачу.", 18, UI.ORANGE)
		return
	var cards := W.grid(parent, 2)
	for operation in view.operations:
		var plan: Dictionary = operation.approaches[1]
		var card := W.panel(cards)
		UI.label(card, str(operation.label), 20)
		UI.label(card, "Подготовка 15 мин · затем три решения · награда до %d €$" % int(plan.reward), 16, UI.MUTED)
		if str(plan.blocked).is_empty(): _button(owner, card, "Начать подготовку", "hack_start", {"id":operation.id})
		else: UI.label(card, "Пока недоступно", 16, UI.ORANGE)

static func _broadcast(owner: Control, parent: Node, view: Dictionary) -> void:
	UI.label(parent, "Подписчики: %d" % int(view.followers), 20, UI.BLUE)
	if not view.broadcast.is_empty():
		var session: Dictionary = view.broadcast
		var card := W.panel(parent)
		UI.label(card, "Эфир · блок %d/%d" % [int(session.step)+1, int(session.segments)], 22)
		UI.label(card, str(session.event.text), 18, UI.MUTED)
		UI.label(card, "Качество %.0f · вовлечение %.0f · доход %d €$" % [float(session.quality), float(session.engagement), int(session.income)], 17, UI.BLUE)
		for choice_id in session.choices:
			_button(owner, card, str(session.choices[choice_id].label) + " · 15 мин", "stream_step", {"token":session.token, "step":session.step, "choice":choice_id})
		_button(owner, card, "Завершить досрочно", "stream_finish", {"token":session.token})
	else:
		if bool(view.busy): UI.label(parent, "Сначала завершите текущую компьютерную задачу.", 18, UI.ORANGE)
		else:
			var topic := str(owner._screen_state.get("computer_topic", view.topics.keys()[0]))
			if not view.topics.has(topic): topic = str(view.topics.keys()[0])
			var format := str(owner._screen_state.get("computer_format", "focused"))
			if not view.formats.has(format): format = "focused"
			var sponsor := str(owner._screen_state.get("computer_sponsor", ""))
			if not sponsor.is_empty() and not view.sponsors.has(sponsor): sponsor = ""
			if not sponsor.is_empty() and not bool(view.sponsors[sponsor].available): sponsor = ""
			var segments := int(owner._screen_state.get("computer_segments", 4))
			UI.label(parent, "Тема", 18, UI.MUTED)
			var topics := W.grid(parent, 2)
			for id in view.topics:
				var topic_label: String = {"games":"Игры", "education":"Обучение", "creative":"Творчество"}.get(str(id), str(id))
				var button := UI.button(topics, topic_label, owner._choose_screen.bind(str(id), "computer_topic"))
				if id == topic: button.modulate = UI.BLUE
			UI.label(parent, "Формат", 18, UI.MUTED)
			_tab(owner, parent, "computer_format", {"focused":"Тематический", "community":"Общение", "showcase":"Портфолио"}, "focused")
			UI.label(parent, "Партнёр", 18, UI.MUTED)
			var sponsors := W.grid(parent, 3)
			var none := UI.button(sponsors, "Без партнёра", owner._choose_screen.bind("", "computer_sponsor"))
			if sponsor.is_empty(): none.modulate = UI.BLUE
			for id in view.sponsors:
				var spec: Dictionary = view.sponsors[id]
				var button := UI.button(sponsors, "%s · от %d подписчиков" % [str(spec.label), int(spec.followers)], owner._choose_screen.bind(str(id), "computer_sponsor"))
				button.disabled = not bool(spec.available)
				if id == sponsor: button.modulate = UI.BLUE
			var durations := UI.row(parent)
			for count in [2, 4, 6]:
				var button := UI.button(durations, "%d блоков" % count, owner._choose_screen.bind(str(count), "computer_segments"))
				if count == segments: button.modulate = UI.BLUE
			_button(owner, parent, "Начать эфир · 10 мин подготовки", "stream_start", {"id":topic, "format":format, "segments":segments, "sponsor":sponsor})
	for row in view.broadcasts.slice(maxi(0, view.broadcasts.size()-6)):
		if not bool(row.completed): continue
		var card := W.panel(parent)
		UI.label(card, "Эфир · качество %d · доход %d €$" % [roundi(float(row.quality)), int(row.income)], 17)
		if not bool(row.highlight) and float(row.quality) >= 40: _button(owner, card, "Опубликовать нарезку · 20 мин", "publish_highlight", {"id":row.id})
