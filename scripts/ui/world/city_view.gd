extends Control
## A schematic view of the active city graph. It does not supply street-level artwork.
signal travel_requested(id: String)
signal close_requested
const City = preload("res://scripts/gameplay/city_layout.gd")
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
var selected := ""
var map_mode := false
var markers: Dictionary = {}
var _sim: Variant
var _graph: Dictionary = {}
var _pins: Control
var _card: PanelContainer
var _heading: Label
var _map_rect := Rect2()
var _path: Array = []

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true
    theme = UI.skin()
    _heading = UI.label(self,"Город · схема",20,UI.BLUE)
    _heading.position = Vector2(32,78)
    _heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _pins = Control.new()
    _pins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _pins.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_pins)
    _card = PanelContainer.new()
    _card.add_theme_stylebox_override("panel",UI.surface(16))
    add_child(_card)
    resized.connect(_layout)

func present(sim, show_map: bool) -> void:
    _sim = sim
    map_mode = show_map
    _graph = City.data(sim.catalog)
    _heading.visible = show_map
    _pins.visible = show_map
    _card.visible = show_map
    UI.clear(_pins)
    markers.clear()
    _path.clear()
    if not show_map:
        queue_redraw()
        return
    var current := City.map_location(sim.catalog,sim.state)
    for point in City.points(sim.catalog):
        var id := str(point.id)
        var button := Button.new()
        button.text = str(point.title)
        button.clip_text = true
        button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        button.add_theme_font_size_override("font_size",roundi(15*UI.text_scale))
        button.add_theme_stylebox_override("normal",UI.style(Color(0.015,0.035,0.05,0.96),UI.ORANGE if id == current else UI.MUTED))
        button.tooltip_text = str(point.title)
        button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        button.pressed.connect(select.bind(id))
        button.set_meta("city_destination",id)
        _pins.add_child(button)
        markers[id] = button
    if not markers.has(selected):
        selected = current if markers.has(current) else str(markers.keys()[0]) if not markers.is_empty() else ""
    if selected.is_empty():
        UI.clear(_card)
        UI.label(_card_content(),"На схеме пока нет доступных меток.",18,UI.MUTED)
    else: select(selected)
    _layout()

func select(id: String) -> void:
    if _sim == null or not markers.has(id): return
    var point := City.point(_sim.catalog,id)
    if point.is_empty(): return
    selected = id
    _path.clear()
    UI.clear(_card)
    var content := _card_content()
    UI.label(content,"ГОРОД · СХЕМА",13,UI.BLUE)
    UI.label(content,str(point.title),23)
    UI.label(content,"Линии показывают связи мест. Время пути рассчитывается по маршруту.",16,UI.MUTED)
    var current := City.map_location(_sim.catalog,_sim.state) == id
    var route: Dictionary = _sim.services.world.route(id)
    if route.ok:
        _path = route.data.path.duplicate()
        UI.label(content,"Вы здесь" if current else "%d мин пешком · выносливость −%.1f" % [int(route.data.minutes),float(route.data.minutes)*0.15],17,UI.ORANGE if current else UI.BLUE)
    else: UI.label(content,Names.error(str(route.get("error","city_route_unavailable"))),17,UI.ORANGE)
    var go := UI.button(content,"К СЦЕНЕ" if current else "ИДТИ  →",close_requested.emit if current else _go)
    go.disabled = not current and not route.ok
    if not current and route.ok and float(_sim.state.player.needs.energy) < float(route.data.minutes)*0.15:
        go.disabled = true
        UI.label(content,"Нужно восстановить выносливость.",16,UI.ORANGE)
    go.set_meta("city_confirm",id)
    go.tooltip_text = "Вернуться к сцене" if current else "Подтвердить переход. Город продолжит жить во время дороги."
    UI.label(content,"Выберите место на схеме.\nM / Esc — вернуться к сцене",14,UI.MUTED)
    for marker_id in markers: markers[marker_id].modulate = UI.ORANGE if marker_id == id else Color.WHITE
    _layout()

func _card_content() -> VBoxContainer:
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    scroll.follow_focus = true
    _card.add_child(scroll)
    var content := UI.column(scroll,9)
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return content

func _go() -> void:
    if _sim == null or not markers.has(selected): return
    var route: Dictionary = _sim.services.world.route(selected)
    if not route.ok or float(_sim.state.player.needs.energy) < float(route.data.minutes)*0.15:
        select(selected)
        return
    travel_requested.emit(selected)

