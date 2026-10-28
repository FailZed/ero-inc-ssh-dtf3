extends VBoxContainer
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const W = preload("res://scripts/ui/gameplay/game_widgets.gd")
const Social = preload("res://scripts/gameplay/social_presentation.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Portrait = preload("res://scripts/ui/gameplay/resident_preview.gd")
var owner_ui: Control
var _list: VBoxContainer
var _detail: VBoxContainer
var _selected := ""
var _buttons: Dictionary = {}

func _ready() -> void:
	add_theme_constant_override("separation",14)
	var tools := UI.row(self)
	var search := LineEdit.new()
	search.placeholder_text = "Найти человека…"
	search.set_meta("input_id","people_search")
	search.text = owner_ui._people_query
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(240,46)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(value): owner_ui._people_query = value; _populate())
	tools.add_child(search)
	UI.button(tools,"Встретиться компанией",owner_ui.open_panel.bind("gathering"))
	W.tabs(self,{"all":"Все", "contacts":"Знакомые", "nearby":"Рядом"},owner_ui._people_filter,func(id): owner_ui._people_filter = id; _populate())
	var columns := UI.row(self,26)
	var roster := ScrollContainer.new()
	roster.custom_minimum_size = Vector2(350,430)
	roster.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster.follow_focus = true
	columns.add_child(roster)
	_list = UI.column(roster,6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail = UI.column(columns,16)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selected = str(owner_ui._screen_state.get("people_selected",""))
	_populate()

func _populate() -> void:
	UI.clear(_list)
	_buttons.clear()
	var sim = Gameplay.simulation
	var ids: Array = sim.state.social.npcs.keys()
	ids.sort_custom(func(a,b): return float(Social.bond(sim,str(a)).closeness) > float(Social.bond(sim,str(b)).closeness))
	var shown: Array[String] = []
	for id in ids:
		var npc: Dictionary = sim.state.social.npcs[id]
		if not owner_ui._people_query.is_empty() and not str(npc.name).to_lower().contains(owner_ui._people_query.to_lower()): continue
		if owner_ui._people_filter == "contacts" and not id in sim.state.social.contacts: continue
		if owner_ui._people_filter == "nearby" and npc.location != sim.state.world.location: continue
		shown.append(str(id))
		var button := UI.button(_list,str(npc.name),_select.bind(str(id)))
		button.custom_minimum_size.y = 58
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.set_meta("person_id",id)
		_buttons[id] = button
	if not _selected in shown: _selected = shown[0] if not shown.is_empty() else ""
	if shown.is_empty(): W.empty(_list,"people","Никого не найдено","Измените фильтр или имя.")
	_present()

func _select(id: String) -> void:
	_selected = id
	owner_ui._screen_state.people_selected = id
	_present()
	if _buttons.has(id): _buttons[id].grab_focus()

func _present() -> void:
	UI.clear(_detail)
	for id in _buttons: _buttons[id].modulate = UI.BLUE if id == _selected else Color.WHITE
	if _selected.is_empty(): W.empty(_detail,"people","Знакомства начинаются со встречи"); return
	var sim = Gameplay.simulation
	var npc: Dictionary = sim.state.social.npcs[_selected]
	var bond := Social.bond(sim,_selected)
	var life := Social.life(sim,_selected)
	var row := UI.row(_detail,28)
	var picture := Portrait.new()
	picture.custom_minimum_size = Vector2(220,310)
	picture.set_actor(npc)
	row.add_child(picture)
	var info := UI.column(row,14)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.label(info,str(npc.name),32)
	UI.label(info,str(bond.status_text),20,UI.BLUE)
	UI.label(info,str(life.emotion),18,UI.MUTED)
	UI.label(info,str(life.location),18,UI.MUTED)
	UI.label(info,str(life.activity),18,UI.MUTED)
	preload("res://scripts/ui/gameplay/social_status.gd").employment(info,sim,_selected)
	if npc.location == sim.state.world.location: W.primary(info,"Поговорить",owner_ui._open_npc.bind(_selected))
	elif _selected in sim.state.social.contacts: W.primary(info,"Написать",owner_ui._open_conversation.bind(_selected,"message"))
	else: UI.button(info,"Открыть карту",owner_ui.open_panel.bind("map"))
	UI.button(info,"Об отношениях",owner_ui._show_npc_details.bind(_selected))
	UI.label(_detail,"Чем сейчас живёт",17,UI.BLUE)
	UI.label(_detail,str(life.goal),23)
	UI.label(_detail,"Этап %d из %d" % [life.stage,life.stages],16,UI.MUTED)
	var pregnancy: Dictionary = sim.services.reproduction.pregnancy(_selected)
	var wellbeing: Dictionary = sim.services.pregnancy_wellbeing.view(_selected)
	if (not pregnancy.is_empty() and pregnancy.known) or (not wellbeing.is_empty() and wellbeing.phase=="postpartum"):
		preload("res://scripts/ui/gameplay/pregnancy_wellbeing_panel.gd").populate(owner_ui,_detail,_selected)
