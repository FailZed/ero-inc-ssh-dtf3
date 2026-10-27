extends Control
## Main-game city: spatial markers and a focused 2.5D view of the current exterior.
signal travel_requested(id: String)
signal close_requested
const City = preload("res://scripts/gameplay/city_layout.gd")
const Atmosphere = preload("res://scripts/gameplay/atmosphere.gd")
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
var selected := ""
var map_mode := false
var markers: Dictionary = {}
var _sim
var _image: TextureRect
var _weather: ColorRect
var _pins: Control
var _card: PanelContainer
var _textures: Dictionary = {}
var _map_rect := Rect2()
var _path: Array = []
var _light := ShaderMaterial.new()
var _rain := ShaderMaterial.new()
var _overlay: Control
var _veil: ColorRect
var _route_line: Line2D

class RouteOverlay extends Control:
	var view
	func _draw() -> void: view.draw_overlay(self)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	theme = UI.skin()
	_light.shader = preload("res://assets/shaders/city_light.gdshader")
	_rain.shader = preload("res://assets/shaders/city_weather.gdshader")
	_veil = ColorRect.new()
	_veil.color = Color("07121c")
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.material = _light
	add_child(_image)
	_weather = ColorRect.new()
	_weather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather.material = _rain
	add_child(_weather)
	_route_line = Line2D.new()
	_route_line.default_color = UI.ORANGE
	_route_line.width = 3
	_route_line.antialiased = true
	add_child(_route_line)
	_overlay = RouteOverlay.new()
	_overlay.view = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_pins = Control.new()
	_pins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pins)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel",UI.surface(18))
	add_child(_card)
	resized.connect(_layout)

func present(sim, show_map: bool) -> void:
	_sim = sim
	map_mode = show_map
	_veil.visible = show_map
	var sky := Atmosphere.profile(sim.state.clock,str(sim.state.world.weather))
	var period := str(sky.period)
	if not _textures.has(period): _textures[period] = load(str(City.data().period_textures[period]))
	_image.texture = _textures[period]
	_light.set_shader_parameter("brightness",sky.brightness)
	_light.set_shader_parameter("saturation",sky.saturation)
	_rain.set_shader_parameter("precipitation",sky.precipitation)
	_rain.set_shader_parameter("overcast",0.0 if sky.weather == "clear" else 1.0)
	_pins.visible = show_map
	_route_line.visible = show_map
	_card.visible = show_map
	if selected.is_empty(): selected = City.map_location(sim.state)
	UI.clear(_pins)
	markers.clear()
	if show_map:
		for point in City.points():
			var id := str(point.runtime_id)
			var button := Button.new()
			button.text = str(point.name)
			button.add_theme_font_size_override("font_size",14)
			button.add_theme_stylebox_override("normal",UI.style(Color(0.015,0.035,0.05,0.94),UI.ORANGE if id == City.map_location(sim.state) else UI.MUTED))
			button.tooltip_text = str(point.get("description",point.name))
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.pressed.connect(select.bind(id))
			button.set_meta("city_destination",id)
			_pins.add_child(button)
			markers[id] = button
		select(selected)
	_layout()

func select(id: String) -> void:
	selected = id
	_path.clear()
	UI.clear(_card)
	var point := City.point(id)
	if point.is_empty(): return
	var content := UI.column(_card,10)
	UI.label(content,"ГОРОД У РЕКИ",13,UI.BLUE)
	UI.label(content,str(point.name),24)
	UI.label(content,str(point.get("description","")),17,UI.MUTED)
	var current := City.map_location(_sim.state) == id
	var route: Dictionary = _sim.services.world.route(id)
	if route.ok:
		_path = route.data.path
		UI.label(content,"Вы здесь" if current else "%d мин пешком · выносливость −%.1f" % [route.data.minutes,float(route.data.minutes)*0.15],17,UI.ORANGE if current else UI.BLUE)
	else: UI.label(content,"Сейчас путь закрыт. Попробуйте прийти в часы работы.",17,UI.ORANGE)
	var go := UI.button(content,"К СЦЕНЕ" if current else "ИДТИ  →",close_requested.emit if current else _go)
	go.disabled = not current and not route.ok
	if not current and route.ok and float(_sim.state.player.needs.energy) < float(route.data.minutes)*0.15:
		go.disabled = true
		UI.label(content,"Нужно восстановить выносливость.",16,UI.ORANGE)
	go.set_meta("city_confirm",id)
	go.tooltip_text = "Перейти в локацию. Время в городе продолжит идти."
	UI.label(content,"Выберите метку на карте.\nM / Esc — вернуться к сцене",14,UI.MUTED)
	# Give wrapped text its actual column width before the first layout pass.
	for child in content.get_children():
		if child is Label: child.custom_minimum_size.x = 248
	for marker in markers:
		markers[marker].modulate = UI.ORANGE if marker == id else Color.WHITE
	_layout()
	_overlay.queue_redraw()

