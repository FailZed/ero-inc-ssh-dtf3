@tool
extends "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_History/history_layer.gd"
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
var _return_focus: WeakRef
var _shade: ColorRect

@onready var history_header: Control = get_node_or_null("HistoryHeader")
@onready var close_button: Button = get_node_or_null("HideHistory")


func _ready() -> void:
	set("theme",UI.skin())
	super._ready()
	get_history_box().add_theme_stylebox_override("panel",UI.surface(26))
	_shade = ColorRect.new()
	_shade.name = "HistoryBackdrop"
	_shade.color = Color(0.005,0.012,0.024,0.8)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	move_child(_shade,0)
	_shade.hide()

func _apply_export_overrides() -> void:
	font_use_global_size = false
	font_custom_size = roundi(20*UI.text_scale)
	super._apply_export_overrides()
	get_node("HistoryHeader/HeaderRow/TitleLabel").text = "Dialogue history" if GameSession.get_language_code() == GameSession.LANGUAGE_EN else "История диалогов"


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	var history_box := get_history_box()
	if history_box == null or not history_box.visible:
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_hide_history_pressed()


func show_history() -> void:
	var control := get_viewport().gui_get_focus_owner()
	if control != null: _return_focus = weakref(control)
	DialogicUtil.autoload().paused = true
	super.show_history()
	_shade.show()
	if history_header != null:
		history_header.show()
	if close_button != null:
		close_button.text = "Back · Esc" if GameSession.get_language_code() == GameSession.LANGUAGE_EN else "Назад · Esc"
		close_button.offset_left = -270
		close_button.offset_right = -84
		close_button.add_theme_font_size_override("font_size",roundi(18*UI.text_scale))
		close_button.show()
		close_button.move_to_front()
		close_button.grab_focus()
		for side in ["left","right","top","bottom","next","previous"]: close_button.set("focus_"+(side if side in ["next","previous"] else "neighbor_"+side),NodePath("."))
	for entry in get_history_log().get_children():
		entry.custom_minimum_size.y = 60
		entry.add_theme_stylebox_override("panel",UI.style(Color(0.008,0.02,0.035,0.5),Color("344c5d")))
		for label in entry.find_children("*","Label",true,false): label.add_theme_font_size_override("font_size",roundi(20*UI.text_scale))
		for text in entry.find_children("*","RichTextLabel",true,false):
			for font in ["normal_font_size","bold_font_size","italics_font_size","bold_italics_font_size"]: text.add_theme_font_size_override(font,roundi(22*UI.text_scale))


func _on_hide_history_pressed() -> void:
	super._on_hide_history_pressed()
	if _shade != null: _shade.hide()
	if history_header != null:
		history_header.hide()
	if _return_focus != null: UI.restore_focus.call_deferred(_return_focus)
