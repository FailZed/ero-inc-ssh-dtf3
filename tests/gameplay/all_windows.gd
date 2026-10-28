extends RefCounted
## Real screen navigation and overlay isolation in a disposable world.
var t
func _init(runner) -> void: t = runner

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var scene := Control.new()
	t.root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	scene.add_child(shell)
	shell.open_panel("people")
	shell._show_npc_details("asuka")
	shell.open_panel("phone")
	shell._back_panel()
	t.check(shell.current_panel == "npc","Back from a phone opened through a person restores that person's page")
	shell._risk_actions("asuka")
	shell._back_panel()
	t.check(shell.current_panel == "npc" and not shell._npc_risk,"Back leaves the risk page before leaving the person")
	shell._back_panel()
	t.check(shell.current_panel == "people","Back from a person restores the people roster")
	shell._back_panel()
	t.check(shell.current_panel == "place","screen history finally returns to the scene")
	var before: Dictionary = t.gameplay.simulation.export_snapshot()
	var growth = load("res://scripts/ui/gameplay/growth_window.gd").new()
	shell.add_child(growth)
	for page in ["skills","needs","habits"]:
		growth.page = page
		growth._refresh()
		await t.process_frame
		t.check(not growth._body.get_children().is_empty(),"growth window presents "+page)
	var key := InputEventKey.new()
	key.keycode = KEY_I
	key.pressed = true
	Input.parse_input_event(key)
	await t.process_frame
	t.check(shell.current_panel == "place","gameplay shortcuts cannot switch the screen behind a modal window")
	growth._window._tab_buttons.skills.grab_focus()
	growth._window._tab_buttons.skills.pressed.emit()
	for frame in range(2): await t.process_frame
	t.check(t.root.get_viewport().gui_get_focus_owner() == growth._window._tab_buttons.skills,"a rebuilt modal tab preserves keyboard focus")
	var focus_stays_inside := true
	for step in range(16):
		var next := InputEventAction.new()
		next.action = "ui_focus_next"
		next.pressed = true
		Input.parse_input_event(next)
		await t.process_frame
		var focused: Control = t.root.get_viewport().gui_get_focus_owner()
		focus_stays_inside = focus_stays_inside and focused != null and growth._window.is_ancestor_of(focused)
	t.check(focus_stays_inside,"Tab navigation remains inside the open game window")
	growth.queue_free()
	await t.process_frame
	var work = load("res://scripts/ui/gameplay/livelihood_window.gd").new()
	shell.add_child(work)
	for page in ["jobs","orders","goals","home"]:
		work.page = page
		work._refresh()
		t.check(not work._body.get_children().is_empty(),"work window presents "+page)
	work.queue_free()
	await t.process_frame
	t.check(before == t.gameplay.simulation.export_snapshot(),"browsing every new modal leaves world time, resources and random state unchanged")
	var menu = load("res://scenes/mainMenu/main_menu.tscn").instantiate()
	scene.add_child(menu)
	menu.open_action("settings")
	menu.settings_text_tab.pressed.emit()
	t.check(menu.text_settings_card.visible and not menu.settings_card.visible and not menu.language_settings_card.visible,"Text is a working settings tab with one visible page")
	menu.settings_language_tab.pressed.emit()
	t.check(menu.language_settings_card.visible and not menu.text_settings_card.visible,"Language is a working settings tab")
	menu.open_action("load_game")
	var entries: Array = []
	for i in range(6): entries.append({"id":"ui-slot-%d" % i,"title":"Тестовый слот","is_empty":false,"can_delete":false})
	menu.load_menu_panel.configure(0,entries,[],[entries])
	menu.load_menu_panel.show_manual_section()
	for frame in range(4): await t.process_frame
	t.check(menu.load_menu_panel.grid.columns == 3 and menu.load_menu_panel.body_margin.get_parent() is ScrollContainer,"six saves stay in a three-column grid with a bounded scroll viewport")
	menu.queue_free()
	await t.process_frame
	var accepted := [0]
	var dialog = load("res://scripts/ui/gameplay/game_widgets.gd").confirm(shell,"Подтверждение","Проверка отмены","Применить",func(): accepted[0] += 1)
	dialog.back_requested.emit()
	await t.process_frame
	t.check(accepted[0] == 0,"canceling a styled confirmation never executes its action")
	var card = load("res://scenes/mainMenu/save_slot_card.tscn").instantiate()
	scene.add_child(card)
	card.bind_entry({"id":"ui-fixture","title":"Тестовый слот","is_empty":false,"can_delete":false},false)
	var activated: Array = []
	card.primary_action_requested.connect(func(id): activated.append(id))
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	card._on_gui_input(accept)
	t.check(activated == ["ui-fixture"] and card.primary_button.visible,"save cards expose a visible action and keyboard activation without touching a save file")
	scene.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