func _go() -> void:
	travel_requested.emit(selected)

func _layout() -> void:
	if _image == null or _sim == null or size.x <= 0: return
	if map_mode:
		var area := Rect2(24,120,maxf(320,size.x-360),maxf(240,size.y-210))
		var scale_factor := minf(area.size.x/1536.0,area.size.y/1024.0)
		_map_rect = Rect2(area.get_center()-Vector2(1536,1024)*scale_factor*0.5,Vector2(1536,1024)*scale_factor)
		_card.position = Vector2(size.x-320,160)
		_card.size = Vector2(284,0)
		for id in markers:
			var anchor := _position(id)
			var offset := Vector2(0,-34)
			if id == "north_shops": offset = Vector2(28,-2)
			if id == "north_alleys": offset = Vector2(-38,30)
			if id == "north_den": offset = Vector2(-32,-34)
			if id == "riverside_cafe": offset = Vector2(12,-34)
			var button: Button = markers[id]
			button.size = Vector2.ZERO
			button.position = anchor + offset - Vector2(button.get_combined_minimum_size().x*0.5,16)
	else:
		# A location is a closer camera view of its actual place in the same city.
		var point := City.point(City.map_location(_sim.state))
		var uv: Array = point.get("anchor_uv",[0.5,0.5])
		var scale_factor := maxf(size.x/1536.0,size.y/1024.0)*2.25
		var dimensions := Vector2(1536,1024)*scale_factor
		var position := size*Vector2(0.43,0.48)-Vector2(float(uv[0]),float(uv[1]))*dimensions
		position = Vector2(clampf(position.x,size.x-dimensions.x,0),clampf(position.y,size.y-dimensions.y,0))
		_map_rect = Rect2(position,dimensions)
	_image.position = _map_rect.position
	_image.size = _map_rect.size
	_weather.position = _map_rect.position if map_mode else Vector2.ZERO
	_weather.size = _map_rect.size if map_mode else size
	_route_line.clear_points()
	if map_mode:
		_route_line.add_point(_position(City.map_location(_sim.state)))
		for id in _path:
			if not id in City.ROOMS: _route_line.add_point(_position(str(id)))
	_overlay.queue_redraw()

func _position(id: String) -> Vector2:
	var point := City.point(id)
	var uv: Array = point.get("anchor_uv",[0.5,0.5])
	# Graph-only bridge points have no clickable marker.
	if point.is_empty():
		var anchors := {"pedestrian_bridge_south":[422,382],"pedestrian_bridge_north":[471,248],"central_bridge_south":[869,490],"central_bridge_north":[948,282]}
		var pixel: Array = anchors.get(id,[768,512])
		uv = [float(pixel[0])/1536.0,float(pixel[1])/1024.0]
	return _map_rect.position+Vector2(float(uv[0]),float(uv[1]))*_map_rect.size

func draw_overlay(canvas: Control) -> void:
	if not map_mode or _sim == null: return
	for id in markers:
		var anchor := _position(id)
		canvas.draw_line(anchor,markers[id].position+markers[id].size*0.5,Color(0.62,0.78,0.9,0.65),1,true)
		canvas.draw_circle(anchor,5,UI.ORANGE if id == City.map_location(_sim.state) else UI.BLUE)
