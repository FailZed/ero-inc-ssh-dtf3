extends Control
signal cancelled
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const Population = preload("res://scripts/mechanics/population.gd")
const Preferences = preload("res://scripts/mechanics/preferences.gd")
const Portrait = preload("res://scripts/ui/gameplay/resident_preview.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const Education = preload("res://scripts/mechanics/education_schedule.gd")
var configuration: Dictionary = Setup.defaults()
var page := 0
var _body: VBoxContainer
var _step: Label
var _next: Button
var _back: Button
var _summary: Label
var _status: Label
var _mode_title: Label
var _mode_description: Label
var _morph_labels: Array[Label] = []
var _count: SpinBox
var _semi: SpinBox
var _furry: SpinBox
var _subject_checks: Dictionary = {}
var _education_status: Label

func _ready() -> void:
	var seed_source := RandomNumberGenerator.new()
	seed_source.randomize()
	configuration.seed = seed_source.randi_range(0,2147483647)
	theme = UI.skin()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.background(self, "res://assets/textures/backgrounds/prolog/warehouse_exterior_night.png", 0.40)
	var root := UI.row(UI.inset(self, 60), 42)
	var aside := UI.column(root, 24)
	aside.custom_minimum_size.x = 280
	UI.label(aside, "ERO INC", 46)
	_mode_title = UI.label(aside, "НОВАЯ ИСТОРИЯ", 17, UI.ORANGE)
	_step = UI.label(aside, "", 26, UI.BLUE)
	_mode_description = UI.label(aside, "", 20, UI.MUTED)
	var space := Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aside.add_child(space)
	_summary = UI.label(aside, "", 18, UI.MUTED)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UI.surface(28))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var content := UI.column(panel, 18)
	_body = UI.scroller(content)
	_status = UI.label(content, "", 18, UI.ORANGE)
	var footer := UI.row(content)
	_back = UI.button(footer, "НАЗАД", _go_back)
	_next = UI.button(footer, "ДАЛЕЕ  →", _go_next)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_show_page()

func _show_page() -> void:
	UI.clear(_body)
	_mode_title.text = "ПЕСОЧНИЦА" if configuration.get("mode","story") == "sandbox" else "НОВАЯ ИСТОРИЯ"
	_mode_description.text = "Город будет жить своим ритмом.\n\nСамостоятельная жизнь без основного сюжета: заботьтесь о себе, обустраивайте дом и знакомьтесь с жителями." if configuration.get("mode","story") == "sandbox" else "Город будет жить своим ритмом.\n\nЭти настройки определяют случайных жителей. Сюжетные персонажи сохраняют свои особенности."
	_step.text = "1 / 2\nЖители города" if page == 0 else "2 / 2\nВаш ритм жизни"
	_next.text = "ДАЛЕЕ  →" if page == 0 else "НАЧАТЬ ПЕСОЧНИЦУ  →" if configuration.get("mode","story") == "sandbox" else "НАЧАТЬ ИСТОРИЮ  →"
	if page == 0: _population_page()
	else: _difficulty_page()
	_refresh()
	_next.grab_focus()

