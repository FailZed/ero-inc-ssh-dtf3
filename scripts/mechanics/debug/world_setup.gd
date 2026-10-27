extends Control
signal setup_confirmed(configuration: Dictionary, simulation)
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const Portrait = preload("res://scripts/mechanics/debug/setup_portrait.gd")
const STAT_LABELS := {"strength":"Сила", "agility":"Ловкость", "charisma":"Харизма", "intellect":"Интеллект", "luck":"Удача", "endurance":"Выносливость", "erudition":"Эрудиция", "authority":"Авторитет", "cunning":"Хитрость"}
const DIFFICULTY_LABELS := {"easy":"Спокойная", "normal":"Обычная", "hard":"Сложная", "custom":"Своя настройка"}
const INK := Color("f2eff9")
const MUTED := Color("9c9eb4")
const ACCENT := Color("c7afff")
const MINT := Color("a8e6d5")
var config: Dictionary = Setup.defaults()
var preview_simulation
var _page := 0
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _stat_values: Dictionary = {}
var _stat_buttons: Dictionary = {}
var _stat_bars: Dictionary = {}
var _points: Label
var _portrait
var _name_caption: Label
var _summary: Label
var _status: Label
var _primary: Button
var _difficulty_cards: Dictionary = {}
var _difficulty_details: Label
var _population_description: Label
var _sample: Label
var _custom_controls: Control
var _npc_values: Dictionary = {}

func _ready() -> void:
	_build_theme()
	_build()
	_show_page(0)
	_refresh()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--setup-capture="): _capture_all(argument.trim_prefix("--setup-capture="))

