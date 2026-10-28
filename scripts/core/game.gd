extends Node2D

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/mainMenu/main_menu.tscn")
const CHARACTER_CREATION_MODAL_SCENE: PackedScene = preload("res://scenes/ui/CharacterCreationModal.tscn")
const WAREHOUSE_GATE_HUB_SCENE: PackedScene = preload("res://scenes/hub/WarehouseGateHub.tscn")
const TOGGLE_MENU_ACTION := "ui_cancel"
const CHARACTER_CREATION_SIGNAL := "open_character_creator"
const WAREHOUSE_GATE_HUB_SIGNAL := "open_warehouse_gate_hub"
const APARTMENT_LOCATIONS_SIGNAL := "open_apartment_locations"
const WAREHOUSE_PROLOG_TIMELINE := "prolog/prolog"
const WAREHOUSE_ENTER_QUEST_ID := &"warehouse_enter"
const WAREHOUSE_ENTER_OBJECTIVE_ID := &"press_warehouse_gate"
const GAMEPLAY_SHELL = preload("res://scripts/ui/gameplay/gameplay_shell.gd")
const GUIDED_EXPLORATION = preload("res://scripts/ui/gameplay/guided_exploration.gd")

var _pause_menu_layer: CanvasLayer
var _pause_menu
var _character_creation_layer: CanvasLayer
var _character_creation_modal
var _hub_layer: CanvasLayer
var _hub_scene
var _dialogic_layout_was_visible := true
var _hub_was_visible_before_pause := false
var _gameplay_shell: Control
var _guided_exploration: Control
var _curriculum_window: Control

func _ready() -> void:
	Dialogic.paused = false
	Dialogic.signal_event.connect(_on_dialogic_signal)
	_ensure_pause_menu()
	_ensure_character_creation_modal()
	_ensure_gameplay_shell()
	Gameplay.phase_changed.connect(_on_gameplay_phase_changed)
	Gameplay.guide_changed.connect(_on_guide_changed)
	Gameplay.story_requested.connect(_resume_story)
	GameSession.resume_autosave_runtime()
	if GameSession.has_pending_load():
		var load_error := GameSession.apply_pending_load()
		if load_error != OK:
			push_warning("Game: failed to apply pending load: %s" % error_string(load_error))
			# Failed loads return to the menu with a readable error; never restart the story.
			return
	else:
		if not Gameplay.is_sandbox(): Dialogic.start(GameSession.DEFAULT_TIMELINE)
	_on_gameplay_phase_changed(Gameplay.phase)
	call_deferred("_restore_exploration")

func _ensure_gameplay_shell() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	_gameplay_shell = GAMEPLAY_SHELL.new()
	_gameplay_shell.menu_requested.connect(open_pause_menu)
	layer.add_child(_gameplay_shell)
	_gameplay_shell.hide()
	_guided_exploration = GUIDED_EXPLORATION.new()
	_guided_exploration.menu_requested.connect(open_pause_menu)
	layer.add_child(_guided_exploration)
	_guided_exploration.hide()

func _restore_exploration() -> void:
	await get_tree().process_frame
	if not str(Gameplay.story_flags.get("guide_stage", "")).is_empty(): _on_guide_changed()
	elif Gameplay.story_flags.get("modal","") == "creator": _open_character_creation()
	elif Gameplay.story_flags.get("modal","") == "curriculum": _open_curriculum()

func _on_guide_changed() -> void:
	_gameplay_shell.hide()
	_guided_exploration.refresh()
	Dialogic.paused = true
	_set_dialog_ui_hidden(true)

func _resume_story(timeline: String) -> void:
	if Gameplay.is_sandbox(): return
	_guided_exploration.hide()
	await Dialogic.end_timeline(true)
	await get_tree().process_frame
	Dialogic.paused = false
	_dialogic_layout_was_visible = true
	Dialogic.start(timeline.get_slice("/",0), timeline.get_slice("/",1))

func _on_gameplay_phase_changed(phase: String) -> void:
	_gameplay_shell.visible = phase == "free_roam"
	_guided_exploration.hide()
	if phase == "free_roam":
		_guided_exploration.hide()
		Dialogic.end_timeline.call_deferred(true)
		_gameplay_shell.open_panel("place")
	else: call_deferred("_restore_exploration")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_MENU_ACTION):
		if _pause_menu == null or not is_instance_valid(_pause_menu):
			return

		if _pause_menu.visible:
			return

		get_viewport().set_input_as_handled()
		open_pause_menu()


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


func _ensure_character_creation_modal() -> void:
	if _character_creation_modal != null and is_instance_valid(_character_creation_modal):
		return

	_character_creation_layer = CanvasLayer.new()
	_character_creation_layer.layer = 90
	add_child(_character_creation_layer)

	_character_creation_modal = CHARACTER_CREATION_MODAL_SCENE.instantiate()
	_character_creation_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_character_creation_modal.profile_confirmed_v2.connect(_on_character_profile_confirmed_v2)
	_character_creation_layer.add_child(_character_creation_modal)


func _ensure_hub_layer() -> void:
	if _hub_layer != null and is_instance_valid(_hub_layer):
		return

	_hub_layer = CanvasLayer.new()
	_hub_layer.layer = 80
	add_child(_hub_layer)


func open_pause_menu(action_name: StringName = &"") -> void:
	GameSession.capture_thumbnail()
	GameSession.pause_autosave_runtime()
	_hub_was_visible_before_pause = _hub_scene != null and is_instance_valid(_hub_scene) and _hub_scene.visible
	if _hub_was_visible_before_pause:
		_hub_scene.hide()
	else:
		_set_dialog_ui_hidden(true)
	_pause_menu.show_overview()
	_pause_menu.show()
	if action_name != StringName():
		_pause_menu.open_action(action_name)
	get_tree().paused = true


