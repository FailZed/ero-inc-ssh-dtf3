extends Control

const Simulation = preload("res://scripts/mechanics/simulation.gd")
var _sim
var _summary: RichTextLabel
var _details: CodeEdit
var _log: RichTextLabel
var _module: OptionButton
var _operation: LineEdit
var _arguments: LineEdit

func _ready() -> void:
	_sim = Simulation.new(42, {"settings": {"start_minutes": 480}})
	_build_ui()
	_seed_session()
	_refresh()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			_capture(argument.trim_prefix("--capture="))

func _capture(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("LAB_CAPTURE ", error_string(error))
	get_tree().quit(0 if error == OK else 1)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("151b27")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var title := Label.new()
	title.text = "Лаборатория механик EroInc"
	title.add_theme_font_size_override("font_size", 28)
	layout.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Отдельная тестовая сессия • Основная игра и её слоты сохранения не используются"
	subtitle.add_theme_color_override("font_color", Color("a4b7cc"))
	layout.add_child(subtitle)
	_summary = RichTextLabel.new()
	_summary.custom_minimum_size.y = 70
	_summary.bbcode_enabled = true
	layout.add_child(_summary)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	layout.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 290
	row.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 6)
	scroll.add_child(controls)
	var commands := [
		["Время +15 минут", "clock", "advance", {"minutes": 15}],
		["Отдых 2 часа", "character", "rest", {"minutes": 120}],
		["Тренировка", "actions", "perform", {"id": "exercise"}],
		["Получить 150 опыта", "character", "gain_xp", {"amount": 150}],
		["Повысить силу", "character", "allocate", {"stat": "strength"}],
		["Эффект концентрации", "character", "effect", {"id": "focused"}],
		["Съесть порцию еды", "inventory", "use", {"id": "meal"}],
		["Приготовить блюдо", "inventory", "craft", {"id": "vegetable_meal"}],
		["Надеть куртку", "inventory", "equip", {"id": "jacket"}],
		["В коридор", "world", "travel", {"id": "apartment_hall"}],
		["На карту", "world", "travel", {"id": "global_map"}],
		["Вернуться в спальню", "world", "travel", {"id": "bedroom"}],
		["Купить книгу на рынке", "inventory", "buy", {"id": "book", "shop": "market"}],
		["Выполнить подработку", "economy", "work", {"id": "freelance"}],
		["Стрим 30 минут", "economy", "stream", {"minutes": 30}],
		["Купить студию", "economy", "buy_asset", {"id": "studio"}],
		["Арендовать квартиру", "housing", "rent", {"id": "apartment"}],
		["Заселиться", "housing", "move_in", {"id": "apartment"}],
		["Сложность: обычная", "preferences", "difficulty", {"id": "normal"}],
		["Сложность: высокая", "preferences", "difficulty", {"id": "hard"}],
		["Говорить с коллегой", "social", "interact", {"id": "colleague"}],
		["Подарить книгу коллеге", "social", "gift", {"id": "colleague", "item": "book"}],
		["Написать сообщение", "social", "message", {"id": "colleague", "text": "Привет!"}],
		["Начать задание", "events", "start_quest", {"id": "first_steps"}],
		["Продвинуть задание", "events", "progress", {"id": "first_steps", "objective": "practice"}],
		["Получить награду", "events", "claim_quest", {"id": "first_steps"}],
		["Разыграть событие вечера", "events", "fire", {"id": "first_evening"}],
		["Блэкджек: ставка 10", "encounters", "game_start", {"type": "blackjack", "stake": 10}],
		["Карты: взять", "encounters", "game_input", {"action": "hit"}],
		["Карты: остановиться", "encounters", "game_input", {"action": "stand"}],
		["Начать спарринг", "encounters", "combat_start", {"npc": "colleague"}],
		["Атака в корпус", "encounters", "combat_action", {"action": "attack", "part": "body"}],
		["Защититься", "encounters", "combat_action", {"action": "guard"}],
		["Закончить ход", "encounters", "combat_action", {"action": "end_turn"}],
		["Создать коллектив", "organizations", "create", {"id": "creative_collective"}],
		["Принять коллегу", "organizations", "recruit", {"id": "creative_collective", "npc": "colleague"}],
		["Начать выставку", "organizations", "project", {"id": "creative_collective", "project": "exhibition"}],
		["Назначить на выставку", "organizations", "assign", {"id": "creative_collective", "npc": "colleague", "task": "exhibition"}],
	]
	for entry in commands:
		var button := Button.new()
		button.text = str(entry[0])
		button.custom_minimum_size.y = 36
		button.pressed.connect(_execute.bind(str(entry[1]), str(entry[2]), entry[3]))
		controls.add_child(button)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_details = CodeEdit.new()
	_details.editable = false
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.add_theme_font_size_override("font_size", 14)
	right.add_child(_details)
	_log = RichTextLabel.new()
	_log.custom_minimum_size.y = 140
	_log.scroll_following = true
	right.add_child(_log)
	var custom := HBoxContainer.new()
	layout.add_child(custom)
	_module = OptionButton.new()
	for id in ["clock"] + _sim.services.keys(): _module.add_item(str(id))
	custom.add_child(_module)
	_operation = LineEdit.new()
	_operation.text = "advance"
	_operation.placeholder_text = "operation"
	_operation.custom_minimum_size.x = 180
	custom.add_child(_operation)
	_arguments = LineEdit.new()
	_arguments.text = '{"minutes":15}'
	_arguments.placeholder_text = "Аргументы JSON"
	_arguments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom.add_child(_arguments)
	var run := Button.new()
	run.text = "Выполнить"
	run.pressed.connect(_run_custom)
	custom.add_child(run)

func _seed_session() -> void:
	for id in ["meal", "grain", "vegetable", "book", "jacket", "stove", "computer"]:
		_sim.command("inventory", "add", {"id": id, "quantity": 2 if id in ["grain", "vegetable", "meal"] else 1})
	_sim.command("world", "install", {"id": "stove"})
	_sim.command("world", "install", {"id": "computer"})
	_sim.command("social", "generate", {"id": "colleague", "name": "Коллега"})
	_sim.command("social", "contact", {"id": "colleague"})

func _execute(module_id: String, operation: String, args: Dictionary) -> void:
	var result: Dictionary = _sim.command(module_id, operation, args)
	_log.append_text("%s.%s → %s\n" % [module_id, operation, "OK " + JSON.stringify(result.get("data", {})) if result.ok else str(result.error)])
	_refresh()

func _run_custom() -> void:
	var args: Variant = JSON.parse_string(_arguments.text)
	if not args is Dictionary:
		_log.append_text("Аргументы должны быть JSON-объектом.\n")
		return
	_execute(_module.get_item_text(_module.selected), _operation.text.strip_edges(), args)

func _refresh() -> void:
	var state: Dictionary = _sim.state
	_summary.text = "[b]%s %s[/b] • %s • Деньги: %d • Банк: %d • Уровень: %d\nЭнергия: %.1f   Сытость: %.1f   Здоровье: %.1f   Гигиена: %.1f   Настроение: %.1f" % [
		state.clock.date_text, state.clock.time_text, state.world.location, state.economy.cash, state.economy.bank,
		state.player.level, state.player.needs.energy, state.player.needs.satiety, state.player.needs.health,
		state.player.needs.hygiene, state.player.needs.mood]
	_details.text = JSON.stringify(state, "  ")
