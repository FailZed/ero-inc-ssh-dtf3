extends "res://scripts/portraits/layered_character_view.gd"
## Semantic silhouettes remain legible without final locally generated NPC portraits.
@export var morphology := "human"
var _texture: Texture2D
func set_actor(actor: Dictionary) -> void:
	super.set_actor(actor)
	morphology = str(actor.appearance.get("morphology","human"))
	_texture = preload("res://scripts/portraits/npc_portrait_library.gd").texture(str(actor.appearance.get("portrait_id","")))
	queue_redraw()
func _ready() -> void:
	super._ready()

func _draw() -> void:
	if composition.get("ok",false):
		super._draw()
		return
	if _texture != null:
		var source := _texture.get_size()
		var factor := minf(size.x/source.x,size.y/source.y)
		var dimensions := source*factor
		draw_texture_rect(_texture,Rect2((size-dimensions)*0.5,dimensions),false)
		return
	var factor := minf(size.x / 220.0, size.y / 220.0)
	draw_set_transform(Vector2(size.x * 0.5, size.y * 0.5), 0, Vector2.ONE * factor)
	var fur := morphology == "furry"
	var tone := Color("b9c8cf") if not fur else Color("b48664")
	draw_circle(Vector2.ZERO, 96, Color("1d3748"))
	draw_arc(Vector2.ZERO, 96, 0, TAU, 80, Color("52788d"), 1.2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-78,98), Vector2(-64,45),Vector2(-25,20),Vector2(25,20),Vector2(64,45),Vector2(78,98)]),Color("476174"))
	if morphology != "human":
		for side in [-1,1]:
			draw_colored_polygon(PackedVector2Array([Vector2(side*48,-16),Vector2(side*60,-100),Vector2(side*14,-56)]), tone)
			draw_colored_polygon(PackedVector2Array([Vector2(side*41,-35),Vector2(side*51,-80),Vector2(side*27,-56)]),Color("735b65"))
	draw_circle(Vector2(0,-24),52,tone)
	if not fur:
		draw_colored_polygon(PackedVector2Array([Vector2(-52,-26),Vector2(-48,-64),Vector2(-12,-82),Vector2(30,-72),Vector2(52,-42),Vector2(9,-53),Vector2(-30,-30)]),Color("25313d"))
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(-27,-15),Vector2(0,22),Vector2(27,-15),Vector2(0,-2)]), Color("ded6bd"))
		draw_circle(Vector2(0,-2),6,Color("233141"))
	for side in [-1,1]: draw_line(Vector2(side*13,-24),Vector2(side*29,-27),Color("1d3041"),3,true)
	if not fur: draw_line(Vector2(-8,9),Vector2(8,9),Color("6b6970"),2,true)
	draw_set_transform(Vector2.ZERO)