func close_pause_menu() -> void:
	if _pause_menu == null or not is_instance_valid(_pause_menu):
		return

	_pause_menu.hide()
	get_tree().paused = false
	if _hub_was_visible_before_pause:
		_hub_scene.show()
		_hub_was_visible_before_pause = false
	else:
		_set_dialog_ui_hidden(false)
	GameSession.resume_autosave_runtime()


func begin_return_to_main_menu() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.hide()
	get_tree().paused = false
	GameSession.pause_autosave_runtime()


func _open_character_creation() -> void:
	if _character_creation_modal == null or not is_instance_valid(_character_creation_modal):
		return
	Gameplay.story_flags.modal = "creator"
	Gameplay._checkpoint()

	_set_dialog_ui_hidden(true)
	GameSession.pause_autosave_runtime()
	Dialogic.paused = true
	_character_creation_modal.open_with_profile(
		GameSession.get_character_profile(),
		GameSession.get_character_stat_labels(),
		GameSession.get_character_creation_texts(),
		GameSession.get_character_appearance_options(GameSession.get_character_profile())
	)


func _close_character_creation() -> void:
	Gameplay.story_flags.modal = ""
	Gameplay._checkpoint()
	if _character_creation_modal != null and is_instance_valid(_character_creation_modal):
		_character_creation_modal.hide()
	Dialogic.paused = false
	_set_dialog_ui_hidden(false)
	GameSession.resume_autosave_runtime()


func _set_dialog_ui_hidden(hidden: bool) -> void:
	var dialogic := DialogicUtil.autoload()
	if dialogic == null or not dialogic.has_subsystem("Styles"):
		return

	if hidden and dialogic.has_subsystem("History"):
		dialogic.History.close_history()

	var layout := dialogic.Styles.get_layout_node()
	if layout == null:
		return

	if hidden:
		if layout.visible: _dialogic_layout_was_visible = true
		layout.hide()
	elif _dialogic_layout_was_visible:
		layout.show()


func _on_dialogic_signal(argument: String):
	match argument:
		'under18age':
			get_tree().quit()
			print("signal to under is emmit")
		CHARACTER_CREATION_SIGNAL:
			_open_character_creation()
		WAREHOUSE_GATE_HUB_SIGNAL:
			_open_warehouse_gate_hub()
		APARTMENT_LOCATIONS_SIGNAL:
			Gameplay.begin_guide("night")
		"open_curriculum":
			_open_curriculum()

func _open_curriculum() -> void:
	if is_instance_valid(_curriculum_window): return
	Gameplay.story_flags.modal = "curriculum"
	Gameplay._checkpoint()
	Dialogic.paused = true
	_set_dialog_ui_hidden(true)
	_ensure_hub_layer()
	_curriculum_window = preload("res://scripts/ui/gameplay/curriculum_window.gd").new()
	_hub_layer.add_child(_curriculum_window)
	_curriculum_window.menu_requested.connect(open_pause_menu)
	_curriculum_window.confirmed.connect(func(subjects, sport):
		if not Gameplay.apply_curriculum(subjects,sport): return
		Gameplay.story_flags.modal = ""
		Gameplay._checkpoint()
		_curriculum_window.queue_free()
		Dialogic.paused = false
		_dialogic_layout_was_visible = true
		_set_dialog_ui_hidden(false))


func _on_character_profile_confirmed_v2(profile: Dictionary) -> void:
	if not GameSession.apply_character_profile_v2(profile):
		return
	Gameplay._on_profile_changed(GameSession.get_character_profile())
	_close_character_creation()
	if Gameplay.is_sandbox() and Gameplay.phase != "free_roam":
		var opened: Dictionary = Gameplay.open_sandbox()
		if not opened.ok: Gameplay.notification.emit("Не удалось открыть песочницу: " + str(opened.error))


func _open_warehouse_gate_hub() -> void:
	_ensure_hub_layer()
	_set_dialog_ui_hidden(true)
	if _hub_scene != null and is_instance_valid(_hub_scene):
		_hub_scene.queue_free()

	_hub_scene = WAREHOUSE_GATE_HUB_SCENE.instantiate()
	_hub_scene.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub_scene.menu_requested.connect(open_pause_menu)
	_hub_scene.gate_requested.connect(_on_hub_gate_requested)
	_hub_layer.add_child(_hub_scene)

	if not QuestWeaverGlobal.is_quest_active(WAREHOUSE_ENTER_QUEST_ID) and not QuestWeaverGlobal.is_quest_completed(WAREHOUSE_ENTER_QUEST_ID):
		QuestWeaverGlobal.start_quest_id(WAREHOUSE_ENTER_QUEST_ID)
	GameSession.pause_autosave_runtime()
	Dialogic.paused = true


func _on_hub_gate_requested() -> void:
	QuestWeaverGlobal.complete_objective(WAREHOUSE_ENTER_OBJECTIVE_ID)
	QuestWeaverGlobal.complete_quest_id(WAREHOUSE_ENTER_QUEST_ID)
	if _hub_scene != null and is_instance_valid(_hub_scene):
		if _hub_scene.has_method("set_objective_completed"):
			_hub_scene.set_objective_completed(true)
		_hub_scene.queue_free()
		_hub_scene = null
	GameSession.resume_autosave_runtime()
	call_deferred("_start_warehouse_prolog_after_hub")


func _start_warehouse_prolog_after_hub() -> void:
	Dialogic.paused = false
	await Dialogic.end_timeline(true)
	await get_tree().process_frame
	_dialogic_layout_was_visible = true
	Dialogic.start(WAREHOUSE_PROLOG_TIMELINE)
