extends Control
class_name LoadMenu

signal slot_primary_action_requested(slot_id: String)
signal slot_delete_requested(slot_id: String)
signal slot_overwrite_requested(slot_id: String)
signal page_changed(section_name: String, page_index: int)

enum PanelMode {
	LOAD,
	SAVE,
}

enum PaginationSection {
	AUTO,
	USER,
}

const SAVE_SLOT_SCENE: PackedScene = preload("res://scenes/mainMenu/save_slot_card.tscn")
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const USER_SLOTS_PER_PAGE := 6
const GRID_GAP := 16.0
const MIN_CARD_WIDTH := 230.0
const MAX_CARD_WIDTH := 405.0
const MIN_PREVIEW_HEIGHT := 104.0
const MAX_PREVIEW_HEIGHT := 172.0
const PREVIEW_HEIGHT_RATIO := 0.42
const MAX_COLUMNS := 3

@onready var section_title_label: Label = $MarginContainer/PanelContainer/MainLayout/HeaderRow/TitleBlock/TitleLabel
@onready var page_info_label: Label = $MarginContainer/PanelContainer/MainLayout/PaginationRow/PageInfoLabel
@onready var auto_tab_button: Button = $MarginContainer/PanelContainer/MainLayout/HeaderRow/TopTabs/AutoTabButton
@onready var manual_tab_button: Button = $MarginContainer/PanelContainer/MainLayout/HeaderRow/TopTabs/ManualTabButton
@onready var pagination_row: Container = $MarginContainer/PanelContainer/MainLayout/PaginationRow
@onready var prev_page_button: Button = $MarginContainer/PanelContainer/MainLayout/PaginationRow/PrevPageButton
@onready var next_page_button: Button = $MarginContainer/PanelContainer/MainLayout/PaginationRow/NextPageButton
@onready var user_pages_row: Container = $MarginContainer/PanelContainer/MainLayout/PaginationRow/UserPagesRow
@onready var body_margin: MarginContainer = $MarginContainer/PanelContainer/MainLayout/BodyPanel/BodyMargin
@onready var grid: GridContainer = $MarginContainer/PanelContainer/MainLayout/BodyPanel/BodyMargin/BodyLayout/SlotGrid
@onready var empty_state_label: Label = $MarginContainer/PanelContainer/MainLayout/BodyPanel/BodyMargin/BodyLayout/EmptyStateLabel

var _panel_mode: int = PanelMode.LOAD
var _current_section: int = PaginationSection.AUTO
var _current_user_page: int = 0
var _auto_entries: Array = []
var _quick_entries: Array = []
var _user_pages: Array = []
var _navigation_bound := false


func _ready() -> void:
	var compact := _compact_landscape()
	$MarginContainer/PanelContainer.add_theme_stylebox_override("panel",UI.surface(16 if compact else 28))
	section_title_label.add_theme_font_size_override("font_size",48 if compact else 40)
	for tab in [auto_tab_button,manual_tab_button]:
		tab.custom_minimum_size.y = 72 if compact else 48
		tab.add_theme_font_size_override("font_size",28 if compact else 17)
	auto_tab_button.get_parent().add_theme_constant_override("separation",10 if compact else 0)
	grid.add_theme_constant_override("h_separation",24 if compact else 16)
	grid.add_theme_constant_override("v_separation",20 if compact else 16)
	_bind_navigation()
	GameSession.language_changed.connect(_refresh_view)
	resized.connect(_on_resized)
	_refresh_view()


func configure(panel_mode: int, auto_entries: Array, quick_entries: Array, user_pages: Array) -> void:
	_panel_mode = panel_mode
	_auto_entries = auto_entries.duplicate(true)
	_quick_entries = quick_entries.duplicate(true)
	_user_pages = user_pages.duplicate(true)
	call_deferred("_refresh_view")


func set_panel_mode(panel_mode: int) -> void:
	_panel_mode = panel_mode
	_refresh_view()


func show_auto_section() -> void:
	_current_section = PaginationSection.AUTO
	_refresh_view()


func show_quick_section() -> void:
	show_manual_section()


func show_manual_section() -> void:
	_current_section = PaginationSection.USER
	_current_user_page = clampi(_current_user_page, 0, _get_user_page_count() - 1)
	_refresh_view()


func show_user_page(page_index: int) -> void:
	_current_section = PaginationSection.USER
	_current_user_page = maxi(page_index, 0)
	_refresh_view()


func _bind_navigation() -> void:
	if _navigation_bound:
		return

	_navigation_bound = true
	auto_tab_button.pressed.connect(show_auto_section)
	manual_tab_button.pressed.connect(show_manual_section)
	prev_page_button.pressed.connect(_on_prev_page_pressed)
	next_page_button.pressed.connect(_on_next_page_pressed)


func _refresh_view() -> void:
	if not is_node_ready():
		return

	if _current_section == PaginationSection.USER:
		_current_user_page = clampi(_current_user_page, 0, _get_user_page_count() - 1)

	section_title_label.text = (GameSession.localize("menu.save_title") if _panel_mode == PanelMode.SAVE else GameSession.localize("menu.load_title")).to_upper()
	_render_navigation()
	_render_grid()


