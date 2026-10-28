extends Control

const GAME_SCENE_PATH := "res://scenes/game/game.tscn"
const TOGGLE_MENU_ACTION := "ui_cancel"
const LoadMenuScript := preload("res://scripts/ui/load_menu.gd")
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")

enum MenuContext {
	START,
	IN_GAME,
}

enum ContentSection {
	OVERVIEW,
	LOAD,
	SAVE,
	SETTINGS,
	GALLERY,
}

@export var menu_context: MenuContext = MenuContext.START

@onready var aside_menu = $MainLayout/AsidePanel/AsideInstance
@onready var content_panel: Control = $MainLayout/ContentPanel
@onready var title_block: Control = $TitleBlock
@onready var content_header: VBoxContainer = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentHeader
@onready var section_heading: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentHeader/ContentTitleLabel
@onready var section_description: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentHeader/ContentSubtitleLabel
@onready var overview_panel: Control = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/OverviewPanel
@onready var overview_text: RichTextLabel = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/OverviewPanel/OverviewCard/OverviewMargin/OverviewText
@onready var load_menu_panel = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/LoadMenuPanel
@onready var settings_menu_panel: Control = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel
@onready var settings_header_title: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsHeader/SettingsHeaderTitle
@onready var settings_game_tab: Button = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsHeader/SettingsTabs/GameTab
@onready var settings_text_tab: Button = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsHeader/SettingsTabs/TextTab
@onready var settings_language_tab: Button = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsHeader/SettingsTabs/LanguageTab
@onready var settings_card: PanelContainer = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard
@onready var autosave_title_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/SettingsText
@onready var autosave_enabled_check: CheckBox = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/AutosaveColumns/AutosaveLeftColumn/AutosaveEnabledCheck
@onready var autosave_time_check: CheckBox = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/AutosaveColumns/AutosaveLeftColumn/AutosaveTimeCheck
@onready var autosave_choice_check: CheckBox = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/AutosaveColumns/AutosaveLeftColumn/AutosaveChoiceCheck
@onready var autosave_slider: HSlider = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/AutosaveColumns/AutosaveRightColumn/AutosaveSlider
@onready var autosave_interval_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/AutosaveColumns/AutosaveRightColumn/AutosaveHeader/AutosaveLabel
@onready var autosave_value_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/AutosaveColumns/AutosaveRightColumn/AutosaveHeader/AutosaveValueLabel
@onready var autosave_hint_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/AutosaveColumns/AutosaveRightColumn/AutosaveHint
@onready var time_settings_title_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/TimeSettingsTitle
@onready var day_length_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/TimeColumns/TimeLeftColumn/DayLengthLabel
@onready var day_length_hint_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/TimeColumns/TimeLeftColumn/DayLengthHint
@onready var day_length_option_button: OptionButton = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/SettingsCard/SettingsMargin/SettingsLayout/TimeColumns/TimeRightColumn/DayLengthOptionButton
@onready var text_title_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard/TextSettingsMargin/TextSettingsLayout/TextSettingsTitle
@onready var text_settings_card: PanelContainer = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard
@onready var instant_text_check: CheckBox = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard/TextSettingsMargin/TextSettingsLayout/TextColumns/TextLeftColumn/InstantTextCheck
@onready var instant_text_hint_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard/TextSettingsMargin/TextSettingsLayout/TextColumns/TextLeftColumn/InstantTextHint
@onready var text_speed_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard/TextSettingsMargin/TextSettingsLayout/TextColumns/TextRightColumn/TextSpeedHeader/TextSpeedLabel
@onready var text_speed_slider: HSlider = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard/TextSettingsMargin/TextSettingsLayout/TextColumns/TextRightColumn/TextSpeedSlider
@onready var text_speed_value_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard/TextSettingsMargin/TextSettingsLayout/TextColumns/TextRightColumn/TextSpeedHeader/TextSpeedValueLabel
@onready var text_speed_hint_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/TextSettingsCard/TextSettingsMargin/TextSettingsLayout/TextColumns/TextRightColumn/TextSpeedHint
@onready var language_title_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/LanguageSettingsCard/LanguageSettingsMargin/LanguageSettingsLayout/LanguageTitle
@onready var language_settings_card: PanelContainer = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/LanguageSettingsCard
@onready var language_hint_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/LanguageSettingsCard/LanguageSettingsMargin/LanguageSettingsLayout/LanguageColumns/LanguageLeftColumn/LanguageHint
@onready var language_option_button: OptionButton = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/SettingsMenuPanel/LanguageSettingsCard/LanguageSettingsMargin/LanguageSettingsLayout/LanguageColumns/LanguageRightColumn/LanguageOptionButton
@onready var gallery_menu_panel: Control = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/GalleryMenuPanel
@onready var gallery_text_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/ContentStack/GalleryMenuPanel/GalleryCard/GalleryMargin/GalleryText
@onready var footer_row: HBoxContainer = $MainLayout/ContentPanel/ContentMargin/ContentLayout/FooterRow
@onready var feedback_label: Label = $MainLayout/ContentPanel/ContentMargin/ContentLayout/FooterRow/FeedbackLabel

