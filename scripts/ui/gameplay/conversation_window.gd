extends Control
## Shared conversation stage: character in the scene, responses to the right, text below.
signal closed
signal menu_requested
signal details_requested(id: String)
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
const Portrait = preload("res://scripts/ui/gameplay/resident_preview.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Social = preload("res://scripts/gameplay/social_presentation.gd")
var npc_id := ""
var mode := "story"
var background_path := "res://assets/textures/backgrounds/campus_v1/hall.tres"
var _portrait: Control
var _speaker: Label
var _text: RichTextLabel
var _options: VBoxContainer
var _context: Label
var _relationship: Label
var _actor: Dictionary = {}
var _refresh_pending := false
var _initiative := ""
var _rendered_turn := -1
var _closing := false

func configure(id: String, conversation_mode: String, background: String, initiative: String = "") -> void:
	npc_id = id
	mode = conversation_mode
	background_path = background
	_initiative = initiative

func _ready() -> void:
	theme = UI.skin()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.background(self,background_path,0.14)
	var vignette := ColorRect.new()
	vignette.color = Color(0.02,0.04,0.07,0.12)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)
	_portrait = Portrait.new()
	_portrait.anchor_left = 0.27
	_portrait.anchor_right = 0.73
	_portrait.anchor_top = 0.025
	_portrait.anchor_bottom = 0.99
	add_child(_portrait)
	var top := HBoxContainer.new()
	_anchor(top,0.035,0.035,0.965,0.10)
	add_child(top)
	UI.button(top,"←  К МЕСТУ",_close)
	_context = UI.label(top,"",20,UI.MUTED)
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UI.button(top,"МЕНЮ",menu_requested.emit)
	var identity := PanelContainer.new()
	identity.add_theme_stylebox_override("panel",UI.surface(20))
	_anchor(identity,0.035,0.16,0.255,0.37 if mode != "story" else 0.28)
	add_child(identity)
	var identity_body := UI.column(identity,7)
	_speaker = UI.label(identity_body,"",32,UI.INK)
	UI.label(identity_body,"ПЕРВЫЙ ДЕНЬ" if mode == "story" else "ПЕРЕПИСКА" if mode == "message" else "ЛИЧНЫЙ РАЗГОВОР",17,UI.BLUE)
	_relationship = UI.label(identity_body, "", 18, UI.MUTED)
	var responses := PanelContainer.new()
	responses.add_theme_stylebox_override("panel",UI.surface(20))
	_anchor(responses,0.755,0.20,0.965,0.69)
	add_child(responses)
	var responses_body := UI.column(responses,14)
	UI.label(responses_body,"ВАШ ОТВЕТ",18,UI.MUTED)
	_options = UI.scroller(responses_body)
	var dialogue := PanelContainer.new()
	_anchor(dialogue,0.08,0.745,0.92,0.965)
	dialogue.add_theme_stylebox_override("panel",UI.surface(24))
	add_child(dialogue)
	var text_body := UI.column(dialogue,10)
	UI.label(text_body,"РАЗГОВОР",17,UI.BLUE)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size",roundi(29 * UI.text_scale))
	_text.add_theme_color_override("default_color",UI.INK)
	_text.add_theme_constant_override("line_separation",7)
	text_body.add_child(_text)
	Gameplay.changed.connect(_queue_refresh)
	if mode != "story":
		var result := Gameplay.execute("npc_dialogue", "open", {"id": npc_id, "channel": "message" if mode == "message" else "face", "initiative": _initiative})
		if not result.ok: _say(Names.error(str(result.error)))
		if mode == "message": Gameplay.execute("social", "read", {"id": npc_id})
	_refresh()
	if mode == "story": _say("Вы подходите к собеседнику. С чего начать разговор?")
	if _options.get_child_count()>0: (_options.get_child(0) as Control).grab_focus()