func _population_page() -> void:
	UI.label(_body, "Режим игры", 26, UI.BLUE)
	var modes := UI.row(_body)
	for id in ["story", "sandbox"]:
		var caption: String = {"story":"ИСТОРИЯ", "sandbox":"ПЕСОЧНИЦА · ЖИЗНЬ В ГОРОДЕ"}[id]
		UI.button(modes, ("✓ " if configuration.get("mode","story") == id else "") + caption, func():
			configuration.mode = id
			if id == "sandbox": configuration.difficulty = "hard"
			_show_page())
	UI.label(_body,"Сюжетное начало, затем свободная жизнь в городе." if configuration.mode == "story" else "Начало у домашнего зеркала, затем самостоятельная жизнь в городе без основного сюжета.",19,UI.MUTED)
	UI.label(_body, "Кто живёт в вашем городе?", 36)
	UI.label(_body, "Люди, полуфурри и фурри — разные внешности, равные возможности.", 20, UI.MUTED)
	var portraits := UI.row(_body, 14)
	_morph_labels.clear()
	for id in ["human", "semi_furry", "furry"]:
		var card := UI.card(portraits)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var portrait := TextureRect.new()
		portrait.texture = load("res://assets/textures/portraits/world_examples/%s.tres" % id)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(140,160)
		card.add_child(portrait)
		UI.label(card, {"human":"ЧЕЛОВЕК", "semi_furry":"ПОЛУФУРРИ", "furry":"ФУРРИ"}[id], 22)
		UI.label(card, {"human":"Человеческие черты", "semi_furry":"Человеческое лицо, звериные уши", "furry":"Шерсть, морда и хвост"}[id], 16, UI.MUTED)
		_morph_labels.append(UI.label(card, "", 24, UI.BLUE))
	var values := W.grid(_body,3)
	_count = _number(values,"Жителей в городе",1,200,int(configuration.population.count),func(v): configuration.population.count = int(v); _refresh())
	_semi = _number(values,"Полуфурри, %",0,100,float(configuration.population.semi_furry_ratio)*100,_change_morphology.bind("semi_furry_ratio"),0.1)
	_furry = _number(values,"Фурри, %",0,100,float(configuration.population.furry_ratio)*100,_change_morphology.bind("furry_ratio"),0.1)
	var fold := UI.button(_body, "Характеры и дополнительные настройки  ▾", func(): pass)
	var advanced := UI.column(_body)
	advanced.visible = false
	fold.pressed.connect(func(): advanced.visible = not advanced.visible)
	_number(advanced, "Минимальный возраст", 18, 80, configuration.population.age_min, func(v): configuration.population.age_min = int(v); _refresh())
	_number(advanced, "Максимальный возраст", 18, 80, configuration.population.age_max, func(v): configuration.population.age_max = int(v); _refresh())
	_number(advanced, "Доля женщин, %", 0, 100, configuration.population.female_ratio * 100, func(v): configuration.population.female_ratio = v / 100.0; _refresh())
	UI.label(advanced, "Характеры жителей", 25, UI.BLUE)
	UI.label(advanced, "Средние склонности города. У каждого жителя — 24 сочетающихся качества, свои ценности и интересы. Внешность не определяет характер.", 18, UI.MUTED)
	var domains := {"honesty": "Честность и скромность", "emotionality": "Эмоциональность", "extraversion": "Общительность", "agreeableness": "Уживчивость", "conscientiousness": "Добросовестность", "openness": "Открытость новому"}
	for key in domains:
		_number(advanced, domains[key], 0, 100, configuration.personality[key], func(v): configuration.personality[key] = int(v))
	_number(advanced, "Разнообразие характеров", 0, 100, configuration.personality.spread, func(v): configuration.personality.spread = int(v))
	_number(advanced, "Минимальная характеристика", 1, 100, configuration.population.stat_min, func(v): configuration.population.stat_min = int(v); _refresh())
	_number(advanced, "Максимальная характеристика", 1, 100, configuration.population.stat_max, func(v): configuration.population.stat_max = int(v); _refresh())
	var options := OptionButton.new()
	for name_text in ["Учёба и работа", "Рабочий город", "Студенческий город"]: options.add_item(name_text)
	options.select(["mixed","work","study"].find(configuration.population.activity_mode))
	options.item_selected.connect(func(i): configuration.population.activity_mode = ["mixed", "work", "study"][i])
	advanced.add_child(options)
	_number(advanced, "Ключ генерации города", 0, 2147483647, configuration.seed, func(v): configuration.seed = int(v))

func _change_morphology(percent: float, key: String) -> void:
	var pop: Dictionary = configuration.population
	var other := "furry_ratio" if key == "semi_furry_ratio" else "semi_furry_ratio"
	var ratio := clampf(percent/100.0,0.0,1.0)
	var previous_remaining := 1.0-float(pop[key])
	var other_ratio := (1.0-ratio)*float(pop[other])/previous_remaining if previous_remaining > 0.000001 else (1.0-ratio)*0.5
	pop[key] = ratio
	pop[other] = clampf(snappedf(other_ratio,0.001),0.0,1.0-ratio)
	_refresh()

func _number(parent: Node, text: String, low: float, high: float, value: float, callback: Callable, step_value: float = 1.0) -> SpinBox:
	var row: Container = UI.column(parent,8) if parent is GridContainer else UI.row(parent)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(row, text, 20, UI.MUTED)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step_value
	spin.value = value
	spin.custom_minimum_size = Vector2(180, 48)
	if parent is GridContainer: spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(callback)
	row.add_child(spin)
	return spin