var _settings_page := "game"
var _active_load_menu_mode: int = LoadMenuScript.PanelMode.LOAD
var _character_workshop: Control


func _ready() -> void:
	theme = preload("res://scripts/ui/gameplay/ui_factory.gd").skin()
	aside_menu.action_requested.connect(_on_aside_action_requested)
	load_menu_panel.slot_primary_action_requested.connect(_on_slot_primary_action_requested)
	load_menu_panel.slot_delete_requested.connect(_on_slot_delete_requested)
	load_menu_panel.slot_overwrite_requested.connect(_on_slot_overwrite_requested)
	GameSession.save_slots_changed.connect(_on_save_slots_changed)
	GameSession.autosave_interval_changed.connect(_on_autosave_interval_changed)
	GameSession.autosave_settings_changed.connect(_sync_autosave_controls)
	GameSession.text_settings_changed.connect(_sync_text_controls)
	GameSession.language_changed.connect(_on_language_changed)
	GameSession.game_time_settings_changed.connect(_sync_time_controls)
	_bind_settings_controls()
	_bind_text_controls()
	_bind_language_controls()
	_apply_settings_visual_style()
	settings_game_tab.pressed.connect(_show_settings_page.bind("game"))
	settings_text_tab.pressed.connect(_show_settings_page.bind("text"))
	settings_language_tab.pressed.connect(_show_settings_page.bind("language"))
	_show_settings_page(_settings_page)
	var paper := Panel.new()
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.add_theme_stylebox_override("panel",UI.surface(0))
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_panel.add_child(paper)
	content_panel.move_child(paper,0)
	_apply_menu_context()
	_refresh_load_menu()
	_apply_translations()
	_show_section(ContentSection.OVERVIEW)
	if menu_context == MenuContext.START and not GameSession.last_load_error.is_empty():
		_show_section(ContentSection.LOAD)
		_set_feedback(GameSession.last_load_error)
	if menu_context == MenuContext.START and OS.get_cmdline_user_args().has("--character-workshop") and not get_tree().has_meta("character_workshop_command_used"):
		get_tree().set_meta("character_workshop_command_used", true)
		_open_character_workshop.call_deferred()


func open_action(action_name: StringName) -> void:
	_on_aside_action_requested(action_name)


func show_overview() -> void:
	_show_section(ContentSection.OVERVIEW)


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_character_workshop): return
	if menu_context != MenuContext.IN_GAME or not visible:
		return

	if event.is_action_pressed(TOGGLE_MENU_ACTION):
		get_viewport().set_input_as_handled()
		_continue_game()


func _apply_menu_context() -> void:
	if menu_context == MenuContext.IN_GAME:
		aside_menu.show_in_game_menu()
	else:
		GameSession.pause_autosave_runtime()
		aside_menu.show_start_menu()

	aside_menu.set_continue_available(GameSession.has_continue_slot())


