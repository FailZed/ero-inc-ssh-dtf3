extends RefCounted
## Personal device settings. Does not read or write game/save snapshots.
const WALLPAPERS := {
	"city":{"title":"Ночной город","path":"res://assets/textures/ui/raster-v1/phone_wallpaper.png"},
	"rain":{"title":"После дождя","path":"res://assets/textures/ui/raster-v1/phone_wallpaper_rain.png"},
	"water":{"title":"Тихая вода","path":"res://assets/textures/ui/raster-v1/phone_wallpaper_water.png"},
	"plain":{"title":"Тёмный фон","path":""}}
var data_dir := "user://phone"
var selected := "city"
var dimming := 0.22
var _custom_texture: Texture2D

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(data_dir.path_join("settings.cfg")) != OK: return
	selected = str(config.get_value("wallpaper","selected","city"))
	dimming = clampf(float(config.get_value("wallpaper","dimming",0.22)),0.0,0.7)
	if not selected in WALLPAPERS and selected != "custom": selected = "city"
	if selected == "custom" and not FileAccess.file_exists(data_dir.path_join("custom.png")): selected = "city"

func save_settings() -> Error:
	var result := DirAccess.make_dir_recursive_absolute(data_dir)
	if result != OK: return result
	var config := ConfigFile.new()
	config.set_value("wallpaper","selected",selected)
	config.set_value("wallpaper","dimming",dimming)
	return config.save(data_dir.path_join("settings.cfg"))

func choose(id: String) -> Error:
	if not id in WALLPAPERS and not (id == "custom" and FileAccess.file_exists(data_dir.path_join("custom.png"))): return ERR_INVALID_PARAMETER
	var previous := selected
	selected = id
	var result := save_settings()
	if result != OK: selected = previous
	return result

func texture(id: String = "") -> Texture2D:
	if id.is_empty(): id = selected
	if id == "plain": return null
	if id == "custom":
		if _custom_texture != null: return _custom_texture
		var pixels := Image.new()
		if pixels.load(data_dir.path_join("custom.png")) != OK: return null
		pixels.generate_mipmaps()
		_custom_texture = ImageTexture.create_from_image(pixels)
		return _custom_texture
	var path := str(WALLPAPERS.get(id,WALLPAPERS.city).path)
	if not ResourceLoader.exists(path,"Texture2D"): return null
	return load(path) as Texture2D

func import_image(path: String) -> Error:
	var pixels := Image.new()
	var result := pixels.load(path)
	if result != OK or pixels.is_empty(): return ERR_FILE_UNRECOGNIZED
	var longest := maxi(pixels.get_width(),pixels.get_height())
	if longest > 3072:
		var scale := 3072.0/longest
		pixels.resize(maxi(1,roundi(pixels.get_width()*scale)),maxi(1,roundi(pixels.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	result = DirAccess.make_dir_recursive_absolute(data_dir)
	if result != OK: return result
	result = pixels.save_png(data_dir.path_join("custom.png"))
	if result != OK: return result
	pixels.generate_mipmaps()
	_custom_texture = ImageTexture.create_from_image(pixels)
	selected = "custom"
	return save_settings()
