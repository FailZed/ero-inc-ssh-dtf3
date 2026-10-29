extends RefCounted
## Original stroke icons and compact state indicators for the free-roam HUD.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
static var _icons: Dictionary = {}

static func icon(id: String) -> Texture2D:
	if _icons.has(id): return _icons[id]
	var paths := {
		"book": '<path d="M16 7C11 4 6 4 2 6v21c5-2 9-2 14 1 5-3 9-3 14-1V6c-4-2-9-2-14 1zM16 7v21M6 11h6M20 11h6"/>',
		"marker": '<circle cx="16" cy="16" r="13"/><circle cx="16" cy="16" r="5" fill="#90c6e8"/>',
		"estate": '<path d="M2 15L16 3l14 12M6 12v17h20V12M13 29V18h7v11"/>',
		"cook": '<path d="M4 12h24v8a10 10 0 01-10 10h-4A10 10 0 014 20zM2 12h28M10 7c0-2 2-3 2-5M17 7c0-2 2-3 2-5M24 7c0-2 2-3 2-5"/>',
		"market": '<path d="M4 12h24v17H4zM2 12l3-8h22l3 8M8 12v5M16 12v5M24 12v5M10 29v-9h12v9"/>',
		"study": '<path d="M3 7c5-2 9-2 13 1 4-3 8-3 13-1v20c-5-2-9-2-13 1-4-3-8-3-13-1zM16 8v20M7 12h5M20 12h5"/>',
		"map": '<path d="M3 6l8-3 10 3 8-3v23l-8 3-10-3-8 3zM11 3v23M21 6v23"/>',
		"people": '<circle cx="12" cy="10" r="5"/><path d="M3 28v-4a9 9 0 0118 0v4M22 6a5 5 0 010 10M25 20a8 8 0 014 8"/>',
		"phone": '<rect x="8" y="2" width="16" height="28" rx="2"/><path d="M12 6h8M14 26h4"/>',
		"inventory": '<rect x="6" y="8" width="20" height="21" rx="4"/><path d="M12 8V5h8v3M10 12h12M10 21h12v6H10zM3 14v11M29 14v11"/>',
		"journal": '<path d="M16 7C11 3 6 3 2 5v23c5-2 10-2 14 1 4-3 9-3 14-1V5c-4-2-9-2-14 2zM16 7v22"/>',
		"profile": '<circle cx="16" cy="10" r="6"/><path d="M4 29v-3a12 12 0 0124 0v3"/>',
		"sections": '<path d="M4 5h9v9H4zM19 5h9v9h-9zM4 20h9v9H4zM19 20h9v9h-9z"/>',
		"clock": '<circle cx="16" cy="16" r="13"/><path d="M16 7v10l6 4"/>',
		"calendar": '<rect x="3" y="6" width="26" height="24" rx="2"/><path d="M3 12h26M9 2v7M23 2v7M9 17h1M16 17h1M23 17h1M9 24h1M16 24h1M23 24h1"/>',
		"health": '<path d="M16 28S2 20 2 11C2 2 13 1 16 8c3-7 14-6 14 3 0 9-14 17-14 17z" fill="#da9a63" fill-opacity=".18"/>',
		"energy": '<path d="M18 2L5 19h10l-1 11 13-18H17z" fill="#90c6e8" fill-opacity=".16"/>',
		"satiety": '<path d="M6 3v10M11 3v10M3 3v8a5 5 0 0010 0V3M8 16v14M24 3v27M24 3c-6 5-6 14 0 14"/>',
		"hygiene": '<path d="M10 10h17M12 10V6a5 5 0 00-10 0M10 14v3M18 14v3M26 14v3M10 23v3M18 23v3M26 23v3"/>',
		"menu": '<path d="M5 8h22M5 16h22M5 24h22"/>',
		"eye": '<path d="M2 16S7 7 16 7s14 9 14 9-5 9-14 9S2 16 2 16z"/><circle cx="16" cy="16" r="4"/>',
		"close": '<path d="M7 7l18 18M25 7L7 25"/>'}
	paths.merge({
		"bed": '<path d="M3 27V10M3 22h26v5M3 17h26v5M8 17v-6h7v6M15 13h11a3 3 0 013 3v1"/>',
		"rest": '<path d="M26 22A12 12 0 0110 5a12 12 0 1016 17z"/>',
		"desk": '<path d="M3 19h26M6 19v10M26 19v10M9 4h16v11H9zM17 15v4M14 19h6"/>',
		"clean": '<path d="M24 3L12 19M8 16l11 8-7 6-10-7zM7 23l5 4M23 17v6M20 20h6"/>',
		"arrow": '<path d="M4 16h24M18 6l10 10-10 10"/>',
		"wallet": '<path d="M4 9l20-5v5M4 9h24v19H4zM21 16h9v7h-9z"/><circle cx="25" cy="19.5" r=".8"/>'})
	paths["credit"] = '<path d="M26 6A13 13 0 1019 29M23 7H16a9 9 0 000 18h7M6 14h19M6 20h16" stroke="#da9a63"/>'
	paths.merge({
		"home": '<path d="M2 15L16 3l14 12M6 12v17h20V12M13 29V18h7v11"/>',
		"outfit": '<path d="M10 3l6 4 6-4 8 9-6 5-3-3v16H11V14l-3 3-6-5z"/>',
		"play": '<path d="M10 4l18 12-18 12z"/>',
		"pause": '<path d="M10 5v22M22 5v22"/>',
		"thirst": '<path d="M16 2S5 15 5 21a11 11 0 0022 0C27 15 16 2 16 2z"/>',
		"toilet": '<path d="M5 3h11v10H5zM7 13v5h22a11 11 0 01-11 10h-6v-5M16 10h12v8M18 28v3h9"/>',
		"leisure": '<path d="M9 10h14c5 0 7 13 5 15s-6-4-7-4H11c-1 0-5 6-7 4S4 10 9 10zM10 13v7M7 16h6"/><circle cx="22" cy="14" r="1"/><circle cx="25" cy="18" r="1"/>',
		"chat": '<path d="M3 4h25v18H13l-7 6v-6H3zM8 10h15M8 15h10"/>'})
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 32 32"><g fill="none" stroke="#c0d4e2" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + str(paths.get(id, paths.sections)) + '</g></svg>'
	var pixels := Image.new()
	if pixels.load_svg_from_string(svg) != OK: return null
	_icons[id] = ImageTexture.create_from_image(pixels)
	return _icons[id]