func _on_aside_action_requested(action_name: StringName) -> void:
	match String(action_name):
		"new_game":
			_start_new_game()
		"continue_game":
			_continue_game()
		"load_game":
			_active_load_menu_mode = LoadMenuScript.PanelMode.LOAD
			_refresh_load_menu()
			load_menu_panel.set_panel_mode(_active_load_menu_mode)
			_show_section(ContentSection.LOAD)
		"save_game":
			_active_load_menu_mode = LoadMenuScript.PanelMode.SAVE
			_refresh_load_menu()
			load_menu_panel.set_panel_mode(_active_load_menu_mode)
			_show_section(ContentSection.SAVE)
		"settings":
			_show_section(ContentSection.SETTINGS)
		"gallery":
			_show_section(ContentSection.GALLERY)
		"character_workshop":
			_open_character_workshop()
		"return_to_main_menu":
			_return_to_main_menu()
		"toggle_language":
			_toggle_language()
		"exit":
			get_tree().quit()
		"about":
			var window := preload("res://scripts/ui/gameplay/game_window.gd").new()
			window.title = "Ero Inc"
			window.subtitle = "Истории и самостоятельная жизнь в Эллизии"
			window.preferred_size = Vector2(900,560)
			window.back_requested.connect(window.queue_free)
			add_child(window)
			UI.label(window.body,"Знакомьтесь с жителями, развивайте навыки и находите свой ритм в городе.",26)
			UI.label(window.body,"Версия "+str(ProjectSettings.get_setting("application/config/version","0.0.0")),18,UI.MUTED)
			window.end_update()

func _open_character_workshop() -> void:
	if is_instance_valid(_character_workshop) or not ClassDB.class_exists("GDCubismUserModel"): return
	var scene := load("res://scenes/characters/character_workshop.tscn") as PackedScene
	if scene == null: return
	_character_workshop = scene.instantiate()
	_character_workshop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_character_workshop)
	_character_workshop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_workshop.closed.connect(aside_menu.focus_workshop)


func _show_section(section: ContentSection) -> void:
	var is_overview := section == ContentSection.OVERVIEW
	content_panel.visible = not is_overview
	title_block.visible = is_overview
	content_header.visible = section != ContentSection.LOAD and section != ContentSection.SAVE and section != ContentSection.SETTINGS
	footer_row.visible = section == ContentSection.OVERVIEW
	overview_panel.visible = section == ContentSection.OVERVIEW
	load_menu_panel.visible = section == ContentSection.LOAD or section == ContentSection.SAVE
	settings_menu_panel.visible = section == ContentSection.SETTINGS
	gallery_menu_panel.visible = section == ContentSection.GALLERY
	if section == ContentSection.GALLERY: _refresh_collection()
	_focus_section.call_deferred(section)

	match section:
		ContentSection.OVERVIEW:
			if menu_context == MenuContext.IN_GAME:
				section_heading.text = GameSession.localize("menu.pause")
				section_description.text = GameSession.localize("menu.overview_pause")
			else:
				section_heading.text = GameSession.localize("menu.main")
				section_description.text = GameSession.localize("menu.overview_start")
		ContentSection.LOAD:
			section_heading.text = GameSession.localize("menu.load_title")
			section_description.text = GameSession.localize("menu.load_desc")
		ContentSection.SAVE:
			section_heading.text = GameSession.localize("menu.save_title")
			section_description.text = GameSession.localize("menu.save_desc")
		ContentSection.SETTINGS:
			section_heading.text = GameSession.localize("menu.settings_title")
			section_description.text = GameSession.localize("menu.settings_desc")
		ContentSection.GALLERY:
			section_heading.text = GameSession.localize("menu.gallery_title")
			section_description.text = GameSession.localize("menu.gallery_desc")


