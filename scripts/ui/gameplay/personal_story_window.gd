extends Control
signal closed
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Portrait = preload("res://scripts/ui/gameplay/resident_preview.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const GameFrame = preload("res://scripts/ui/gameplay/game_window.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
var npc_id := ""
var _body: VBoxContainer
var _portrait: Control
var _queued := false
var _window: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.skin()
	_window = GameFrame.new()
	_window.title = "Личная история"
	_window.subtitle = "Важные разговоры и совместные дела"
	_window.back_requested.connect(func(): closed.emit(); queue_free())
	add_child(_window)
	var root := UI.row(_window.body,36)
	var side := UI.column(root,12)
	side.custom_minimum_size.x = 300
	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(300,420)
	side.add_child(_portrait)
	_body = UI.column(root,20)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Gameplay.changed.connect(_queue_refresh)
	_refresh()

func _queue_refresh() -> void:
	if _queued: return
	_queued = true
	call_deferred("_refresh")

func _refresh() -> void:
	_queued = false
	if not is_inside_tree(): return
	UI.clear(_body)
	var npc: Dictionary = Gameplay.simulation.state.social.npcs.get(npc_id,{})
	if npc.is_empty(): return
	_portrait.set_actor(npc)
	var view: Dictionary = Gameplay.simulation.services.npc_stories.present(npc_id)
	UI.label(_body,str(npc.name),32,UI.BLUE)
	UI.label(_body,str(view.title),26)
	UI.label(_body,str(view.text),23)
	if not str(view.instruction).is_empty(): UI.label(_body,str(view.instruction),20,UI.ORANGE)
	if int(view.required) > 1: UI.label(_body,"Выполнено: %d / %d" % [int(view.goal.get("count",0)),int(view.required)],19,UI.BLUE)
	var blocked := str(view.blocked)
	if not blocked.is_empty(): UI.label(_body,Names.error(blocked),19,UI.MUTED)
	if view.status == "available":
		var start := UI.button(_body,"ПОГОВОРИТЬ ОБ ЭТОМ",func(): Gameplay.execute("npc_stories","start",{"id":npc_id}))
		start.disabled = not blocked.is_empty()
	elif view.status == "active":
		for choice in view.choices:
			var costs: Array[String] = ["%d мин" % int(choice.get("minutes",5))]
			if float(choice.get("energy",0)) > 0: costs.append("силы −%d" % int(choice.energy))
			if int(choice.get("cost",0)) > 0: costs.append("%d ¤" % int(choice.cost))
			var caption := str(choice.text) + "\n" + " · ".join(costs)
			var button := UI.button(_body,caption,func(): Gameplay.execute("npc_stories","choose",{"id":npc_id,"node":view.node,"choice":choice.id}))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.disabled = not blocked.is_empty()
	else: UI.label(_body,"Эта история завершена. Обычная жизнь и общение продолжаются.",19,UI.MUTED)
	_window.end_update()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()
