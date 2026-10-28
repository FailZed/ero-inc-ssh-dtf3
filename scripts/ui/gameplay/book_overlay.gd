extends Control
## A separate illustrated book over the live scene; all text remains live Controls.
signal closed
signal screen_requested(id: String)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const HUD = preload("res://scripts/ui/gameplay/hud_widgets.gd")
const CHAPTERS := [
	{"title":"Личное", "items":[["profile","Персонаж","profile"], ["health","Самочувствие","health"], ["family","Семья","home"]]},
	{"title":"Город", "items":[["map","Карта города","map"], ["people","Отношения","people"], ["phone","Телефон","phone"], ["home","Мой дом","home"]]},
	{"title":"Истории", "items":[["journal","Журнал","journal"], ["activities","Занятия","desk"], ["work","Работа и деньги","wallet"], ["club","Мой клуб","people"], ["digital","Цифровой мир","desk"], ["collection","Воспоминания","eye"]]}
]
var _book: Control
var _scroll: ScrollContainer
var _content: VBoxContainer
var _chapter_title: Label
var _tabs: Array[Button] = []
var _chapter := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.0, 0.008, 0.02, 0.44)
	add_child(veil)
	veil.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: hide_book())
	_book = Control.new()
	add_child(_book)
	var image := TextureRect.new()
	image.texture = preload("res://assets/textures/ui/book/book_blank.png")
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(image)
	var wallpaper := TextureRect.new()
	var crop := AtlasTexture.new()
	crop.atlas = preload("res://assets/textures/ui/raster-v1/phone_wallpaper.png")
	crop.region = Rect2(0, 400, 765, 1060)
	wallpaper.texture = crop
	wallpaper.anchor_left = 0.13
	wallpaper.anchor_right = 0.46
	wallpaper.anchor_top = 0.31
	wallpaper.anchor_bottom = 0.82
	wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wallpaper.modulate = Color(0.58, 0.70, 0.82, 0.73)
	wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(wallpaper)
	var title := UI.label(_book, "Разделы", 38, UI.INK)
	_place(title, 0.15, 0.17, 0.44, 0.27)
	var back := UI.button(_book, "‹  Назад", hide_book)
	_place(back, 0.14, 0.80, 0.31, 0.88)
	HUD.quiet_button(back)
	back.add_theme_font_size_override("font_size", 19)
	_chapter_title = UI.label(_book, "", 29, UI.INK)
	_place(_chapter_title, 0.54, 0.17, 0.84, 0.26)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_book.add_child(_scroll)
	_place(_scroll, 0.53, 0.29, 0.84, 0.85)
	_content = UI.column(_scroll, 5)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in CHAPTERS.size():
		var tab := UI.button(_book, CHAPTERS[index].title, _select_chapter.bind(index))
		_place(tab, 0.86, 0.20 + index * 0.20, 0.985, 0.28 + index * 0.20)
		tab.add_theme_font_size_override("font_size", 16)
		tab.custom_minimum_size.y = 52
		_tabs.append(tab)
	resized.connect(_fit_book)
	_fit_book()
	_select_chapter(0)
	visible = false

func _place(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0
	control.offset_top = 0
	control.offset_right = 0
	control.offset_bottom = 0

func _fit_book() -> void:
	if not is_instance_valid(_book): return
	var width := minf(size.x * 0.96, size.y * 0.94 * (1672.0 / 941.0))
	var height := width * 941.0 / 1672.0
	_book.position = (size - Vector2(width, height)) * 0.5
	_book.size = Vector2(width, height)
	var narrow := size.x < 900.0 or size.y < 600.0
	_chapter_title.add_theme_font_size_override("font_size", 20 if narrow else 29)
	for tab in _tabs: tab.add_theme_font_size_override("font_size", 12 if narrow else 16)

func _select_chapter(index: int) -> void:
	_chapter = index
	_chapter_title.text = str(CHAPTERS[index].title).to_upper()
	for tab_index in _tabs.size():
		_tabs[tab_index].add_theme_stylebox_override("normal", HUD.shortcut_style(tab_index == index))
	UI.clear(_content)
	for spec in CHAPTERS[index].items:
		var button := UI.button(_content, spec[1], _open_screen.bind(spec[0]))
		button.icon = HUD.icon(spec[2])
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", 28)
		button.add_theme_constant_override("h_separation", 18)
		button.add_theme_font_size_override("font_size", 18)
		button.custom_minimum_size.y = 52
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HUD.quiet_button(button)
	if is_visible_in_tree() and not _content.get_children().is_empty():
		(_content.get_child(0) as Control).grab_focus()

func _open_screen(id: String) -> void:
	hide_book()
	screen_requested.emit(id)

func show_book() -> void:
	visible = true
	_select_chapter(_chapter)

func hide_book() -> void:
	if not visible: return
	visible = false
	closed.emit()