func _difficulty_page() -> void:
	UI.label(_body, "В каком ритме вы хотите жить?", 36)
	UI.label(_body, "Потребности, расходы и самостоятельная жизнь жителей действуют с начала свободной игры." if configuration.get("mode","story") == "sandbox" else "Первая глава посвящена истории. Свободные занятия и последствия включатся после её завершения.", 20, UI.MUTED)
	UI.label(_body, "Отношения и семья", 26, UI.BLUE)
	for id in ["romance", "adult", "pregnancy"]:
		var content_toggle := CheckBox.new()
		content_toggle.text = {"romance":"Романтика и отношения", "adult":"Взрослые личные темы · 18+", "pregnancy":"Беременность и появление детей"}[id]
		content_toggle.button_pressed = bool(configuration.content.get(id,true))
		content_toggle.toggled.connect(func(value): configuration.content[id] = value)
		_body.add_child(content_toggle)
	if configuration.get("mode","story") == "sandbox":
		_number(_body, "Деньги на начало жизни", 100, 1000, configuration.get("sandbox",{}).get("start_cash",250), func(v): configuration.sandbox.start_cash = int(v))
		_education_settings()
	var choices := W.grid(_body,3)
	for id in ["easy", "normal", "hard"]:
		var card := W.panel(choices,18)
		var names := {"easy":"СПОКОЙНАЯ ЖИЗНЬ", "normal":"ОБЫЧНЫЙ РИТМ", "hard":"КАЖДЫЙ ДЕНЬ ИМЕЕТ ВЕС"}
		var descriptions := {"easy":"Больше пространства для общения и исследования. Мягкие условия повседневной жизни.", "normal":"Нужно планировать день и расходы. За ошибки можно восстановиться без жёстких последствий.", "hard":"Ресурсы ограничены, соперники настойчивее. Голод, истощение и задолженность имеют последствия."}
		var select := UI.button(card,("✓ " if configuration.difficulty == id else "") + names[id].capitalize(),func(): configuration.difficulty = id; _show_page())
		select.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		select.custom_minimum_size.y = 72
		if configuration.difficulty == id: select.modulate = UI.BLUE
		select.tooltip_text = descriptions[id]
		UI.label(card, descriptions[id], 19, UI.MUTED)
	UI.button(_body, "СВОИ ПРАВИЛА  ▾", func(): configuration.difficulty = "custom"; _show_page())
	if configuration.difficulty == "custom":
		var custom := UI.card(_body)
		UI.label(custom, "Свои правила", 24, UI.BLUE)
		var names := {"satiety_enabled":"Учитывать голод", "rent_enabled":"Плата за жильё", "education_failure":"Последствия пропусков", "starvation_attrition":"Урон от голода", "exhaustion_enabled":"Истощение", "eviction_enabled":"Выселение за долги"}
		var baseline: Dictionary = Gameplay.simulation.catalog.difficulties.custom
		for id in Preferences.TOGGLES:
			var check := CheckBox.new()
			check.text = names[id]
			check.button_pressed = bool(configuration.custom.get(id, baseline.get(id, true)))
			check.toggled.connect(func(v): configuration.custom[id] = v)
			custom.add_child(check)
		var numeric := {"xp":"Скорость развития", "need_decay":"Расход потребностей", "resource_cost":"Стоимость усилий", "relation_gain":"Рост отношений", "dialogue_fatigue":"Усталость от общения", "injury_damage":"Тяжесть травм", "injury_recovery":"Восстановление", "initial_points":"Начальные очки", "combat_accuracy":"Помощь в бою", "enemy_accuracy":"Точность противника", "npc_tactics":"Тактика противника", "interaction_bonus":"Бонус общения"}
		for id in Preferences.RANGES:
			if id == "minigame_floor": numeric[id] = "Минимальная сложность мини-игр"
			if id == "skill_help_cap": numeric[id] = "Максимальная помощь навыков"
			_number(custom, numeric[id], Preferences.RANGES[id][0], Preferences.RANGES[id][1], configuration.custom.get(id, baseline.get(id, 1)), func(v): configuration.custom[id] = int(v) if id == "initial_points" else v; _refresh(), 1.0 if id == "initial_points" else 0.05)
	UI.label(_body,"Бытовые потребности",26,UI.BLUE)
	UI.label(_body,"Можно отключить отдельные потребности: они исчезнут из HUD и перестанут влиять на героя. Во время игры эти настройки доступны в разделе потребностей.",19,UI.MUTED)
	for id in ["hydration","satiety","hygiene","bladder","rested","fun","social"]:
		var toggle := CheckBox.new()
		toggle.text = {"hydration":"Вода","satiety":"Голод","hygiene":"Гигиена","bladder":"Туалет","rested":"Сон","fun":"Досуг","social":"Общение"}[id]
		toggle.button_pressed = bool(configuration.needs.get(id,configuration.difficulty != "easy" if id == "satiety" else true))
		toggle.toggled.connect(func(value): configuration.needs[id] = value)
		_body.add_child(toggle)
	UI.label(_body, "Внешность и имя героя вы выберете дома, перед зеркалом.", 19, UI.BLUE)

