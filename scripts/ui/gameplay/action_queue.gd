extends PanelContainer
## Session-only UI plan. Commands remain owned and validated by Gameplay.
signal execute_requested(command: Dictionary)
signal layout_changed
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var planning := false
var running := false
var entries: Array[Dictionary] = []
var _body: VBoxContainer
var _toggle: Button
var _list: VBoxContainer
var _run: Button
var _status: Label
var _generation := 0
var _compact_landscape := false

func _ready() -> void:
	custom_minimum_size.x = 340
	size_flags_vertical = Control.SIZE_SHRINK_END
	var skin := HUD.panel_style()
	skin.content_margin_left = 14
	skin.content_margin_right = 14
	skin.content_margin_top = 10
	skin.content_margin_bottom = 10
	add_theme_stylebox_override("panel", skin)
	_body = UI.column(self, 6)
	var top := UI.row(_body, 10)
	_toggle = UI.button(top, "ПЛАН ДЕЙСТВИЙ", func():
		planning = not planning
		refresh())
	_toggle.toggle_mode = true
	_toggle.custom_minimum_size.y = 32
	_toggle.add_theme_font_size_override("font_size", 14)
	_toggle.tooltip_text = "Включите планирование: действия по месту будут добавляться в очередь. Shift + нажатие добавляет действие в любой момент."
	HUD.quiet_button(_toggle)
	_run = HUD.dock_button(top, "Выполнить план / остановить", "", "play", _toggle_run)
	_run.custom_minimum_size = Vector2(34, 32)
	_list = UI.column(_body, 2)
	_status = UI.label(_body, "", 13, UI.MUTED)
	refresh()

func set_compact_landscape(enabled: bool) -> void:
	if _compact_landscape == enabled: return
	_compact_landscape = enabled
	custom_minimum_size.x = 500 if enabled else 340
	_toggle.custom_minimum_size.y = 54 if enabled else 32
	_toggle.add_theme_font_size_override("font_size",24 if enabled else 14)
	_run.custom_minimum_size = Vector2(58,54) if enabled else Vector2(34,32)
	_run.add_theme_constant_override("icon_max_width",40 if enabled else 26)
	_status.add_theme_font_size_override("font_size",22 if enabled else 13)
	refresh()

func enqueue(command: Dictionary) -> void:
	if entries.size() >= 6:
		_status.text = "В плане уже 6 действий."
		return
	entries.append(command.duplicate(true))
	refresh()

func refresh() -> void:
	if not is_instance_valid(_list): return
	_toggle.set_pressed_no_signal(planning)
	_toggle.text = "ПЛАН · %d / 6" % entries.size() if not entries.is_empty() else "ПЛАН ДЕЙСТВИЙ"
	_toggle.modulate = UI.BLUE if planning else Color.WHITE
	_run.icon = HUD.icon("pause" if running else "play")
	_run.disabled = entries.is_empty()
	UI.clear(_list)
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var row := UI.row(_list, 6)
		var caption := UI.label(row, "%02d  %s" % [index + 1, entry.title], 22 if _compact_landscape else 14)
		caption.max_lines_visible = 1
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.tooltip_text = str(entry.title)
		caption.custom_minimum_size.x = 270 if _compact_landscape else 180
		var remove := UI.button(row, "×", _remove.bind(index))
		remove.custom_minimum_size = Vector2(46,44) if _compact_landscape else Vector2(28,26)
		remove.add_theme_font_size_override("font_size",26 if _compact_landscape else 20)
		remove.tooltip_text = "Убрать действие из плана"
		HUD.quiet_button(remove)
	_status.text = "Выполняется по порядку…" if running else "Нажмите ▶, чтобы начать" if not entries.is_empty() else "Shift + действие — добавить в план"
	layout_changed.emit()

func _remove(index: int) -> void:
	entries.remove_at(index)
	if entries.is_empty():
		running = false
		_generation += 1
	refresh()
	_run.grab_focus()

func _toggle_run() -> void:
	_generation += 1
	running = not running
	refresh()
	if running: _next.call_deferred(_generation)

func _next(generation: int) -> void:
	if generation != _generation or not running or entries.is_empty(): return
	if get_tree().paused:
		stop("План остановлен на паузе.")
		return
	execute_requested.emit(entries[0].duplicate(true))

func resolve(success: bool, reason: String = "") -> void:
	if success and not entries.is_empty(): entries.pop_front()
	if not success or entries.is_empty():
		running = false
		_generation += 1
	refresh()
	if not success: _status.text = reason
	if running:
		# Yield between commands so stop/remove and newly opened encounters can intervene.
		get_tree().create_timer(0.65).timeout.connect(_next.bind(_generation))

func stop(reason: String = "") -> void:
	_generation += 1
	running = false
	refresh()
	if not reason.is_empty(): _status.text = reason
