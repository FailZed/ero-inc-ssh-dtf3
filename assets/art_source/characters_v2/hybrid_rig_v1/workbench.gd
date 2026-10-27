extends Control

const Character := preload("res://hybrid_character.gd")
const LABELS := {"neutral":"Спокойная стойка", "gesture":"Открытая ладонь", "head_tilt":"Наклон головы", "lean":"Наклон корпуса", "folded":"Скрещённые руки", "seated_front":"Сидя"}
var actor: Node2D
var stage: Control
var mode_label: Label
var description: Label
var selector: OptionButton
var skeleton_check: CheckButton
var breathe_check: CheckButton
var buttons: Dictionary = {}
var capture_path := ""

func box(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	return style

func label(text: String, size_px: int = 18) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size_px)
	return node

func _ready() -> void:
	var art_theme := Theme.new()
	art_theme.default_font_size = 17
	art_theme.set_color("font_color", "Label", Color("e7eced"))
	art_theme.set_stylebox("normal", "Button", box(Color("111e2d"), Color("324a60")))
	art_theme.set_stylebox("hover", "Button", box(Color("21394e"), Color("7096ad")))
	art_theme.set_stylebox("pressed", "Button", box(Color("2c4a60"), Color("a2c4d4")))
	art_theme.set_stylebox("focus", "Button", box(Color(0,0,0,0), Color("d8b486")))
	art_theme.set_stylebox("disabled", "Button", box(Color("101722"), Color("283542")))
	art_theme.set_stylebox("panel", "PanelContainer", box(Color("101b29"), Color("3b5366")))
	theme = art_theme
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side, 22)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var title := label("EroInc  /  Персонажи", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var badge := label("ГИБРИД · ПРОТОТИП", 14)
	badge.add_theme_color_override("font_color", Color("d9a46d"))
	header.add_child(badge)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 290
	side.add_theme_constant_override("separation", 10)
	body.add_child(side)
	side.add_child(label("ПЕРСОНАЖ", 13))
	selector = OptionButton.new()
	selector.add_item("Женская основа")
	selector.add_item("Мужская основа")
	selector.item_selected.connect(_select_body)
	side.add_child(selector)
	side.add_child(HSeparator.new())
	side.add_child(label("ПОЛОЖЕНИЕ", 13))
	var group := ButtonGroup.new()
	for key: String in LABELS:
		var button := Button.new()
		button.text = LABELS[key]
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_pose.bind(key))
		buttons[key] = button
		side.add_child(button)
	side.add_child(HSeparator.new())
	skeleton_check = CheckButton.new()
	skeleton_check.text = "Показать скелет"
	skeleton_check.toggled.connect(func(enabled: bool): actor.show_bones = enabled; actor.queue_redraw())
	side.add_child(skeleton_check)
	breathe_check = CheckButton.new()
	breathe_check.text = "Спокойное дыхание"
	breathe_check.button_pressed = true
	breathe_check.toggled.connect(func(enabled: bool): actor.set_breathing(enabled))
	side.add_child(breathe_check)
	description = label("", 15)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 285
	description.add_theme_color_override("font_color", Color("a9bdcb"))
	side.add_child(description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var note := label("Кисти и одежда — следующий этап.\nПрофиль требует отдельной основы.", 14)
	note.add_theme_color_override("font_color", Color("819aac"))
	side.add_child(note)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(frame)
	stage = Control.new()
	stage.custom_minimum_size = Vector2(480, 500)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(stage)
	actor = Character.new()
	stage.add_child(actor)
	stage.resized.connect(_fit_actor)
	mode_label = label("", 13)
	mode_label.position = Vector2(8, 4)
	mode_label.add_theme_color_override("font_color", Color("a5c1d3"))
	stage.add_child(mode_label)
	actor.pose_changed.connect(_pose_changed)
	var footer := label("Отдельный стенд · Сложная поза переключает рисунок, а не растягивает исходное тело", 14)
	footer.add_theme_color_override("font_color", Color("819aac"))
	page.add_child(footer)
	_select_body(0)
	buttons.neutral.grab_focus()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=").replace("\\", "/")
	if not capture_path.is_empty():
		_capture.call_deferred()

func _fit_actor() -> void:
	if not is_instance_valid(actor) or actor.data.is_empty():
		return
	var ratio := maxf(0.1, (stage.size.y - 64.0) / 1395.0)
	actor.scale = Vector2.ONE * ratio
	actor.position = Vector2(stage.size.x * 0.5 - 736.0 * ratio, stage.size.y - 20.0 - 1395.0 * ratio)

func _select_body(index: int) -> void:
	actor.load_body("female" if index == 0 else "male")
	selector.select(index)
	for key: String in buttons:
		buttons[key].disabled = not key in actor.available_poses()
		buttons[key].tooltip_text = "Отдельная отрисовка ещё не подготовлена" if buttons[key].disabled else ""
	_fit_actor()
	_select_pose("neutral")

func _select_pose(pose: String) -> void:
	if actor.set_pose(pose):
		buttons[pose].button_pressed = true

func _pose_changed(_pose: String, mode: String) -> void:
	skeleton_check.disabled = mode == "redraw"
	breathe_check.disabled = mode == "redraw"
	skeleton_check.tooltip_text = "Цельная пробная поза пока статична" if mode == "redraw" else ""
	breathe_check.tooltip_text = skeleton_check.tooltip_text
	mode_label.text = "ПРОБНАЯ ЦЕЛЬНАЯ ПОЗА" if mode == "redraw" else "СКЕЛЕТ + ВЕСА СЕТКИ"
	description.text = "Референс отдельной позы. Для финального набора ещё нужны сверка внешности и подготовка слоёв." if mode == "redraw" else "Одна и та же основа тела. Пока доступны дыхание и малые наклоны. Движения рук требуют раздельных поверхностей тела и конечностей."

func _capture() -> void:
	if not capture_path.begins_with("E:/"):
		push_error("Capture output must remain on E:")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(capture_path)
	for sex_index in [0, 1]:
		_select_body(sex_index)
		breathe_check.button_pressed = false
		actor.set_breathing(false)
		var sex: String = actor.data.sex
		for pose: String in actor.available_poses():
			if not actor.set_pose(pose, true):
				push_error("Pose texture unavailable during capture: "+pose)
				get_tree().quit(1)
				return
			buttons[pose].button_pressed = true
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(capture_path+"/"+sex+"-"+pose+".png")
			if pose == "neutral":
				actor.skin.visible = false
				actor.redraw.texture = load(actor.data.texture)
				actor.redraw.visible = true
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(capture_path+"/"+sex+"-reference.png")
				actor.set_pose("neutral", true)
		actor.set_pose("head_tilt", true)
		buttons.head_tilt.button_pressed = true
		skeleton_check.button_pressed = true
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_path+"/"+sex+"-rig-overlay.png")
		skeleton_check.button_pressed = false
	print("Captured live Godot workbench to "+capture_path)
	get_tree().quit()
