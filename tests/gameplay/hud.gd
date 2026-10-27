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
	t.check(shell._hero._needs.keys() == ["hydration", "satiety", "hygiene", "bladder", "rested", "fun", "social"] and shell._hero._health.bar.value == t.gameplay.simulation.state.player.needs.health and shell._hero._energy.bar.value == t.gameplay.simulation.state.player.needs.energy, "HUD shows HP, stamina and the seven requested live needs without a portrait")
	t.check(shell._cash.text == "250 ¤" and shell._cash.autowrap_mode == TextServer.AUTOWRAP_OFF, "money remains a single readable line")
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
	var minute := int(t.session.get_game_time_snapshot().total_minutes)
	shell._wait.pressed.emit()
	t.check(int(t.session.get_game_time_snapshot().total_minutes) == minute + 15 and int(t.gameplay.simulation.state.clock.total_minutes) == minute + 15, "clock shortcut advances exactly fifteen minutes through the real game")
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
