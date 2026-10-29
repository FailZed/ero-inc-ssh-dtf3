extends Control
signal menu_requested
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Guide = preload("res://scripts/gameplay/guided_story.gd")
var _background: TextureRect
var _quest_title: Label
var _objective: Label
var _place_title: Label
var _objects: VBoxContainer
var _exits: VBoxContainer
var _thought: Label
var _hint: Label
var _hint_timer: Timer
var _journal: PanelContainer
var _journal_body: VBoxContainer
func _ready() -> void:
	theme = UI.skin()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.background(self,"res://assets/textures/backgrounds/location_pack_v1/bedroom_night.png",0.1)
	_background = get_child(0)
	var root := UI.column(UI.inset(self,40),16)
	var header := UI.row(root,40)
	_place_title = UI.label(header,"",30)
	var quest := UI.card(header)
	quest.custom_minimum_size.x = 500
	quest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_title = UI.label(quest,"",24,UI.BLUE)
	_objective = UI.label(quest,"",21)
	_hint = UI.label(quest,"",18,UI.ORANGE)
	var middle := UI.row(root,30)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var filler := Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(filler)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",UI.surface(20))
	panel.custom_minimum_size.x = 450
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(panel)
	_objects = UI.scroller(panel)
	_journal = PanelContainer.new()
	_journal.add_theme_stylebox_override("panel",UI.surface(22))
	_journal.custom_minimum_size.x = 500
	_journal.visible = false
	middle.add_child(_journal)
	_journal_body = UI.scroller(_journal)
	var bottom := UI.card(root)
	_thought = UI.label(bottom,"",22)
	_exits = UI.column(bottom,10)
	var navigation := UI.row(bottom)
	UI.button(navigation,"МЕНЮ",menu_requested.emit)
	UI.button(navigation,"ЖУРНАЛ ЗАДАЧ",_toggle_journal)
	UI.button(navigation,"НАПОМНИТЬ ЦЕЛЬ",_show_hint)
	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.wait_time = 45
	_hint_timer.timeout.connect(_show_hint)
	add_child(_hint_timer)
	Gameplay.guide_changed.connect(refresh)
	refresh()

func refresh() -> void:
	var id := str(Gameplay.story_flags.get("guide_stage",""))
	if not Guide.STAGES.has(id): hide(); return
	show()
	var stage: Dictionary = Guide.STAGES[id]
	var place_id := str(Gameplay.story_flags.get("guide_location",stage.start))
	var place: Dictionary = Guide.PLACES[place_id]
	_background.texture = load(Guide.background(place_id, int(Gameplay.simulation.state.clock.minute_of_day)))
	_place_title.text = place.title
	_quest_title.text = "ТЕКУЩАЯ ЗАДАЧА · " + str(stage.title)
	_objective.text = stage.objective
	_hint.text = ""
	_thought.text = "Можно осмотреться. Отмеченное действие продолжит историю."
	UI.clear(_objects)
	UI.label(_objects,"Осмотреться",24,UI.BLUE)
	for object_id in place.objects:
		var goal: bool = place_id == stage.goal_place and object_id == stage.goal
		var button := UI.button(_objects,("◆  " if goal else "") + str(stage.action if goal else place.objects[object_id]),_inspect.bind(object_id))
		if goal:
			button.add_theme_color_override("font_color",UI.ORANGE)
			button.grab_focus()
	var crowd: Array = Gameplay.story_crowd(place_id)
	if not crowd.is_empty():
		UI.label(_objects,"Студенты рядом" if place_id.begins_with("campus") else "Прохожие",24,UI.BLUE)
		for npc_id in crowd:
			var npc: Dictionary = Gameplay.simulation.state.social.npcs[npc_id]
			UI.button(_objects,str(npc.name),_open_resident.bind(npc_id))
	UI.clear(_exits)
	var exits := UI.row(_exits)
	for destination in place.exits:
		var button := UI.button(exits,"→ " + str(Guide.PLACES[destination].title),_travel.bind(destination))
		if not destination in stage.allowed:
			button.text += " · позже"
			button.disabled = true
			button.tooltip_text = "Сначала завершите текущую задачу."
	_hint_timer.start()
	if _journal.visible: _refresh_journal()

func _inspect(id: String) -> void:
	var result := Gameplay.inspect_story_object(id)
	if result.get("text","") != "": _thought.text = result.text
	_hint_timer.start()

func _travel(id: String) -> void:
	Gameplay.guided_travel(id)

func _show_hint() -> void:
	var stage: Dictionary = Guide.STAGES.get(str(Gameplay.story_flags.get("guide_stage","")),{})
	_hint.text = str(stage.get("hint",""))

func _toggle_journal() -> void:
	_journal.visible = not _journal.visible
	if _journal.visible: _refresh_journal()

func _open_resident(id: String) -> void:
	var conversation := preload("res://scripts/ui/gameplay/conversation_window.gd").new()
	conversation.configure(id,"story",Guide.background(str(Gameplay.story_flags.guide_location), int(Gameplay.simulation.state.clock.minute_of_day)))
	conversation.menu_requested.connect(menu_requested.emit)
	add_child(conversation)

func _refresh_journal() -> void:
	UI.clear(_journal_body)
	UI.label(_journal_body,"Первый день",30)
	var stage: Dictionary = Guide.STAGES[Gameplay.story_flags.guide_stage]
	UI.label(_journal_body,stage.objective,24,UI.BLUE)
	for entry in Gameplay.story_flags.get("completed_tasks",[]):
		UI.label(_journal_body,"✓  " + str(entry),20,UI.MUTED)
	UI.label(_journal_body,"Осмотренные предметы: %d" % Gameplay.story_flags.get("inspected",{}).size(),20,UI.MUTED)

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if _journal.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_journal.hide()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		get_viewport().set_input_as_handled()
		_toggle_journal()
