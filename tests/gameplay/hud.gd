extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func _click(button: Button) -> void:
	# Controls rebuilt by map selection receive their final layout on a later frame.
	await t.process_frame
	await t.process_frame
	var position: Vector2 = button.get_viewport().get_screen_transform() * button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await t.process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = position
	click.global_position = position
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await t.process_frame
	click = click.duplicate()
	click.pressed = false
	click.button_mask = 0
	Input.parse_input_event(click)
	await t.process_frame

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var scene := Control.new()
	t.root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	var before: Dictionary = t.gameplay.simulation.export_snapshot()
	scene.add_child(shell)
	shell.open_panel("place")
	await t.process_frame
	t.check(t.gameplay.simulation.export_snapshot() == before, "rendering the game HUD does not change time, RNG or NPCs")
	t.check(not shell._sections_overlay.visible and not shell._close_panel.visible, "game starts on the scene with detailed navigation closed")
	for button in shell._dock_buttons.values():
		t.check(button.icon != null and button.text.is_empty() and not button.tooltip_text.is_empty(), "HUD shortcut is a real icon with a descriptive tooltip")
	t.check(shell._hero._needs.keys() == ["hydration", "satiety", "hygiene", "bladder", "rested", "fun", "social"] and shell._hero._health.value == t.gameplay.simulation.state.player.needs.health and shell._hero._energy.value == t.gameplay.simulation.state.player.needs.energy, "HUD shows live numeric HP, stamina and seven need icons without a portrait")
	t.check(not shell._main_panel.visible and shell._scene_actions.buttons.has("needs.sleep") and shell._scene_actions.actions.any(func(action): return action.id == "route.apartment_hall"),"the scene drawer exposes sleep and retains doorway actions")
	t.check(shell._cash.text == "250" and shell._cash.tooltip_text.contains("€$") and shell._cash.autowrap_mode == TextServer.AUTOWRAP_OFF, "money uses the compact credit mark and remains a single readable line")
	t.check(not shell._scene_actions.panel.is_visible_in_tree() and shell._hero._grid.columns == 3 and shell._hero._grid.get_child_count() == 9, "the scene starts uncluttered with a compact nine-need meter grid")
	await _click(shell._dock_buttons.actions)
	t.check(shell._scene_actions.panel.is_visible_in_tree() and shell._scene_actions.buttons["needs.sleep"].get_child_count() > 0, "the dock toggle opens illustrated scene actions")
	await _click(shell._scene_actions._tabs["people"])
	t.check(shell._scene_actions.page == "people" and shell._scene_actions.buttons.has("screen.people"), "the drawer switches to nearby people")
	shell._scene_actions.select_page("actions")
	await _click(shell._dock_buttons.actions)
	t.check(not shell._scene_actions.panel.is_visible_in_tree(), "the same dock toggle hides the action palette")
	shell.open_panel("map")
	await t.process_frame
	var original_marker: String = shell._city.selected
	var other_marker := ""
	for id in shell._city.markers:
		if id != original_marker: other_marker = str(id); break
	await _click(shell._city.markers[other_marker])
	t.check(shell._city.selected == other_marker, "real pointer input reaches a city marker beneath the HUD")
	await _click(shell._city.markers[original_marker])
	var map_back: Button = shell._city._card.find_children("*", "Button", true, false)[0]
	await _click(map_back)
	t.check(shell.current_panel == "place", "real pointer input reaches the map card and returns to the scene")
	t.check(t.gameplay.simulation.export_snapshot() == before, "map selection and return do not advance the world")
	shell._scene_actions.buttons["needs.sleep"].pressed.emit()
	t.check(shell._sleep_picker.visible and shell._sleep_picker.slider.value == 480 and t.gameplay.simulation.export_snapshot() == before, "sleep opens a duration slider without advancing time")
	shell._sleep_picker.slider.value = 75
	t.check(shell._sleep_picker._duration.text == "1 ч 15 мин", "sleep slider previews the selected duration")
	var cancel_sleep := InputEventKey.new()
	cancel_sleep.keycode = KEY_ESCAPE
	cancel_sleep.pressed = true
	shell._unhandled_input(cancel_sleep)
	t.check(not shell._sleep_picker.visible and shell.current_panel == "place" and t.gameplay.simulation.export_snapshot() == before, "Escape closes only the sleep picker without changing the world")
	shell._toggle_book()
	t.check(shell._book_overlay.visible and not shell._scene_actions.visible,"the separate book opens over the compact scene without advancing time")
	shell._book_overlay.hide_book()
	t.check(not shell._book_overlay.visible and shell._scene_actions.visible,"closing the book restores the existing compact scene controls")
	# The same icon opens and closes its actual game screen.
	shell._dock_buttons.inventory.pressed.emit()
	t.check(shell.current_panel == "inventory" and shell._close_panel.visible, "inventory icon opens the real inventory")
	shell._dock_buttons.inventory.pressed.emit()
	t.check(shell.current_panel == "place", "repeating a shortcut returns to the scene")
	shell._toggle_sections()
	t.check(shell._sections_overlay.visible and t.root.get_viewport().gui_get_focus_owner() != null, "all sections remain available with an initial keyboard focus")
	shell._nav_buttons.health.pressed.emit()
	t.check(shell.current_panel == "health" and not shell._sections_overlay.visible, "extended navigation opens a game section and closes its overlay")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	shell._unhandled_input(escape)
	t.check(shell.current_panel == "place", "Escape closes the section before requesting the pause menu")
	shell._toggle_hud()
	t.check(not shell._chrome.visible and shell._hud_hint.visible, "scene viewing mode hides the entire HUD and keeps its restore control")
	shell._unhandled_input(escape)
	t.check(shell._chrome.visible and not shell._hud_hint.visible, "Escape can restore the hidden HUD")
	t.check(t.gameplay.simulation.export_snapshot() == before, "opening and closing game UI consumes no world time or relationship rewards")
	shell._toggle_plan()
	shell._scene_actions.buttons["needs.leisure"].pressed.emit()
	t.check(shell._queue.entries.size() == 1 and t.gameplay.simulation.export_snapshot() == before,"a context hobby action enters the plan without advancing time")
	shell._queue._remove(0)
	shell._toggle_plan()
	shell._toggle_plan()
	shell._scene_actions.buttons["needs.sleep"].pressed.emit()
	shell._sleep_picker.slider.value = 90
	shell._sleep_picker.confirm_button.pressed.emit()
	t.check(shell._queue.entries.size() == 1 and int(shell._queue.entries[0].args.minutes) == 90 and t.gameplay.simulation.export_snapshot() == before, "planning queues the chosen sleep duration without advancing time")
	shell._queue._remove(0)
	shell._toggle_plan()
	var secondary: Array = shell._scene_actions.actions.map(func(action): return action.id)
	t.check("character.rest" in secondary and "world.clean" in secondary and "screen.map" in secondary,"the location menu retains rest, cleaning and map actions")
	var minute := int(t.session.get_game_time_snapshot().total_minutes)
	shell._wait.pressed.emit()
	t.check(int(t.session.get_game_time_snapshot().total_minutes) == minute + 15 and int(t.gameplay.simulation.state.clock.total_minutes) == minute + 15, "clock shortcut advances exactly fifteen minutes through the real game")
	shell._scene_actions.select_page("places")
	shell._scene_actions.buttons["route.apartment_hall"].pressed.emit()
	t.check(t.gameplay.simulation.state.world.location == "apartment_hall","the doorway row travels through the real world command")
	shell._scene_actions.buttons["route.bedroom"].pressed.emit()
	t.check(t.gameplay.simulation.state.world.location == "bedroom","the hall row returns to the bedroom")
	# Incoming messages appear as a badge, and the phone retains its real dialogue route.
	t.gameplay.simulation.state.social.messages.append({"id": t.gameplay.simulation.state.social.next_message_id, "npc": "ellie", "text": "Тестовое входящее", "incoming": true, "read": false, "minute": int(t.gameplay.simulation.state.clock.total_minutes)})
	t.gameplay.simulation.state.social.next_message_id += 1
	shell._refresh()
	t.check(not shell._phone_badge.text.is_empty() and shell._dock_buttons.phone.text.is_empty(), "unread phone messages use a badge on the icon")
	shell._dock_buttons.phone.pressed.emit()
	t.check(shell.current_panel == "phone", "phone icon opens contacts and contextual correspondence")
	t.gameplay.execute("encounters", "game_start", {"type": "timing"})
	shell.open_panel("place")
	t.check(shell._wait.disabled and not shell._close_panel.visible and shell._main_panel.anchor_left < 0.5, "active encounters get a full game window and disable the wait shortcut")
	t.gameplay.execute("encounters", "cancel_game")
	shell._refresh()
	var sleep_minute := int(t.gameplay.simulation.state.clock.total_minutes)
	shell._sleep_picker.show_picker()
	shell._sleep_picker.slider.value = 75
	shell._sleep_picker.confirm_button.pressed.emit()
	t.check(int(t.gameplay.simulation.state.clock.total_minutes) == sleep_minute + 75 and not shell._sleep_picker.visible, "confirming the slider sleeps for the selected duration")
	scene.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
