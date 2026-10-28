extends Control
## One small contextual drawer. Only existing shell callbacks execute game actions.
signal navigation_changed
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var actions: Array[Dictionary] = []
var buttons: Dictionary = {}
var page := "actions"
var collapsed := false
var panel: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _tabs: Dictionary = {}
var _location := ""
var _saved_scroll := 0
var _focus_id := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "SceneInteraction"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -380
	panel.offset_right = 0
	panel.add_theme_stylebox_override("panel",UI.surface(14))
	add_child(panel)
	var column := UI.column(panel,8)
	var header := UI.row(column,8)
	_title = UI.label(header,"Действия",23)
	var fold := UI.button(header,"−",func(): collapsed = not collapsed; _rebuild())
	fold.custom_minimum_size = Vector2(36,32)
	fold.tooltip_text = "Свернуть или раскрыть панель"
	HUD.quiet_button(fold)
	_body = UI.scroller(column)
	_scroll = _body.get_parent()
	_body.minimum_size_changed.connect(func(): _fit.call_deferred())
	var tabs := UI.row(column,6)
	for spec in [["actions","Действия","desk"],["people","Люди рядом","people"],["places","Куда пойти","map"]]:
		var button := HUD.dock_button(tabs,spec[1],"",spec[2],select_page.bind(spec[0]))
		button.custom_minimum_size = Vector2(64,42)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs[spec[0]] = button
	resized.connect(_fit)
	resized.connect(_wire_navigation)

func begin(location: String, _texture: Texture2D) -> void:
	_saved_scroll = _scroll.scroll_vertical
	var focused := get_viewport().gui_get_focus_owner()
	_focus_id = str(focused.get_meta("scene_action","")) if focused != null else ""
	if location != _location: _saved_scroll = 0
	_location = location
	actions.clear()

func add_action(id: String, caption: String, callback: Callable, hint: String) -> Button:
	actions.append({"id":id,"caption":caption,"callback":callback,"hint":hint})
	return null

func finish() -> void:
	_rebuild()

func select_page(id: String) -> void:
	page = id
	collapsed = false
	_saved_scroll = 0
	_focus_id = ""
	_rebuild()
	_tabs[id].grab_focus()

func show_actions(_at: Vector2 = Vector2.ZERO) -> void:
	select_page("actions")

func _category(id: String) -> String:
	if id.begins_with("person.") or id == "screen.people": return "people"
	if id.begins_with("route.") or id == "screen.map": return "places"
	return "actions"

func _rebuild() -> void:
	UI.clear(_body)
	buttons.clear()
	_title.text = {"actions":"Действия","people":"Люди рядом","places":"Куда пойти"}[page]
	_scroll.visible = not collapsed
	for id in _tabs:
		_tabs[id].modulate = UI.BLUE if id == page else UI.MUTED
	for action in actions:
		if _category(action.id) != page: continue
		var button := UI.button(_body,str(action.caption).replace("  →","").replace("\n"," · "),action.callback)
		button.set_meta("scene_action",action.id)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 42
		button.add_theme_font_size_override("font_size",roundi(19*UI.text_scale))
		button.tooltip_text = action.hint
		HUD.quiet_button(button)
		buttons[action.id] = button
	if buttons.is_empty(): UI.label(_body,"Здесь пока никого нет." if page == "people" else "Пока нет доступных вариантов.",19,UI.MUTED)
	_fit.call_deferred()
	_restore.call_deferred()
	_wire_navigation.call_deferred()

func _fit() -> void:
	if not is_inside_tree(): return
	var height := 100.0 if collapsed else clampf(130+_body.get_combined_minimum_size().y,220,minf(480,size.y-8))
	panel.offset_top = -height
	panel.offset_bottom = 0

func _restore() -> void:
	if not is_inside_tree(): return
	_scroll.scroll_vertical = _saved_scroll
	if buttons.has(_focus_id) and buttons[_focus_id].is_visible_in_tree(): buttons[_focus_id].grab_focus()

func _wire_navigation() -> void:
	if not is_inside_tree(): return
	# Containers finish arranging the new rows before directional paths are measured.
	await get_tree().process_frame
	if not is_inside_tree(): return
	# The shell owns the HUD focus graph; rows are replaced when a tab changes.
	navigation_changed.emit()
	var rows: Array = [] if collapsed else buttons.values()
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
