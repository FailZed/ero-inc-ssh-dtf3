extends VBoxContainer
## A small inspector inside the existing place panel. Commands are emitted, never run here.
signal action_requested(module_id: String, operation: String, args: Dictionary)
signal selection_changed(location_id: String, object_id: String)

const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Content = preload("res://scripts/gameplay/city_place_content.gd")

var _content: Dictionary = {}
var _context: Dictionary = {}
var _locale := "ru"
var _location_id := ""
var _object_id := ""
var _object_ids: Array[String] = []
var _selection_by_location: Dictionary = {}
var _last_choice: Dictionary = {}
var _selector_label: Label
var _selector: OptionButton
var _description: Label
var _status: Label
var _choices: VBoxContainer
var _built := false

func _ready() -> void:
	_build()

func setup(content: Dictionary, locale: String = "ru") -> void:
	_content = content.duplicate(true)
	_locale = locale
	_build()
	_selector_label.text = _text("city.ui.objects")

func supports(location_id: String) -> bool:
	return _content.get("scenes", {}).has(location_id)

func update(context: Dictionary) -> void:
	_context = context
	_build()
	_last_choice.clear()
	var state: Dictionary = context.get("state", {})
	var location_id := str(state.get("world", {}).get("location", ""))
	visible = supports(location_id)
	if not visible:
		_location_id = location_id
		_object_id = ""
		_object_ids.clear()
		_selector.clear()
		_selector.disabled = true
		_description.text = ""
		UI.clear(_choices)
		return
	var scene := Content.describe(_content, location_id, _context, _locale)
	if not scene.ok:
		_status.text = _reason(str(scene.get("error", "")))
		_description.text = ""
		_selector.disabled = true
		_object_id = ""
		_object_ids.clear()
		UI.clear(_choices)
		return
	_location_id = location_id
	_object_id = str(_selection_by_location.get(location_id, _object_id))
	_selector.set_meta("input_id", "city_place_selector:" + location_id)
	_selector.clear()
	_object_ids.clear()
	for object in scene.data.objects:
		_object_ids.append(str(object.id))
		_selector.add_item(str(object.title))
	if not _object_id in _object_ids:
		_object_id = _object_ids[0] if not _object_ids.is_empty() else ""
	_selector.disabled = _object_ids.is_empty()
	if not _object_id.is_empty():
		_selector.select(_object_ids.find(_object_id))
		_selection_by_location[location_id] = _object_id
		_selector.tooltip_text = _selector.get_item_text(_selector.selected)
	_render_inspection()

func select_object(object_id: String) -> void:
	if not object_id in _object_ids: return
	_object_id = object_id
	_selection_by_location[_location_id] = object_id
	_selector.select(_object_ids.find(object_id))
	_selector.tooltip_text = _selector.get_item_text(_selector.selected)
	_last_choice.clear()
	_render_inspection()

func selected_choice_descriptor() -> Dictionary:
	return _last_choice.duplicate(true)

func selected_object_id() -> String:
	return _object_id

func _build() -> void:
	if _built: return
	_built = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 9)
	var row := UI.row(self, 8)
	_selector_label = UI.label(row, _text("city.ui.objects"), 15, UI.MUTED)
	_selector = OptionButton.new()
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.custom_minimum_size.y = 40
	_selector.focus_mode = Control.FOCUS_ALL
	_selector.fit_to_longest_item = false
	_selector.clip_text = true
	_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selector.item_selected.connect(_on_selected)
	row.add_child(_selector)
	_status = UI.label(self, _text("city.ui.free_inspection"), 15, UI.MUTED)
	_description = UI.label(self, "", 18)
	_choices = UI.column(self, 6)

func _on_selected(index: int) -> void:
	if index < 0 or index >= _object_ids.size(): return
	_object_id = _object_ids[index]
	_selection_by_location[_location_id] = _object_id
	_selector.tooltip_text = _selector.get_item_text(index)
	_last_choice.clear()
	_render_inspection()
	selection_changed.emit(_location_id, _object_id)

