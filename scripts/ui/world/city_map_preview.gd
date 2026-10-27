extends Control
## Art study only. Does not replace gameplay geography or change save state.
const ROOT := "res://assets/textures/world/city-river-v2/"
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
var _picture: TextureRect
var _textures: Dictionary = {}
var _labeled := true
var _toggle: Button

func _ready() -> void:
	GameSession.pause_autosave_runtime()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var capture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): capture = arg.trim_prefix("--capture=")
		if arg == "--clean": _labeled = false
	for variant in ["labeled", "clean"]:
		var source := Image.load_from_file(ROOT + "city-" + variant + "-v2.png")
		if source == null or source.is_empty():
			push_error("City map image could not be loaded: " + variant)
			get_tree().quit(1)
			return
		_textures[variant] = ImageTexture.create_from_image(source)
	var backdrop := ColorRect.new()
	backdrop.color = Color("071019")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_picture = TextureRect.new()
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	var controls := HBoxContainer.new()
	controls.position = Vector2(20, 20)
	controls.theme = UI.skin()
	add_child(controls)
	_toggle = UI.button(controls, "", _toggle_labels)
	_toggle.tooltip_text = "Tab — переключить подписи. Это отдельный просмотр арт-макета."
	_show_variant()
	controls.visible = capture.is_empty()
	if not capture.is_empty():
		for frame in range(8): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(capture.get_base_dir())
		var status := get_viewport().get_texture().get_image().save_png(capture)
		print("CITY_MAP_CAPTURE ", JSON.stringify({"ok":status == OK,"variant":"labeled" if _labeled else "clean","path":capture}))
		get_tree().quit(0 if status == OK else 1)

func _show_variant() -> void:
	_picture.texture = _textures["labeled" if _labeled else "clean"]
	_toggle.text = "ПОКАЗАТЬ ЧИСТЫЙ ФОН · TAB" if _labeled else "ПОКАЗАТЬ ПОДПИСИ · TAB"

func _toggle_labels() -> void:
	_labeled = not _labeled
	_show_variant()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_toggle_labels()
		get_viewport().set_input_as_handled()
