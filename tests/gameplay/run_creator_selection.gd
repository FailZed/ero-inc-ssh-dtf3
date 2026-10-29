extends SceneTree
## Real GG geometry/input regression; run in a disposable main-project fixture.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		printerr("FAIL: ", title)

func _click(modal, point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		modal._glass_input(event)

func _point(modal, id: String) -> Vector2:
	var meshes: Dictionary = modal._portrait.get_actor().get_drawable_meshes()
	return modal._points_rect(modal._mesh_points(meshes[id])).get_center()

func _settle() -> void:
	for i in range(8): await process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await _settle()
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("EROINC_ARTIFACTS")
	if output.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output)
	_check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "capture " + name)

func _run() -> void:
	var session := root.get_node("GameSession")
	session.pause_autosave_runtime()
	var before: Dictionary = session.get_character_profile()
	var world_before: Dictionary = root.get_node("Gameplay").simulation.export_snapshot()
	root.size = Vector2i(1440, 900)
	var modal = load("res://scenes/ui/CharacterCreationModal.tscn").instantiate()
	root.add_child(modal)
	modal.open_with_profile(before, session.get_character_stat_labels(), {}, session.get_character_appearance_options())
	await _settle()
	_check(modal._model_ready, "native GG loaded")
	if not modal._model_ready: _finish(); return
	var appearance: Dictionary = modal._current_live2d()
	modal._zone_buttons[""].pressed.emit()
	await _settle()
	var face := _point(modal, "SkinFace")
	var torso := _point(modal, "LongHoodieFront")
	var started := Time.get_ticks_usec()
	for i in range(90): modal._pick_zone([face, torso, Vector2(5, 5)][i % 3])
	print("CREATOR_PICK_MEAN_US ", (Time.get_ticks_usec() - started) / 90.0)
	_check(modal._pick_zone(face) == "face" and modal._pick_zone(torso) == "body", "visible face and clothed torso resolve to different regions")
	_click(modal, Vector2(5, 5))
	_check(modal._zone.is_empty(), "empty glass does not select a region")
	_click(modal, face)
	await _settle()
	_check(modal._zone == "face" and modal._zone_buttons.face.button_pressed and modal._shape_sliders.is_empty(), "face click opens face controls and marks the face button")
	await _capture("desktop-face-selected")
	modal._change_zoom(0.25)
	modal._pan = Vector2(40, 30)
	modal._head_tilt = 0.25
	modal._refresh_framing()
	await _settle()
	_check(modal._pick_zone(_point(modal, "SkinFace")) == "face", "face hit follows zoom, pan and native head deformation")
	modal._zone_buttons[""].pressed.emit()
	await _settle()
	_check(modal._zone.is_empty() and modal._zoom == 1.0 and modal._pan == Vector2.ZERO and modal._zone_buttons[""].button_pressed, "overview resets camera and selection through keyboard-accessible button")
	_click(modal, _point(modal, "LongHoodieFront"))
	await _settle()
	_check(modal._zone == "body" and modal._shape_sliders.size() == 6, "torso click opens supported body controls")
	await _capture("desktop-body-selected")
	modal._select_zone("")
	face = _point(modal, "SkinFace")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.position = face; press.pressed = true
	modal._glass_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = face + Vector2(40, 20); motion.relative = Vector2(40, 20); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	modal._glass_input(motion)
	press.position = motion.position; press.pressed = false
	modal._glass_input(press)
	_check(modal._zone.is_empty() and modal._pan == Vector2(40, 20) and not modal._dragging, "drag pans without accidental region selection")
	root.size = Vector2i(700, 900)
	modal._select_zone("")
	await _settle()
	_check(modal._pick_zone(_point(modal, "SkinFace")) == "face", "picking follows narrow-screen framing")
	var actual_button_height: float = modal._zone_buttons.face.get_global_rect().size.y * root.get_final_transform().get_scale().y
	_check(actual_button_height >= 44.0 and modal._layout_root.size.x <= 701.0, "narrow controls retain a 44px target under the main game canvas stretch")
	var tap := InputEventScreenTouch.new()
	tap.index = 0; tap.position = _point(modal, "SkinFace"); tap.pressed = true
	modal._glass_input(tap)
	tap.pressed = false
	modal._glass_input(tap)
	await _settle()
	_check(modal._zone == "face" and modal._touch_index == -1, "touch tap selects face and releases pointer")
	await _capture("narrow-face-selected")
	modal._select_zone("body")
	await _settle()
	await _capture("narrow-body-selected")
	var actual_modal: Rect2 = root.get_final_transform() * modal._settings.get_global_rect()
	_check(actual_modal.end.y <= float(root.size.y) + 1.0 and actual_modal.end.x <= float(root.size.x) + 1.0, "both axes keep the full settings panel inside the physical window")
	print("CREATOR_VIEWPORT_SCALE ", root.get_final_transform().get_scale(), " SETTINGS_PIXELS ", actual_modal)
	modal._select_zone("")
	await _settle()
	if DisplayServer.get_name() != "headless":
		var screen_point: Vector2 = modal._glass.get_viewport().get_screen_transform() * modal._glass.get_global_transform_with_canvas() * _point(modal, "SkinFace")
		var move := InputEventMouseMotion.new()
		move.position = screen_point
		move.global_position = screen_point
		Input.parse_input_event(move)
		await process_frame
		for down in [true, false]:
			var input := InputEventMouseButton.new()
			input.button_index = MOUSE_BUTTON_LEFT
			input.pressed = down
			input.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			input.position = screen_point
			input.global_position = screen_point
			Input.parse_input_event(input)
			await process_frame
		await _settle()
		_check(modal._zone == "face", "physical-coordinate mouse event reaches the face through real GUI routing after compensation")
	modal._select_zone("body")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"; cancel.pressed = true
	modal._unhandled_input(cancel)
	_check(modal._zone.is_empty() and modal._zoom == 1.0, "Escape returns to overview")
	_check(modal._current_live2d() == appearance and session.get_character_profile() == before and root.get_node("Gameplay").simulation.export_snapshot() == world_before, "selection and camera do not change appearance, session or world")
	modal.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	print("CREATOR_SELECTION_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
