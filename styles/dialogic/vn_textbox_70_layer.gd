@tool
extends "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_VN_Textbox/vn_textbox_layer.gd"
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")

## Width of the dialog window relative to the current viewport.
## The shared conversation stage leaves breathing room at both screen edges.
@export_range(0.0, 1.0, 0.01) var box_width_ratio: float = 0.84

## Height of the dialog window relative to the current viewport.
## Space for multiple readable lines above the action toolbar.
@export_range(0.0, 1.0, 0.01) var box_height_ratio: float = 0.20

## Transparency of the main dialog box.
## 1.0 is fully opaque, 0.0 is fully transparent.
@export_range(0.0, 1.0, 0.01) var box_opacity: float = 0.97

## Show a custom side menu with dialog actions.
@export var show_side_controls: bool = true

## Default delay between letters in seconds.
## Smaller value = faster typing.
@export_range(0.0, 0.2, 0.001) var text_letter_speed: float = 0.01

## Allow the player to skip the letter-by-letter reveal.
@export var text_reveal_skippable: bool = true

## Small input lock after skipping text reveal.
@export_range(0.0, 1.0, 0.01) var text_reveal_skip_delay: float = 0.1

## Small input lock before advancing to the next line.
@export_range(0.0, 1.0, 0.01) var text_advance_delay: float = 0.1

## Force auto-advance for dialog text.
@export var autoadvance_enabled: bool = false

## Base delay for auto-advance.
@export_range(0.0, 10.0, 0.01) var autoadvance_fixed_delay: float = 1.0

## Additional auto-advance delay per character.
@export_range(0.0, 1.0, 0.01) var autoadvance_per_character_delay: float = 0.1

## Ignore punctuation and similar characters in auto-advance timing.
@export var autoadvance_ignored_characters_enabled: bool = true

var _textbox_hidden := false

@onready var controls_panel: PanelContainer = get_node_or_null("Anchor/AnimationParent/DialogControlsPanel")
@onready var dialog_text_panel: PanelContainer = get_node_or_null("Anchor/AnimationParent/Sizer/DialogTextPanel")
@onready var dialog_text: RichTextLabel = get_node_or_null("Anchor/AnimationParent/Sizer/DialogTextPanel/DialogicNode_DialogText")
@onready var next_indicator: Control = get_node_or_null("Anchor/AnimationParent/Sizer/DialogTextPanel/NextIndicator")
@onready var name_label_panel: PanelContainer = get_node_or_null("Anchor/AnimationParent/Sizer/DialogTextPanel/NameLabelHolder/NameLabelPanel")
@onready var history_button: Button = get_node_or_null("Anchor/AnimationParent/DialogControlsPanel/Buttons/HistoryButton")
@onready var hide_button: Button = get_node_or_null("Anchor/AnimationParent/DialogControlsPanel/Buttons/HideButton")
@onready var save_button: Button = get_node_or_null("Anchor/AnimationParent/DialogControlsPanel/Buttons/SaveButton")
@onready var load_button: Button = get_node_or_null("Anchor/AnimationParent/DialogControlsPanel/Buttons/LoadButton")
@onready var menu_button: Button = get_node_or_null("Anchor/AnimationParent/DialogControlsPanel/Buttons/MenuButton")


func _apply_export_overrides() -> void:
	super._apply_export_overrides()
	_apply_dialogic_runtime_settings()
	_apply_box_settings.call_deferred()


func _ready() -> void:
	super._ready()
	set("theme",UI.skin())
	dialog_text_panel.add_theme_stylebox_override("panel",UI.surface(26))
	controls_panel.add_theme_stylebox_override("panel",UI.style(Color(0.01,0.025,0.04,0.8),Color("38576d")))
	name_label_panel.add_theme_stylebox_override("panel",UI.style(Color("0a1723"),UI.BLUE))
	if Engine.is_editor_hint():
		return

	GameSession.language_changed.connect(_apply_localized_button_texts)
	get_viewport().size_changed.connect(_apply_box_settings)

	if history_button != null:
		history_button.pressed.connect(_on_history_button_pressed)
	if hide_button != null:
		hide_button.pressed.connect(_on_hide_button_pressed)
	if save_button != null:
		save_button.pressed.connect(_on_save_button_pressed)
	if load_button != null:
		load_button.pressed.connect(_on_load_button_pressed)
	if menu_button != null:
		menu_button.pressed.connect(_on_menu_button_pressed)
	_sync_hide_button_text()
	_apply_localized_button_texts()


