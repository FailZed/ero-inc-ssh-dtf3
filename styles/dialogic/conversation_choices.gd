@tool
extends "res://addons/dialogic/Modules/DefaultLayoutParts/Layer_VN_Choices/vn_choice_layer.gd"
## Responses occupy the right side of the conversation, leaving the face clear.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const BORDER := Color("527489")
const PANEL := Color("0a1723")
const SELECTED := Color("183248")
var _choices: VBoxContainer
var _panel: PanelContainer
var _scroll: ScrollContainer

func get_choices() -> VBoxContainer:
	return _choices if _choices != null else get_node("Choices")

func _apply_export_overrides() -> void:
	if _panel == null:
		_choices = get_node("Choices")
		_panel = PanelContainer.new()
		_panel.name = "ResponsePanel"
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.anchor_left = 0.755
		_panel.anchor_top = 0.18
		_panel.anchor_right = 0.965
		_panel.anchor_bottom = 0.67
		_panel.add_theme_stylebox_override("panel",UI.surface(20))
		add_child(_panel)
		var column := UI.column(_panel,14)
		UI.label(column,"ВАШ ОТВЕТ",18,UI.MUTED)
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.follow_focus = true
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(_scroll)
		_choices.owner = null
		_choices.reparent(_scroll,false)
		_choices.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_choices.alignment = BoxContainer.ALIGNMENT_BEGIN
	font_size_use_global = false
	font_size_custom = roundi(23*UI.text_scale)
	boxes_min_size = Vector2(0,64)
	super._apply_export_overrides()
	for button in get_choices().get_children():
		if not button is DialogicNode_ChoiceButton or button.is_queued_for_deletion(): continue
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_stylebox_override("normal",UI.style(PANEL,BORDER))
		button.add_theme_stylebox_override("hover",UI.style(SELECTED,UI.BLUE))
		button.add_theme_stylebox_override("focus",UI.style(SELECTED,UI.BLUE))
		button.add_theme_stylebox_override("pressed",UI.style(SELECTED,UI.BLUE))
		button.add_theme_color_override("font_color",UI.INK)
		button.visibility_changed.connect(_update_visibility)
	_update_visibility()

func _update_visibility() -> void:
	# Dialogic discovers choices only under visible parents. Hiding this panel
	# prevents the first question from ever finding its buttons.
	var active := get_choices().get_children().any(func(child): return child is DialogicNode_ChoiceButton and not child.is_queued_for_deletion() and child.visible)
	_panel.modulate.a = 1.0 if active else 0.0
