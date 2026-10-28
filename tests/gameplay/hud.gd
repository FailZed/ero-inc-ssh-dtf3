extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var scene := Control.new()
	t.root.add_child(scene)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	var before: Dictionary = t.gameplay.simulation.export_snapshot()
	scene.add_child(shell)
	shell.open_panel("place")
	await t.process_frame
	t.check(t.gameplay.simulation.export_snapshot() == before, "rendering the game HUD does not change time, RNG or NPCs")
	t.check(not shell._sections_overlay.visible and not shell._close_panel.visible, "game starts on the scene with detailed navigation closed")
	for button in shell._dock_buttons.values():
		t.check(button.icon != null and button.text.is_empty() and not button.tooltip_text.is_empty(), "HUD shortcut is a real icon with a descriptive tooltip")
	t.check(shell._hero._needs.keys() == ["health", "energy", "hydration", "satiety", "hygiene", "bladder", "rested", "fun", "social"] and shell._hero._needs.health.value == t.gameplay.simulation.state.player.needs.health and shell._hero._needs.energy.value == t.gameplay.simulation.state.player.needs.energy, "HUD shows nine live needs without a portrait")
	var location_plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/location_interactions.json"))
	var missing_locations: Array = []
	for location in t.gameplay.simulation.catalog.locations:
		if not location_plan.locations.has(location): missing_locations.append(location)
	t.check(missing_locations.is_empty(), "editable location JSON covers every playable location: " + str(missing_locations))
	t.check(not shell._objective.visible and shell._world_hotspots._groups.has("bed"), "the scene hides the quest and exposes a bed action marker")
	shell._world_hotspots.present([{"caption":"Душ","kind":"hygiene"},{"caption":"Туалет","kind":"toilet"},{"caption":"Вода","kind":"thirst"}], "bathroom")
	t.check(shell._world_hotspots._markers.has("shower") and shell._world_hotspots._markers.has("toilet") and shell._world_hotspots._markers.has("sink"), "bathroom objects have separate scene markers")
	shell._world_hotspots.present([{"caption":"Каша","kind":"cook"},{"caption":"Омлет","kind":"cook"},{"caption":"Вода","kind":"thirst"}], "kitchen")
	t.check(shell._world_hotspots._groups.stove.size() == 2 and shell._world_hotspots._markers.has("sink"), "multiple recipes share one stove marker while the sink stays separate")
	shell._world_hotspots._activate_group("stove")
	t.check(shell._world_hotspots.menu_is_open() and shell._world_hotspots._menu.find_children("*", "ScrollContainer", true, false).size() == 1, "stove choices open a scrollable context menu")
	shell._world_hotspots.close_menu()
	shell._refresh()
	t.check(shell._cash.text == "250 ¤" and shell._cash.autowrap_mode == TextServer.AUTOWRAP_OFF, "money remains a single readable line")
	shell._book_button.pressed.emit()
	t.check(shell._book_overlay.visible and shell._world_hotspots.visible == false and shell.current_panel == "place", "the separate book opens over the unchanged scene")
	shell._book_overlay.hide_book()
	t.check(not shell._book_overlay.visible and shell._world_hotspots.visible, "closing the book restores scene actions")
	shell._world_hotspots._activate_group("bed")
	t.check(shell._world_hotspots.menu_is_open() and shell._world_hotspots._menu.find_children("*", "HSlider", true, false).size() == 1, "bed choices open a touch-friendly sleep slider")
	var sleep_slider: HSlider = shell._world_hotspots._menu.find_children("*", "HSlider", true, false)[0]
	sleep_slider.value = 90
	t.check(shell._world_hotspots._sleep_minutes == 90 and t.gameplay.simulation.export_snapshot() == before, "choosing ninety minutes of sleep changes only the pending UI value")
	shell._world_hotspots.close_menu()
	# The same icon opens and closes its actual game screen.
	shell._dock_buttons.inventory.pressed.emit()
	t.check(shell.current_panel == "inventory" and shell._close_panel.visible, "inventory icon opens the real inventory")
	shell._book_button.pressed.emit()
	t.check(shell.current_panel == "place" and shell._book_overlay.visible, "opening the book from inventory restores the live scene behind it")
	shell._book_overlay.hide_book()
	shell._dock_buttons.inventory.pressed.emit()
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
	var minute := int(t.session.get_game_time_snapshot().total_minutes)
	shell._wait.pressed.emit()
	t.check(shell.current_panel == "phone" and int(t.session.get_game_time_snapshot().total_minutes) == minute, "calendar shortcut opens the phone without advancing time")
	shell.open_panel("place")
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
	scene.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