func _refresh_collection() -> void:
	var parent := gallery_text_label.get_parent()
	for child in parent.get_children():
		if child.get_meta("collection_view", false): parent.remove_child(child); child.queue_free()
	gallery_text_label.visible = Gameplay.phase != "free_roam"
	if Gameplay.phase != "free_roam":
		gallery_text_label.text = "Коллекция станет доступна в загруженной свободной игре."
		return
	var viewer := preload("res://scripts/ui/gameplay/collection_view.gd").new()
	var scroll := ScrollContainer.new()
	scroll.set_meta("collection_view", true)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 350
	parent.add_child(scroll)
	scroll.add_child(viewer)

func _start_new_game() -> void:
	if not ResourceLoader.exists(GAME_SCENE_PATH):
		_set_feedback(GameSession.localize("feedback.scene_missing", {"path": GAME_SCENE_PATH}))
		push_warning("MainMenu: missing scene at %s" % GAME_SCENE_PATH)
		return

	if get_node_or_null("WorldSetup") != null: return
	var setup := preload("res://scenes/ui/WorldSetup.tscn").instantiate()
	add_child(setup)


func _continue_game() -> void:
	if menu_context == MenuContext.IN_GAME:
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.has_method("close_pause_menu"):
			current_scene.close_pause_menu()
		else:
			get_tree().paused = false
			hide()
		return

	var load_error := GameSession.continue_latest_game()
	if load_error != OK:
		_set_feedback(GameSession.localize("feedback.no_continue"))


func _return_to_main_menu() -> void:
	if menu_context != MenuContext.IN_GAME:
		return

	var current_scene := get_tree().current_scene
	if current_scene != null and current_scene.has_method("begin_return_to_main_menu"):
		current_scene.begin_return_to_main_menu()

	var return_error := GameSession.return_to_main_menu()
	if return_error != OK:
		_set_feedback(GameSession.localize("feedback.return_failed", {"error": error_string(return_error)}))


func _on_slot_primary_action_requested(slot_id: String) -> void:
	if _active_load_menu_mode == LoadMenuScript.PanelMode.SAVE:
		var save_error := GameSession.save_slot(slot_id)
		if save_error == OK:
			_refresh_load_menu()
			_set_feedback(GameSession.localize("feedback.save_updated", {"slot": slot_id}))
		else:
			_set_feedback(GameSession.localize("feedback.save_failed", {"slot": slot_id, "error": error_string(save_error)}))
		return

	if menu_context == MenuContext.IN_GAME:
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.has_method("close_pause_menu"):
			current_scene.close_pause_menu()
			call_deferred("_load_slot_after_pause_closed", slot_id)
			return

	var load_error := GameSession.request_load_slot(slot_id)
	if load_error != OK:
		_set_feedback(GameSession.localize("feedback.load_failed", {"slot": slot_id, "error": error_string(load_error)}))


func _on_slot_delete_requested(slot_id: String) -> void:
	W.confirm(self,"Удалить сохранение?","Это сохранение будет удалено. Остальные слоты останутся доступны.","Удалить",_delete_slot.bind(slot_id))

func _delete_slot(slot_id: String) -> void:
	var delete_error := GameSession.delete_slot(slot_id)
	if delete_error == OK:
		_refresh_load_menu()
		_set_feedback(GameSession.localize("feedback.delete_ok", {"slot": slot_id}))
	else:
		_set_feedback(GameSession.localize("feedback.delete_failed", {"slot": slot_id, "error": error_string(delete_error)}))


func _on_slot_overwrite_requested(slot_id: String) -> void:
	W.confirm(self,"Заменить сохранение?","Текущая игра займёт выбранный слот.","Сохранить",_overwrite_slot.bind(slot_id))

func _overwrite_slot(slot_id: String) -> void:
	var save_error := GameSession.save_slot(slot_id)
	if save_error == OK:
		_refresh_load_menu()
		_set_feedback(GameSession.localize("feedback.overwrite_ok", {"slot": slot_id}))
	else:
		_set_feedback(GameSession.localize("feedback.overwrite_failed", {"slot": slot_id, "error": error_string(save_error)}))


