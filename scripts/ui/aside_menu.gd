extends Control

signal action_requested(action_name: StringName)

enum MenuPreset {
	START_GAME,
	IN_GAME,
}

const PRESET_CONFIG := {
	MenuPreset.START_GAME: {
		"title_key": "menu.main",
		"buttons": {
			"new_game": true,
			"continue_game": true,
			"load_game": true,
			"save_game": false,
			"settings": true,
			"gallery": true,
			"return_to_main_menu": false,
			"exit": true,
		},
	},
	MenuPreset.IN_GAME: {
		"title_key": "menu.pause",
		"buttons": {
			"new_game": false,
			"continue_game": true,
			"load_game": true,
			"save_game": true,
			"settings": true,
			"gallery": false,
			"return_to_main_menu": true,
			"exit": true,
		},
	},
}

@onready var new_game_button: Button = $VBoxContainer/MenuButtons/NewGameButton
@onready var continue_game_button: Button = $VBoxContainer/MenuButtons/ContinueGameButton
@onready var load_game_button: Button = $VBoxContainer/MenuButtons/LoadGameButton
@onready var save_game_button: Button = $VBoxContainer/MenuButtons/SaveGameButton
@onready var settings_button: Button = $VBoxContainer/MenuButtons/SettingsButton
@onready var gallery_button: Button = $VBoxContainer/MenuButtons/GalleryButton
@onready var return_to_main_menu_button: Button = $VBoxContainer/MenuButtons/ReturnToMainMenuButton
@onready var exit_button: Button = $VBoxContainer/MenuButtons/ExitButton
@onready var language_button: Button = $FooterPanel/LanguageButton
@onready var version_label: Label = $FooterPanel/VersionLabel

@export var initial_preset: int = MenuPreset.START_GAME

var _current_preset: int = MenuPreset.START_GAME
var _continue_available := false
var _workshop_button: Button

const EN_MENU_LABELS := {
	"button.new_game": "NEW GAME",
	"button.continue": "CONTINUE",
	"button.load_game": "LOAD",
	"button.save_game": "SAVE",
	"button.settings": "SETTINGS",
	"button.gallery": "GALLERY",
	"button.return_to_main_menu": "MAIN MENU",
	"button.exit": "EXIT",
}


func _ready() -> void:
	var minimal = preload("res://scripts/ui/gameplay/hud_widgets.gd")
	for button in [new_game_button, continue_game_button, load_game_button, save_game_button, settings_button, gallery_button, return_to_main_menu_button, exit_button]:
		minimal.quiet_button(button)
	_bind_buttons()
	_workshop_button = preload("res://scripts/ui/gameplay/ui_factory.gd").button($VBoxContainer/MenuButtons, "Мастерская персонажей", func(): action_requested.emit(&"character_workshop"))
	minimal.quiet_button(_workshop_button)
	$VBoxContainer/MenuButtons.move_child(_workshop_button, gallery_button.get_index())
	_workshop_button.disabled = not ClassDB.class_exists("GDCubismUserModel")
	_workshop_button.tooltip_text = "Мастерская персонажей · Live2D · Windows x64"
	GameSession.language_changed.connect(_refresh_localized_ui)
	apply_preset(initial_preset)


func apply_preset(preset: int) -> void:
	_current_preset = preset
	var config: Dictionary = PRESET_CONFIG.get(preset, PRESET_CONFIG[MenuPreset.START_GAME])
	_refresh_localized_ui()

	_set_button_state(new_game_button, config["buttons"]["new_game"])
	var continue_visible := bool(config["buttons"]["continue_game"])
	if preset == MenuPreset.START_GAME:
		continue_visible = continue_visible and _continue_available
	_set_button_state(continue_game_button, continue_visible)
	_set_button_state(load_game_button, config["buttons"]["load_game"])
	_set_button_state(save_game_button, config["buttons"]["save_game"])
	_set_button_state(settings_button, config["buttons"]["settings"])
	_set_button_state(gallery_button, config["buttons"]["gallery"])
	_set_button_state(return_to_main_menu_button, config["buttons"]["return_to_main_menu"])
	_set_button_state(exit_button, config["buttons"]["exit"])


func show_start_menu() -> void:
	apply_preset(MenuPreset.START_GAME)


func show_in_game_menu() -> void:
	apply_preset(MenuPreset.IN_GAME)


func set_continue_available(available: bool) -> void:
	_continue_available = available
	apply_preset(_current_preset)


func _bind_buttons() -> void:
	new_game_button.pressed.connect(func() -> void: action_requested.emit(&"new_game"))
	continue_game_button.pressed.connect(func() -> void: action_requested.emit(&"continue_game"))
	load_game_button.pressed.connect(func() -> void: action_requested.emit(&"load_game"))
	save_game_button.pressed.connect(func() -> void: action_requested.emit(&"save_game"))
	settings_button.pressed.connect(func() -> void: action_requested.emit(&"settings"))
	gallery_button.pressed.connect(func() -> void: action_requested.emit(&"gallery"))
	return_to_main_menu_button.pressed.connect(func() -> void: action_requested.emit(&"return_to_main_menu"))
	exit_button.pressed.connect(func() -> void: action_requested.emit(&"exit"))
	language_button.pressed.connect(func() -> void: action_requested.emit(&"toggle_language"))
	$FooterPanel/CreditsButton.pressed.connect(func(): action_requested.emit(&"about"))


func _set_button_state(button: Button, visible: bool) -> void:
	button.visible = visible
	button.disabled = not visible


func _refresh_localized_ui() -> void:
	if is_instance_valid(_workshop_button): _workshop_button.text = "WORKSHOP" if GameSession.get_language_code() == GameSession.LANGUAGE_EN else "МАСТЕРСКАЯ"
	new_game_button.text = _menu_label("button.new_game")
	continue_game_button.text = _menu_label("button.continue")
	load_game_button.text = _menu_label("button.load_game")
	save_game_button.text = _menu_label("button.save_game")
	settings_button.text = _menu_label("button.settings")
	gallery_button.text = _menu_label("button.gallery")
	return_to_main_menu_button.text = _menu_label("button.return_to_main_menu")
	exit_button.text = _menu_label("button.exit")
	language_button.text = GameSession.get_language_code().to_upper()
	version_label.text = "VER. %s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	$FooterPanel/CreditsButton.text = "About" if GameSession.get_language_code() == GameSession.LANGUAGE_EN else "Об игре"


func _menu_label(key: String) -> String:
	if GameSession.get_language_code() == GameSession.LANGUAGE_EN:
		return str(EN_MENU_LABELS.get(key, GameSession.localize(key))).to_upper()
	return GameSession.localize(key).to_upper()

func focus_workshop() -> void:
	if is_instance_valid(_workshop_button): _workshop_button.grab_focus()