func _education_settings() -> void:
	UI.label(_body,"Учёба и свободное время",26,UI.BLUE)
	var plan: Dictionary = configuration.sandbox.education
	var enrolled := CheckBox.new()
	enrolled.text = "Я учусь в университете"
	enrolled.button_pressed = plan.enrolled
	enrolled.set_meta("education_enrolled",true)
	enrolled.toggled.connect(func(value):
		configuration.sandbox.education = Education.defaults() if value else {"enrolled":false,"subjects":[]}
		_show_page())
	_body.add_child(enrolled)
	_subject_checks.clear()
	if not plan.enrolled:
		UI.label(_body,"Свободная жизнь без обязательных занятий, пропусков и отчисления. Развивать навыки и пользоваться городом можно в обычном порядке.",19,UI.MUTED)
		return
	UI.label(_body,"Выберите 2–4 предмета. Понедельник: общий день группы, 10:00–11:00. Учёбу придётся совмещать с работой; дорога тоже занимает время.",19,UI.MUTED)
	var grid := W.grid(_body,2)
	for id in Education.SUBJECTS:
		var spec: Dictionary = Education.SUBJECTS[id]
		var card := W.panel(grid,14)
		var subject := CheckBox.new()
		subject.text = str(spec.title)
		subject.button_pressed = id in plan.subjects
		subject.set_meta("education_subject",id)
		subject.toggled.connect(func(value):
			if value and not id in plan.subjects: plan.subjects.append(id)
			elif not value: plan.subjects.erase(id)
			_refresh_education()
			_refresh())
		card.add_child(subject)
		_subject_checks[id] = subject
		UI.label(card,"%s · %02d:00–%02d:00" % ["Вт, чт" if spec.days == [2,4] else "Ср, пт",int(spec.hours[0])/60,int(spec.hours[1])/60],17,UI.MUTED)
	_education_status = UI.label(_body,"",19,UI.BLUE)
	_refresh_education()
	UI.label(_body,"Допуск с опозданием — до 15 минут включительно. Занятие закончится по расписанию; опыт и учебный результат будут ниже. Позже допуск закрыт, пропуск фиксируется в конце занятия.",18,UI.MUTED)

func _refresh_education() -> void:
	var selected: Array = configuration.sandbox.education.subjects
	_education_status.text = "Выбрано %d / 4 · нужно минимум 2" % selected.size()
	for id in _subject_checks: _subject_checks[id].disabled = selected.size() >= 4 and not id in selected

func _refresh() -> void:
	var pop: Dictionary = configuration.population
	var counts := Population.morphology_counts(pop)
	if page == 0:
		if is_instance_valid(_semi): _semi.set_value_no_signal(float(pop.semi_furry_ratio)*100)
		if is_instance_valid(_furry): _furry.set_value_no_signal(float(pop.furry_ratio)*100)
		for i in range(_morph_labels.size()):
			var id: String = Population.MORPHOLOGIES[i]
			var ratio := 1.0-float(pop.semi_furry_ratio)-float(pop.furry_ratio) if id == "human" else float(pop[id+"_ratio"])
			_morph_labels[i].text = "%.1f%% · %d жителей" % [ratio*100,int(counts[id])]
	_summary.text = "%d жителей\n%d людей · %d полуфурри · %d фурри\n\n%d начальных очков" % [int(pop.count), counts.human, counts.semi_furry, counts.furry, Setup.point_budget(configuration)]
	var valid := Population.valid(pop) and Preferences.validate_values(configuration.custom)
	_status.text = "" if valid else "Проверьте диапазоны возраста и характеристик."
	if page == 1 and not Education.valid_plan(configuration.sandbox.education):
		valid = false
		_status.text = "Для студента выберите от 2 до 4 разных предметов."
	_next.disabled = not valid

func _go_back() -> void:
	if page == 0: cancelled.emit(); queue_free()
	else: page = 0; _show_page()

func _go_next() -> void:
	if page == 0: page = 1; _show_page(); return
	var result := Gameplay.begin_new_game(configuration)
	if result != OK: _status.text = "Не удалось начать игру. Проверьте настройки."

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()