func _refresh_load_menu() -> void:
	var slot_collections := GameSession.build_slot_collections(_active_load_menu_mode == LoadMenuScript.PanelMode.SAVE)
	load_menu_panel.configure(
		_active_load_menu_mode,
		slot_collections.get("auto_entries", []),
		slot_collections.get("quick_entries", []),
		slot_collections.get("user_pages", [])
	)
	aside_menu.set_continue_available(GameSession.has_continue_slot())


func _on_save_slots_changed() -> void:
	_refresh_load_menu()


func _bind_settings_controls() -> void:
	var autosave_bounds := GameSession.get_autosave_interval_bounds()
	autosave_slider.min_value = autosave_bounds.get("min", 5)
	autosave_slider.max_value = autosave_bounds.get("max", 30)
	autosave_slider.step = autosave_bounds.get("step", 5)
	_sync_autosave_controls()
	autosave_enabled_check.toggled.connect(_on_autosave_enabled_toggled)
	autosave_time_check.toggled.connect(_on_autosave_time_toggled)
	autosave_choice_check.toggled.connect(_on_autosave_choice_toggled)
	autosave_slider.value_changed.connect(_on_autosave_slider_value_changed)
	_bind_time_controls()


func _bind_time_controls() -> void:
	day_length_option_button.clear()
	for option in GameSession.get_game_day_length_options():
		day_length_option_button.add_item(GameSession.localize(str(option.get("label_key", ""))))
	_sync_time_controls()
	day_length_option_button.item_selected.connect(_on_day_length_item_selected)


func _bind_text_controls() -> void:
	var text_speed_bounds := GameSession.get_text_speed_bounds()
	text_speed_slider.min_value = text_speed_bounds.get("min", 0.5)
	text_speed_slider.max_value = text_speed_bounds.get("max", 3.0)
	text_speed_slider.step = text_speed_bounds.get("step", 0.25)
	_sync_text_controls()
	instant_text_check.toggled.connect(_on_instant_text_toggled)
	text_speed_slider.value_changed.connect(_on_text_speed_slider_value_changed)


func _bind_language_controls() -> void:
	language_option_button.clear()
	for option in GameSession.get_language_options():
		language_option_button.add_item(GameSession.localize(str(option.get("label_key", ""))))
	_sync_language_controls()
	language_option_button.item_selected.connect(_on_language_item_selected)


func _apply_settings_visual_style() -> void:
	for panel in [settings_card,text_settings_card,language_settings_card]:
		panel.add_theme_stylebox_override("panel",UI.style(Color(0.025,0.06,0.09,0.55),Color("38576d")))
	for title in [settings_header_title,autosave_title_label,time_settings_title_label,text_title_label,language_title_label]:
		title.add_theme_color_override("font_color",UI.INK)
		title.add_theme_font_size_override("font_size",32 if title == settings_header_title else 24)
	for label in [autosave_interval_label,autosave_value_label,text_speed_label,text_speed_value_label,language_hint_label,instant_text_hint_label,autosave_hint_label,day_length_label,day_length_hint_label,text_speed_hint_label]:
		label.add_theme_color_override("font_color",UI.MUTED)
		label.add_theme_font_size_override("font_size",18)
	for check in [autosave_enabled_check,autosave_time_check,autosave_choice_check,instant_text_check]:
		check.custom_minimum_size.y = 46
		check.add_theme_font_size_override("font_size",20)
	for option in [language_option_button,day_length_option_button]:
		option.custom_minimum_size.y = 50
		option.add_theme_font_size_override("font_size",20)

func _show_settings_page(id: String) -> void:
	_settings_page = id
	settings_game_tab.get_parent().show()
	settings_card.visible = id == "game"
	text_settings_card.visible = id == "text"
	language_settings_card.visible = id == "language"
	for pair in [["game",settings_game_tab],["text",settings_text_tab],["language",settings_language_tab]]:
		pair[1].add_theme_stylebox_override("normal",UI.style(Color("24465b") if pair[0] == id else Color.TRANSPARENT,UI.BLUE if pair[0] == id else Color("38576d")))
		pair[1].add_theme_color_override("font_color",UI.BLUE if pair[0] == id else UI.INK)

