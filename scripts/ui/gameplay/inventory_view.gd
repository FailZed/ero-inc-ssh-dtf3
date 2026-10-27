extends VBoxContainer
## Search and selection are presentation state; browsing never executes a command.
signal action_requested(module_id: String, operation: String, args: Dictionary)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Art = preload("res://scripts/ui/gameplay/item_art.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const FILTERS := {"all":"Всё", "food":"Еда", "clothes":"Одежда", "equipment":"Для дома", "other":"Другое"}
var sim
var view_state: Dictionary = {"query":"", "filter":"all", "selected":"", "sort":0}
var _grid: GridContainer
var _detail: VBoxContainer
var _count: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_theme_constant_override("separation", 18)
	var tools := UI.row(self)
	var search := LineEdit.new()
	search.placeholder_text = "Поиск в сумке…"
	search.set_meta("input_id","inventory_search")
	search.text = str(view_state.query)
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(180, 48)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(value): view_state.query = value; _populate())
	tools.add_child(search)
	var sort := OptionButton.new()
	for title in ["По названию", "Сначала тяжёлые", "По количеству"]: sort.add_item(title)
	sort.select(int(view_state.sort))
	sort.item_selected.connect(func(index): view_state.sort = index; _populate())
	tools.add_child(sort)
	var filters := UI.row(self, 6)
	var group := ButtonGroup.new()
	for id in FILTERS:
		var button := UI.button(filters, FILTERS[id], func(): view_state.filter = id; _populate())
		button.toggle_mode = true
		button.button_group = group
		button.set_pressed_no_signal(view_state.filter == id)
		button.custom_minimum_size.y = 38
	_count = UI.label(self, "", 15, UI.MUTED)
	var columns := UI.row(self, 24)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	columns.add_child(_grid)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 340
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.8
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(panel)
	_detail = UI.column(panel, 14)
	_populate()

func _category(item: Dictionary) -> String:
	if item.has("slot"): return "clothes"
	if item.has("equipment"): return "equipment"
	if item.get("category", "") == "food": return "food"
	return "other"

func _populate() -> void:
	UI.clear(_grid)
	var items: Array[String] = []
	for id in sim.state.inventory.items:
		if int(sim.state.inventory.items[id]) <= 0: continue
		if view_state.filter != "all" and _category(sim.catalog.items[id]) != view_state.filter: continue
		if not str(view_state.query).is_empty() and not Names.title(id).to_lower().contains(str(view_state.query).to_lower()): continue
		items.append(str(id))
	items.sort_custom(func(a, b):
		if int(view_state.sort) == 1: return float(sim.catalog.items[a].get("weight", 0)) > float(sim.catalog.items[b].get("weight", 0))
		if int(view_state.sort) == 2: return int(sim.state.inventory.items[a]) > int(sim.state.inventory.items[b])
		return Names.title(a).naturalnocasecmp_to(Names.title(b)) < 0)
	_count.text = "%d предметов · вес %.1f / %.1f кг" % [items.size(), sim.services.inventory.weight(), sim.services.inventory.capacity()]
	if not str(view_state.selected) in items: view_state.selected = items[0] if not items.is_empty() else ""
	for id in items:
		var item: Dictionary = sim.catalog.items[id]
		var button := UI.button(_grid, "", func(): view_state.selected = id; _populate(); _focus_item(id))
		button.set_meta("item_id", id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(116, 132)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = Art.texture(id, item)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 78)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("h_separation", 16)
		button.add_theme_font_size_override("font_size", 18)
		button.tooltip_text = Names.title(id) + " · открыть описание и действия"
		var tile := UI.style(Color("132531"), Color("385566"))
		tile.set_border_width_all(1)
		if id == view_state.selected:
			button.set_meta("initial_focus",true)
			tile.bg_color = Color("284657")
			tile.border_color = UI.BLUE
		button.add_theme_stylebox_override("normal", tile)
		var count := UI.label(button, "× %d" % sim.state.inventory.items[id], 15)
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -52
		count.offset_right = -8
		count.offset_top = -28
		count.offset_bottom = -5
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if items.is_empty(): UI.label(_grid, "Ничего не найдено.\nИзмените поиск или категорию.", 20, UI.MUTED)
	else:
		for index in range(maxi(0, 15 - items.size())):
			var slot := PanelContainer.new()
			slot.custom_minimum_size = Vector2(116, 132)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot.add_theme_stylebox_override("panel", UI.style(Color(0.06,0.10,0.13,0.48), Color(0.25,0.36,0.43,0.25)))
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_grid.add_child(slot)
	_show_detail()

func _focus_item(id: String) -> void:
	for child in _grid.get_children():
		if child.get_meta("item_id", "") == id: child.grab_focus()

func _show_detail() -> void:
	UI.clear(_detail)
	var id := str(view_state.selected)
	if id.is_empty():
		UI.label(_detail, "Выберите предмет в сумке", 24)
		return
	var item: Dictionary = sim.catalog.items[id]
	var art := TextureRect.new()
	art.texture = Art.texture(id, item)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = 164
	_detail.add_child(art)
	UI.label(_detail, Names.title(id), 30)
	UI.label(_detail, str(FILTERS[_category(item)]).to_upper(), 14, UI.MUTED)
	UI.label(_detail, "%d шт.   ·   %.1f кг / шт." % [sim.state.inventory.items[id], float(item.get("weight", 0))], 17, UI.MUTED)
	if item.has("restore"):
		for need in item.restore: UI.label(_detail, "%s  +%d" % [Names.title(need), roundi(float(item.restore[need]))], 18, UI.BLUE)
	if item.has("restore") or item.has("effect"):
		var use := W.primary(_detail, "Поесть · 5 мин" if item.get("category", "") == "food" else "Использовать", func(): action_requested.emit("inventory", "use", {"id":id}))
		use.set_meta("gameplay_action",{"module":"inventory","operation":"use","args":{"id":id}})
	if item.has("slot"):
		var equip := W.primary(_detail, "Надеть", func(): action_requested.emit("appearance", "equip", {"id":id}))
		equip.set_meta("gameplay_action",{"module":"appearance","operation":"equip","args":{"id":id}})
	if item.has("equipment"):
		var residence := str(sim.state.housing.residence)
		var home: bool = sim.state.world.location in ["bedroom","kitchen","bathroom","apartment_hall"] and not residence.is_empty()
		var install := UI.button(_detail, "УСТАНОВИТЬ ДОМА", func(): action_requested.emit("housing", "furnish", {"id":residence,"item":id}))
		install.set_meta("gameplay_action",{"module":"housing","operation":"furnish","args":{"id":residence,"item":id}})
		install.disabled = not home
		if not home: UI.label(_detail, "Установка доступна в вашем доме.", 16, UI.ORANGE)
