extends Control
## A compact, always-visible need glyph; the label and exact value remain readable on touch.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
var kind := "satiety"
var title := ""
var metric_title := ""
var value := 100.0
var show_caption := true

func _ready() -> void:
	custom_minimum_size = Vector2(72, 78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_value(amount: float) -> void:
	value = clampf(amount, 0.0, 100.0)
	tooltip_text = "%s · %s: %d / 100" % [title, metric_title, roundi(value)]
	queue_redraw()

func _draw() -> void:
	var color := UI.ORANGE if value < 30.0 else UI.BLUE
	var icon_size := Vector2(26, 26)
	draw_texture_rect(HUD.icon(kind), Rect2(Vector2((size.x - icon_size.x) * 0.5, 2), icon_size), false, color)
	draw_string(get_theme_default_font(), Vector2(0, 49), str(roundi(value)), HORIZONTAL_ALIGNMENT_CENTER, size.x, roundi(17 * UI.text_scale), UI.INK)
	if show_caption: draw_string(get_theme_default_font(), Vector2(0, 72), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, roundi(13 * UI.text_scale), UI.MUTED)
