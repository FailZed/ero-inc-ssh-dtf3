extends Control
## A quiet need indicator. The complete value remains available in its tooltip.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var kind := "satiety"
var title := ""
var metric_title := ""
var value := 100.0

func _ready() -> void:
	custom_minimum_size = Vector2(72,92) if kind != "energy" else Vector2(116,92)
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_value(amount: float) -> void:
	value = clampf(amount, 0.0, 100.0)
	custom_minimum_size = Vector2(maxf(72,get_theme_default_font().get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(17*UI.text_scale)).x+12),92+24*maxf(0,UI.text_scale-1))
	tooltip_text = "%s · %s: %d / 100\nОткрыть самочувствие" % [title, metric_title, roundi(value)]
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, 21)
	var color := UI.ORANGE if value < 30.0 else UI.BLUE
	draw_texture_rect(HUD.icon(kind),Rect2(center-Vector2(15,15),Vector2(30,30)),false,color)
	var font := get_theme_default_font()
	draw_string(font,Vector2(0,62),str(roundi(value)),HORIZONTAL_ALIGNMENT_CENTER,size.x,roundi(18*UI.text_scale),UI.ORANGE if value<30 else UI.INK)
	draw_string(font,Vector2(0,86+24*maxf(0,UI.text_scale-1)),title,HORIZONTAL_ALIGNMENT_CENTER,size.x,roundi(17*UI.text_scale),UI.MUTED)
