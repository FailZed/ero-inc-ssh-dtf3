extends Control
signal cell_selected(cell: Vector2i)
var dimensions := Vector2i(8,6)
var plan: Array = []
var _cursor := Vector2i(-1,-1)
var selected_item := ""
var footprint := Vector2i.ONE
const Art = preload("res://scripts/ui/gameplay/item_art.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const FLOOR = preload("res://assets/textures/ui/windows-v2/room_floor.png")
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): _cursor = Vector2i(-1,-1); queue_redraw())

func _cell_size() -> float:
	return maxf(1,minf((size.x-48)/dimensions.x,(size.y-48)/dimensions.y))

func _draw() -> void:
	var cell := _cell_size()
	var origin := (size-Vector2(dimensions)*cell)*0.5
	var bounds := Rect2(origin,Vector2(dimensions)*cell)
	draw_texture_rect(FLOOR,bounds.grow(16),false)
	for y in range(dimensions.y):
		for x in range(dimensions.x):
			var rect := Rect2(origin+Vector2(x,y)*cell,Vector2.ONE*cell)
			if has_focus(): draw_rect(rect.grow(-1),Color(0.46,0.64,0.74,0.12),false,1)
			if _cursor == Vector2i(x,y): draw_rect(rect.grow(-1),Color(0.61,0.80,0.92,0.3))
	var font := ThemeDB.fallback_font
	for item in plan:
		var rect := Rect2(origin+Vector2(item.x,item.y)*cell,Vector2(item.width,item.height)*cell)
		draw_rect(rect.grow(-3),Color("304957"))
		draw_texture_rect(Art.texture(str(item.item)),rect.grow(-6),false)
		if rect.size.x > 95: draw_string(font,rect.position+Vector2(7,rect.size.y-6),Names.title(str(item.item)),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-12,13,Color("e4edf4"))
	if not selected_item.is_empty() and _cursor.x >= 0:
		var preview := Rect2(origin+Vector2(_cursor)*cell,Vector2(footprint)*cell)
		var allowed := _can_place(_cursor)
		draw_rect(preview.grow(-2),Color(0.56,0.79,0.92,0.20) if allowed else Color(0.85,0.44,0.25,0.25))
		draw_texture_rect(Art.texture(selected_item),preview.grow(-6),false,Color(1,1,1,0.65))
		draw_rect(preview.grow(-2),Color("90c6e8") if allowed else Color("da9a63"),false,2)
		tooltip_text = "Нажмите, чтобы поставить" if allowed else "Здесь недостаточно места"

func _can_place(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x+footprint.x > dimensions.x or cell.y+footprint.y > dimensions.y: return false
	var area := Rect2i(cell,footprint)
	for item in plan:
		if item.item != selected_item and area.intersects(Rect2i(item.x,item.y,item.width,item.height)): return false
	return true

func _gui_input(event: InputEvent) -> void:
	var cell := _cell_size()
	var origin := (size-Vector2(dimensions)*cell)*0.5
	if event is InputEventMouseMotion:
		_cursor = Vector2i((event.position-origin)/cell) if Rect2(origin,Vector2(dimensions)*cell).has_point(event.position) else Vector2i(-1,-1)
		queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not Rect2(origin,Vector2(dimensions)*cell).has_point(event.position): return
		grab_focus()
		var selected := Vector2i((event.position-origin)/cell)
		if selected.x >= 0 and selected.y >= 0 and selected.x < dimensions.x and selected.y < dimensions.y: cell_selected.emit(selected)
		accept_event()
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_accept"):
		if _cursor.x < 0: _cursor = Vector2i.ZERO
		if event.is_action_pressed("ui_left"): _cursor.x = maxi(0,_cursor.x-1)
		elif event.is_action_pressed("ui_right"): _cursor.x = mini(dimensions.x-1,_cursor.x+1)
		elif event.is_action_pressed("ui_up"): _cursor.y = maxi(0,_cursor.y-1)
		elif event.is_action_pressed("ui_down"): _cursor.y = mini(dimensions.y-1,_cursor.y+1)
		elif event.is_action_pressed("ui_accept"): cell_selected.emit(_cursor)
		else: return
		queue_redraw()
		accept_event()
