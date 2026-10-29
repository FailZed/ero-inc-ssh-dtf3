extends Control
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const GameFrame = preload("res://scripts/ui/gameplay/game_window.gd")
const Art = preload("res://scripts/ui/gameplay/item_art.gd")
const CATEGORIES := {"all":"Все направления","mind":"Умственные","technical":"Технические","body":"Физические","creative":"Творческие","social":"Социальные","craft":"Прикладные"}
var page := "skills"
var category := "all"
var _body: VBoxContainer
var _status: Label
var _queued := false
var _window: Control
var _skill_selected := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.skin()
	_window = GameFrame.new()
	_window.title = "Навыки и привычки"
	_window.subtitle = "Выберите, чему посвятить свободное время"
	_window.back_requested.connect(queue_free)
	add_child(_window)
	_status = _window.status
	_body = _window.body
	Gameplay.changed.connect(_queue_refresh)
	_refresh()

func _queue_refresh() -> void:
	if _queued: return
	_queued = true
	call_deferred("_refresh")

func _refresh() -> void:
	_queued = false
	if not is_inside_tree(): return
	_window.begin_update()
	_window.set_tabs({"skills":"Практика","needs":"Потребности","habits":"Привычки"},page,func(id): page = id; _refresh())
	match page:
		"skills": _skills()
		"needs": _needs()
		"habits": _habits()
	_window.end_update()

func _skills() -> void:
	var sim = Gameplay.simulation
	UI.label(_body,"Занимайтесь регулярно: опыт в выбранном деле поможет в связанных испытаниях.",18,UI.MUTED)
	var filter := OptionButton.new()
	for title in CATEGORIES.values(): filter.add_item(title)
	filter.select(CATEGORIES.keys().find(category))
	filter.item_selected.connect(func(index): category = CATEGORIES.keys()[index]; _refresh())
	_body.add_child(filter)
	var columns := UI.row(_body,30)
	var index := UI.scroller(columns)
	index.get_parent().custom_minimum_size = Vector2(350,470)
	index.get_parent().size_flags_horizontal = Control.SIZE_FILL
	var detail := UI.column(columns,18)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids: Array = sim.catalog.skills.keys().filter(func(id): return category == "all" or category == sim.catalog.skills[id].category)
	if ids.is_empty(): W.empty(detail,"journal","В этом направлении пока нет занятий"); return
	if not _skill_selected in ids: _skill_selected = str(ids[0]) if not ids.is_empty() else ""
	for id in ids:
		var entry := UI.button(index,str(sim.catalog.skills[id].label),func(): _skill_selected = id; _refresh())
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.set_meta("focus_id",id)
		if id == _skill_selected: entry.modulate = UI.BLUE
	for id in sim.catalog.skills:
		var spec: Dictionary = sim.catalog.skills[id]
		if id != _skill_selected: continue
		var card := detail
		W.illustration(card,Art.texture("computer" if spec.category == "technical" else "book"),140)
		var level: int = sim.services.growth.level(id)
		var score := int(sim.state.player.skills.get(id,0))
		UI.label(card,spec.label,25,UI.BLUE)
		W.meter(card,"Уровень %d / 10" % level,score,"journal",maxi(score,10*(level+1)*(level+1)))
		UI.label(card,spec.practice,20)
		UI.label(card,"%d мин · силы −%d · %d €$ · +%d практики" % [spec.minutes,ceili(float(spec.energy)*sim.multiplier("resource_cost")),spec.cost,spec.xp],17,UI.MUTED)
		var reason: String = sim.services.growth.practice_blocked(id)
		if not reason.is_empty(): UI.label(card,Names.error(reason),17,UI.MUTED)
		var start := W.primary(card,"Практиковать · %d мин" % spec.minutes,_act.bind("practice",{"id":id}))
		start.set_meta("practice_id",id)
		start.disabled = not reason.is_empty()
		if reason == "practice_location": UI.button(card,"К МЕСТУ ПРАКТИКИ",_travel.bind(str(spec.locations[0])))

func _needs() -> void:
	var sim = Gameplay.simulation
	UI.label(_body,"Выберите, за какими потребностями хотите следить. Здоровье и силы всегда остаются активными.",21,UI.MUTED)
	for id in sim.services.growth.NEED_IDS:
		var toggle := CheckBox.new()
		toggle.text = str(sim.catalog.growth_rules.habits[id].label)
		toggle.button_pressed = sim.services.growth.enabled(id)
		toggle.set_meta("need_id",id)
		toggle.toggled.connect(func(value): _act("need_toggle",{"id":id,"enabled":value}))
		_body.add_child(toggle)
	UI.label(_body,"На автоматических работах герой делает перерывы на воду, еду и туалет, поддерживает общение. Такие смены всё равно утомляют: сон и восстановление сил нужно планировать отдельно.",20,UI.MUTED)

func _habits() -> void:
	var sim = Gameplay.simulation
	UI.label(_body,"Очков развития: %d. Привычки снижают расход потребностей на 12%% за ступень и ослабляют их штрафы на 15%%. Три ступени: требуется практика 10 / 50 / 150 в связанном навыке; стоимость 1 / 2 / 3 очка." % int(sim.state.player.points),20,UI.MUTED)
	var grid := W.grid(_body,2)
	for id in sim.catalog.growth_rules.habits:
		var spec: Dictionary = sim.catalog.growth_rules.habits[id]
		var rank := int(sim.state.growth.habits.get(id,0))
		var card := W.panel(grid)
		UI.label(card,"%s · %d / 3" % [spec.label,rank],25,UI.BLUE)
		var skills: Array[String] = []
		for skill in spec.skills: skills.append(Names.title(skill))
		UI.label(card,"Связанные навыки: "+", ".join(skills),18,UI.MUTED)
		UI.label(card,"Расход −%d%% · влияние на самочувствие −%d%%" % [rank*12,rank*15],20)
		if rank < 3:
			var reason: String = sim.services.growth.habit_blocked(id)
			var buy := UI.button(card,"РАЗВИТЬ · %d ОЧК." % (rank+1),_act.bind("habit",{"id":id}))
			buy.set_meta("habit_id",id)
			buy.disabled = not reason.is_empty()
			if not reason.is_empty(): UI.label(card,Names.error(reason),18,UI.MUTED)

func _act(operation: String, args: Dictionary) -> void:
	var result: Dictionary = Gameplay.execute("growth",operation,args)
	_status.text = "Готово" if result.ok else Names.error(str(result.error))
	_window.notice(_status.text)
	if not result.ok: _queue_refresh()

func _travel(id: String) -> void:
	var result: Dictionary = Gameplay.execute("world","journey",{"id":id})
	_status.text = "" if result.ok else Names.error(str(result.error))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): get_viewport().set_input_as_handled(); queue_free()
