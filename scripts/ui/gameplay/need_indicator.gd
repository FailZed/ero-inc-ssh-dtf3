extends Control
## A quiet need indicator. The complete value remains available in its tooltip.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var kind := "satiety"
var title := ""
var metric_title := ""
var value := 100.0
var enlarged_icon := false

func _ready() -> void:
	custom_minimum_size = Vector2(170,44) if enlarged_icon else Vector2(156,40)
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_value(amount: float) -> void:
	value = clampf(amount, 0.0, 100.0)
	custom_minimum_size = Vector2(170,44) if enlarged_icon else Vector2(156,40)
	tooltip_text = "%s · %s: %d / 100\nОткрыть самочувствие" % [title, metric_title, roundi(value)]
	queue_redraw()

func set_compact_icon_scale(enabled: bool) -> void:
	enlarged_icon = enabled
	set_value(value)

func _draw() -> void:
	var color := UI.ORANGE if value < 30.0 else UI.BLUE
	var icon_size := 40.0 if enlarged_icon else 26.0
	var baseline := 22.0 if enlarged_icon else 20.0
	var bar_left := 48.0 if enlarged_icon else 44.0
	var bar_width := 77.0 if enlarged_icon else 76.0
	draw_texture_rect(HUD.icon(kind),Rect2(Vector2(4,baseline-icon_size*0.5),Vector2(icon_size,icon_size)),false,color)
	draw_rect(Rect2(Vector2(bar_left,baseline-3.5),Vector2(bar_width,7)),Color(0.44,0.62,0.73,0.24))
	draw_rect(Rect2(Vector2(bar_left,baseline-3.5),Vector2(bar_width*value/100.0,7)),color)
	draw_string(get_theme_default_font(),Vector2(128 if enlarged_icon else 120,baseline+9),str(roundi(value)),HORIZONTAL_ALIGNMENT_RIGHT,42 if enlarged_icon else 36,roundi((22 if enlarged_icon else 17)*UI.text_scale),UI.ORANGE if value < 30.0 else UI.INK)
