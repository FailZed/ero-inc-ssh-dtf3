extends PanelContainer
class_name SaveSlotCard
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")

const DEFAULT_CARD_SIZE := Vector2(405, 292)
const DEFAULT_PREVIEW_SIZE := Vector2(328, 156)
const CARD_VERTICAL_CHROME := 126.0

signal primary_action_requested(slot_id: String)
signal delete_requested(slot_id: String)
signal overwrite_requested(slot_id: String)

@onready var preview_frame: PanelContainer = $MarginContainer/VBoxContainer/PreviewFrame
@onready var preview_texture: TextureRect = $MarginContainer/VBoxContainer/PreviewFrame/PreviewTexture
@onready var marker_dots: Label = $MarginContainer/VBoxContainer/PreviewFrame/MarkerDots
@onready var empty_overlay: CenterContainer = $MarginContainer/VBoxContainer/PreviewFrame/EmptyOverlay
@onready var empty_label: Label = $MarginContainer/VBoxContainer/PreviewFrame/EmptyOverlay/EmptyLabel
@onready var title_label: Label = $MarginContainer/VBoxContainer/MetaBox/TitleLabel
@onready var date_label: Label = $MarginContainer/VBoxContainer/MetaBox/DateLabel
@onready var actions_row: Container = $MarginContainer/VBoxContainer/ActionsRow
@onready var primary_button: Button = $MarginContainer/VBoxContainer/ActionsRow/PrimaryButton
@onready var delete_button: Button = $MarginContainer/VBoxContainer/ActionsRow/DeleteButton
@onready var overwrite_button: Button = $MarginContainer/VBoxContainer/ActionsRow/OverwriteButton

var _entry: Dictionary = {}
var _is_save_mode := false


func _ready() -> void:
	var window_size := DisplayServer.window_get_size()
	var compact := window_size.x > window_size.y and window_size.x <= 1100
	focus_mode = Control.FOCUS_ALL
	var card_style := UI.style(Color("0e202d"),Color(0.48,0.70,0.82,0.68))
	card_style.set_border_width_all(1)
	card_style.set_content_margin_all(10)
	add_theme_stylebox_override("panel",card_style)
	title_label.add_theme_font_size_override("font_size",roundi((30 if compact else 20)*UI.text_scale))
	date_label.add_theme_font_size_override("font_size",roundi((25 if compact else 17)*UI.text_scale))
	empty_label.add_theme_font_size_override("font_size",roundi((30 if compact else 20)*UI.text_scale))
	for button in [primary_button,delete_button,overwrite_button]:
		button.add_theme_font_size_override("font_size",roundi((27 if compact else 18)*UI.text_scale))
		button.custom_minimum_size.y = 68 if compact else 42
	primary_button.flat = false
	var action_style := UI.style(Color(0.10,0.22,0.30,0.92),Color(0.53,0.72,0.83,0.72))
	action_style.set_border_width_all(1)
	primary_button.add_theme_stylebox_override("normal",action_style)
	primary_button.custom_minimum_size.x = 180 if compact else 130
	delete_button.add_theme_color_override("font_color",UI.MUTED)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	primary_button.pressed.connect(_on_primary_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	overwrite_button.pressed.connect(_on_overwrite_pressed)
	GameSession.language_changed.connect(_apply_entry_state)
	set_display_size(DEFAULT_CARD_SIZE.x, DEFAULT_PREVIEW_SIZE.y)
	preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_texture.custom_minimum_size = Vector2.ZERO
	_apply_placeholder_state()


func bind_entry(entry: Dictionary, is_save_mode: bool) -> void:
	_entry = entry.duplicate(true)
	_is_save_mode = is_save_mode
	_apply_entry_state()


func set_display_size(card_width: float, preview_height: float) -> void:
	var width := maxf(card_width, 220.0)
	var height := maxf(preview_height + CARD_VERTICAL_CHROME, 196.0)
	custom_minimum_size = Vector2(width, height)
	preview_frame.custom_minimum_size = Vector2(maxf(width - 36.0, 188.0), maxf(preview_height, 104.0))


func _apply_placeholder_state() -> void:
	title_label.text = GameSession.localize("slot.empty")
	date_label.text = GameSession.localize("slot.no_data")
	empty_label.text = GameSession.localize("slot.empty")
	marker_dots.visible = false
	preview_texture.texture = _make_preview_texture(Color(0.05, 0.08, 0.11, 1.0))
	empty_overlay.visible = true


func _apply_entry_state() -> void:
	var is_empty := bool(_entry.get("is_empty", false))
	var title := str(_entry.get("title", GameSession.localize("slot.empty")))
	var saved_at := str(_entry.get("saved_at_text", GameSession.localize("slot.no_data")))
	var preview_color: Color = _entry.get("preview_color", Color(0.2, 0.22, 0.26, 1.0))
	var preview_image: Texture2D = _entry.get("preview_texture", null)
	var can_primary_action := bool(_entry.get("can_primary_action", not is_empty or _is_save_mode))
	var can_delete := bool(_entry.get("can_delete", not is_empty))
	var can_overwrite := bool(_entry.get("can_overwrite", not is_empty))

	title_label.text = GameSession.localize("slot.empty") if is_empty else title
	date_label.text = GameSession.localize("slot.empty") if is_empty else saved_at
	date_label.visible = not is_empty
	empty_label.text = "+"
	empty_label.add_theme_font_size_override("font_size",roundi(48*UI.text_scale))
	marker_dots.visible = not is_empty
	preview_texture.texture = _make_preview_texture(Color("0c1d29")) if is_empty else preview_image if preview_image else _make_preview_texture(preview_color)
	empty_overlay.visible = is_empty
	preview_texture.visible = true

	primary_button.visible = can_primary_action and (not is_empty or _is_save_mode)
	delete_button.visible = can_delete and not is_empty
	overwrite_button.visible = false
	actions_row.visible = delete_button.visible or primary_button.visible

	primary_button.text = GameSession.localize("button.save") if _is_save_mode else GameSession.localize("button.load")
	delete_button.text = "Удалить" if GameSession.get_language_code() != "en" else "Delete"
	overwrite_button.text = GameSession.localize("button.overwrite")
	if is_empty and not _is_save_mode:
		primary_button.disabled = true
	elif is_empty:
		primary_button.disabled = false
	else:
		primary_button.disabled = false

	delete_button.disabled = is_empty or not can_delete
	overwrite_button.disabled = is_empty or not can_overwrite

	modulate = Color(0.72,0.78,0.82,0.9) if is_empty and not _is_save_mode else Color.WHITE


func _on_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		accept_event()
		_activate_slot()
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			grab_focus()
			_activate_slot()


func _activate_slot() -> void:
	var is_empty := bool(_entry.get("is_empty", false))
	var can_primary_action := bool(_entry.get("can_primary_action", not is_empty or _is_save_mode))
	var can_overwrite := bool(_entry.get("can_overwrite", not is_empty))

	if _is_save_mode and not is_empty and can_overwrite:
		overwrite_requested.emit(str(_entry.get("id", "")))
		return

	if can_primary_action and (not is_empty or _is_save_mode):
		primary_action_requested.emit(str(_entry.get("id", "")))


func _on_primary_pressed() -> void:
	_activate_slot()


func _on_delete_pressed() -> void:
	if not bool(_entry.get("is_empty", false)):
		delete_requested.emit(str(_entry.get("id", "")))


func _on_overwrite_pressed() -> void:
	_activate_slot()




func _make_preview_texture(color: Color) -> Texture2D:
	var image := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)
