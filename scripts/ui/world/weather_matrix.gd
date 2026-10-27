extends Control
## Native-rendered QA reference: same source images, profiles and shaders as the game.
const City = preload("res://scripts/gameplay/city_layout.gd")
const Atmosphere = preload("res://scripts/gameplay/atmosphere.gd")
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation",2)
	grid.add_theme_constant_override("v_separation",2)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grid)
	for pair in [[360,"morning"],[720,"day"],[1140,"sunset"],[1380,"night"]]:
		for weather in ["clear","cloudy","rain","snow"]:
			var frame := Control.new()
			frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
			frame.custom_minimum_size = Vector2(300,190)
			grid.add_child(frame)
			var profile := Atmosphere.profile({"minute_of_day":pair[0]},weather)
			var picture := TextureRect.new()
			picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.texture = load(str(City.data().period_textures[pair[1]]))
			var light := ShaderMaterial.new()
			light.shader = preload("res://assets/shaders/city_light.gdshader")
			light.set_shader_parameter("brightness",profile.brightness)
			light.set_shader_parameter("saturation",profile.saturation)
			picture.material = light
			frame.add_child(picture)
			var sky := ColorRect.new()
			sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var material := ShaderMaterial.new()
			material.shader = preload("res://assets/shaders/city_weather.gdshader")
			material.set_shader_parameter("precipitation",profile.precipitation)
			material.set_shader_parameter("overcast",0.0 if weather == "clear" else 1.0)
			sky.material = material
			frame.add_child(sky)
			var caption := PanelContainer.new()
			caption.custom_minimum_size.x = 220
			caption.position = Vector2(8,8)
			caption.add_theme_stylebox_override("panel",UI.style())
			frame.add_child(caption)
			var label := UI.label(caption,str(profile.label),16)
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
