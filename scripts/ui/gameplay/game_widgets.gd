extends RefCounted
## Small game-facing pieces. No simulation commands or state changes here.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")

static func panel(parent: Node, padding: int = 20, color: Color = Color(0.035, 0.065, 0.085, 0.92)) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UI.style(color, Color(0.35, 0.49, 0.58, 0.42))
	style.set_border_width_all(1)
	style.set_content_margin_all(padding)
	frame.add_theme_stylebox_override("panel", style)
	parent.add_child(frame)
	return UI.column(frame, 12)

static func icon(parent: Node, kind: String, pixels: int = 28, color: Color = UI.BLUE) -> TextureRect:
	var result := TextureRect.new()
	result.texture = HUD.icon(kind)
	result.custom_minimum_size = Vector2(pixels, pixels)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.modulate = color
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func tabs(parent: Node, items: Dictionary, selected: String, callback: Callable) -> HBoxContainer:
	var row := UI.row(parent, 8)
	for id in items:
		var button := UI.button(row, str(items[id]), callback.bind(id))
		button.set_meta("screen_tab", id)
		button.custom_minimum_size.y = 42
		button.add_theme_font_size_override("font_size", roundi(18 * UI.text_scale))
		HUD.quiet_button(button)
		if id == selected:
			button.set_meta("initial_focus",true)
			button.add_theme_stylebox_override("normal", HUD.button_style(Color(0.12, 0.22, 0.28, 0.75), UI.BLUE))
			button.modulate = UI.BLUE
	return row

static func empty(parent: Node, kind: String, title: String, detail: String = "") -> void:
	var box := UI.column(parent, 18)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size.y = 220
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	icon(box, kind, 54, UI.MUTED)
	var heading := UI.label(box, title, 25)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not detail.is_empty():
		var text := UI.label(box, detail, 18, UI.MUTED)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

static func meter(parent: Node, title: String, amount: float, kind: String, maximum: float = 100.0) -> void:
	var column := UI.column(parent, 7)
	var row := UI.row(column, 10)
	icon(row, kind, 22, UI.ORANGE if amount < 30 else UI.BLUE)
	UI.label(row, title, 18)
	var number := UI.label(row, "%d / %d" % [roundi(amount), roundi(maximum)], 17, UI.MUTED)
	number.autowrap_mode = TextServer.AUTOWRAP_OFF
	number.size_flags_horizontal = Control.SIZE_SHRINK_END
	var bar := HUD.rail(column, 6, UI.ORANGE if amount < 30 else UI.BLUE)
	bar.max_value = maximum
	bar.value = amount

static func primary(parent: Node, title: String, callback: Callable) -> Button:
	var result := UI.button(parent, title, callback)
	result.add_theme_stylebox_override("normal", UI.style(Color("284657"), Color("8db8ce")))
	result.custom_minimum_size.y = 48
	result.set_meta("initial_focus",true)
	return result

static func grid(parent: Node, columns: int = 2) -> GridContainer:
	var result := GridContainer.new()
	result.columns = columns
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_constant_override("h_separation", 16)
	result.add_theme_constant_override("v_separation", 16)
	parent.add_child(result)
	return result

static func avatar(parent: Node, name: String, pixels: int = 48) -> void:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(pixels, pixels)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := UI.style(Color("29404f"), Color("547386"))
	style.set_border_width_all(1)
	style.set_content_margin_all(0)
	style.set_corner_radius_all(pixels/2)
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var initials := UI.label(frame, name.substr(0, 1).to_upper(), roundi(pixels * 0.42), UI.INK)
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): ignore_pointer(child)

static func confirm(owner: Control, title: String, message: String, accept_text: String, action: Callable) -> Control:
	var dialog := preload("res://scripts/ui/gameplay/game_window.gd").new()
	dialog.title = title
	dialog.subtitle = message
	dialog.preferred_size = Vector2(780,350)
	dialog.back_requested.connect(dialog.queue_free)
	owner.add_child(dialog)
	var cancel := UI.button(dialog.footer,"Отмена",dialog.queue_free)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accept := primary(dialog.footer,accept_text,func(): action.call(); dialog.queue_free())
	accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.restore_focus.call_deferred(weakref(cancel))
	return dialog

static func illustration(parent: Node, texture: Texture2D, height: float = 150) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size.y = height
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture
