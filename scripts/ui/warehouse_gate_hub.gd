extends Control

signal menu_requested
signal gate_requested

@export var quest_id: StringName = &"warehouse_enter"
@export var objective_id: StringName = &"press_warehouse_gate"
@export var quest_title := "Войти на склад"
@export_multiline var quest_description := "Перед тобой заброшенный склад. Осмотри ворота и попробуй попасть внутрь."
@export var objective_text := "Нажать на ворота"

@onready var hub_ui = $HubUI
@onready var gate_hotspot: Button = $GateHotspot
@onready var background_shade: ColorRect = $BackgroundShade


func _ready() -> void:
	hub_ui.menu_requested.connect(menu_requested.emit)
	gate_hotspot.pressed.connect(gate_requested.emit)
	GameSession.game_time_changed.connect(_on_game_time_changed)
	hub_ui.set_quest_weaver_context(quest_id, quest_title, quest_description, objective_id, objective_text)
	_on_game_time_changed(GameSession.get_game_time_snapshot())
	hub_ui.open()


func _exit_tree() -> void:
	if GameSession.game_time_changed.is_connected(_on_game_time_changed):
		GameSession.game_time_changed.disconnect(_on_game_time_changed)


func set_objective_completed(completed: bool) -> void:
	hub_ui.set_objective_completed(completed)


func _on_game_time_changed(snapshot: Dictionary) -> void:
	var phase := str(snapshot.get("phase", "night"))
	match phase:
		"dawn":
			background_shade.color = Color(0.38, 0.28, 0.18, 0.18)
		"day":
			background_shade.color = Color(0.68, 0.76, 0.82, 0.08)
		"evening":
			background_shade.color = Color(0.42, 0.18, 0.08, 0.24)
		_:
			background_shade.color = Color(0.00784314, 0.0117647, 0.0196078, 0.34)

	var capabilities: Dictionary = snapshot.get("capabilities", {})
	gate_hotspot.disabled = not bool(capabilities.get("warehouse_gate", true))
