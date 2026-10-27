extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func _button(node: Node, caption: String) -> Button:
	for child in node.find_children("*","Button",true,false):
		if child.text == caption: return child
	return null

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	var scene := Control.new()
	t.root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	scene.add_child(shell)
	var before: Dictionary = sim.export_snapshot()
	shell.open_panel("phone")
	var phone = shell._phone_view
	var settings = load("res://scripts/ui/gameplay/phone_preferences.gd").new()
	settings.data_dir = "user://ui-phone-test-%d" % Time.get_ticks_usec()
	phone.preferences = settings
	t.check(phone.visible and not shell._main_panel.visible and not shell._header.visible and not shell._bottom.visible, "phone is a device over the world with the ordinary HUD put away")
	t.check(phone._frame.get_global_rect().size.x < phone._frame.get_global_rect().size.y * 0.65, "phone has a real portrait device shape")
	var app_buttons: Array = phone._body.find_children("*","Button",true,false).filter(func(button): return button.has_meta("phone_app"))
	t.check(app_buttons.size() == 6 and app_buttons.all(func(button): return button.icon is CompressedTexture2D and button.icon.resource_path.get_file().begins_with("app_")),"Android-style home apps use the six imported raster launcher icons")
	await t.process_frame
	var messages_button: Button
	for button in phone._body.find_children("*","Button",true,false):
		if button.tooltip_text == "Сообщения": messages_button = button; break
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = messages_button.get_viewport().get_screen_transform() * messages_button.get_global_transform_with_canvas() * (messages_button.size * 0.5)
	click.global_position = click.position
	click.pressed = true
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	var motion := InputEventMouseMotion.new()
	motion.position = click.position
	motion.global_position = click.position
	Input.parse_input_event(motion)
	await t.process_frame
	Input.parse_input_event(click)
	await t.process_frame
	click = click.duplicate()
	click.pressed = false
	click.button_mask = 0
	Input.parse_input_event(click)
	await t.process_frame
	t.check(phone.app == "messages", "real pointer input opens a phone app through the device surface")
	for app in ["contacts","messages","calendar","bank","wallpapers","home"]: phone._open_app(app)
	t.check(before == sim.export_snapshot(), "browsing phone apps changes neither world time, relationships nor random state")
	phone._open_app("wallpapers")
	for button in phone._body.find_children("*","Button",true,false):
		if button.get_meta("wallpaper_id","") == "rain": button.pressed.emit(); break
	t.check(phone._preview_choice == "rain" and settings.selected == "city","wallpaper tile selects a preview while preserving the installed background")
	phone._preview_dimming = 0.35
	_button(phone,"Установить").pressed.emit()
	t.check(phone.app == "home" and settings.selected == "rain" and phone._wallpaper.visible and phone._wallpaper.texture != null,"wallpaper gallery applies a raster background to the real phone home screen")
	var reloaded = load("res://scripts/ui/gameplay/phone_preferences.gd").new()
	reloaded.data_dir = settings.data_dir
	reloaded.load_settings()
	t.check(reloaded.selected == "rain" and is_equal_approx(reloaded.dimming,0.35),"phone wallpaper and dimming persist independently of game slots")
	phone._open_app("wallpapers")
	phone._preview_choice = "water"
	phone.go_back()
	t.check(settings.selected == "rain","Back cancels a wallpaper preview without changing the installed background")
	t.check(settings.choose("missing") == ERR_INVALID_PARAMETER and settings.selected == "rain","unknown wallpaper IDs preserve the current background")
	var fixture := Image.create(24,48,false,Image.FORMAT_RGBA8)
	fixture.fill(Color("23435f"))
	var source: String = settings.data_dir.path_join("fixture.png")
	fixture.save_png(source)
	phone._import_wallpaper(source)
	DirAccess.remove_absolute(source)
	t.check(settings.selected == "custom" and phone.app == "home" and settings.texture().get_width() == 24,"custom image is copied into phone settings and remains available after the original file is removed")
	reloaded.load_settings()
	t.check(reloaded.selected == "custom" and reloaded.texture() != null,"custom wallpaper survives reopening the phone settings")
	settings.choose("plain")
	phone._go_home()
	t.check(not phone._wallpaper.visible,"plain background remains available without a wallpaper image")
	t.check(before == sim.export_snapshot(),"installing and importing phone wallpapers never alters world state or game saves")
	phone.open_thread("ellie")
	var minute := int(sim.state.clock.total_minutes)
	var count: int = sim.state.social.messages.size()
	phone._composer.text = "Увидимся в городе."
	phone._composer.text_changed.emit(phone._composer.text)
	phone._send()
	t.check(sim.state.social.messages.size() == count+1 and sim.state.social.messages[-1].text == "Увидимся в городе." and not sim.state.social.messages[-1].incoming, "phone composer sends the actual player's text to the real contact")
	t.check(int(sim.state.clock.total_minutes) == minute, "sending an ordinary message respects the real zero-minute message rule")
	phone._composer.text = "Несохранённый черновик"
	phone._composer.text_changed.emit(phone._composer.text)
	phone._open_app("contacts")
	phone.open_thread("ellie")
	t.check(phone._composer.text == "Несохранённый черновик", "drafts survive changing phone apps")
	phone.drafts.ellie = ""
	phone._rebuild()
	count = sim.state.social.messages.size()
	phone._send()
	t.check(sim.state.social.messages.size() == count, "empty compose submissions do not create messages")
	var npc: Dictionary = sim.state.social.npcs.ellie
	sim.services.npc_agency._cancel(npc,"phone_ui_fixture")
	npc.schedule = []
	npc.decision = {"committed":false}
	npc.activity = "idle"
	npc.pinned_until = int(sim.state.clock.total_minutes)+1440
	npc.mind.boundaries.contact = true
	phone._begin_topics()
	var dialogue: Dictionary = sim.services.npc_dialogue.present("ellie")
	t.check(phone._session == "ellie" and not dialogue.is_empty() and not is_instance_valid(shell._conversation), "contextual phone dialogue stays inside the device")
	minute = int(sim.state.clock.total_minutes)
	phone._choose("goal",int(dialogue.turn))
	await t.process_frame
	t.check(int(sim.state.clock.total_minutes) == minute+3 and npc.mind.dialogue.node == "goal", "phone topic choice advances the real dialogue and clock exactly once")
	t.check(sim.state.social.messages[-1].kind == "npc_reply" and sim.state.social.messages[-1].read, "NPC replies become real read chat bubbles")
	var reply := str(sim.state.social.messages[-1].text)
	phone.drafts.ellie = "Спасибо!"
	phone._send()
	var visible_replies := 0
	for label in phone._body.find_children("*","Label",true,false):
		if label.text == reply: visible_replies += 1
	t.check(visible_replies == 1, "free-form messages do not fabricate or repeat a contextual NPC reply")
	for index in range(45):
		sim.state.social.messages.append({"id":sim.state.social.next_message_id,"npc":"ellie","text":"Запись для проверки прокрутки %d" % index,"incoming":false,"read":true,"minute":int(sim.state.clock.total_minutes)})
		sim.state.social.next_message_id += 1
	phone._history_limit = 100
	phone._rebuild()
	for frame in range(3): await t.process_frame
	phone._message_scroll.scroll_vertical = 0
	t.gameplay.execute("social","message",{"id":"ellie","text":"Новое входящее","incoming":true})
	for frame in range(3): await t.process_frame
	t.check(phone._message_scroll.scroll_vertical == 0, "incoming messages do not pull the reader away from older chat history")
	t.check(sim.state.social.messages[-1].read, "incoming messages are marked read while the thread is actually open")
	phone.go_back()
	t.check(phone.app == "messages" and npc.mind.dialogue.node == "end", "Back closes the active remote conversation and returns to chat list")
	phone.go_back()
	t.check(phone.app == "home", "Back from an app returns to the phone home screen")
	phone.go_back()
	t.check(shell.current_panel == "place" and not phone.visible and shell._header.visible, "Back from phone home puts the device away and restores the scene")
	shell.open_panel("phone")
	phone.open_person("ellie")
	phone.app = "meeting"
	phone._rebuild()
	minute = int(sim.state.clock.total_minutes)
	count = sim.state.social.appointments.size()
	_button(phone,"Предложить встречу").pressed.emit()
	t.check(phone.app == "calendar" and sim.state.social.appointments.size() == count+1 and int(sim.state.clock.total_minutes) == minute, "phone meeting form records the selected real appointment without consuming world time")
	phone._open_app("bank")
	var cash := int(sim.state.economy.cash)
	var bank := int(sim.state.economy.bank)
	_button(phone,"Внести на счёт").pressed.emit()
	t.check(int(sim.state.economy.cash) == cash-50 and int(sim.state.economy.bank) == bank+50, "phone banking uses the existing real money transaction")
	shell.open_panel("place")
	before = sim.export_snapshot()
	for entry in [["journal","journal_tab",["tasks","stories","history","achievements"]],["activities","activities_tab",["day","training","university","games"]],["work","work_tab",["projects","jobs","shop","channel","assets"]],["health","health_tab",["needs","treatment","reproduction"]],["home","home_tab",["room","properties","household"]],["family","family_tab",["care","duties","budget","history"]],["digital","digital_tab",["tasks","history"]]]:
		shell.open_panel(entry[0])
		for tab in entry[2]:
			shell._choose_screen(tab,entry[1])
			t.check(shell._body.get_child_count()>0,"game screen tab renders: %s / %s" % [entry[0],tab])
	t.check(before == sim.export_snapshot(), "all new game screens and action forecasts are read-only when browsed")
	shell._show_npc_details("ellie")
	for tab in ["about","together","gifts","history"]:
		shell._choose_screen(tab,"person_tab")
		t.check(shell._body.get_child_count()>0,"person screen renders " + tab)
	t.check(before == sim.export_snapshot(), "person actions, gifts and relationship history browsing consume no rewards or random state")
	scene.queue_free()
	await t.process_frame
	for file in ["settings.cfg","custom.png"]: DirAccess.remove_absolute(settings.data_dir.path_join(file))
	DirAccess.remove_absolute(settings.data_dir)
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