func _focus_section(section: ContentSection) -> void:
	if section == ContentSection.OVERVIEW:
		if aside_menu.continue_game_button.visible: aside_menu.continue_game_button.grab_focus()
		else: aside_menu.new_game_button.grab_focus()
		return
	var surface: Control = settings_menu_panel if section == ContentSection.SETTINGS else gallery_menu_panel if section == ContentSection.GALLERY else load_menu_panel
	for control in surface.find_children("*","BaseButton",true,false):
		if control.is_visible_in_tree() and not control.disabled: control.grab_focus(); return


func _sync_autosave_controls() -> void:
	var autosave_enabled := GameSession.is_autosave_enabled()
	var time_enabled := GameSession.is_time_autosave_enabled()
	var choice_enabled := GameSession.is_choice_autosave_enabled()
	var interval_minutes := GameSession.get_autosave_interval_minutes()

	autosave_enabled_check.set_pressed_no_signal(autosave_enabled)
	autosave_time_check.set_pressed_no_signal(time_enabled)
	autosave_choice_check.set_pressed_no_signal(choice_enabled)
	autosave_time_check.disabled = not autosave_enabled
	autosave_choice_check.disabled = not autosave_enabled
	autosave_slider.editable = autosave_enabled and time_enabled
	autosave_slider.modulate = Color.WHITE if autosave_slider.editable else Color(0.7, 0.7, 0.7, 1.0)
	if int(autosave_slider.value) != interval_minutes:
		autosave_slider.value = interval_minutes
	_update_autosave_interval_label(interval_minutes)


func _on_autosave_enabled_toggled(enabled: bool) -> void:
	GameSession.set_autosave_enabled(enabled)


func _on_autosave_time_toggled(enabled: bool) -> void:
	GameSession.set_time_autosave_enabled(enabled)


func _on_autosave_choice_toggled(enabled: bool) -> void:
	GameSession.set_choice_autosave_enabled(enabled)


func _on_autosave_slider_value_changed(value: float) -> void:
	GameSession.set_autosave_interval_minutes(int(value))


func _on_autosave_interval_changed(minutes: int) -> void:
	_sync_autosave_controls()


func _update_autosave_interval_label(minutes: int) -> void:
	autosave_value_label.text = GameSession.localize("time.minutes", {"value": minutes})


func _sync_time_controls() -> void:
	var options := GameSession.get_game_day_length_options()
	var current_id := GameSession.get_game_day_length_id()
	for index in range(options.size()):
		var option: Dictionary = options[index]
		day_length_option_button.set_item_text(index, GameSession.localize(str(option.get("label_key", ""))))
		if str(option.get("id", "")) == current_id:
			day_length_option_button.select(index)
			break


func _on_day_length_item_selected(index: int) -> void:
	var options := GameSession.get_game_day_length_options()
	if index >= 0 and index < options.size():
		GameSession.set_game_day_length_id(str(options[index].get("id", GameSession.GAME_DAY_LENGTH_MEDIUM)))


func _sync_text_controls() -> void:
	var instant_text_enabled := GameSession.is_instant_text_enabled()
	var text_speed_multiplier := GameSession.get_text_speed_multiplier()

	instant_text_check.set_pressed_no_signal(instant_text_enabled)
	text_speed_slider.editable = not instant_text_enabled
	text_speed_slider.modulate = Color.WHITE if text_speed_slider.editable else Color(0.7, 0.7, 0.7, 1.0)
	if absf(text_speed_slider.value - text_speed_multiplier) > 0.001:
		text_speed_slider.value = text_speed_multiplier
	_update_text_speed_label(text_speed_multiplier)


func _on_instant_text_toggled(enabled: bool) -> void:
	GameSession.set_instant_text_enabled(enabled)


