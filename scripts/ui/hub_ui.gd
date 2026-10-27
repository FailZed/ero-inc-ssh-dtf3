extends Control

signal menu_requested
signal back_requested
signal inventory_requested
signal profile_requested
signal journal_requested

@export var quest_resource: Resource
@export var quest_id: StringName = &""
@export var quest_title := ""
@export_multiline var quest_description := ""
@export var objective_id: StringName = &""
@export var objective_text := ""
@export var open_on_ready := false
@export var use_location_back := true
@export var hide_back_when_unavailable := true

@onready var menu_button: Button = $BottomBar/MenuButton
@onready var inventory_button: Button = $BottomBar/InventoryButton
@onready var profile_button: Button = $BottomBar/ProfileButton
@onready var journal_button: Button = $BottomBar/JournalButton
@onready var back_button: Button = $BackButton
@onready var time_label: Label = $StatusPanel/StatusRow/TimeGroup/TimeLabel
@onready var date_label: Label = $StatusPanel/StatusRow/DateGroup/DateLabel
@onready var quest_title_label: Label = $QuestPanel/QuestLayout/QuestHeader/QuestTitle
@onready var quest_description_label: Label = $QuestPanel/QuestLayout/QuestDescription
@onready var objective_label: Label = $QuestPanel/QuestLayout/ObjectiveRow/ObjectiveLabel
@onready var progress_label: Label = $QuestPanel/QuestLayout/ObjectiveRow/ProgressLabel


func _ready() -> void:
	theme = preload("res://scripts/ui/gameplay/ui_factory.gd").skin()
	hide()
	menu_button.pressed.connect(menu_requested.emit)
	inventory_button.pressed.connect(inventory_requested.emit)
	profile_button.pressed.connect(profile_requested.emit)
	journal_button.pressed.connect(journal_requested.emit)
	back_button.pressed.connect(_on_back_button_pressed)
	if LocationManager.has_signal("location_changed"):
		LocationManager.location_changed.connect(_refresh_back_button)
	if GameSession.has_signal("game_time_changed"):
		GameSession.game_time_changed.connect(_on_game_time_changed)
	if QuestWeaverGlobal.has_signal("quest_objective_progress_changed"):
		QuestWeaverGlobal.quest_objective_progress_changed.connect(_on_quest_objective_progress_changed)
	if QuestWeaverGlobal.has_signal("quest_objective_state_changed"):
		QuestWeaverGlobal.quest_objective_state_changed.connect(_on_quest_objective_state_changed)
	_apply_quest_resource()
	_apply_quest_weaver_context()
	_on_game_time_changed(GameSession.get_game_time_snapshot())
	_refresh_back_button(LocationManager.current_location_id)
	if open_on_ready:
		open()


func _exit_tree() -> void:
	if LocationManager.location_changed.is_connected(_refresh_back_button):
		LocationManager.location_changed.disconnect(_refresh_back_button)
	if GameSession.game_time_changed.is_connected(_on_game_time_changed):
		GameSession.game_time_changed.disconnect(_on_game_time_changed)
	if QuestWeaverGlobal.quest_objective_progress_changed.is_connected(_on_quest_objective_progress_changed):
		QuestWeaverGlobal.quest_objective_progress_changed.disconnect(_on_quest_objective_progress_changed)
	if QuestWeaverGlobal.quest_objective_state_changed.is_connected(_on_quest_objective_state_changed):
		QuestWeaverGlobal.quest_objective_state_changed.disconnect(_on_quest_objective_state_changed)


func open() -> void:
	show()


func close() -> void:
	hide()


func set_quest_resource(resource: Resource) -> void:
	quest_resource = resource
	if is_node_ready():
		_apply_quest_resource()


func set_quest_weaver_context(
	new_quest_id: StringName,
	new_quest_title: String,
	new_quest_description: String,
	new_objective_id: StringName,
	new_objective_text: String
) -> void:
	quest_id = new_quest_id
	quest_title = new_quest_title
	quest_description = new_quest_description
	objective_id = new_objective_id
	objective_text = new_objective_text
	if is_node_ready():
		_apply_quest_weaver_context()


func set_objective_completed(completed: bool) -> void:
	progress_label.text = "1/1" if completed else "0/1"


func _on_back_button_pressed() -> void:
	back_requested.emit()
	if use_location_back:
		LocationManager.go_back()


func _refresh_back_button(_location_id: String = "") -> void:
	var can_return := use_location_back and LocationManager.can_go_back()
	back_button.disabled = not can_return
	if hide_back_when_unavailable:
		back_button.visible = can_return


func _apply_quest_resource() -> void:
	if quest_resource == null:
		return

	if "quest_name" in quest_resource:
		quest_title_label.text = str(quest_resource.get("quest_name")).to_upper()
	if "quest_description" in quest_resource:
		quest_description_label.text = str(quest_resource.get("quest_description"))
	if "quest_objective" in quest_resource:
		objective_label.text = str(quest_resource.get("quest_objective"))
	set_objective_completed(bool(quest_resource.get("objective_completed")) if "objective_completed" in quest_resource else false)


func _apply_quest_weaver_context() -> void:
	if quest_id == &"":
		return

	if not quest_title.is_empty():
		quest_title_label.text = quest_title.to_upper()
	if not quest_description.is_empty():
		quest_description_label.text = quest_description
	if not objective_text.is_empty():
		objective_label.text = objective_text

	var active_objectives := QuestWeaverGlobal.get_active_objectives(quest_id)
	for active_objective in active_objectives:
		if active_objective is ObjectiveResource and active_objective.id == objective_id:
			objective_label.text = active_objective.description
			if active_objective.show_counter:
				progress_label.text = "%d/1" % int(active_objective.current_progress)
			else:
				set_objective_completed(active_objective.status == ObjectiveResource.Status.COMPLETED)
			return

	set_objective_completed(
		objective_id != &"" and QuestWeaverGlobal.is_objective_completed(objective_id)
	)


func _on_quest_objective_progress_changed(changed_quest_id: StringName, changed_objective_id: StringName, _current_progress: int, _max_progress: int) -> void:
	if changed_quest_id == quest_id or changed_objective_id == objective_id:
		_apply_quest_weaver_context()


func _on_quest_objective_state_changed(changed_quest_id: StringName, changed_objective_id: StringName, _new_status: int) -> void:
	if changed_quest_id == quest_id or changed_objective_id == objective_id:
		_apply_quest_weaver_context()


func _on_game_time_changed(snapshot: Dictionary) -> void:
	time_label.text = str(snapshot.get("time_text", "00:00"))
	date_label.text = str(snapshot.get("date_text", "APR 12"))

	var capabilities: Dictionary = snapshot.get("capabilities", {})
	var social_available := bool(capabilities.get("social", true))
	var exploration_available := bool(capabilities.get("exploration", true))
	inventory_button.disabled = not exploration_available
	profile_button.disabled = not social_available
	journal_button.disabled = false
