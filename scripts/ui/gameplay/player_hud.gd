extends Button
## All nine player resources stay visible without a boxed dashboard or progress rails.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const Need = preload("res://scripts/ui/gameplay/need_indicator.gd")
const NEEDS := [
	["health", "ХП", "health", "Здоровье"],
	["energy", "Силы", "energy", "Выносливость"],
	["hydration", "Жажда", "thirst", "Запас воды"],
	["satiety", "Голод", "satiety", "Сытость"],
	["hygiene", "Гигиена", "hygiene", "Чистота"],
	["bladder", "Туалет", "toilet", "Комфорт"],
	["rested", "Сон", "rest", "Выспанность"],
	["fun", "Досуг", "leisure", "Удовлетворённость досугом"],
	["social", "Общение", "chat", "Удовлетворённость общением"]]
var _needs: Dictionary = {}
var _row: HBoxContainer
var _visible_count := 9

func _ready() -> void:
	custom_minimum_size = Vector2(690, 86)
	size_flags_vertical = Control.SIZE_SHRINK_END
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := UI.style(Color.TRANSPARENT, Color.TRANSPARENT)
		style.set_border_width_all(0)
		style.set_content_margin_all(0)
		if state != "normal": style.border_width_bottom = 1; style.border_color = UI.BLUE
		add_theme_stylebox_override(state, style)
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override("separation", 4)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for spec in NEEDS:
		var indicator := Need.new()
		indicator.kind = spec[2]
		indicator.title = spec[1]
		indicator.metric_title = spec[3]
		_row.add_child(indicator)
		_needs[spec[0]] = indicator
	tooltip_text = "Самочувствие · открыть подробности"
	get_viewport().size_changed.connect(_fit_needs)
	_fit_needs()

func present(player: Dictionary, condition: Dictionary = {}) -> void:
	_visible_count = 0
	for spec in NEEDS:
		var id: String = spec[0]
		var indicator: Control = _needs[id]
		indicator.visible = not id in condition.get("disabled_needs", [])
		if indicator.visible: _visible_count += 1
		indicator.set_value(float(player.needs.get(id, 100.0)))
	_fit_needs()

func _fit_needs() -> void:
	if not is_instance_valid(_row): return
	var viewport_width := get_viewport_rect().size.x
	var compact := viewport_width < 1120.0
	var width := 44.0 if viewport_width < 900.0 else 48.0 if compact else 72.0
	var separation := 2 if compact else 4
	_row.add_theme_constant_override("separation", separation)
	for indicator in _needs.values():
		indicator.custom_minimum_size = Vector2(width, 56 if compact else 78)
		indicator.show_caption = not compact
		indicator.queue_redraw()
	custom_minimum_size = Vector2(maxf(width, _visible_count * width + maxi(0, _visible_count - 1) * separation), 64 if compact else 86)