func _render_navigation() -> void:
	auto_tab_button.button_pressed = _current_section == PaginationSection.AUTO
	manual_tab_button.button_pressed = _current_section == PaginationSection.USER
	var compact := _compact_landscape()
	auto_tab_button.text = ("Auto" if compact else "Auto & quick") if GameSession.get_language_code() == GameSession.LANGUAGE_EN else ("Авто" if compact else "Авто и быстрые")
	manual_tab_button.text = ("Slots" if compact else "My saves") if GameSession.get_language_code() == GameSession.LANGUAGE_EN else ("Слоты" if compact else "Мои сохранения")
	pagination_row.visible = true
	var show_pagination := _current_section == PaginationSection.USER
	prev_page_button.visible = show_pagination
	next_page_button.visible = show_pagination
	page_info_label.visible = show_pagination

	for child in user_pages_row.get_children():
		child.queue_free()

	var page_count := _get_user_page_count()
	page_info_label.text = "%d / %d" % [_current_user_page + 1, page_count]
	prev_page_button.disabled = _current_user_page <= 0
	next_page_button.disabled = _current_user_page >= page_count - 1


func _on_user_page_pressed(page_index: int) -> void:
	_current_section = PaginationSection.USER
	_current_user_page = page_index
	_refresh_view()


func _on_prev_page_pressed() -> void:
	if _current_section != PaginationSection.USER:
		return
	_current_user_page = maxi(_current_user_page - 1, 0)
	_refresh_view()


func _on_next_page_pressed() -> void:
	if _current_section != PaginationSection.USER:
		return
	_current_user_page = mini(_current_user_page + 1, _get_user_page_count() - 1)
	_refresh_view()


func _render_grid() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var entries: Array = _get_active_entries()
	empty_state_label.visible = entries.is_empty()
	empty_state_label.text = GameSession.localize("load.empty")
	var layout := _calculate_grid_layout(entries.size())
	grid.columns = layout["columns"]

	for entry in entries:
		var slot_card = SAVE_SLOT_SCENE.instantiate()
		grid.add_child(slot_card)
		slot_card.set_display_size(layout["card_width"], layout["preview_height"])
		slot_card.primary_action_requested.connect(_on_slot_primary_action_requested)
		slot_card.delete_requested.connect(_on_slot_delete_requested)
		slot_card.overwrite_requested.connect(_on_slot_overwrite_requested)
		slot_card.bind_entry(entry, _panel_mode == PanelMode.SAVE)

	page_changed.emit(_section_name(_current_section), _current_user_page)


func _get_active_entries() -> Array:
	match _current_section:
		PaginationSection.AUTO:
			return _auto_entries+_quick_entries
		PaginationSection.USER:
			if _current_user_page < _user_pages.size():
				return _user_pages[_current_user_page]
			return []
		_:
			return []


func _get_user_page_count() -> int:
	return maxi(_user_pages.size(), 1)


func _calculate_grid_layout(item_count: int) -> Dictionary:
	var available_width := _get_available_grid_width()
	var compact := _compact_landscape()
	var columns := mini(2 if compact else MAX_COLUMNS, maxi(item_count, 1))
	while columns > 1 and (available_width-GRID_GAP*float(columns-1))/float(columns) < MIN_CARD_WIDTH: columns -= 1

	var raw_width := (available_width - GRID_GAP * float(columns - 1)) / float(columns)
	var card_width := minf(raw_width,620.0 if compact else MAX_CARD_WIDTH)
	var preview_height := clampf(roundf(card_width * (0.38 if compact else PREVIEW_HEIGHT_RATIO)),160.0 if compact else MIN_PREVIEW_HEIGHT,220.0 if compact else MAX_PREVIEW_HEIGHT)

	return {
		"columns": columns,
		"card_width": maxf(card_width, MIN_CARD_WIDTH),
		"preview_height": preview_height,
	}


func _get_available_grid_width() -> float:
	return maxf(size.x-128.0,MIN_CARD_WIDTH)

func _compact_landscape() -> bool:
	var window_size := DisplayServer.window_get_size()
	return window_size.x > window_size.y and window_size.x <= 1100


func _on_resized() -> void:
	call_deferred("_refresh_view")


func _section_name(section: int) -> String:
	match section:
		PaginationSection.AUTO:
			return "auto"
		PaginationSection.USER:
			return "user"
		_:
			return "unknown"


func _on_slot_primary_action_requested(slot_id: String) -> void:
	slot_primary_action_requested.emit(slot_id)


func _on_slot_delete_requested(slot_id: String) -> void:
	slot_delete_requested.emit(slot_id)


func _on_slot_overwrite_requested(slot_id: String) -> void:
	slot_overwrite_requested.emit(slot_id)


func _make_page_button_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.06, 0.09, 0.42) if active else Color(0.01, 0.02, 0.03, 0.28)
	style.border_color = Color(0.21, 0.62, 0.95, 0.9) if active else Color(0.36, 0.58, 0.73, 0.32)
	style.set_border_width_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