static func button_style(background: Color = Color.TRANSPARENT, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := UI.style(background, border)
	style.set_border_width_all(0)
	style.border_width_bottom = 1 if border.a > 0 else 0
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

static func panel_style(background: Color = Color(0.018, 0.045, 0.065, 0.90)) -> StyleBoxFlat:
	var style := UI.style(background, Color(0.39, 0.57, 0.68, 0.32))
	for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 0)
	style.shadow_color = Color(0.0, 0.01, 0.02, 0.30)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 5)
	return style

static func quiet_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_style())
	button.add_theme_stylebox_override("hover", button_style(Color(0.08,0.16,0.22,0.86), UI.BLUE))
	button.add_theme_stylebox_override("pressed", button_style(Color(0.10,0.21,0.29,0.9), UI.BLUE))
	button.add_theme_stylebox_override("focus", button_style(Color.TRANSPARENT, UI.BLUE))
	button.add_theme_stylebox_override("disabled", button_style())

static func action_card(button: Button, kind: String, large: bool) -> void:
	var diameter := 74.0 if large else 48.0
	var normal := UI.style(Color(0.006,0.021,0.034,0.68),Color.TRANSPARENT)
	normal.set_border_width_all(0)
	normal.content_margin_left = roundi(diameter+20.0)
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.055,0.13,0.18,0.90)
	hover.border_color = UI.BLUE
	hover.border_width_left = 2
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover)
	button.add_theme_stylebox_override("focus",hover)
	var orb := PanelContainer.new()
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.anchor_top = 0.5
	orb.anchor_bottom = 0.5
	orb.offset_left = 4
	orb.offset_right = diameter+4
	orb.offset_top = -diameter*0.5
	orb.offset_bottom = diameter*0.5
	var orb_style := UI.style(Color(0.012,0.043,0.065,0.90),Color(0.50,0.73,0.85,0.80))
	orb_style.set_border_width_all(1)
	orb_style.set_corner_radius_all(roundi(diameter*0.5))
	orb_style.set_content_margin_all(10 if large else 8)
	orb.add_theme_stylebox_override("panel",orb_style)
	button.add_child(orb)
	var glyph := TextureRect.new()
	glyph.texture = icon(kind)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.add_child(glyph)

static func dock_button(parent: Node, title: String, key: String, kind: String, callback: Callable) -> Button:
	var button := UI.button(parent, "", callback)
	button.icon = icon(kind)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 26)
	button.custom_minimum_size = Vector2(54, 54)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = title + (" · " + key if not key.is_empty() else "")
	button.set_meta("hud_label", button.tooltip_text)
	quiet_button(button)
	return button

static func labeled_button(parent: Node, title: String, key: String, kind: String, callback: Callable) -> Button:
	var button := dock_button(parent,title,key,kind,callback)
	button.custom_minimum_size = Vector2(96,96)
	button.add_theme_constant_override("icon_max_width",32)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var skin := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		skin.content_margin_bottom = 34
		button.add_theme_stylebox_override(state,skin)
	var caption := UI.label(button,title,18)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -30
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button

static func rail(parent: Node, height: int, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(32, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := button_style(Color(0.30, 0.45, 0.55, 0.19))
	var fill := button_style(color)
	for style in [background, fill]:
		for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 0)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar
