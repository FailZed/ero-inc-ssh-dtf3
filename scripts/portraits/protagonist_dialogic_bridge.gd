extends Node

const PROTAGONIST_IDENTIFIER := "ГГ"
const DEFAULT_PORTRAIT := "base"
const DEFAULT_POSITION_ID := "center"
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
var _speaker_revision := 0


func _ready() -> void:
	GameSession.player_profile_changed.connect(_on_player_profile_changed)
	if Dialogic != null:
		Dialogic.timeline_started.connect(_on_timeline_started)
		Dialogic.Text.speaker_updated.connect(_on_speaker_updated)
	call_deferred("_apply_current_profile_to_dialogic")


func _on_timeline_started() -> void:
	_speaker_revision += 1
	# A chapter scene must never carry an adult portrait into a flashback.
	for joined in Dialogic.Portraits.get_joined_characters():
		if not Visuals.story_actor(joined.get_identifier()).is_empty():
			Dialogic.Portraits.remove_character(joined)
	_apply_current_profile_to_dialogic()


func _on_speaker_updated(value: DialogicCharacter) -> void:
	_speaker_revision += 1
	if value == null or Visuals.story_actor(value.get_identifier()).is_empty(): return
	_show_story_speaker.call_deferred(value,_speaker_revision)


func _show_story_speaker(value: DialogicCharacter, revision: int) -> void:
	if revision != _speaker_revision or not GameSession.is_game_scene_active(): return
	for joined in Dialogic.Portraits.get_joined_characters():
		if joined != value and not Visuals.story_actor(joined.get_identifier()).is_empty():
			Dialogic.Portraits.remove_character(joined)
	if not Dialogic.Portraits.is_character_joined(value):
		await Dialogic.Portraits.join_character(value,"neutral","center",false,0,"","Fade In",0.0,false)
	if revision != _speaker_revision and Dialogic.Text.speaker_identifier != value.get_identifier():
		Dialogic.Portraits.remove_character(value)


func _on_player_profile_changed(_profile: Dictionary) -> void:
	_apply_current_profile_to_dialogic()


func _apply_current_profile_to_dialogic() -> void:
	if Dialogic == null or not Dialogic.has_subsystem("Portraits") or not GameSession.is_game_scene_active():
		return

	var profile := GameSession.get_character_profile()
	var protagonist := DialogicResourceUtil.get_character_resource(PROTAGONIST_IDENTIFIER)
	if protagonist == null:
		return

	if not bool((profile.get("meta", {}) as Dictionary).get("is_character_created", false)):
		if Dialogic.Portraits.is_character_joined(protagonist):
			Dialogic.Portraits.leave_character(protagonist)
		return

	var extra_data := ProtagonistAppearanceAssembler.build_dialogic_extra_data(profile)
	if Dialogic.Portraits.is_character_joined(protagonist):
		Dialogic.Portraits.change_character_extradata(protagonist, extra_data)
		return

	# First-person story scenes do not automatically place the adult hero in every
	# background (including childhood flashbacks). Explicit timeline joins still
	# apply the profile in the layered portrait's _ready(). The mirror owns its preview.