func _anchor(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom

func _queue_refresh() -> void:
	if _refresh_pending or _closing: return
	_refresh_pending = true
	call_deferred("_refresh")

func _refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree() or _closing: return
	if not Gameplay.simulation.state.social.npcs.has(npc_id): _close(); return
	_actor = Gameplay.simulation.state.social.npcs[npc_id]
	var previous := get_viewport().gui_get_focus_owner()
	var previous_text: String = previous.text if previous is Button and _options.is_ancestor_of(previous) else ""
	_portrait.set_actor(_actor)
	_speaker.text = str(_actor.name)
	_context.text = "Можно осмотреться после разговора" if mode == "story" else ("Переписка · " if mode == "message" else "") + Names.title(str(_actor.location))
	UI.clear(_options)
	if mode == "story":
		for topic in ["introduce","directions","day"]:
			_choice({"introduce":"Представиться","directions":"Спросить дорогу","day":"Как проходит день?"}[topic],_story_topic.bind(topic))
	else:
		var view := Social.bond(Gameplay.simulation, npc_id)
		_relationship.text = "%s\nДоверие %d · комфорт %d" % [view.status_text, view.trust, view.comfort]
		var dialogue: Dictionary = Gameplay.simulation.services.npc_dialogue.present(npc_id)
		if not dialogue.is_empty():
			if _rendered_turn != int(dialogue.turn):
				_rendered_turn = int(dialogue.turn)
				_say(str(dialogue.utterance.text))
				_portrait.set_expression(str(dialogue.utterance.expression))
			for choice in dialogue.choices:
				var minutes := int(Gameplay.simulation.catalog.agency_actions[Gameplay.simulation.catalog.dialogue_choices[choice.id].action].minutes) if not str(Gameplay.simulation.catalog.dialogue_choices[choice.id].action).is_empty() else int(choice.minutes)
				var caption := str(choice.text) + (" · %d мин" % minutes if minutes > 0 else "")
				var button := _choice(caption, _dialogue_choice.bind(str(choice.id), int(dialogue.turn)))
				button.disabled = not str(choice.blocked).is_empty()
				button.tooltip_text = Names.error(str(choice.blocked)) if button.disabled else ""
		if mode == "free" and _actor.location == Gameplay.simulation.state.world.location and not npc_id in Gameplay.simulation.state.social.contacts:
			_choice("Обменяться контактами", _contact)
		_choice("Подарки, встречи и отношения…",func(): details_requested.emit(npc_id); _close())
	_choice("Закрыть переписку" if mode == "message" else "Попрощаться",_close)
	for button in _options.find_children("*","Button",true,false):
		if not button.disabled and (button.text == previous_text or previous_text.is_empty()):
			UI.restore_focus.call_deferred(weakref(button))
			break

func _choice(text: String, callback: Callable) -> Button:
	var button := UI.button(_options,text,callback)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 64
	button.add_theme_font_size_override("font_size",23)
	return button

func _story_topic(topic: String) -> void:
	var result := Gameplay.talk_to_story_npc(npc_id,topic)
	if result.ok:
		_portrait.set_expression("smile" if topic == "introduce" else "attentive")
		_say(str(result.text))
	else: _say(Names.error(str(result.error)))

func _dialogue_choice(choice: String, turn: int) -> void:
	var before := Social.bond(Gameplay.simulation, npc_id)
	var result := Gameplay.execute("npc_dialogue", "choose", {"id": npc_id, "choice": choice, "turn": turn})
	if not result.ok: _say(Names.error(str(result.error))); return
	_refresh()
	var changes := Social.change_summary(before, Social.bond(Gameplay.simulation, npc_id))
	if not changes.is_empty(): _text.text += "\n" + changes

func _contact() -> void:
	var result := Gameplay.execute("social", "contact", {"id": npc_id})
	if not result.ok: _say(Names.error(str(result.error))); return
	_say("Вы обменялись контактами. Теперь можно написать или договориться о встрече.")

func _say(text: String) -> void:
	_text.text = text
	_text.scroll_to_line(0)

func _close() -> void:
	if _closing: return
	_closing = true
	if mode != "story" and Gameplay.simulation.state.social.npcs.has(npc_id): Gameplay.execute("npc_dialogue", "close", {"id": npc_id})
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
