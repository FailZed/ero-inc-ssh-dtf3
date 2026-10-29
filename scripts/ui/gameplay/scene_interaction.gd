extends Control
## A compact action palette opened from the scene dock.
signal navigation_changed
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var actions: Array[Dictionary] = []
var buttons: Dictionary = {}
var page := "actions"
var drawer_open := false
var panel: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _tabs: Dictionary = {}
var _location := ""
var _saved_scroll := 0
var _focus_id := ""
var mobile_layout := false
var _fold: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "SceneInteraction"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -410
	panel.offset_right = -12
	var surface := UI.style(Color(0.012,0.029,0.043,0.90),Color(0.48,0.70,0.82,0.82))
	surface.set_border_width_all(2)
	surface.set_content_margin_all(12)
	surface.shadow_color = Color(0.0,0.0,0.0,0.48)
	surface.shadow_size = 8
	panel.add_theme_stylebox_override("panel",surface)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var column := UI.column(panel,10)
	var header := UI.row(column,8)
	_title = UI.label(header,"Действия",22,UI.INK)
	_fold = HUD.dock_button(header,"Скрыть действия","","close",hide_drawer)
	_fold.custom_minimum_size = Vector2(42,42)
	_fold.tooltip_text = "Скрыть действия"
	HUD.quiet_button(_fold)
	var tabs := UI.row(column,6)
	for spec in [["actions","Дела","desk"],["people","Люди","people"],["places","Путь","map"]]:
		var button := HUD.labeled_button(tabs,spec[1],"",spec[2],select_page.bind(spec[0]))
		button.custom_minimum_size = Vector2(112,64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs[spec[0]] = button
	_body = UI.scroller(column)
	_scroll = _body.get_parent()
	_body.minimum_size_changed.connect(func(): _fit.call_deferred())
	resized.connect(_fit)
	resized.connect(_wire_navigation)
	_apply_size()
	panel.hide()

func begin(location: String, _texture: Texture2D) -> void:
	_saved_scroll = _scroll.scroll_vertical
	var focused := get_viewport().gui_get_focus_owner()
	_focus_id = str(focused.get_meta("scene_action","")) if focused != null else ""
	if location != _location:
		_saved_scroll = 0
		hide_drawer()
	_location = location
	actions.clear()

func add_action(id: String, caption: String, callback: Callable, hint: String, kind: String = "arrow") -> Button:
	actions.append({"id":id,"caption":caption,"callback":callback,"hint":hint,"kind":kind})
	return null

func finish() -> void:
	_rebuild()

func set_mobile_layout(enabled: bool) -> void:
	if mobile_layout == enabled: return
	mobile_layout = enabled
	if is_inside_tree():
		_apply_size()
		_rebuild()

func _apply_size() -> void:
	panel.offset_left = -690 if mobile_layout else -410
	panel.offset_right = -8 if mobile_layout else -12
	_title.add_theme_font_size_override("font_size",roundi((36 if mobile_layout else 20)*UI.text_scale))
	_fold.custom_minimum_size = Vector2(78,78) if mobile_layout else Vector2(42,42)
	_fold.add_theme_constant_override("icon_max_width",44 if mobile_layout else 24)
	_body.add_theme_constant_override("separation",6 if mobile_layout else 8)
	for button in _tabs.values():
		button.custom_minimum_size = Vector2(180,96) if mobile_layout else Vector2(112,64)
		button.add_theme_constant_override("icon_max_width",52 if mobile_layout else 27)
		for child in button.get_children():
			if child is Label:
				child.add_theme_font_size_override("font_size",roundi((30 if mobile_layout else 18)*UI.text_scale))
				child.offset_top = -42 if mobile_layout else -30

func select_page(id: String) -> void:
	page = id
	drawer_open = true
	panel.show()
	_saved_scroll = 0
	_focus_id = ""
	_rebuild()
	_tabs[id].grab_focus()

func show_actions(_at: Vector2 = Vector2.ZERO) -> void:
	select_page("actions")

func toggle_drawer() -> void:
	if drawer_open: hide_drawer()
	else: select_page(page)

func hide_drawer() -> void:
	drawer_open = false
	if is_instance_valid(panel): panel.hide()
	navigation_changed.emit()

func _category(id: String) -> String:
	if id.begins_with("person.") or id == "screen.people": return "people"
	if id.begins_with("route.") or id == "screen.map": return "places"
	return "actions"

func _rebuild() -> void:
	UI.clear(_body)
	buttons.clear()
	_title.text = {"actions":"Действия","people":"Люди рядом","places":"Переходы"}[page]
	for id in _tabs:
		_tabs[id].modulate = UI.BLUE if id == page else UI.MUTED
	for action in actions:
		if _category(action.id) != page: continue
		var button := UI.button(_body,str(action.caption).replace("  →","").replace("\n"," · "),action.callback)
		button.set_meta("scene_action",action.id)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 104 if mobile_layout else 60
		button.add_theme_font_size_override("font_size",roundi((36 if mobile_layout else 23)*UI.text_scale))
		button.tooltip_text = action.hint
		HUD.action_card(button,str(action.kind),mobile_layout)
		buttons[action.id] = button
	if buttons.is_empty(): UI.label(_body,"Здесь пока никого нет." if page == "people" else "Пока нет доступных вариантов.",32 if mobile_layout else 19,UI.MUTED)
	_fit.call_deferred()
	panel.visible = drawer_open
	_restore.call_deferred()
	_wire_navigation.call_deferred()

func _fit() -> void:
	if not is_inside_tree(): return
	# This layer ends above the dock; a small overlap keeps the palette near its toggle.
	var dock_clearance := -10.0 if mobile_layout else -25.0
	var header_and_tabs := 190.0 if mobile_layout else 112.0
	var visible_rows := mini(buttons.size(),3 if mobile_layout else 5)
	var row_height := 104.0 if mobile_layout else 60.0
	var row_spacing := 14.0
	var desired := header_and_tabs+visible_rows*row_height+maxi(0,visible_rows-1)*row_spacing+36.0
	var height := minf(desired,maxf(180.0,size.y-dock_clearance-24.0))
	panel.offset_top = -dock_clearance-height
	panel.offset_bottom = -dock_clearance

func _restore() -> void:
	if not is_inside_tree(): return
	_scroll.scroll_vertical = _saved_scroll
	if drawer_open and buttons.has(_focus_id) and buttons[_focus_id].is_visible_in_tree(): buttons[_focus_id].grab_focus()

func _wire_navigation() -> void:
	if not is_inside_tree(): return
	# Containers finish arranging the new rows before directional paths are measured.
	await get_tree().process_frame
	if not is_inside_tree(): return
	# The shell owns the HUD focus graph; rows are replaced when a tab changes.
	navigation_changed.emit()
	var rows: Array = buttons.values() if drawer_open else []
	var tabs: Array = _tabs.values()
	for index in range(tabs.size()):
		var tab: Button = tabs[index]
		tab.focus_neighbor_left = tab.get_path_to(tabs[(index+tabs.size()-1)%tabs.size()])
		tab.focus_neighbor_right = tab.get_path_to(tabs[(index+1)%tabs.size()])
		if not rows.is_empty(): tab.focus_neighbor_top = tab.get_path_to(rows.back())
	for index in range(rows.size()):
		var row: Button = rows[index]
		if index > 0: row.focus_neighbor_top = row.get_path_to(rows[index-1])
		row.focus_neighbor_bottom = row.get_path_to(rows[index+1] if index+1 < rows.size() else _tabs[page])
