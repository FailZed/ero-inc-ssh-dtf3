extends Control
## QA reference for atmosphere profiles over the new graph schematic, not location artwork.
const City = preload("res://scripts/gameplay/city_layout.gd")
const Atmosphere = preload("res://scripts/gameplay/atmosphere.gd")
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")

class SchematicCell extends Control:
	var graph: Dictionary = {}
	var profile: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		resized.connect(queue_redraw)

	func _position(id: String) -> Vector2:
		var uv: Array = graph.locations[id].map.position_uv
		return Vector2(float(uv[0]),float(uv[1]))*size

	func _draw() -> void:
		if graph.is_empty() or profile.is_empty(): return
		var period_tint: Color = {"morning":Color("19313f"),"day":Color("264452"),"sunset":Color("332b32"),"night":Color("081722")}[profile.period]
		var brightness := float(profile.brightness)
		draw_rect(Rect2(Vector2.ZERO,size),period_tint*Color(brightness,brightness,brightness,1))
		var band: Array = graph.map.river_band_uv
		draw_rect(Rect2(Vector2(0,float(band[0])*size.y),Vector2(size.x,float(band[1]-band[0])*size.y)),Color("183e53"))
		for edge in graph.routes:
			var a: Dictionary = graph.locations[edge.from_id]
			var b: Dictionary = graph.locations[edge.to_id]
			if a.kind != "public_exterior" or b.kind != "public_exterior" or a.map.offscreen or b.map.offscreen: continue
			draw_line(_position(str(edge.from_id)),_position(str(edge.to_id)),Color("536c7c"),1,true)
		for point in graph.locations.values():
			if point.map.marker: draw_circle(_position(str(point.id)),2.4,Color("a7c8db"))
		draw_rect(Rect2(Vector2.ZERO,size),Color("4b687b"),false,1)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.skin()
	var graph := City.source()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",2)
	grid.add_theme_constant_override("v_separation",2)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grid)
	for minute in [360,720,1140,1380]:
		for weather in ["clear","cloudy","rain","snow"]:
			var frame := SchematicCell.new()
			frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
			frame.custom_minimum_size = Vector2(300,190)
			frame.graph = graph
			frame.profile = Atmosphere.profile({"minute_of_day":minute},weather)
			grid.add_child(frame)
			var sky := ColorRect.new()
			sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var material := ShaderMaterial.new()
			material.shader = preload("res://assets/shaders/city_weather.gdshader")
			material.set_shader_parameter("precipitation",frame.profile.precipitation)
			material.set_shader_parameter("overcast",0.0 if weather == "clear" else 1.0)
			sky.material = material
			frame.add_child(sky)
			var caption := PanelContainer.new()
			caption.position = Vector2(8,8)
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			caption.add_theme_stylebox_override("panel",UI.style())
			frame.add_child(caption)
			var label := UI.label(caption,"Схема · "+str(frame.profile.label),15)
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