func _apply_box_settings() -> void:
	var dialog_text_panel_node: PanelContainer = %DialogTextPanel

	var panel_modulate := dialog_text_panel_node.self_modulate
	panel_modulate.a = clampf(box_opacity, 0.0, 1.0)
	dialog_text_panel_node.self_modulate = panel_modulate

	# Read the current visible viewport size so the dialog scales with resolution.
	var viewport := get_viewport()
	if viewport == null:
		return

	var viewport_size := viewport.get_visible_rect().size
	var toolbar_height := maxf(48,controls_panel.get_combined_minimum_size().y) if controls_panel != null and show_side_controls else 0.0
	var bottom_margin := maxf(box_margin_bottom,toolbar_height+44)

	# Final pixel size of the dialog box.
	# Width  = viewport width  * box_width_ratio
	# Height = viewport height * box_height_ratio
	var resolved_box_size := Vector2(
		maxf(1.0, viewport_size.x * clampf(box_width_ratio, 0.0, 1.0)),
		maxf(1.0,viewport_size.y*clampf(box_height_ratio,0.0,1.0)*maxf(1.0,UI.text_scale))
	)

	# Apply the computed size and keep the box anchored at the bottom center.
	var sizer: Control = %Sizer
	sizer.custom_minimum_size = resolved_box_size
	sizer.size = resolved_box_size
	sizer.position = resolved_box_size * Vector2(-0.5,-1)+Vector2(0,-bottom_margin)
	dialog_text_panel_node.custom_minimum_size = resolved_box_size

	if controls_panel != null:
		controls_panel.visible = show_side_controls
		controls_panel.custom_minimum_size = Vector2.ZERO
		controls_panel.size = Vector2(resolved_box_size.x,toolbar_height)
		controls_panel.position = Vector2(-resolved_box_size.x*0.5,-24-toolbar_height)


func _apply_text_settings() -> void:
	var dialog_text_node = %DialogicNode_DialogText
	dialog_text_node.alignment = text_alignment
	for font in ["normal_font_size","bold_font_size","italics_font_size","bold_italics_font_size"]: dialog_text_node.add_theme_font_size_override(font,roundi(29*UI.text_scale))
	for button in [history_button,hide_button,save_button,load_button,menu_button]:
		if button != null: button.add_theme_font_size_override("font_size",roundi(20*UI.text_scale))


func _apply_name_label_settings() -> void:
	var name_label_node = %DialogicNode_NameLabel
	name_label_node.use_character_color = false
	name_label_node.add_theme_color_override("font_color",Color("90c6e8"))
	name_label_node.add_theme_font_size_override("font_size",roundi(26*UI.text_scale))

	var name_panel: PanelContainer = %NameLabelPanel
	var text_panel: PanelContainer = %DialogTextPanel
	name_panel.position = name_label_box_offset + Vector2(0, -40)
	name_panel.position -= Vector2(
		text_panel.get_theme_stylebox(&"panel", &"PanelContainer").content_margin_left,
		text_panel.get_theme_stylebox(&"panel", &"PanelContainer").content_margin_top
	)
	name_panel.anchor_left = name_label_alignment / 2.0
	name_panel.anchor_right = name_label_alignment / 2.0
	name_panel.grow_horizontal = [1, 2, 0][name_label_alignment]


