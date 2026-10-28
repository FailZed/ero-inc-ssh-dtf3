extends RefCounted
var t
func _init(runner) -> void: t = runner

func _action(view: Control, operation: String) -> Button:
	for button in view._detail.find_children("*","Button",true,false):
		if button.get_meta("gameplay_action",{}).get("operation","") == operation: return button
	return null

func _select(view: Control, id: String) -> void:
	for button in view._grid.get_children():
		if button.get_meta("item_id","") == id: button.pressed.emit(); return

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	var clothing := ""
	for id in sim.catalog.items:
		var item: Dictionary = sim.catalog.items[id]
		if item.has("slot") and str(item.slot) != "weapon" and preload("res://scripts/mechanics/core/rules.gd").check(sim.state,item.get("requirements",{})):
			clothing = id; break
	t.check(not clothing.is_empty(),"inventory fixture has an available wearable item")
	if not clothing.is_empty(): t.gameplay.execute("inventory","add",{"id":clothing})
	var scene := Control.new()
	t.root.add_child(scene)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	scene.add_child(shell)
	shell.open_panel("inventory")
	var view = shell._body.get_child(0)
	var before: Dictionary = sim.export_snapshot()
	_select(view,"meal")
	t.check(view._grid.columns == 1 and view._grid.get_child_count() == sim.state.inventory.items.size(),"bag lists owned things without empty filler slots")
	t.check(before == sim.export_snapshot(),"selecting an item only shows its contextual actions")
	var count := int(sim.state.inventory.items.meal)
	var use := _action(view,"use")
	t.check(use != null and not use.disabled,"selected meal exposes its real use action")
	if use != null: use.pressed.emit()
	t.check(int(sim.state.inventory.items.get("meal",0)) == count-1 and shell.current_panel == "inventory","using one item updates the bag and keeps it open")
	view = shell._body.get_child(0)
	_select(view,"book")
	var read := _action(view,"perform")
	t.check(read != null and not read.disabled,"a selected book offers the existing reading action")
	var minute := int(sim.state.clock.total_minutes)
	if read != null: read.pressed.emit()
	t.check(int(sim.state.inventory.items.get("book",0)) > 0 and int(sim.state.clock.total_minutes) == minute+int(sim.catalog.actions.read.get("minutes",30)),"reading uses the book without consuming it and advances the actual activity duration")
	if not clothing.is_empty():
		view = shell._body.get_child(0)
		_select(view,clothing)
		var equip := _action(view,"equip")
		t.check(equip != null and not equip.disabled,"wearable item exposes equip")
		if equip != null: equip.pressed.emit()
		var slot: String = sim.catalog.items[clothing].slot
		t.check(sim.state.inventory.equipped.get(slot,"") == clothing,"equip changes the actual character equipment")
		view = shell._body.get_child(0)
		var remove := _action(view,"unequip")
		t.check(remove != null,"equipped item replaces equip with remove")
		if remove != null: remove.pressed.emit()
		t.check(not sim.state.inventory.equipped.has(slot) and int(sim.state.inventory.items.get(clothing,0)) > 0,"removing equipment returns it to owned things without consuming it")
		shell._back_panel()
		shell.open_panel("inventory")
		t.check(shell._inventory_state.selected == clothing,"returning to the bag preserves the chosen thing")
	shell.open_panel("place")
	before = sim.export_snapshot()
	for page in ["people","places","actions"]: shell._scene_actions.select_page(page)
	t.check(before == sim.export_snapshot(),"switching context lists consumes no time, items or random state")
	scene.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
