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
	scene.add_child(shell)
	var before: Dictionary = t.gameplay.simulation.export_snapshot()
	for id in ["inventory","profile","health","family","people","phone","journal","activities","work","club","home","digital","collection","interface"]:
		shell.open_panel(id)
		t.check(shell._phone_view.visible if id == "phone" else not shell._title.text.is_empty() and shell._body.get_child_count() > 0, "game screen renders and identifies " + id)
	for id in ["family","digital","collection"]:
		t.check(shell._nav_buttons.has(id), "on-demand section browser exposes " + id)
	shell.open_panel("journal")
	shell._choose_screen("available", "journal_tab")
	t.check(shell._body.find_children("*", "Button", true, false).any(func(button): return button.text == "Принять"), "journal exposes a real quest acceptance action")
	shell._choose_screen("day", "journal_tab")
	t.check(shell._body.find_children("*", "Label", true, false).any(func(label): return "Обязательные деньги" in label.text), "journal shows the shared day budget and priorities")
	shell.open_panel("digital")
	shell._choose_screen("workbench", "digital_tab")
	for tab in ["orders", "practice", "operations", "broadcast"]:
		shell._choose_screen(tab, "computer_tab")
		t.check(shell._body.get_child_count() > 0, "staged computer workbench renders " + tab)
	shell.open_panel("profile")
	for tab in ["skills", "perks", "attributes"]:
		shell._select_profile_tab(tab)
		t.check(shell._profile_tab == tab and shell._body.get_child_count() > 0, "minimal profile tab opens " + tab)
	shell.open_panel("inventory")
	var inventory = shell._body.get_child(0)
	t.check(inventory.has_signal("action_requested"), "inventory uses a shared real command route")
	var search: LineEdit = inventory.find_children("*", "LineEdit", true, false)[0]
	search.text = "definitely_missing_item"
	search.text_changed.emit(search.text)
	t.check(inventory._grid.get_child_count() == 1 and inventory._grid.get_child(0) is Label, "inventory search has a readable empty state")
	search.text = ""
	search.text_changed.emit("")
	t.check(not inventory._grid.get_children().is_empty(), "clearing search restores inventory items")
	t.check(t.gameplay.simulation.export_snapshot() == before, "all section browsing and inventory search leave simulation and RNG untouched")
	shell.open_panel("place")
	var queue = shell._queue
	t.check(not queue.visible, "empty plan stays hidden in the minimal HUD")
	shell._toggle_plan()
	t.check(queue.visible and queue.planning, "Q route opens the optional action plan")
	shell._toggle_plan()
	var entry := {"title":"Отдохнуть · 15 мин", "module":"character", "operation":"rest", "args":{"minutes":15}}
	queue.planning = true
	shell._context_action(shell._act.bind("character", "rest", {"minutes":15}), "Отдохнуть · 15 мин")
	t.check(queue.entries.size() == 1 and before == t.gameplay.simulation.export_snapshot(), "planning captures a real action without spending time")
	queue._remove(0)
	t.check(queue.entries.is_empty() and before == t.gameplay.simulation.export_snapshot(), "removing a planned action leaves the world unchanged")
	for i in range(7): queue.enqueue(entry)
	t.check(queue.entries.size() == 6, "plan has a bounded six-action capacity")
	queue.entries.clear()
	queue.enqueue(entry)
	queue.enqueue(entry)
	var minute := int(t.gameplay.simulation.state.clock.total_minutes)
	queue._toggle_run()
	await t.process_frame
	queue.stop()
	t.check(int(t.gameplay.simulation.state.clock.total_minutes) == minute + 15 and queue.entries.size() == 1, "first queued action executes once and pause preserves the next")
	await t.create_timer(0.75).timeout
	t.check(int(t.gameplay.simulation.state.clock.total_minutes) == minute + 15, "paused timers cannot execute a stale queued command")
	queue.entries.clear()
	queue.enqueue({"title":"Недоступный душ", "module":"world", "operation":"shower", "args":{}})
	before = t.gameplay.simulation.export_snapshot()
	queue._toggle_run()
	await t.process_frame
	t.check(not queue.running and queue.entries.size() == 1 and before == t.gameplay.simulation.export_snapshot(), "unavailable queued action stops atomically and remains reviewable")
	queue.entries.clear()
	queue.enqueue(entry)
	queue._toggle_run()
	shell.open_panel("journal")
	await t.process_frame
	t.check(not queue.running and before == t.gameplay.simulation.export_snapshot(), "opening a screen cancels a pending deferred execution")
	shell._choose_screen("day", "journal_tab")
	t.check(shell._body.find_children("*", "Label", true, false).any(func(label): return "Прогноз текущего плана" in label.text) and before == t.gameplay.simulation.export_snapshot(), "day view forecasts the queued action without changing world or RNG")
	var cancel := InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B
	cancel.pressed = true
	shell._unhandled_input(cancel)
	t.check(shell.current_panel == "place", "controller cancel returns from a screen to the scene")
	scene.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
