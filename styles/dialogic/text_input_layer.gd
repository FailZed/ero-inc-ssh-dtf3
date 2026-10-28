@tool
extends "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_TextInput/text_input_layer.gd"
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
var _shade: ColorRect

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	_shade = ColorRect.new()
	_shade.name = "InputBackdrop"
	_shade.color = Color(0.005,0.012,0.024,0.8)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	move_child(_shade,0)
	var input: Control = get_node("DialogicNode_TextInput")
	input.visibility_changed.connect(func():
		_shade.visible = input.visible
		if input.visible: UI.focus_loop.call_deferred(input))
	_shade.visible = input.visible

func _apply_export_overrides() -> void:
	super._apply_export_overrides()
	set("theme",UI.skin())
	var panel := get_node("DialogicNode_TextInput/TextInputPanel") as PanelContainer
	panel.self_modulate = Color.WHITE
	panel.add_theme_stylebox_override("panel",UI.surface(26))
	var field := panel.get_node("VBoxContainer/InputField") as LineEdit
	field.custom_minimum_size.y = 50
	field.add_theme_font_size_override("font_size",roundi(22*UI.text_scale))
	var confirm := panel.get_node("VBoxContainer/ConfirmationButton") as Button
	confirm.custom_minimum_size = Vector2(180,48)
	confirm.text = "Confirm" if GameSession.get_language_code() == GameSession.LANGUAGE_EN else "Подтвердить"
	confirm.add_theme_font_size_override("font_size",roundi(20*UI.text_scale))
	var label := panel.get_node("VBoxContainer/TextLabel") as Label
	label.add_theme_color_override("font_color",UI.INK)
	label.add_theme_font_size_override("font_size",roundi(23*UI.text_scale))
