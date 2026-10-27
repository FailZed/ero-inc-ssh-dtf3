extends HBoxContainer
## Raster notebook surface with live navigation on the left and one entry on the right.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
var _paper: Texture2D

func _ready() -> void:
	custom_minimum_size = Vector2(1180,480)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation",28)
	resized.connect(queue_redraw)
	var path := "res://assets/textures/ui/raster-v1/journal_surface.png"
	if ResourceLoader.exists(path): _paper = load(path)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func sheet(left: bool) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.custom_minimum_size.x = 350 if left else 802
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",72 if left else 28)
	margin.add_theme_constant_override("margin_right",28 if left else 76)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side,26)
	add_child(margin)
	return UI.column(margin,18)

func _draw() -> void:
	if _paper != null:
		draw_texture_rect(_paper,Rect2(Vector2(-8,-8),size+Vector2(16,16)),false,Color(0.34,0.43,0.51))
