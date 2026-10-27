extends Control
## Shared registration canvas; each visible slot remains an independently inspectable sprite.
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
const TINT_SHADER = preload("res://scripts/portraits/character_tint.gdshader")
const STATE_SHADER = preload("res://scripts/portraits/character_state.gdshader")
const StateOverlay = preload("res://scripts/portraits/character_state_overlay.gd")
var actor: Dictionary = {}
var expression := "neutral"
var wardrobe := "context"
var framing := "dialogue"
var mirrored := false
var use_pregnancy_layers := true
var equipment: Dictionary = {}
var composition: Dictionary = {}
var _textures: Dictionary = {}
var _sprites: Dictionary = {}
var _canvas: Node2D
var _state_overlay: Node2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout)
	_layout()

func set_actor(value: Dictionary) -> void:
	actor = value.duplicate(true)
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var gameplay: Node = loop.root.get_node_or_null("Gameplay")
		if gameplay != null and gameplay.simulation != null:
			actor = Visuals.Pregnancy.with_runtime(actor,gameplay.simulation.state)
	rebuild()

func set_expression(value: String) -> void:
	expression = value
	rebuild()

func set_wardrobe(value: String) -> void:
	wardrobe = value
	rebuild()

func rebuild() -> void:
	composition = Visuals.assemble(actor,expression,wardrobe,equipment,use_pregnancy_layers)
	if _canvas == null:
		_canvas = Node2D.new()
		_canvas.name = "CharacterLayers"
		add_child(_canvas)
	_canvas.visible = composition.get("ok",false)
	var needed := {}
	var visible_ids := {}
	for layer in composition.layers: visible_ids[layer.id] = true
	# Detach obsolete nodes before creating their replacement. queue_free alone
	# keeps names reserved until the frame ends and breaks rapid face changes.
	for id in _sprites.keys():
		if not visible_ids.has(id):
			_canvas.remove_child(_sprites[id])
			_sprites[id].queue_free()
			_sprites.erase(id)
	var draw_order := 0
	for layer in composition.layers:
		var path := str(layer.texture)
		if not _textures.has(path) and ResourceLoader.exists(path,"Texture2D"): _textures[path] = load(path)
		needed[path] = true
		if not _sprites.has(layer.id):
			var sprite := Sprite2D.new()
			sprite.name = str(layer.id)
			sprite.centered = false
			_canvas.add_child(sprite)
			_sprites[layer.id] = sprite
		var sprite: Sprite2D = _sprites[layer.id]
		sprite.texture = _textures.get(path)
		# Keep layer ordering inside this Control's branch. Positive global Z
		# would let clothes and hair draw over later dialogue/mirror UI siblings.
		sprite.z_index = 0
		_canvas.move_child(sprite,draw_order)
		draw_order += 1
		var offset: Array = layer.get("offset",[0,0])
		sprite.position = Vector2(offset[0],offset[1])
		if sprite.texture != null:
			var canvas: Array = composition.rig.canvas
			sprite.scale = Vector2(canvas[0],canvas[1])/sprite.texture.get_size()
		if layer.get("tint","") in ["hair","eyes"]:
			var material := ShaderMaterial.new()
			material.shader = TINT_SHADER
			material.set_shader_parameter("tint",layer.color)
			sprite.material = material
			sprite.modulate = Color.WHITE
		else:
			sprite.material = null
			sprite.modulate = layer.color
		var state: Dictionary = composition.get("condition",{})
		if float(state.get("dirty",0)) > 0 or state.get("tired",false):
			var state_material := ShaderMaterial.new()
			state_material.shader = STATE_SHADER
			state_material.set_shader_parameter("dirt",float(state.get("dirty",0)))
			state_material.set_shader_parameter("fatigue",1.0 if state.get("tired",false) else 0.0)
			state_material.set_shader_parameter("tint_enabled",layer.get("tint","") in ["hair","eyes"])
			state_material.set_shader_parameter("tint",layer.color)
			sprite.material = state_material
		if layer.has("pregnancy_material"):
			var garment_material: ShaderMaterial = load(layer.pregnancy_material).duplicate()
			garment_material.set_shader_parameter("garment_role",int(layer.pregnancy_role))
			garment_material.set_shader_parameter("dirt",float(state.get("dirty",0)))
			garment_material.set_shader_parameter("fatigue",1.0 if state.get("tired",false) else 0.0)
			sprite.material = garment_material
	if _state_overlay == null:
		_state_overlay = StateOverlay.new()
		_state_overlay.name = "StateOverlay"
		add_child(_state_overlay)
	_state_overlay.visible = composition.get("ok",false)
	if composition.get("ok",false):
		_state_overlay.canvas = Vector2(composition.rig.canvas[0],composition.rig.canvas[1])
		_state_overlay.rig_id = str(composition.profile.rig)
	_state_overlay.injuries = actor.get("injuries",{}).duplicate(true)
	_state_overlay.queue_redraw()
	for path in _textures.keys():
		if not needed.has(path): _textures.erase(path)
	_layout()
	queue_redraw()

func _layout() -> void:
	if _canvas == null or not composition.get("ok",false): return
	var rig: Dictionary = composition.rig
	var values: Array = rig.get(framing+"_frame",rig.frame)
	var frame := Rect2(values[0],values[1],values[2],values[3])
	var factor := minf(size.x/frame.size.x,size.y/frame.size.y)
	var origin := (size-frame.size*factor)*Vector2(0.5,1.0)-frame.position*factor
	_canvas.position = Vector2(size.x-origin.x,origin.y) if mirrored else origin
	_canvas.scale = Vector2(-factor,factor) if mirrored else Vector2(factor,factor)
	if _state_overlay != null:
		_state_overlay.position = _canvas.position
		_state_overlay.scale = _canvas.scale

func _draw() -> void:
	pass
