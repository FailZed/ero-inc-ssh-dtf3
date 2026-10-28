extends "res://tests/gameplay/run.gd"
## Small keyboard regression pass; all state is disposable and autosave is paused.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
var shell

func _frames() -> void:
	for index in range(4): await process_frame

func _key(code: Key, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await _frames()

func _owner() -> Control:
	return root.gui_get_focus_owner()

func _view(): return shell._body.get_child(0)

func _item(id: String) -> Button:
	for button in _view()._grid.get_children():
		if button.get_meta("item_id","") == id: return button
	return null

func _action(operation: String) -> Button:
	for button in _view()._detail.find_children("*","Button",true,false):
		if button.get_meta("gameplay_action",{}).get("operation","") == operation: return button
	return null

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	fresh_world()
	gameplay.complete_chapter_one()
	root.size = Vector2i(1366,768)
	var scene := Control.new()
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	scene.add_child(shell)
	await _frames()
	var drawer = shell._scene_actions
	for page in ["people","places","actions"]:
		drawer._tabs[page].grab_focus()
		await _key(KEY_ENTER)
		check(drawer.page == page,"Enter switches to the %s scene tab" % page)
		await _key(KEY_UP)
		check(_owner() != null and drawer._body.is_ancestor_of(_owner()),"Up from %s tab reaches its rebuilt list" % page)
		await _key(KEY_DOWN)
		check(_owner() == drawer._tabs[page],"Down from the last %s row returns to its active tab" % page)
	# Tab must leave a rebuilt list and still reach the other HUD controls.
	drawer.select_page("actions")
	await _frames()
	drawer._tabs.actions.grab_focus()
	await _key(KEY_RIGHT)
	check(_owner() == drawer._tabs.people,"Right moves between the contextual tabs")
	await _key(KEY_LEFT)
	check(_owner() == drawer._tabs.actions,"Left returns to the previous contextual tab")
	var visited: Array[Control] = []
	drawer._tabs.actions.grab_focus()
	for index in range(35):
		await _key(KEY_TAB)
		if _owner() != null and not _owner() in visited: visited.append(_owner())
	check(visited.any(func(control): return drawer._body.is_ancestor_of(control)),"Tab visits contextual actions after switching pages")
	check(visited.any(func(control): return not drawer.is_ancestor_of(control)),"Tab can leave the compact scene panel for the HUD")
	visited.clear()
	for index in range(35):
		await _key(KEY_TAB,true)
		if _owner() != null and not _owner() in visited: visited.append(_owner())
	check(visited.any(func(control): return drawer._body.is_ancestor_of(control)) and visited.any(func(control): return not drawer.is_ancestor_of(control)),"Shift+Tab crosses both the scene list and HUD after rebuilding")
	var fold: Button = drawer._title.get_parent().get_child(1)
	fold.grab_focus()
	await _key(KEY_ENTER)
	check(drawer.collapsed,"keyboard folds the scene panel")
	await _key(KEY_TAB)
	check(_owner() != null and not drawer._body.is_ancestor_of(_owner()),"Tab skips the folded scene list")
	fold.grab_focus()
	await _key(KEY_ENTER)
	drawer._tabs.actions.grab_focus()
	await _key(KEY_UP)
	check(not drawer.collapsed and _owner() != null and drawer._body.is_ancestor_of(_owner()),"unfolding restores directional navigation into the scene list")
	shell.open_panel("inventory")
	await _frames()
	var view = _view()
	var options: Array[Node] = view.find_children("*","OptionButton",true,false)
	options[0].grab_focus()
	await _key(KEY_SPACE)
	check(options[0].get_popup().visible,"keyboard opens the inventory category popup")
	await _key(KEY_ESCAPE)
	check(shell.current_panel == "inventory" and not options[0].get_popup().visible and _owner() == options[0],"Esc closes only the category popup and returns focus to its selector")
	view._tools[0].text = "Нет такой вещи"
	view._tools[0].text_changed.emit("Нет такой вещи")
	view._tools.back().grab_focus()
	await _key(KEY_DOWN)
	check(_owner() == view._tools.back(),"an empty search leaves a valid focus target instead of a deleted item row")
	view._tools[0].text = ""
	view._tools[0].text_changed.emit("")
	_item("meal").grab_focus()
	await _key(KEY_ENTER)
	check(_owner() == _item("meal"),"selecting an item with Enter restores focus to the replacement row")
	await _key(KEY_RIGHT)
	check(_owner() == _action("use"),"Right from the selected meal reaches its use action")
	await _key(KEY_LEFT)
	check(_owner() != null and _view()._grid.is_ancestor_of(_owner()),"Left from the item action returns to the owned list")
	await _key(KEY_TAB)
	check(_owner() != null and view.is_ancestor_of(_owner()),"Tab from a rebuilt inventory row remains usable")
	var count := int(gameplay.simulation.state.inventory.items.meal)
	_action("use").grab_focus()
	await _key(KEY_ENTER)
	check(int(gameplay.simulation.state.inventory.items.get("meal",0)) == count-1,"keyboard use consumes exactly one item")
	check(_owner() != null and _view().is_ancestor_of(_owner()) and shell._inventory_state.selected == "meal","using an item retains selection and usable inventory focus")
	var clothing := ""
	for id in gameplay.simulation.catalog.items:
		var item: Dictionary = gameplay.simulation.catalog.items[id]
		if item.has("slot") and item.slot != "weapon" and preload("res://scripts/mechanics/core/rules.gd").check(gameplay.simulation.state,item.get("requirements",{})):
			clothing = id; break
	gameplay.execute("inventory","add",{"id":clothing})
	await _frames()
	_item(clothing).grab_focus()
	await _key(KEY_ENTER)
	_action("equip").grab_focus()
	await _key(KEY_ENTER)
	check(_action("unequip") != null and _owner() == _item(clothing),"equip returns focus to the selected item after the action changes")
	_action("unequip").grab_focus()
	await _key(KEY_ENTER)
	check(_action("equip") != null and _owner() == _item(clothing),"unequip returns focus to the same owned item")
	await _key(KEY_ESCAPE)
	check(shell.current_panel == "place","Esc from the inventory returns to the scene")
	shell.open_panel("inventory")
	await _frames()
	check(_owner() == _item(clothing),"reopening the inventory focuses the selected owned item")
	var previous_scale := UI.text_scale
	UI.text_scale = 1.25
	var names = load("res://scripts/gameplay/presentation.gd")
	var old_title: Dictionary = names._content_labels.get(clothing,{}).duplicate(true)
	names._content_labels[clothing] = {"label":"Утеплённая городская куртка с внутренними карманами и съёмным капюшоном"}
	shell._refresh()
	await _frames()
	var row := _item(clothing)
	check(shell._main_panel.size.x <= shell._main_panel.get_parent_control().size.x*0.64+1 and _view().size.x <= shell._body.size.x+1,"long item name at 125% preserves the compact inventory width")
	print("UI_FOCUS_LONG_NAME ",JSON.stringify({"row":str(row.get_global_rect()),"view":str(_view().get_global_rect()),"detail":str(_view()._detail.get_global_rect()),"panel":str(shell._main_panel.get_global_rect()),"viewport":str(root.get_visible_rect())}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(arg.trim_prefix("--capture="))
	if old_title.is_empty(): names._content_labels.erase(clothing)
	else: names._content_labels[clothing] = old_title
	UI.text_scale = previous_scale
	scene.queue_free()
	await _frames()
	print("UI_FOCUS_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
