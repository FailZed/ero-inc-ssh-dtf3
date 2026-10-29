extends Control
## Chooses a sleep duration over the current scene without advancing the world.
signal duration_selected(minutes: int)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var slider: HSlider
var confirm_button: Button
var _duration: Label
var _panel: PanelContainer
var _return_focus: WeakRef

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.0, 0.008, 0.02, 0.48)
	add_child(veil)
	veil.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: hide_picker())
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.surface(20))
	add_child(_panel)
	var content := UI.column(_panel, 15)
	UI.label(content, "ПОСПАТЬ", 26, UI.INK)
	UI.label(content, "Выберите, сколько времени провести во сне.", 18, UI.MUTED)
	_duration = UI.label(content, "", 24, UI.BLUE)
	slider = HSlider.new()
	slider.min_value = 15
	slider.max_value = 720
	slider.step = 15
	slider.value = 480
	slider.custom_minimum_size = Vector2(240, 38)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(_update_duration)
	content.add_child(slider)
	_update_duration(slider.value)
	var buttons := UI.row(content, 12)
	confirm_button = UI.button(buttons, "Поспать", _confirm)
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HUD.quiet_button(confirm_button)
	var cancel := UI.button(buttons, "Отмена", hide_picker)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HUD.quiet_button(cancel)
	resized.connect(_fit)
	_fit()
	visible = false

func _fit() -> void:
	if not is_instance_valid(_panel) or size.x <= 0.0: return
	var width := minf(520.0, size.x - 32.0)
	slider.custom_minimum_size.x = minf(240.0, width - 40.0)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -148
	_panel.offset_bottom = 148

func _update_duration(value: float) -> void:
	var minutes := int(value)
	_duration.text = "%d ч %02d мин" % [int(minutes / 60), minutes % 60]
	if is_instance_valid(confirm_button): confirm_button.tooltip_text = "Поспать %d минут" % minutes

func show_picker() -> void:
	var previous := get_viewport().gui_get_focus_owner()
	_return_focus = weakref(previous) if previous != null and not is_ancestor_of(previous) else null
	visible = true
	UI.focus_loop(_panel)
	slider.grab_focus()

func hide_picker() -> void:
	if not visible: return
	visible = false
	if _return_focus != null: UI.restore_focus.call_deferred(_return_focus)

func _confirm() -> void:
	var minutes := int(slider.value)
	hide_picker()
	duration_selected.emit(minutes)

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)):
		get_viewport().set_input_as_handled()
		hide_picker()
