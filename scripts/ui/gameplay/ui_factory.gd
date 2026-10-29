extends RefCounted
const INK := Color("e4edf4")
const MUTED := Color("9ab1c2")
const BLUE := Color("90c6e8")
const ORANGE := Color("da9a63")
static var text_scale := 1.0
static var _preferences_loaded := false

static func restore_focus(target: WeakRef) -> void:
	var control = target.get_ref()
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree() and not control.is_queued_for_deletion(): control.grab_focus()

static func focus_loop(root: Control) -> void:
	# Keep Tab and directional navigation inside the active window.
	var controls: Array[Control] = []
	for node in root.find_children("*","Control",true,false):
		if node.focus_mode == Control.FOCUS_ALL and node.is_visible_in_tree() and not node.is_queued_for_deletion() and not (node is BaseButton and node.disabled): controls.append(node)
	for index in range(controls.size()):
		var source := controls[index]
		source.focus_next = source.get_path_to(controls[(index+1)%controls.size()])
		source.focus_previous = source.get_path_to(controls[(index+controls.size()-1)%controls.size()])
		for direction in [Vector2.LEFT,Vector2.UP,Vector2.RIGHT,Vector2.DOWN]:
			var closest: Control = source
			var best := INF
			for candidate in controls:
				var delta := candidate.get_global_rect().get_center()-source.get_global_rect().get_center()
				var forward := delta.dot(direction)
				if forward <= 1: continue
				var distance := forward+absf(delta.cross(direction))*3.0
				if distance < best: best = distance; closest = candidate
			source.set("focus_neighbor_"+{Vector2.LEFT:"left",Vector2.UP:"top",Vector2.RIGHT:"right",Vector2.DOWN:"bottom"}[direction],source.get_path_to(closest))

static func surface(padding: int = 24) -> StyleBoxFlat:
	var result := style(Color(0.012,0.029,0.043,0.93),Color(0.48,0.70,0.82,0.82))
	result.set_border_width_all(2)
	result.set_content_margin_all(padding)
	result.shadow_color = Color(0.0,0.0,0.0,0.48)
	result.shadow_size = 8
	return result

static func set_text_scale(value: float) -> void:
	text_scale = clampf(value, 0.9, 1.25)
	var config := ConfigFile.new()
	config.set_value("interface", "text_scale", text_scale)
	config.save("user://interface.cfg")

static func apply_text_scale(node: Node) -> void:
	if node is Control and node.has_meta("ui_font_size"):
		node.add_theme_font_size_override("font_size", roundi(float(node.get_meta("ui_font_size")) * text_scale))
	for child in node.get_children(): apply_text_scale(child)
static func style(background: Color = Color(0.018, 0.037, 0.055, 0.48), border: Color = Color(0.30, 0.47, 0.59, 0.32)) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = background
	result.border_color = border
	result.set_border_width_all(0)
	result.border_width_bottom = 1 if border.a > 0.0 else 0
	result.content_margin_left = 18
	result.content_margin_right = 18
	result.content_margin_top = 12
	result.content_margin_bottom = 12
	return result

static func skin() -> Theme:
	if not _preferences_loaded:
		_preferences_loaded = true
		var config := ConfigFile.new()
		if config.load("user://interface.cfg") == OK: text_scale = clampf(float(config.get_value("interface", "text_scale", 1.0)), 0.9, 1.25)
	var result := Theme.new()
	result.default_font = preload("res://assets/fonts/pt-serif/PT_Serif-Web-Regular.ttf")
	result.default_font_size = roundi(20 * text_scale)
	for type in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "RichTextLabel", "SpinBox"]:
		result.set_color("font_color", type, INK)
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, style())
		result.set_stylebox("hover", type, style(Color("183248"), BLUE))
		result.set_stylebox("pressed", type, style(Color("294a60"), BLUE))
		result.set_stylebox("disabled", type, style(Color("101b25"), Color("253b4a")))
		result.set_stylebox("focus", type, style(Color.TRANSPARENT, BLUE))
		result.set_color("font_disabled_color", type, Color("657988"))
		result.set_color("font_hover_color", type, Color("f1f6fa"))
		result.set_color("font_focus_color", type, BLUE)
		result.set_color("font_pressed_color", type, BLUE)
		result.set_color("font_hover_pressed_color", type, BLUE)
		result.set_constant("h_separation", type, 10)
	result.set_stylebox("panel", "PopupMenu", style(Color("081521"), Color("4c6b80")))
	result.set_stylebox("hover", "PopupMenu", style(Color("203c50"), BLUE))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	result.set_stylebox("panel", "TooltipPanel", style(Color("081521"), Color("607e93")))
	result.set_color("font_color", "TooltipLabel", INK)
	result.set_font_size("font_size", "TooltipLabel", roundi(17 * text_scale))
	result.set_color("font_selected_color", "LineEdit", Color.WHITE)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("caret_color", "LineEdit", BLUE)
	result.set_color("selection_color", "LineEdit", Color("35546a"))
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 12)
	for direction in ["VScrollBar", "HScrollBar"]:
		var track := style(Color("101d28"), Color.TRANSPARENT)
		track.set_content_margin_all(3)
		result.set_stylebox("scroll", direction, track)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			var thumb := style(Color("4c6b80") if state == "grabber" else BLUE, Color.TRANSPARENT)
			thumb.set_content_margin_all(3)
			result.set_stylebox(state, direction, thumb)
	result.set_stylebox("panel", "PanelContainer", style())
	for type in ["CheckBox","CheckButton"]:
		result.set_constant("h_separation",type,12)
		result.set_color("font_hover_color",type,BLUE)
		result.set_stylebox("focus",type,style(Color(0.1,0.22,0.30,0.35),BLUE))
	for direction in ["HSlider","VSlider"]:
		var track := style(Color("1c3546"),Color.TRANSPARENT)
		track.set_content_margin_all(3)
		result.set_stylebox("slider",direction,track)
		result.set_stylebox("grabber_area",direction,style(BLUE,Color.TRANSPARENT))
	result.set_color("font_color","RichTextLabel",INK)
	result.set_stylebox("normal", "LineEdit", style(Color("0a1723")))
	result.set_stylebox("focus", "LineEdit", style(Color("142b3c"), BLUE))
	result.set_stylebox("background", "ProgressBar", style(Color("14232f"), Color("294354")))
	result.set_stylebox("fill", "ProgressBar", style(Color("6799b7"), BLUE))
	return result

static func label(parent: Node, text: String, size: int = 20, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = text
	result.set_meta("ui_font_size", size)
	result.add_theme_font_size_override("font_size", roundi(size * text_scale))
	result.add_theme_color_override("font_color", color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

static func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 48
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.pressed.connect(action)
	parent.add_child(result)
	return result

static func column(parent: Node, gap: int = 14) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	parent.add_child(result)
	return result

static func row(parent: Node, gap: int = 14) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	parent.add_child(result)
	return result

static func card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(Color.TRANSPARENT, Color.TRANSPARENT))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	return column(panel, 10)

static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func background(parent: Control, path: String, shade: float = 0.3) -> void:
	var texture := TextureRect.new()
	texture.texture = load(path)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(texture)
	var tint := ColorRect.new()
	tint.color = Color(0.01, 0.025, 0.04, shade)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tint)

static func inset(parent: Control, amount: int = 48) -> MarginContainer:
	var result := MarginContainer.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: result.add_theme_constant_override("margin_" + side, amount)
	parent.add_child(result)
	return result

static func scroller(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var result := column(scroll)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result