func _apply_dialogic_runtime_settings() -> void:
	ProjectSettings.set_setting("dialogic/text/letter_speed", text_letter_speed)
	ProjectSettings.set_setting("dialogic/text/initial_text_reveal_skippable", text_reveal_skippable)
	ProjectSettings.set_setting("dialogic/text/text_reveal_skip_delay", text_reveal_skip_delay)
	ProjectSettings.set_setting("dialogic/text/advance_delay", text_advance_delay)
	ProjectSettings.set_setting("dialogic/text/autoadvance_enabled", autoadvance_enabled)
	ProjectSettings.set_setting("dialogic/text/autoadvance_fixed_delay", autoadvance_fixed_delay)
	ProjectSettings.set_setting("dialogic/text/autoadvance_per_character_delay", autoadvance_per_character_delay)
	ProjectSettings.set_setting("dialogic/text/autoadvance_ignored_characters_enabled", autoadvance_ignored_characters_enabled)

	if Engine.is_editor_hint():
		ProjectSettings.save()

	var dialogic := DialogicUtil.autoload()
	if dialogic == null:
		return

	if dialogic.has_subsystem("Text"):
		dialogic.Text.update_text_speed(text_letter_speed)
		dialogic.Text.set_text_reveal_skippable(text_reveal_skippable)

	if dialogic.has_subsystem("Inputs") and dialogic.Inputs.auto_advance != null:
		dialogic.Inputs.auto_advance.enabled_forced = autoadvance_enabled
		dialogic.Inputs.auto_advance.fixed_delay = autoadvance_fixed_delay
		dialogic.Inputs.auto_advance.per_character_delay = autoadvance_per_character_delay
		dialogic.Inputs.auto_advance.ignored_characters_enabled = autoadvance_ignored_characters_enabled


func _on_history_button_pressed() -> void:
	var dialogic := DialogicUtil.autoload()
	if dialogic == null or not dialogic.has_subsystem("History"):
		return

	if not dialogic.History.simple_history_enabled:
		return

	var history_layer := _find_history_layer()
	if history_layer != null and history_layer.has_method("get_history_box") and history_layer.get_history_box().visible:
		dialogic.History.close_history()
	else:
		dialogic.History.open_history()


func _on_hide_button_pressed() -> void:
	_textbox_hidden = not _textbox_hidden
	var dialog_text_panel: Node = get_node_or_null("Anchor/AnimationParent/Sizer/DialogTextPanel")
	if dialog_text_panel != null:
		dialog_text_panel.visible = not _textbox_hidden
	_sync_hide_button_text()


func _on_save_button_pressed() -> void:
	_open_pause_menu(&"save_game")


func _on_load_button_pressed() -> void:
	_open_pause_menu(&"load_game")


func _on_menu_button_pressed() -> void:
	_open_pause_menu()


func _open_pause_menu(action_name: StringName = &"") -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	if tree.current_scene.has_method("open_pause_menu"):
		tree.current_scene.open_pause_menu(action_name)


func _sync_hide_button_text() -> void:
	if hide_button == null:
		return
	hide_button.text = GameSession.localize("button.show_window") if _textbox_hidden else GameSession.localize("button.hide_window")


func _find_history_layer() -> Node:
	var dialogic := DialogicUtil.autoload()
	if dialogic == null or not dialogic.has_subsystem("Styles"):
		return null

	var layout := dialogic.Styles.get_layout_node()
	if layout == null:
		return null

	return _find_history_layer_recursive(layout)


func _find_history_layer_recursive(node: Node) -> Node:
	if node.has_method("get_history_box") and node.has_method("show_history"):
		return node

	for child in node.get_children():
		var found := _find_history_layer_recursive(child)
		if found != null:
			return found

	return null


func _apply_localized_button_texts() -> void:
	if history_button != null:
		history_button.text = "History" if GameSession.get_language_code() == GameSession.LANGUAGE_EN else "История"
	if save_button != null:
		save_button.text = GameSession.localize("button.dialog_save")
	if load_button != null:
		load_button.text = GameSession.localize("button.dialog_load")
	if menu_button != null:
		menu_button.text = GameSession.localize("button.menu")
	_sync_hide_button_text()
