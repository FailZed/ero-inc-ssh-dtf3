extends SceneTree
## Focused headless mirror contract in a disposable test project.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		printerr("FAIL: ", title)

func _run() -> void:
	var session := root.get_node("GameSession")
	var gameplay := root.get_node("Gameplay")
	session.pause_autosave_runtime()
	root.size = Vector2i(1366, 768)
	var scene := Control.new()
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var modal = load("res://scenes/ui/CharacterCreationModal.tscn").instantiate()
	scene.add_child(modal)
	var world_before: Dictionary = gameplay.simulation.export_snapshot()
	var session_before: Dictionary = session.get_character_profile()
	modal.open_with_profile(session_before, session.get_character_stat_labels(), {}, session.get_character_appearance_options())
	await process_frame
	_check(modal.visible and modal._model_ready and modal._portrait.is_model_loaded(), "mirror shows the loaded GG Live2D model")
	_check(modal._shape_sliders.size() == 6 and modal._profile.appearance.gender == session_before.appearance.gender, "creator shows only supported body morphs and preserves profile gender")
	modal._set_shape(0.5, "ParamThighSize")
	_check(is_equal_approx(float(modal._portrait.get_appearance().shape.ParamThighSize), 0.5) and is_equal_approx(float(modal._profile.appearance.live2d.shape.ParamThighSize), 0.5), "morph updates both model and pending profile")
	modal._undo_appearance()
	_check(is_equal_approx(float(modal._portrait.get_appearance().shape.ParamThighSize), 0.0), "undo restores the previous model value")
	modal._select_zone("face")
	_check(modal._body.find_children("*", "Button", true, false).any(func(button): return button.text == "Сбросить"), "face color controls retain reset and undo actions")
	modal._set_palette("eyes", "sky")
	_check(modal._zone == "face" and modal._shape_sliders.is_empty() and modal._portrait.get_appearance().palette.eyes == "sky", "face mode changes real eye color without fake sculpt sliders")
	modal._select_page(1)
	_check(modal._stat_values.size() == 5 and not modal._confirm.disabled, "identity page keeps all five stats and a usable confirmation")
	modal._set_gender("female")
	_check(modal._profile.appearance.gender == "female" and modal._profile.appearance.genital_type == "vulva" and modal._profile.appearance.genital_size == "full", "choosing female keeps the profile anatomy fields consistent")
	modal._set_gender("male")
	_check(modal._profile.appearance.gender == "male" and modal._profile.appearance.genital_type == "penis" and modal._profile.appearance.genital_size == "average", "choosing male preserves profile identity without claiming a male Live2D preview")
	var confirmed: Array[Dictionary] = []
	modal.profile_confirmed_v2.connect(func(profile: Dictionary): confirmed.append(profile))
	modal._confirm_profile()
	_check(confirmed.size() == 1 and confirmed[0].appearance.live2d.palette.eyes == "sky", "confirmation emits the edited GG profile")
	_check(gameplay.simulation.export_snapshot() == world_before and session.get_character_profile() == session_before, "preview and confirmation do not mutate world or saves before GameSession applies the profile")
	root.size = Vector2i(800, 900)
	await process_frame
	_check(modal._reflection.anchor_bottom < modal._settings.anchor_top and modal._settings.get_global_rect().end.y <= modal.get_global_rect().end.y, "narrow layout stacks mirror and controls within the game canvas")
	scene.queue_free()
	await process_frame
	print("CREATOR_UI_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