func _on_text_speed_slider_value_changed(value: float) -> void:
	GameSession.set_text_speed_multiplier(value)


func _update_text_speed_label(multiplier: float) -> void:
	text_speed_value_label.text = "%d%%" % int(round(multiplier * 100.0))


func _load_slot_after_pause_closed(slot_id: String) -> void:
	var load_error := GameSession.request_load_slot(slot_id)
	if load_error != OK:
		_set_feedback(GameSession.localize("feedback.load_failed", {"slot": slot_id, "error": error_string(load_error)}))


func _set_feedback(message: String) -> void:
	feedback_label.text = message


func _sync_language_controls() -> void:
	var options := GameSession.get_language_options()
	var current_code := GameSession.get_language_code()
	for index in range(options.size()):
		var option: Dictionary = options[index]
		language_option_button.set_item_text(index, GameSession.localize(str(option.get("label_key", ""))))
		if str(option.get("code", "")) == current_code:
			language_option_button.select(index)
			break


func _on_language_item_selected(index: int) -> void:
	var options := GameSession.get_language_options()
	if index >= 0 and index < options.size():
		GameSession.set_language_code(str(options[index].get("code", GameSession.LANGUAGE_RU)))


func _toggle_language() -> void:
	var options := GameSession.get_language_options()
	if options.is_empty():
		return
	var current_code := GameSession.get_language_code()
	var next_index := 0
	for index in range(options.size()):
		if str(options[index].get("code", "")) == current_code:
			next_index = (index + 1) % options.size()
			break
	GameSession.set_language_code(str(options[next_index].get("code", GameSession.LANGUAGE_RU)))


func _on_language_changed() -> void:
	_sync_language_controls()
	_refresh_load_menu()
	_apply_translations()
	_show_section(_current_content_section())


func _apply_translations() -> void:
	settings_header_title.text = GameSession.localize("menu.settings_title").to_upper()
	settings_game_tab.text = "GAME" if GameSession.get_language_code() == GameSession.LANGUAGE_EN else "ИГРА"
	settings_text_tab.text = GameSession.localize("settings.text").to_upper()
	settings_language_tab.text = GameSession.localize("settings.language").to_upper()
	overview_text.text = GameSession.localize("overview.text")
	gallery_text_label.text = GameSession.localize("gallery.text")
	autosave_title_label.text = GameSession.localize("settings.autosaves")
	autosave_enabled_check.text = GameSession.localize("settings.autosave_enabled")
	autosave_time_check.text = GameSession.localize("settings.autosave_time")
	autosave_choice_check.text = GameSession.localize("settings.autosave_choice")
	autosave_interval_label.text = GameSession.localize("settings.autosave_interval")
	autosave_hint_label.text = GameSession.localize("settings.autosave_hint")
	time_settings_title_label.text = GameSession.localize("settings.time")
	day_length_label.text = GameSession.localize("settings.day_length")
	day_length_hint_label.text = GameSession.localize("settings.day_length_hint")
	text_title_label.text = GameSession.localize("settings.text")
	instant_text_check.text = GameSession.localize("settings.instant_text")
	instant_text_hint_label.text = GameSession.localize("settings.instant_text_hint")
	text_speed_label.text = GameSession.localize("settings.text_speed")
	text_speed_hint_label.text = GameSession.localize("settings.text_speed_hint")
	language_title_label.text = GameSession.localize("settings.language")
	language_hint_label.text = GameSession.localize("settings.language_hint")
	_update_autosave_interval_label(GameSession.get_autosave_interval_minutes())
	_sync_time_controls()


func _current_content_section() -> ContentSection:
	if load_menu_panel.visible:
		return ContentSection.SAVE if _active_load_menu_mode == LoadMenuScript.PanelMode.SAVE else ContentSection.LOAD
	if settings_menu_panel.visible:
		return ContentSection.SETTINGS
	if gallery_menu_panel.visible:
		return ContentSection.GALLERY
	return ContentSection.OVERVIEW
