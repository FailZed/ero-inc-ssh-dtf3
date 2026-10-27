extends Control
## Uses EroInc's existing layers directly; never reads the active GameSession.
var appearance: Dictionary = {}
var _textures: Dictionary = {}

func _ready() -> void:
	clip_contents = true

func set_appearance(value: Dictionary) -> void:
	appearance = value.duplicate(true)
	queue_redraw()

func _texture(id: String) -> Texture2D:
	if not _textures.has(id):
		var path := "res://assets/textures/portraits/protagonist_layers/%s.png" % id
		_textures[id] = load(path) if ResourceLoader.exists(path) else null
	return _textures[id]

func _layer(id: String, origin: Vector2, dimensions: Vector2, tint: Color = Color.WHITE) -> void:
	var texture := _texture(id)
	if texture != null: draw_texture_rect(texture, Rect2(origin, dimensions), false, tint)

func _draw() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.51)
	draw_circle(center, minf(size.x * 0.43, size.y * 0.4), Color("29283d"))
	draw_arc(center, minf(size.x * 0.43, size.y * 0.4), 0, TAU, 100, Color("48435e"), 1, true)
	var factor := minf(size.x / 190.0, size.y / 250.0)
	draw_set_transform(Vector2(size.x * 0.5, 413.0 * factor + 16.0), 0, Vector2.ONE * factor)
	var gender := "female" if appearance.get("gender", "male") == "female" else "male"
	_layer("body_%s_%s" % [gender, appearance.get("body_type", "slim")], Vector2(-126, -378), Vector2(252, 378))
	# Neutral clothing drawn in Godot; all preview variants remain clothed.
	var pants := PackedVector2Array([Vector2(-34,-246), Vector2(34,-246), Vector2(40,-157), Vector2(23,-30), Vector2(4,-30), Vector2(0,-155), Vector2(-4,-30), Vector2(-23,-30), Vector2(-40,-157)])
	draw_colored_polygon(pants, Color("343c52"))
	var shirt := PackedVector2Array([Vector2(-11,-349),Vector2(11,-349),Vector2(37,-335),Vector2(51,-307),Vector2(34,-295),Vector2(30,-239),Vector2(-30,-239),Vector2(-34,-295),Vector2(-51,-307),Vector2(-37,-335)])
	draw_colored_polygon(shirt, Color("899aaf"))
	draw_line(Vector2(0,-337), Vector2(0,-245), Color("697b95"), 1.0, true)
	for y in [-321, -301, -281, -261]: draw_circle(Vector2(1,y), 1.3, Color("d3d9e0"))
	_layer("face_%s" % appearance.get("face_id", "soft"), Vector2(-41,-396), Vector2(79,74))
	var long_hair: bool = appearance.get("hair_style", "short") == "long"
	var tint := Color(1.26, 1.17, 0.82) if appearance.get("hair_color", "dark") == "light" else Color.WHITE
	_layer("hair_%s_dark" % ("long" if long_hair else "short"), Vector2(-65,-410) if long_hair else Vector2(-41,-413), Vector2(128,128) if long_hair else Vector2(77,76), tint)
	draw_set_transform(Vector2.ZERO)
