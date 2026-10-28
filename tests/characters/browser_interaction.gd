extends SceneTree
var passed := 0
var failed := 0
var browser: Control
func check(ok: bool, title: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(title)
func _initialize() -> void:
	run.call_deferred()
func frames(count: int = 3) -> void:
	for i in range(count): await process_frame
func point_for(zone_id: String) -> Vector2:
	for mesh: MeshInstance2D in browser._pointer._meshes.values():
		if mesh.mesh.get_surface_count() == 0: continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, indices.size()-2, 3):
			var center: Variant = (vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0
			var point := mesh.to_global(Vector2(center.x,center.y))
			if browser._canvas.get_global_rect().has_point(point) and browser._pointer.hit_test(point).get("id", "") == zone_id: return point
	return Vector2.INF
func button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1440,960)
	browser = load("res://assets/characters/mdrg_study/scenes/browser.tscn").instantiate()
	root.add_child(browser)
	await frames(8)
	check(browser._model_ready, "browser loads native model")
	check(browser._current.name == "interaction_model", "interactive model selected on startup")
	check(browser._outfit_select.item_count == 3 and not browser._outfit_select.disabled, "clothes enabled")
	for zoom: float in [1.0, 1.3]:
		browser._pan = Vector2(35,-15)
		browser._set_zoom(zoom)
		await frames()
		for zone: String in ["head", "face", "hand_l", "hand_r", "body"]:
			var point := point_for(zone)
			check(point != Vector2.INF, "reachable " + zone)
			if point == Vector2.INF: continue
			button(point, true)
			check(browser._pointer.held.get("id", "") == zone, "routed press " + zone)
			if browser._pointer.held.is_empty(): continue
			var id: String = browser._pointer.held.x
			var saved_value: float = browser._pointer._saved[id].value
			var was_held: bool = browser._pointer._saved[id].hold
			var before: float = browser._actor.get_parameter_value(id)
			motion(point+Vector2(20,8))
			await frames()
			check(not is_equal_approx(before, browser._actor.get_parameter_value(id)), "routed drag " + zone)
			button(Vector2(4,4), false)
			check(is_equal_approx(saved_value, browser._actor.get_parameter_value(id)), "restored immediately on release " + zone)
			await frames()
			check(browser._pointer.held.is_empty(), "release outside canvas " + zone)
			check(browser._actor.is_parameter_held(id) == was_held, "restores hold ownership " + zone)
	for index in range(3):
		browser._outfit_select.select(index)
		browser._outfit_select.item_selected.emit(index)
		await frames()
		var title: String = browser._outfit_select.get_item_text(index)
		for id: String in browser._pointer.profile.outfits[title]:
			check(is_equal_approx(browser._actor.get_parameter_value(id), float(browser._pointer.profile.outfits[title][id])), "outfit " + title + " " + id)
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--capture="):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(arg.trim_prefix("--capture=").trim_suffix(".png") + "-outfit-%d.png" % index)
		browser._reset_pose()
		await frames()
		for id: String in browser._pointer.profile.outfits[title]:
			check(is_equal_approx(browser._actor.get_parameter_value(id), float(browser._pointer.profile.outfits[title][id])), "outfit survives pose reset " + id)
	browser._outfit_select.select(0)
	browser._select_outfit(0)
	await frames()
	var point := point_for("head")
	button(point, true)
	await frames()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await frames()
	check(browser._pointer.held.is_empty(), "escape releases")
	button(point, false)
	button(point, true)
	await frames()
	browser._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(browser._pointer.held.is_empty(), "focus loss releases")
	button(point, false)
	browser._select_model(browser._model_select.selected)
	await frames()
	check(browser._model_ready and browser._pointer.zones.size() == 5, "reload rebinds zones")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	browser.queue_free()
	await frames()
	print("BROWSER_INTERACTION_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(0 if failed == 0 else 1)