func _render_inspection() -> void:
	var focus := _remember_local_focus()
	UI.clear(_choices)
	if _object_id.is_empty():
		_description.text = ""
		_restore_local_focus(focus)
		return
	var result := Content.inspect(_content, _location_id, _object_id, _context, _locale)
	if not result.ok:
		_description.text = _reason(str(result.get("error", "")))
		_last_choice.clear()
		_restore_local_focus(focus)
		return
	_description.text = str(result.data.text)
	_status.text = _text("city.ui.free_inspection")
	var service: Dictionary = result.data.get("service_status", {})
	if not service.is_empty():
		var service_text := str(service.title) + " · " + str(service.text)
		if not service.available: service_text += " — " + _reason(str(service.error))
		UI.label(_choices, service_text, 16, UI.MUTED if service.available else UI.ORANGE)
	for choice in result.data.choices:
		var command: Dictionary = choice.get("command", {})
		# Travel, services and people stay in the existing shell's place controls.
		if command.get("module") != "actions" or command.get("operation") != "perform": continue
		var minutes := int(choice.minutes)
		var caption := str(choice.label) + " · " + (_text("city.ui.minutes") % minutes)
		var button := UI.button(_choices, caption, _request_action.bind(str(choice.id), _location_id, _object_id))
		button.custom_minimum_size.y = 42
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not bool(choice.available)
		button.set_meta("city_place_choice", {"location_id":_location_id,"object_id":_object_id,"choice_id":str(choice.id)})
		button.set_meta("gameplay_action", command.duplicate(true))
		button.set_meta("confirmation_required", true)
		if button.disabled:
			var reason := _reason(str(choice.error))
			button.tooltip_text = reason
			UI.label(_choices, reason, 16, UI.ORANGE)
		else:
			button.tooltip_text = caption
	_restore_local_focus(focus)

func _request_action(choice_id: String, source_location: String, source_object: String) -> void:
	_last_choice.clear()
	if not is_inside_tree() or not is_visible_in_tree() or source_location != _location_id or source_object != _object_id: return
	var result := Content.choice(_content, _location_id, _object_id, choice_id, _context, _locale)
	if not result.ok:
		_status.text = _reason(str(result.get("error", "")))
		return
	var descriptor: Dictionary = result.data
	var command: Dictionary = descriptor.get("command", {})
	if command.get("module") != "actions" or command.get("operation") != "perform": return
	var args: Dictionary = command.get("args", {})
	if not str(args.get("id", "")) in ["wp_last_crate", "wp_rain_margin"]: return
	_last_choice = descriptor.duplicate(true)
	_last_choice.location_id = _location_id
	_last_choice.object_id = _object_id
	# Shell owns the single confirmation. Its existing command path rechecks availability.
	action_requested.emit("actions", "perform", args.duplicate(true))

func _remember_local_focus() -> Dictionary:
	if not is_inside_tree(): return {}
	var owner := get_viewport().gui_get_focus_owner()
	if owner == _selector: return {"kind":"selector"}
	if owner == null or not is_ancestor_of(owner) or not owner.has_meta("city_place_choice"): return {}
	var focus: Dictionary = owner.get_meta("city_place_choice").duplicate(true)
	focus.kind = "choice"
	return focus

func _restore_local_focus(focus: Dictionary) -> void:
	if focus.is_empty() or not is_inside_tree() or not is_visible_in_tree() or _selector.disabled: return
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and owner != _selector and not is_ancestor_of(owner): return
	if focus.get("kind") == "choice" and focus.get("location_id") == _location_id and focus.get("object_id") == _object_id:
		for control in _choices.get_children():
			if control is Button and not control.disabled and control.get_meta("city_place_choice", {}).get("choice_id") == focus.get("choice_id"):
				control.grab_focus()
				return
	_selector.grab_focus()

func _text(key: String) -> String:
	return Content.text(_content, key, _locale)

func _reason(error: String) -> String:
	var keys := {
		"action_closed":"city.ui.closed", "location_closed":"city.ui.closed", "service_closed":"city.ui.closed", "city_service_closed":"city.ui.closed",
		"action_daily_limit":"city.ui.done_today", "city_notice_already_sheltered":"city.ui.notice_done",
		"city_rain_required":"city.ui.rain_needed", "story_locked":"city.ui.story_locked",
		"city_content_authority_missing":"city.ui.authority_missing", "city_content_access_missing":"city.ui.authority_missing",
		"city_route_unavailable":"city.ui.no_route", "location_requirements":"city.ui.access_denied",
		"private_home":"city.ui.access_denied", "invitation_required":"city.ui.access_denied", "city_private_access_required":"city.ui.access_denied", "city_activity_access_required":"city.ui.access_denied"
	}
	return _text(str(keys.get(error, "city.ui.action_unavailable")))
