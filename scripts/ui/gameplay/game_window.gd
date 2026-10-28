extends Control
## Shared game overlay: consistent back, safe margins, focus and scroll ownership.
signal back_requested
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
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

func _ready() -> void:
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
	panel.add_theme_stylebox_override("panel",UI.surface(30))
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(panel)
	resized.connect(_fit)
	_fit()
	var content := UI.column(panel,18)
	var header := UI.row(content,20)
	var titles := UI.column(header,5)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(titles,title,34)
	if not subtitle.is_empty(): UI.label(titles,subtitle,18,UI.MUTED)
	_close = UI.button(header,"Назад · Esc",back_requested.emit)
	_close.set_meta("window_back",true)
	_close.custom_minimum_size.x = 150
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs = UI.row(content,10)
	tabs.visible = false
	status = UI.label(content,"",18,UI.ORANGE)
	status.visible = false
	body = UI.scroller(content)
	_scroll = body.get_parent()
	footer = UI.row(content,14)
	_wire_focus.call_deferred()
	tree_exiting.connect(func():
		if _return_focus != null: UI.restore_focus.call_deferred(_return_focus))

func _fit() -> void:
	panel.size = Vector2(maxf(320,minf(preferred_size.x,size.x-96)),maxf(260,minf(preferred_size.y,size.y-96)))
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
	_restore.call_deferred()

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
