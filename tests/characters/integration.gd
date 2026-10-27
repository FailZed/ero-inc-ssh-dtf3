extends SceneTree

var failed := 0
var passed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		push_error("FAIL: "+label)

func _run() -> void:
	await process_frame
	var menu := load("res://scenes/mainMenu/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	await process_frame
	var aside: Control = menu.aside_menu
	check(is_instance_valid(aside._workshop_button) and not aside._workshop_button.disabled,"menu entry enabled")
	var initial_pause := paused
	menu.open_action(&"character_workshop")
	await process_frame
	var workshop: Control = menu._character_workshop
	check(is_instance_valid(workshop),"opens workshop inside main menu")
	if not is_instance_valid(workshop): quit(1); return
	check(workshop.puppet.bank.definitions.size()==106,"integrated model loaded")
	check(paused == initial_pause,"opening preserves pause state")
	workshop._close()
	await process_frame
	check(not is_instance_valid(menu._character_workshop),"close frees workshop")
	check(aside._workshop_button.has_focus(),"keyboard focus restored")
	menu.menu_context = menu.MenuContext.IN_GAME
	menu._apply_menu_context()
	paused = true
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.open_action(&"character_workshop")
	await process_frame
	check(is_instance_valid(menu._character_workshop),"opens from pause menu")
	check(menu._character_workshop.can_process(),"workshop processes while game paused")
	menu._character_workshop._close()
	await process_frame
	check(paused,"closing preserves paused game")
	paused = initial_pause
	menu.free()
	await process_frame
	print("CHARACTERS_INTEGRATION_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(1 if failed else 0)
