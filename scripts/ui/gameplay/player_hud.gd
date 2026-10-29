extends Button
## Nine live needs stay in the same lower-left grid at every landscape size.
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const Need = preload("res://scripts/ui/gameplay/need_indicator.gd")
const NEEDS := [
	["hydration","Жажда","thirst","Запас воды"],
	["satiety","Голод","satiety","Сытость"],
	["hygiene","Гигиена","hygiene","Чистота"],
	["bladder","Туалет","toilet","Комфорт"],
	["rested","Сон","rest","Выспанность"],
	["fun","Досуг","leisure","Удовлетворённость досугом"],
	["social","Общение","people","Удовлетворённость общением"]]
var _health: Control
var _energy: Control
var _needs: Dictionary = {}
var _grid: GridContainer

func set_compact_icon_scale(enlarged: bool) -> void:
	if not is_instance_valid(_grid): return
	for indicator in [_health,_energy] + _needs.values():
		indicator.set_compact_icon_scale(enlarged)
	custom_minimum_size = _grid.get_combined_minimum_size()

func _ready() -> void:
	size_flags_vertical = Control.SIZE_SHRINK_END
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	HUD.quiet_button(self)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation",10)
	_grid.add_theme_constant_override("v_separation",4)
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_grid)
	_health = _indicator(["health","ХП","health","Здоровье"])
	_energy = _indicator(["energy","Выносливость","energy","Запас сил"])
	for spec in NEEDS: _needs[spec[0]] = _indicator(spec)
	tooltip_text = "ХП, выносливость и потребности · открыть самочувствие"
	set_compact_icon_scale(false)

func _indicator(spec: Array) -> Control:
	var indicator := Need.new()
	indicator.title = spec[1]
	indicator.kind = spec[2]
	indicator.metric_title = spec[3]
	_grid.add_child(indicator)
	return indicator

func present(player: Dictionary, condition: Dictionary = {}) -> void:
	_health.set_value(float(player.needs.health))
	_energy.set_value(float(player.needs.energy))
	_energy.tooltip_text += "\nВосстановление в спокойных действиях: %.2f за игровую минуту" % float(condition.get("recovery",1.0))
	for id in _needs:
		_needs[id].visible = not id in condition.get("disabled_needs",[])
		_needs[id].set_value(float(player.needs[id]))
	custom_minimum_size = _grid.get_combined_minimum_size()
