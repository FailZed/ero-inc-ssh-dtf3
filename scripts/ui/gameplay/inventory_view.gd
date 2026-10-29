extends VBoxContainer
## Compact item list and contextual actions. Selecting or filtering never uses an item.
signal action_requested(module_id: String, operation: String, args: Dictionary)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Art = preload("res://scripts/ui/gameplay/item_art.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const FILTERS := {"all":"Все вещи","food":"Еда","clothes":"Одежда","equipment":"Для дома","other":"Другое"}
var sim
var view_state: Dictionary = {"query":"", "filter":"all", "selected":"", "sort":0}
var _grid: GridContainer
var _detail: VBoxContainer
var _count: Label
var _tools: Array[Control] = []
var _compact_landscape := false

func _ready() -> void:
	var window_size := DisplayServer.window_get_size()
	_compact_landscape = window_size.x > window_size.y and window_size.x <= 1100
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tools := UI.row(self,10)
	var search := LineEdit.new()
	search.placeholder_text = "Найти вещь…"
	search.set_meta("input_id","inventory_search")
	search.text = str(view_state.query)
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(180,84 if _compact_landscape else 44)
	if _compact_landscape: search.add_theme_font_size_override("font_size",roundi(30*UI.text_scale))
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(value): view_state.query = value; _populate())
	tools.add_child(search)
	var filter := OptionButton.new()
	filter.set_meta("input_id","inventory_filter")
	for id in FILTERS:
		filter.add_item(FILTERS[id])
		filter.set_item_metadata(filter.item_count-1,id)
		if id == view_state.filter: filter.select(filter.item_count-1)
	filter.item_selected.connect(func(index): view_state.filter = str(filter.get_item_metadata(index)); _populate())
	if _compact_landscape:
		filter.custom_minimum_size.y = 84
		filter.add_theme_font_size_override("font_size",roundi(30*UI.text_scale))
	tools.add_child(filter)
	var sort := OptionButton.new()
	sort.set_meta("input_id","inventory_sort")
	for title in ["По названию","По весу","По количеству"]: sort.add_item(title)
	sort.select(int(view_state.sort))
	sort.item_selected.connect(func(index): view_state.sort = index; _populate())
	if _compact_landscape:
		sort.custom_minimum_size.y = 84
		sort.add_theme_font_size_override("font_size",roundi(30*UI.text_scale))
	tools.add_child(sort)
	_tools.assign([search,filter,sort])
	_count = UI.label(self,"",30 if _compact_landscape else 17,UI.INK if _compact_landscape else UI.MUTED)
	var columns := UI.row(self,32)
	var list := UI.column(columns,6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := UI.row(list)
	UI.label(heading,"Вещь",28 if _compact_landscape else 18,UI.INK if _compact_landscape else UI.MUTED)
	var quantity := UI.label(heading,"Кол.",28 if _compact_landscape else 18,UI.INK if _compact_landscape else UI.MUTED)
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity.custom_minimum_size.x = 60
	quantity.size_flags_horizontal = Control.SIZE_SHRINK_END
	var weight := UI.label(heading,"Вес",28 if _compact_landscape else 18,UI.INK if _compact_landscape else UI.MUTED)
	weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weight.custom_minimum_size.x = 82
	weight.size_flags_horizontal = Control.SIZE_SHRINK_END
	_grid = GridContainer.new()
	_grid.columns = 1
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("v_separation",3)
	list.add_child(_grid)
	_detail = UI.column(columns,12)
	_detail.custom_minimum_size.x = 360
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_stretch_ratio = 0.65
	_populate()

func _category(item: Dictionary) -> String:
	if item.has("slot"): return "clothes"
	if item.has("equipment"): return "equipment"
	if item.get("category","") == "food": return "food"
	return "other"

func _populate() -> void:
	UI.clear(_grid)
	var items: Array[String] = []
	for id in sim.state.inventory.items:
		if int(sim.state.inventory.items[id]) <= 0: continue
		if view_state.filter != "all" and _category(sim.catalog.items[id]) != view_state.filter: continue
		if not str(view_state.query).is_empty() and not Names.title(id).to_lower().contains(str(view_state.query).to_lower()): continue
		items.append(str(id))
	items.sort_custom(func(a,b):
		if int(view_state.sort) == 1: return float(sim.catalog.items[a].get("weight",0)) > float(sim.catalog.items[b].get("weight",0))
		if int(view_state.sort) == 2: return int(sim.state.inventory.items[a]) > int(sim.state.inventory.items[b])
		return Names.title(a).naturalnocasecmp_to(Names.title(b)) < 0)
	_count.text = "В сумке: %d · вес %.1f / %.1f кг" % [items.size(),sim.services.inventory.weight(),sim.services.inventory.capacity()]
	if not str(view_state.selected) in items: view_state.selected = items[0] if not items.is_empty() else ""
	for id in items:
		var item: Dictionary = sim.catalog.items[id]
		var wearing: bool = id in sim.state.inventory.equipped.values()
		var button := UI.button(_grid,Names.title(id)+(" · надето" if wearing else ""),func(): view_state.selected = id; _populate(); _focus_item(id))
		button.set_meta("item_id",id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 88 if _compact_landscape else 54
		button.icon = Art.texture(id,item)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width",54 if _compact_landscape else 34)
		button.add_theme_constant_override("h_separation",12)
		button.add_theme_font_size_override("font_size",roundi((30 if _compact_landscape else 20)*UI.text_scale))
		button.tooltip_text = Names.title(id)+" · описание и действия"
		var style := UI.style(Color("183248") if id == view_state.selected else Color(0.025,0.05,0.07,0.48),UI.BLUE if id == view_state.selected else Color(0.3,0.45,0.55,0.25))
		style.content_margin_right = 170
		button.add_theme_stylebox_override("normal",style)
		for state in ["hover","pressed","focus","disabled"]:
			var padded: StyleBox = button.get_theme_stylebox(state).duplicate()
			padded.content_margin_right = 170
			button.add_theme_stylebox_override(state,padded)
		if id == view_state.selected: button.set_meta("initial_focus",true)
		var values := HBoxContainer.new()
		values.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		values.offset_left = -158
		values.offset_right = -12
		values.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(values)
		for value in [str(sim.state.inventory.items[id]),"%.2f" % float(item.get("weight",0))]:
			var label := UI.label(values,value,28 if _compact_landscape else 18,UI.INK if _compact_landscape else UI.MUTED)
			label.custom_minimum_size.x = 60
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if items.is_empty(): UI.label(_grid,"Ничего не найдено. Измените поиск или категорию.",20,UI.MUTED)
	_show_detail()
	_wire_navigation()

func _wire_navigation() -> void:
	var rows: Array[Control] = []
	var selected: Control
	for row in _grid.get_children():
		if not row is Button: continue
		rows.append(row)
		if row.get_meta("item_id","") == view_state.selected: selected = row
	var actions: Array[Control] = []
	for button in _detail.find_children("*","Button",true,false):
		if not button.disabled: actions.append(button)
	var order: Array[Control] = _tools.duplicate()
	order.append_array(rows)
	order.append_array(actions)
	# Only link the internal sequence; its ends keep normal navigation to Back/HUD.
	for index in range(order.size()):
		var control := order[index]
		control.focus_previous = control.get_path_to(order[index-1]) if index > 0 else NodePath("")
		control.focus_next = control.get_path_to(order[index+1]) if index+1 < order.size() else NodePath("")
	for index in range(rows.size()):
		var row := rows[index]
		row.focus_neighbor_top = row.get_path_to(rows[index-1] if index > 0 else _tools.back())
		if index+1 < rows.size(): row.focus_neighbor_bottom = row.get_path_to(rows[index+1])
		elif not actions.is_empty(): row.focus_neighbor_bottom = row.get_path_to(actions.front())
		if not actions.is_empty(): row.focus_neighbor_right = row.get_path_to(actions.front())
	for tool in _tools: tool.focus_neighbor_bottom = tool.get_path_to(selected if selected != null else tool)
	if selected != null:
		for action in actions: action.focus_neighbor_left = action.get_path_to(selected)

func _focus_item(id: String) -> void:
	for child in _grid.get_children():
		if child.get_meta("item_id","") == id: child.grab_focus()

func _action(caption: String, module_id: String, operation: String, args: Dictionary) -> Button:
	var button := W.primary(_detail,caption,func(): action_requested.emit(module_id,operation,args))
	if _compact_landscape:
		button.custom_minimum_size.y = 84
		button.add_theme_font_size_override("font_size",roundi(30*UI.text_scale))
	button.set_meta("gameplay_action",{"module":module_id,"operation":operation,"args":args})
	return button

func _show_detail() -> void:
	UI.clear(_detail)
	var id := str(view_state.selected)
	if id.is_empty():
		UI.label(_detail,"Выберите вещь",34 if _compact_landscape else 24,UI.MUTED)
		return
	var item: Dictionary = sim.catalog.items[id]
	var identity := UI.row(_detail,14)
	var art := TextureRect.new()
	art.texture = Art.texture(id,item)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(72,72)
	identity.add_child(art)
	UI.label(identity,Names.title(id),36 if _compact_landscape else 27)
	UI.label(_detail,"%s · %d шт. · %.2f кг за вещь" % [FILTERS[_category(item)],int(sim.state.inventory.items[id]),float(item.get("weight",0))],30 if _compact_landscape else 18,UI.INK if _compact_landscape else UI.MUTED)
	if item.has("description"): UI.label(_detail,str(item.description),30 if _compact_landscape else 20)
	for need in item.get("restore",{}): UI.label(_detail,"%s +%d" % [Names.title(need),roundi(float(item.restore[need]))],30 if _compact_landscape else 19,UI.BLUE)
	if item.has("restore") or item.has("effect"):
		_action("Поесть · 5 мин" if item.get("category","") == "food" else "Использовать","inventory","use",{"id":id})
	if id == "book" and sim.catalog.actions.has("read"):
		_action("Почитать · %d мин" % int(sim.catalog.actions.read.get("minutes",30)),"actions","perform",{"id":"read"})
	if item.has("slot"):
		var worn: bool = sim.state.inventory.equipped.get(str(item.slot),"") == id
		if worn: _action("Убрать" if item.slot == "weapon" else "Снять","appearance","unequip",{"slot":str(item.slot)})
		else:
			var equip := _action("Взять в руки" if item.slot == "weapon" else "Надеть","appearance","equip",{"id":id})
			equip.disabled = not Rules.check(sim.state,item.get("requirements",{}))
			if equip.disabled: UI.label(_detail,"Пока не хватает характеристик для этой вещи.",18,UI.ORANGE)
	if item.has("equipment"):
		var residence := str(sim.state.housing.residence)
		var home: bool = sim.is_player_home_location(str(sim.state.world.location)) and not residence.is_empty()
		var installed: bool = sim.state.housing.properties.get(residence,{}).get("equipment",{}).has(id)
		var install := _action("Уже установлено" if installed else "Установить дома","housing","furnish",{"id":residence,"item":id})
		install.disabled = not home or installed
		if not home: UI.label(_detail,"Можно установить у себя дома.",18,UI.MUTED)
