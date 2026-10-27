extends Node2D

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/mainMenu/main_menu.tscn")

var _pause_menu_layer: CanvasLayer
var _pause_menu
var _hub_ui


func _ready() -> void:
	_hub_ui = get_node_or_null("Hud/HubUI")
	if _hub_ui != null and _hub_ui.has_signal("menu_requested"):
		_hub_ui.menu_requested.connect(open_pause_menu)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		open_pause_menu()


func open_pause_menu() -> void:
	_ensure_pause_menu()
	if _pause_menu == null or _pause_menu.visible:
		return

	if _hub_ui != null:
		_hub_ui.hide()
	_pause_menu.show_overview()
	_pause_menu.show()
	get_tree().paused = true


func close_pause_menu() -> void:
	if _pause_menu == null or not is_instance_valid(_pause_menu):
		return

	_pause_menu.hide()
	get_tree().paused = false
	if _hub_ui != null:
		_hub_ui.open()
	GameSession.resume_autosave_runtime()


func begin_return_to_main_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.hide()
	get_tree().paused = false
	GameSession.pause_autosave_runtime()


func _ensure_pause_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return

	_pause_menu_layer = CanvasLayer.new()
	_pause_menu_layer.layer = 100
	_pause_menu_layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_pause_menu_layer)

	_pause_menu = MAIN_MENU_SCENE.instantiate()
	_pause_menu.menu_context = _pause_menu.MenuContext.IN_GAME
	_pause_menu.visible = false
	_pause_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu_layer.add_child(_pause_menu)
