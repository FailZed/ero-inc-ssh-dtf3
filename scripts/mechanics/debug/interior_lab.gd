extends Control
const Simulation = preload("res://scripts/mechanics/simulation.gd")
const LABELS := {"desk": "Стол", "chair": "Стул", "bookshelf": "Шкаф", "stove": "Плита", "computer": "Компьютер"}
var _sim
var _selected := "desk"
var _rotated := false
var _room := Rect2()
var _cell := 70.0
var _status: Label

func _ready() -> void:
	_sim = Simulation.new(42, {"settings": {"start_cash": 5000}})
	_sim.command("housing", "buy", {"id": "apartment"})
	_sim.command("housing", "move_in", {"id": "apartment"})
	for item in LABELS:
		_sim.command("inventory", "add", {"id": item})
		_sim.command("housing", "furnish", {"id": "apartment", "item": item})
	for placement in [["desk", 0, 0], ["chair", 0, 2], ["bookshelf", 6, 3]]:
		_sim.command("interior", "place", {"id": "apartment", "item": placement[0], "x": placement[1], "y": placement[2]})
	_build_ui()
	resized.connect(queue_redraw)
	queue_redraw()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): _capture(argument.trim_prefix("--capture="))

func _build_ui() -> void:
	var sidebar := VBoxContainer.new()
	sidebar.position = Vector2(24, 100)
	sidebar.custom_minimum_size = Vector2(250, 450)
	sidebar.add_theme_constant_override("separation", 12)
	add_child(sidebar)
	for item in LABELS:
		var button := Button.new()
		button.text = str(LABELS[item])
		button.custom_minimum_size.y = 44
		button.pressed.connect(_select.bind(str(item)))
		sidebar.add_child(button)
	var rotate := Button.new()
	rotate.text = "Повернуть (R)"
	rotate.custom_minimum_size.y = 44
	rotate.pressed.connect(_rotate)
	sidebar.add_child(rotate)
	var remove := Button.new()
	remove.text = "Убрать с плана"
	remove.custom_minimum_size.y = 44
	remove.pressed.connect(_unplace)
	sidebar.add_child(remove)
	_status = Label.new()
	_status.custom_minimum_size.x = 250
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sidebar.add_child(_status)
	_status.text = "Выбран: Стол. Нажмите на клетку комнаты."

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("141d2b"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(24, 45), "Лаборатория интерьера", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("eef5ff"))
	draw_string(font, Vector2(24, 76), "ЛКМ — разместить или переместить • R — поворот • отдельная тестовая сессия", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("aec2d9"))
	_cell = maxf(24.0, minf((size.x - 360.0) / 8.0, (size.y - 180.0) / 6.0))
	_room = Rect2(320, 115, _cell * 8, _cell * 6)
	draw_rect(_room, Color("223449"))
	for x in range(9): draw_line(_room.position + Vector2(x * _cell, 0), _room.position + Vector2(x * _cell, _room.size.y), Color("43566c"))
	for y in range(7): draw_line(_room.position + Vector2(0, y * _cell), _room.position + Vector2(_room.size.x, y * _cell), Color("43566c"))
	if _sim == null: return
	for placed in _sim.services.interior.render_plan("apartment"):
		var rectangle := Rect2(_room.position + Vector2(placed.x, placed.y) * _cell + Vector2(3, 3), Vector2(placed.width, placed.height) * _cell - Vector2(6, 6))
		var color := Color("61aa98") if placed.item == _selected else Color("547da8")
		draw_rect(rectangle, color)
		draw_rect(rectangle, Color("c4d9e8"), false, 2)
		draw_string(font, rectangle.position + Vector2(8, 24), str(LABELS.get(placed.item, placed.item)), HORIZONTAL_ALIGNMENT_LEFT, rectangle.size.x - 12, 16, Color("101c2c"))
	draw_string(font, Vector2(320, _room.end.y + 32), "Комната 8 × 6 • Пересечения и выход за границы отклоняются", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("aec2d9"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R: _rotate()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _room.has_point(event.position):
		var tile: Vector2 = (event.position - _room.position) / _cell
		var result: Dictionary = _sim.command("interior", "place", {"id": "apartment", "item": _selected, "x": int(tile.x), "y": int(tile.y), "rotated": _rotated})
		_status.text = "Размещено: %s" % LABELS[_selected] if result.ok else "Размещение отклонено: %s" % result.error
		queue_redraw()

func _select(item: String) -> void:
	_selected = item
	_status.text = "Выбран: %s. Поворот: %s" % [LABELS[item], "да" if _rotated else "нет"]
	queue_redraw()

func _rotate() -> void:
	_rotated = not _rotated
	_select(_selected)

func _unplace() -> void:
	_sim.command("interior", "unplace", {"id": "apartment", "item": _selected})
	_status.text = "Предмет убран с плана; он остаётся в оборудовании квартиры."
	queue_redraw()

func _capture(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("INTERIOR_CAPTURE ", error_string(error))
	get_tree().quit(0 if error == OK else 1)
