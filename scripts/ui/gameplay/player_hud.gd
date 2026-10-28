extends Button
## The approved scene HUD: nine light icons, live values and permanent captions.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
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
var _row: HBoxContainer

func _ready() -> void:
	size_flags_vertical = Control.SIZE_SHRINK_END
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	HUD.quiet_button(self)
	_row = UI.row(self,6)
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_health = _indicator(["health","ХП","health","Здоровье"])
	_energy = _indicator(["energy","Выносливость","energy","Запас сил"])
	for spec in NEEDS: _needs[spec[0]] = _indicator(spec)
	tooltip_text = "ХП, выносливость и потребности · открыть самочувствие"

func _indicator(spec: Array) -> Control:
	var indicator := Need.new()
	indicator.title = spec[1]
	indicator.kind = spec[2]
	indicator.metric_title = spec[3]
	_row.add_child(indicator)
	return indicator

func present(player: Dictionary, condition: Dictionary = {}) -> void:
	_health.set_value(float(player.needs.health))
	_energy.set_value(float(player.needs.energy))
	_energy.tooltip_text += "\nВосстановление в спокойных действиях: %.2f за игровую минуту" % float(condition.get("recovery",1.0))
	for id in _needs:
		_needs[id].visible = not id in condition.get("disabled_needs",[])
		_needs[id].set_value(float(player.needs[id]))
	custom_minimum_size = _row.get_combined_minimum_size()