func _layout() -> void:
    if _sim == null or not map_mode or size.x <= 0.0 or size.y <= 0.0: return
    _heading.size = Vector2(maxf(0,size.x-64),36*UI.text_scale)
    var stacked := size.x < 900.0
    var card_width := size.x-48.0 if stacked else minf(300.0,size.x-48.0)
    var card_height := minf(288.0,size.y*0.4) if stacked else minf(520.0,size.y-140.0)
    var area := Rect2(24,116,maxf(180,size.x-372),maxf(180,size.y-160))
    if stacked: area = Rect2(24,116,maxf(180,size.x-48),maxf(160,size.y-card_height-164))
    var reference: Array = _graph.map.reference_size_px
    var reference_size := Vector2(float(reference[0]),float(reference[1]))
    var factor := minf(area.size.x/reference_size.x,area.size.y/reference_size.y)
    _map_rect = Rect2(area.get_center()-reference_size*factor*0.5,reference_size*factor)
    _card.position = Vector2(24,size.y-card_height-24) if stacked else Vector2(size.x-card_width-24,116)
    _card.size = Vector2(card_width,card_height)
    var ids: Array = markers.keys()
    ids.sort_custom(func(a,b):
        var ua: Array = _graph.locations[a].map.position_uv
        var ub: Array = _graph.locations[b].map.position_uv
        return float(ua[0]) < float(ub[0]) if ua[1] == ub[1] else float(ua[1]) < float(ub[1]))
    if ids.is_empty(): queue_redraw(); return
    var first: Button = markers[ids[0]]
    var dimensions := Vector2(minf(166*UI.text_scale,(_map_rect.size.x-32.0)/4.0),maxf(34*UI.text_scale,first.get_combined_minimum_size().y))
    var columns := maxi(1,floori((_map_rect.size.x+8.0)/(dimensions.x+8.0)))
    var rows := maxi(1,floori((_map_rect.size.y+8.0)/(dimensions.y+8.0)))
    var slots: Array[Rect2] = []
    for row in rows:
        for column in columns:
            var center := _map_rect.position+Vector2((column+0.5)*_map_rect.size.x/columns,(row+0.5)*_map_rect.size.y/rows)
            slots.append(Rect2(center-dimensions*0.5,dimensions))
    for id in ids:
        var anchor: Vector2 = _position(str(id))
        var button: Button = markers[id]
        var best_index := 0
        var best_score := INF
        for index in slots.size():
            var score := anchor.distance_squared_to(slots[index].get_center())
            if score < best_score: best_index = index; best_score = score
        if slots.is_empty(): continue
        button.position = slots[best_index].position
        button.size = dimensions
        slots.remove_at(best_index)
    queue_redraw()

func _position(id: String) -> Variant:
    if not _graph.locations.has(id): return null
    var point: Dictionary = _graph.locations[id]
    if point.map.get("offscreen",false): return null
    var uv: Array = point.map.position_uv
    return _map_rect.position+Vector2(float(uv[0]),float(uv[1]))*_map_rect.size

func _draw() -> void:
    if not map_mode or _graph.is_empty() or _map_rect.size.x <= 0: return
    draw_rect(Rect2(Vector2.ZERO,size),Color("07121c"))
    draw_rect(_map_rect,Color("0e202d"))
    draw_rect(_map_rect,Color("4b687b"),false,1)
    var band: Array = _graph.map.river_band_uv
    var river := Rect2(_map_rect.position+Vector2(0,float(band[0]))*_map_rect.size,Vector2(_map_rect.size.x,float(band[1]-band[0])*_map_rect.size.y))
    draw_rect(river,Color("163c53"))
    for edge in _graph.routes:
        var a: Dictionary = _graph.locations[edge.from_id]
        var b: Dictionary = _graph.locations[edge.to_id]
        if a.kind != "public_exterior" or b.kind != "public_exterior": continue
        var start: Variant = _position(str(edge.from_id))
        var finish: Variant = _position(str(edge.to_id))
        if start is Vector2 and finish is Vector2: draw_line(start,finish,Color("355366"),1.4,true)
    var previous: Variant = _position(City.map_location(_sim.catalog,_sim.state))
    for id in _path:
        var position: Variant = _position(str(id))
        if position is Vector2:
            if previous is Vector2 and previous != position: draw_line(previous,position,UI.ORANGE,3.0,true)
            previous = position
    var current := City.map_location(_sim.catalog,_sim.state)
    for id in markers:
        var anchor: Vector2 = _position(str(id))
        var button: Button = markers[id]
        draw_line(anchor,button.position+button.size*0.5,Color(0.62,0.78,0.9,0.45),1,true)
        draw_circle(anchor,5,UI.ORANGE if id == current else UI.BLUE)
