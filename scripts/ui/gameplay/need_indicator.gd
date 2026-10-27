extends Control
## A quiet need indicator. The complete value remains available in its tooltip.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var kind := "satiety"
var title := ""
var metric_title := ""
var value := 100.0

func _ready() -> void:
	custom_minimum_size = Vector2(34, 54)
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_value(amount: float) -> void:
	value = clampf(amount, 0.0, 100.0)
	tooltip_text = "%s · %s: %d / 100\nЧем полнее индикатор, тем лучше" % [title, metric_title, roundi(value)]
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x * 0.5, 17)
	var color := UI.ORANGE if value < 30.0 else UI.BLUE
	var radius := 15.0
	draw_arc(center, radius, -PI * 0.5, PI * 1.5, 48, Color(0.40, 0.58, 0.69, 0.22), 2.0, true)
	if value > 0.0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * value / 100.0, 48, color, 2.0, true)
	draw_texture_rect(HUD.icon(kind), Rect2(center - Vector2(8, 8), Vector2(16, 16)), false, color)
	draw_string(get_theme_default_font(), Vector2(center.x - 26, 50), title, HORIZONTAL_ALIGNMENT_CENTER, 52, 12, UI.MUTED)
