@tool
extends "res://addons/dialogic/Modules/Character/dialogic_portrait.gd"
## Dialogic adapter for the same registered layers used by the mirror and NPCs.
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
const View = preload("res://scripts/portraits/layered_character_view.gd")
var _view: Control
var _mirrored := false

func _should_do_portrait_update(_character: DialogicCharacter, _portrait: String) -> bool:
	return true

func _ensure_view() -> void:
	if _view != null: return
	_view = View.new()
	_view.position = Vector2(-380,-1080)
	_view.size = Vector2(760,1080)
	add_child(_view)

func _update_portrait(value: DialogicCharacter, expression: String) -> void:
	apply_character_and_portrait(value,expression)
	_ensure_view()
	var actor: Dictionary
	if character.get_identifier() == "ГГ":
		actor = Visuals.player_actor({} if Engine.is_editor_hint() else GameSession.get_character_profile())
		if not Engine.is_editor_hint() and Gameplay.simulation != null:
			actor = Visuals.player_actor(GameSession.get_character_profile(), Gameplay.simulation.state.player)
	else:
		actor = Visuals.story_actor(character.get_identifier())
		if not Engine.is_editor_hint() and Gameplay.simulation != null and Gameplay.simulation.state.social.npcs.has(actor.get("id","")):
			actor = Gameplay.simulation.state.social.npcs[actor.id].duplicate(true)
	if actor.is_empty():
		_view.hide()
		return
	_view.show()
	_view.expression = portrait if portrait in Visuals.EXPRESSIONS else "neutral"
	_view.mirrored = _mirrored
	_view.set_actor(actor)

func apply_profile(profile: Dictionary) -> void:
	_ensure_view()
	_view.set_actor(Visuals.player_actor(profile))

func _get_covered_rect() -> Rect2:
	return Rect2(-380,-1080,760,1080)

func _set_mirror(value: bool) -> void:
	_mirrored = value
	if _view != null:
		_view.mirrored = value
		_view._layout()

func _set_extra_data(_data: String) -> void:
	# Existing profile notifications remain compatible; no slot migration.
	if not Engine.is_editor_hint() and character != null and character.get_identifier() == "ГГ":
		apply_profile(GameSession.get_character_profile())
