extends Button
## Two primary resources and seven real needs, without character art.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const Need = preload("res://scripts/ui/gameplay/need_indicator.gd")
const NEEDS := [
	["hydration", "Жажда", "thirst", "Запас воды"],
	["satiety", "Голод", "satiety", "Сытость"],
	["hygiene", "Гигиена", "hygiene", "Чистота"],
	["bladder", "Туалет", "toilet", "Комфорт"],
	["rested", "Сон", "rest", "Выспанность"],
	["fun", "Досуг", "leisure", "Удовлетворённость досугом"],
	["social", "Общение", "chat", "Удовлетворённость общением"]]
var _health: Dictionary
var _energy: Dictionary
var _needs: Dictionary = {}
var _needs_row: HBoxContainer

func _ready() -> void:
	custom_minimum_size = Vector2(420, 150)
	size_flags_vertical = Control.SIZE_SHRINK_END
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := HUD.panel_style()
		if state in ["hover", "pressed"]: style.bg_color = Color(0.035, 0.085, 0.12, 0.96)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = UI.BLUE
		add_theme_stylebox_override(state, style)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 18)
	for side in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var body := UI.column(margin, 14)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	var resources := UI.row(body, 24)
	_health = _resource(resources, "ХП", "health", UI.ORANGE)
	_energy = _resource(resources, "Выносливость", "energy", UI.BLUE)
	var lower := UI.row(body, 20)
	_needs_row = lower
	lower.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in NEEDS:
		var need := Need.new()
		need.kind = spec[2]
		need.title = spec[1]
		need.metric_title = spec[3]
		lower.add_child(need)
		_needs[spec[0]] = need
	_ignore_pointer(margin)
	for need in _needs.values(): need.mouse_filter = Control.MOUSE_FILTER_PASS
	_health.row.mouse_filter = Control.MOUSE_FILTER_PASS
	_energy.row.mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "ХП, выносливость и потребности\nОткрыть самочувствие"

func _resource(parent: Node, title: String, kind: String, color: Color) -> Dictionary:
	var box := UI.column(parent, 7)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := UI.row(box, 6)
	var icon := TextureRect.new()
	icon.texture = HUD.icon(kind)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(icon)
	var caption := UI.label(heading, title, 14, UI.MUTED)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	var value := UI.label(heading, "", 16)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	var bar := HUD.rail(box, 5, color)
	return {"label": value, "bar": bar, "fill": bar.get_theme_stylebox("fill"), "title": title, "row": box}

func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_pointer(child)

func present(player: Dictionary, condition: Dictionary = {}) -> void:
	for entry in [["health", _health], ["energy", _energy]]:
		var meter: Dictionary = entry[1]
		var amount := float(player.needs[entry[0]])
		meter.bar.value = amount
		meter.label.text = str(roundi(amount))
		meter.fill.bg_color = UI.ORANGE if entry[0] == "health" or amount < 30 else UI.BLUE
		meter.row.tooltip_text = "%s: %d / 100" % [meter.title, roundi(amount)]
	_energy.row.tooltip_text += "\nВосстановление в спокойных действиях: %.2f за игровую минуту\nВо время нагрузки выносливость расходуется" % float(condition.get("recovery", 1.0))
	var visible_count := 0
	for id in _needs:
		_needs[id].visible = not id in condition.get("disabled_needs",[])
		if _needs[id].visible: visible_count += 1
		_needs[id].set_value(float(player.needs[id]))
	_needs_row.visible = visible_count > 0
	custom_minimum_size.y = 150 if visible_count > 0 else 95