func _style(background: Color, border: Color = Color("303247"), radius: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _build_theme() -> void:
	var skin := Theme.new()
	skin.default_font_size = 18
	skin.set_color("font_color", "Label", INK)
	skin.set_color("font_color", "Button", INK)
	skin.set_color("font_hover_color", "Button", INK)
	skin.set_color("font_pressed_color", "Button", Color("171526"))
	skin.set_color("font_disabled_color", "Button", Color("64677b"))
	skin.set_stylebox("normal", "Button", _style(Color("242637")))
	skin.set_stylebox("hover", "Button", _style(Color("343147"), ACCENT))
	skin.set_stylebox("pressed", "Button", _style(ACCENT, ACCENT))
	skin.set_stylebox("focus", "Button", _style(Color(0,0,0,0), MINT))
	skin.set_stylebox("disabled", "Button", _style(Color("1c1e2c")))
	for control in ["LineEdit", "SpinBox", "OptionButton"]:
		skin.set_color("font_color", control, INK)
		skin.set_stylebox("normal", control, _style(Color("11131f"), Color("393c52"), 10))
	skin.set_stylebox("grabber_area", "HSlider", _style(ACCENT, ACCENT, 3))
	skin.set_stylebox("grabber_area_highlight", "HSlider", _style(MINT, MINT, 3))
	theme = skin

func _label(text: String, font_size: int = 18, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _text(text: String, font_size: int = 17, color: Color = MUTED) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _vbox(parent: Node, separation: int = 14) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _hbox(parent: Node, separation: int = 16) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box

func _card(parent: Node, width: float = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("1b1d2c")))
	panel.custom_minimum_size.x = width
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	return _vbox(panel, 14)

func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 44
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("11131e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var root := _vbox(margin, 20)
	var header := _hbox(root)
	header.add_child(_label("ero / inc", 25, ACCENT))
	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(top_spacer)
	header.add_child(_label("НОВАЯ ИСТОРИЯ", 14, MUTED))
	root.add_child(_label("Настройте свою историю", 36))
	var navigation := _hbox(root, 12)
	var titles := ["01   Создание персонажа", "02   Случайные NPC", "03   Сложность"]
	for index in range(3):
		var tab := _button(navigation, titles[index], _show_page.bind(index))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.append(tab)
	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	for index in range(3):
		var scroll := ScrollContainer.new()
		scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(scroll)
		var page := HBoxContainer.new()
		page.add_theme_constant_override("separation", 22)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(page)
		_pages.append(scroll)
		if index == 0: _build_character(page)
		elif index == 1: _build_population(page)
		else: _build_difficulty(page)
	var footer := _hbox(root, 20)
	var footer_text := _vbox(footer, 4)
	footer_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = _label("", 16, MUTED)
	footer_text.add_child(_summary)
	_status = _label("Ваш новый мир можно сначала проверить отдельно.", 14, MUTED)
	footer_text.add_child(_status)
	_button(footer, "Назад", func(): _show_page(maxi(0, _page - 1)))
	_primary = _button(footer, "Далее  →", _next)
	_primary.custom_minimum_size.x = 250
	_primary.add_theme_stylebox_override("normal", _style(ACCENT, ACCENT, 12))
	_primary.add_theme_color_override("font_color", Color("171526"))

func _option(parent: Node, title: String, options: Dictionary, value: String, setter: Callable) -> OptionButton:
	parent.add_child(_label(title, 14, MUTED))
	var selector := OptionButton.new()
	selector.custom_minimum_size.y = 44
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in options:
		selector.add_item(str(options[id]))
		selector.set_item_metadata(selector.item_count - 1, id)
		if id == value: selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(index): setter.call(selector.get_item_metadata(index)); _refresh())
	parent.add_child(selector)
	return selector

func _build_character(page: Node) -> void:
	var preview := _card(page, 300)
	preview.size_flags_stretch_ratio = 0.85
	preview.add_child(_label("ВАШ ПЕРСОНАЖ", 13, MINT))
	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(270, 390)
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(_portrait)
	_name_caption = _label("Алекс Ривер", 25)
	preview.add_child(_name_caption)
	preview.add_child(_text("Внешность можно менять. Ваши решения определят всё остальное.", 16))
	var identity := _card(page, 310)
	identity.add_child(_label("01 / Личность", 23))
	identity.add_child(_label("Имя и фамилия", 14, MUTED))
	var name_input := LineEdit.new()
	name_input.text = config.profile.full_name
	name_input.max_length = 48
	name_input.custom_minimum_size.y = 46
	name_input.text_changed.connect(func(value): config.profile.full_name = value; _refresh())
	identity.add_child(name_input)
	identity.add_child(_label("Возраст", 14, MUTED))
	var age := SpinBox.new()
	age.min_value = 18
	age.max_value = 80
	age.value = config.profile.age
	age.value_changed.connect(func(value): config.profile.age = int(value); _refresh())
	identity.add_child(age)
	_option(identity, "Гендер", {"male":"Мужской", "female":"Женский", "nonbinary":"Небинарный"}, config.profile.appearance.gender, func(value): config.profile.appearance.gender = value)
	_option(identity, "Телосложение", {"slim":"Стройное", "athletic":"Атлетическое"}, "slim", func(value): config.profile.appearance.body_type = value)
	_option(identity, "Черты лица", {"soft":"Мягкие", "sharp":"Выразительные"}, "soft", func(value): config.profile.appearance.face_id = value)
	var hair := _hbox(identity, 12)
	var hair_style := _vbox(hair, 6)
	hair_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option(hair_style, "Причёска", {"short":"Короткая", "long":"Длинная"}, "short", func(value): config.profile.appearance.hair_style = value)
	var hair_color := _vbox(hair, 6)
	hair_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option(hair_color, "Цвет", {"dark":"Тёмный", "light":"Светлый"}, "dark", func(value): config.profile.appearance.hair_color = value)
	var attributes := _card(page, 370)
	attributes.size_flags_stretch_ratio = 1.2
	attributes.add_child(_label("02 / Характеристики", 23))
	_points = _label("", 17, MINT)
	attributes.add_child(_points)
	for key in Setup.STATS:
		var row := _hbox(attributes, 10)
		var title := _label(STAT_LABELS[key], 17)
		title.custom_minimum_size.x = 130
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var minus := _button(row, "−", _change_stat.bind(key, -1))
		minus.custom_minimum_size = Vector2(38, 34)
		var value := _label("", 20)
		value.custom_minimum_size.x = 28
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		var plus := _button(row, "+", _change_stat.bind(key, 1))
		plus.custom_minimum_size = Vector2(38, 34)
		_stat_values[key] = value
		_stat_buttons[key] = [minus, plus]
	attributes.add_child(_text("Характеристики влияют на действия, разговоры, работу и бой. Неиспользованные очки останутся у персонажа.", 15))
	_button(attributes, "Сбросить распределение", func():
		for key in Setup.STATS: config.profile.stats[key] = 5
		_refresh())

func _slider(parent: Node, label: String, key: String, low: float, high: float, step: float, target: Dictionary, suffix: String = "") -> void:
	var row := _hbox(parent)
	var title := _label(label, 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var value := _label("", 17, MINT)
	row.add_child(value)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(target.get(key, 1))
	slider.custom_minimum_size.y = 24
	parent.add_child(slider)
	var update := func(number):
		target[key] = int(number) if step >= 1 else snappedf(number, step)
		value.text = (str(int(number)) if step >= 1 else "%.2f" % number) + suffix
	update.call(slider.value)
	slider.value_changed.connect(func(number): update.call(number); _refresh())

func _build_population(page: Node) -> void:
	var population := _card(page, 360)
	population.add_child(_label("Население города", 25))
	population.add_child(_text("Задайте диапазоны. У каждого жителя будут собственные характеристики, привычки, расписание и отношения."))
	_slider(population, "Количество жителей", "count", 8, 120, 1, config.population)
	_slider(population, "Доля женщин", "female_ratio", 0, 1, 0.05, config.population)
	_slider(population, "Доля полуфурри", "semi_furry_ratio", 0, 1, 0.05, config.population)
	_slider(population, "Доля фурри", "furry_ratio", 0, 1, 0.05, config.population)
	population.add_child(_text("Остальные жители — люди. Сумма долей полуфурри и фурри не должна превышать 100%."))
	_slider(population, "Минимальный возраст", "age_min", 18, 60, 1, config.population)
	_slider(population, "Максимальный возраст", "age_max", 18, 80, 1, config.population)
	_slider(population, "Минимум характеристик", "stat_min", 1, 25, 1, config.population)
	_slider(population, "Максимум характеристик", "stat_max", 1, 30, 1, config.population)
	_option(population, "Основной ритм жизни", {"mixed":"Разнообразный", "work":"Работа", "study":"Обучение"}, "mixed", func(value): config.population.activity_mode = value)
	var traits := _card(page, 350)
	traits.add_child(_label("Характер жителей", 25))
	traits.add_child(_text("Это средние значения. Разброс сохранит индивидуальность каждого NPC."))
	for pair in [["sociability","Общительность"],["bravery","Смелость"],["responsibility","Ответственность"],["loyalty","Верность"],["cunning","Хитрость"],["romantic","Романтичность"]]:
		_slider(traits, pair[1], pair[0], 0, 100, 1, config.population)
	_slider(traits, "Разброс характеров", "trait_spread", 0, 50, 1, config.population)
	var sample := _card(page, 330)
	sample.add_child(_label("Будущие знакомства", 24, MINT))
	_population_description = _text("", 18)
	sample.add_child(_population_description)
	sample.add_child(HSeparator.new())
	_sample = _text("Нажмите «Пример жителей», чтобы увидеть, как эти настройки влияют на людей вашего мира.", 18, INK)
	sample.add_child(_sample)
	_button(sample, "Пример жителей  ↻", _sample_population)
	sample.add_child(_label("Воспроизводимый мир", 17, ACCENT))
	var seed_input := SpinBox.new()
	seed_input.min_value = 0
	seed_input.max_value = 2147483647
	seed_input.value = config.seed
	seed_input.value_changed.connect(func(value): config.seed = int(value); _refresh())
	sample.add_child(seed_input)
	sample.add_child(_text("Одинаковое число и настройки создают одинаковых жителей.", 15))

func _build_difficulty(page: Node) -> void:
	var presets := _card(page, 320)
	presets.add_child(_label("Ваш темп игры", 25))
	var descriptions := {"easy":"Больше свободы для знакомства с миром.", "normal":"Баланс возможностей и последствий.", "hard":"Ресурсы, риск и долгосрочные решения.", "custom":"Выберите правила под себя."}
	for id in DIFFICULTY_LABELS:
		var button := _button(presets, DIFFICULTY_LABELS[id] + "\n" + descriptions[id], _select_difficulty.bind(id))
		button.custom_minimum_size.y = 84
		button.add_theme_font_size_override("font_size", 17)
		_difficulty_cards[id] = button
	var details := _card(page, 330)
	details.add_child(_label("Правила прохождения", 25))
	_difficulty_details = _text("", 20, INK)
	details.add_child(_difficulty_details)
	details.add_child(HSeparator.new())
	details.add_child(_text("Сложность влияет на стартовые очки, потребности, отношения и последствия ошибок. Изменения видны до создания мира.", 17))
	var custom := _card(page, 350)
	custom.add_child(_label("Точная настройка", 25))
	_custom_controls = _vbox(custom, 12)
	var base := {"xp":1.0, "need_decay":1.0, "relation_gain":1.0, "injury_damage":0.5}
	for key in base:
		if not config.custom.has(key): config.custom[key] = base[key]
	_slider(_custom_controls, "Получение опыта", "xp", 0.5, 2, 0.1, config.custom, " ×")
	_slider(_custom_controls, "Расход потребностей", "need_decay", 0.25, 2, 0.05, config.custom, " ×")
	_slider(_custom_controls, "Развитие отношений", "relation_gain", 0.5, 2, 0.1, config.custom, " ×")
	_slider(_custom_controls, "Тяжесть травм", "injury_damage", 0, 2, 0.1, config.custom, " ×")
	for pair in [["satiety_enabled","Следить за сытостью"],["rent_enabled","Платить за аренду"],["education_failure","Последствия пропусков"],["exhaustion_enabled","Обморок от истощения"],["starvation_attrition","Потеря формы от голода"],["eviction_enabled","Выселение за долги"]]:
		var toggle := CheckButton.new()
		toggle.text = pair[1]
		toggle.button_pressed = bool(config.custom.get(pair[0], pair[0] in ["satiety_enabled", "rent_enabled", "education_failure"]))
		config.custom[pair[0]] = toggle.button_pressed
		toggle.toggled.connect(func(enabled): config.custom[pair[0]] = enabled; _refresh())
		_custom_controls.add_child(toggle)

func _show_page(index: int) -> void:
	_page = clampi(index, 0, 2)
	for i in range(_pages.size()):
		_pages[i].visible = i == _page
		_tabs[i].add_theme_stylebox_override("normal", _style(Color("343047") if i == _page else Color("1b1d2b"), ACCENT if i == _page else Color("303247"), 12))
	if _primary != null: _primary.text = "Создать пробный мир  →" if _page == 2 else "Далее  →"

func _change_stat(key: String, delta: int) -> void:
	var next := int(config.profile.stats[key]) + delta
	if next < 5 or next > 30 or delta > 0 and Setup.remaining_points(config) <= 0: return
	config.profile.stats[key] = next
	_refresh()

func _select_difficulty(id: String) -> void:
	config.difficulty = id
	_refresh()

func _refresh() -> void:
	if _points == null: return
	var remaining := Setup.remaining_points(config)
	_points.text = "Доступно %d из %d стартовых очков" % [remaining, Setup.point_budget(config)]
	_points.add_theme_color_override("font_color", MINT if remaining >= 0 else Color("ffadad"))
	for key in _stat_values:
		_stat_values[key].text = str(config.profile.stats[key])
		_stat_buttons[key][0].disabled = int(config.profile.stats[key]) <= 5
		_stat_buttons[key][1].disabled = remaining <= 0 or int(config.profile.stats[key]) >= 30
	_portrait.set_appearance(config.profile.appearance)
	_name_caption.text = str(config.profile.full_name).strip_edges()
	_summary.text = "%s  ·  %d жителей  ·  %s" % [config.profile.full_name, config.population.count, DIFFICULTY_LABELS[config.difficulty]]
	_population_description.text = "%d взрослых жителей\nВозраст: %d–%d лет\nЖенщины: %d%% · Мужчины: %d%%\nХарактеристики: %d–%d" % [config.population.count, config.population.age_min, config.population.age_max, roundi(float(config.population.female_ratio) * 100), 100 - roundi(float(config.population.female_ratio) * 100), config.population.stat_min, config.population.stat_max]
	for id in _difficulty_cards:
		_difficulty_cards[id].add_theme_stylebox_override("normal", _style(Color("343047") if id == config.difficulty else Color("242637"), ACCENT if id == config.difficulty else Color("303247")))
	var presets := {"easy":[1.1,0.75,0.0,false,false,false], "normal":[1.0,1.0,0.5,true,true,false], "hard":[0.9,1.25,1.0,true,true,true], "custom":[config.custom.get("xp",1.0),config.custom.get("need_decay",1.0),config.custom.get("injury_damage",0.5),config.custom.get("satiety_enabled",true),config.custom.get("rent_enabled",true),config.custom.get("exhaustion_enabled",false)]}
	var rules: Array = presets[config.difficulty]
	_difficulty_details.text = "%d стартовых очков\n\nОпыт                         %.2f ×\nПотребности             %.2f ×\nТравмы                       %.2f ×\n\nСытость: %s\nАренда: %s\nИстощение: %s" % [Setup.point_budget(config),rules[0],rules[1],rules[2],"включена" if rules[3] else "отключена","включена" if rules[4] else "отключена","обморок и восстановление" if rules[5] else "без обмороков"]
	_custom_controls.modulate.a = 1.0 if config.difficulty == "custom" else 0.6
	for child in _custom_controls.get_children():
		if child is Range: child.editable = config.difficulty == "custom"
		if child is BaseButton: child.disabled = config.difficulty != "custom"
	var valid := Setup.validate(config)
	_primary.disabled = not valid.ok
	_status.text = "Можно перераспределить очки или создать мир с оставшимся запасом." if valid.ok else "Проверьте имя, диапазоны NPC и бюджет характеристик."

func _sample_population() -> void:
	var result := Setup.build(config)
	if not result.ok:
		_status.text = "Невозможно построить пример: " + str(result.error)
		return
	var lines: Array[String] = []
	for npc in result.data.simulation.state.social.npcs.values():
		var morphology: String = {"human": "Человек", "semi_furry": "Полуфурри", "furry": "Фурри"}.get(npc.appearance.get("morphology", "human"), "Человек")
		lines.append("%s · %d лет · %s\n%s\nОбщительность %d · Верность %d" % [npc.name, npc.age, morphology, "Работает" if npc.biography.role == "worker" else "Учится", npc.traits.sociability, npc.traits.loyalty])
		if lines.size() >= 4: break
	_sample.text = "\n\n".join(lines)

func _next() -> void:
	if _page < 2: _show_page(_page + 1); return
	var result := Setup.build(config)
	if not result.ok:
		_status.text = "Создание не выполнено: " + str(result.error)
		return
	preview_simulation = result.data.simulation
	setup_confirmed.emit(config.duplicate(true), preview_simulation)
	_status.text = "Пробный мир создан: %d жителей. Профиль и правила применены." % preview_simulation.state.social.npcs.size()

func _capture_all(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	for index in range(3):
		_show_page(index)
		if index == 1: _sample_population()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var error := get_viewport().get_texture().get_image().save_png(directory.path_join(["character", "npcs", "difficulty"][index] + ".png"))
		print("SETUP_CAPTURE ", index, " ", error_string(error))
	_select_difficulty("custom")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var custom_error := get_viewport().get_texture().get_image().save_png(directory.path_join("difficulty-custom.png"))
	print("SETUP_CAPTURE custom ", error_string(custom_error))
	_next()
	print("SETUP_CREATED ", preview_simulation.state.social.npcs.size() if preview_simulation != null else -1)
	get_tree().quit(0 if preview_simulation != null else 1)
