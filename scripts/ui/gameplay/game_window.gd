extends Control
## Shared game overlay: consistent back, safe margins, focus and scroll ownership.
signal back_requested
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var title := ""
var subtitle := ""
var preferred_size := Vector2(1480,910)
var body: VBoxContainer
var tabs: HBoxContainer
var footer: HBoxContainer
var status: Label
var panel: PanelContainer
var _scroll: ScrollContainer
var _return_focus: WeakRef
var _memory: Dictionary = {}
var _close: Button
var _tab_buttons: Dictionary = {}
var _selected_tab := ""
var _compact_landscape := false

func _ready() -> void:
	var window_size := DisplayServer.window_get_size()
	_compact_landscape = window_size.x > window_size.y and window_size.x <= 1100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.skin()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var previous := get_viewport().gui_get_focus_owner()
	if previous != null: _return_focus = weakref(previous)
	var shade := ColorRect.new()
	shade.color = Color(0.005,0.012,0.024,0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	panel.name = "GameWindow"
	panel.add_theme_stylebox_override("panel",UI.surface(22 if _compact_landscape else 30))
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(panel)
	resized.connect(_fit)
	_fit()
	var content := UI.column(panel,18)
	var header := UI.row(content,20)
	var titles := UI.column(header,5)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(titles,title,48 if _compact_landscape else 34)
	if not subtitle.is_empty(): UI.label(titles,subtitle,28 if _compact_landscape else 18,UI.MUTED)
	_close = HUD.dock_button(header,"Закрыть окно","Esc","close",back_requested.emit)
	_close.set_meta("window_back",true)
	_close.custom_minimum_size = Vector2(80,80) if _compact_landscape else Vector2(54,54)
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs = UI.row(content,10)
	tabs.visible = false
	status = UI.label(content,"",18,UI.ORANGE)
	status.visible = false
	body = UI.scroller(content)
	_scroll = body.get_parent()
	footer = UI.row(content,14)
	_adapt_body_for_landscape.call_deferred()
	_wire_focus.call_deferred()
	tree_exiting.connect(func():
		if _return_focus != null: UI.restore_focus.call_deferred(_return_focus))

func _fit() -> void:
	var desired_width := maxf(preferred_size.x,1700.0) if _compact_landscape else preferred_size.x
	var desired_height := preferred_size.y
	if _compact_landscape: desired_height = maxf(desired_height,980.0 if desired_height >= 850.0 else 700.0)
	panel.size = Vector2(maxf(320,minf(desired_width,size.x-(80.0 if _compact_landscape else 96.0))),maxf(260,minf(desired_height,size.y-(80.0 if _compact_landscape else 96.0))))
	panel.position = (size-panel.size)*0.5
	if is_node_ready(): _wire_focus.call_deferred()

func _wire_focus() -> void:
	if is_inside_tree(): UI.focus_loop(panel)

func set_tabs(items: Dictionary, selected: String, callback: Callable) -> void:
	if selected != _selected_tab: _memory.scroll = 0
	_selected_tab = selected
	UI.clear(tabs)
	_tab_buttons.clear()
	tabs.visible = not items.is_empty()
	for id in items:
		var button := UI.button(tabs,str(items[id]),callback.bind(str(id)))
		button.set_meta("window_tab",id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("normal",UI.style(Color("24465b") if selected == id else Color.TRANSPARENT,UI.BLUE if selected == id else Color("3a5364")))
		_tab_buttons[id] = button
	_adapt_body_for_landscape.call_deferred()

func notice(message: String) -> void:
	status.text = message
	status.visible = not message.is_empty()

func begin_update() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_memory = {"scroll":_scroll.scroll_vertical}
	if focused != null and (body.is_ancestor_of(focused) or tabs.is_ancestor_of(focused)):
		_memory.text = focused.text if focused is BaseButton else ""
		for key in ["input_id","need_id","gameplay_action","focus_id","window_tab"]:
			if focused.has_meta(key): _memory.key = key; _memory.value = focused.get_meta(key); break
	UI.clear(body)

func end_update() -> void:
	notice(status.text)
	_adapt_body_for_landscape()
	_restore.call_deferred()

func _adapt_body_for_landscape() -> void:
	if not _compact_landscape or not is_instance_valid(body): return
	for root in [body,tabs,footer]:
		for control in root.find_children("*","Control",true,false):
			if not (control is Label or control is BaseButton or control is LineEdit): continue
			var base_size := int(control.get_meta("landscape_base_font_size",control.get_theme_font_size("font_size")))
			control.set_meta("landscape_base_font_size",base_size)
			control.add_theme_font_size_override("font_size",roundi(base_size*1.6))
			if control is BaseButton or control is LineEdit:
				var base_height := float(control.get_meta("landscape_base_height",control.custom_minimum_size.y))
				control.set_meta("landscape_base_height",base_height)
				control.custom_minimum_size.y = maxf(base_height,88.0)

func _restore() -> void:
	if not is_inside_tree(): return
	_wire_focus()
	_scroll.set_deferred("scroll_vertical",int(_memory.get("scroll",0)))
	var controls := body.find_children("*","Control",true,false)
	if _memory.get("key","") == "window_tab": controls = tabs.find_children("*","Control",true,false)
	for control in controls:
		if not control.is_visible_in_tree() or (control is BaseButton and control.disabled): continue
		var matches: bool = control.has_meta(str(_memory.get("key",""))) and control.get_meta(str(_memory.get("key",""))) == _memory.get("value")
		if matches or (control is BaseButton and not str(_memory.get("text","")).is_empty() and control.text == _memory.text): control.grab_focus(); return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): return
	for control in controls:
		if control is BaseButton and control.is_visible_in_tree() and not control.disabled: control.grab_focus(); return
	_close.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_I,KEY_J,KEY_C,KEY_M,KEY_P,KEY_R,KEY_Q,KEY_H,KEY_F1,KEY_B]: get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		back_requested.emit()
