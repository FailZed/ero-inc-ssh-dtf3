extends Control
## Real Godot captures from a disposable in-memory world. Never saves a game slot.
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")
var destination := "res://docs/ui/captures/review"
var report: Array[Dictionary] = []
var quick := false
var interaction_only := false
var background_capture := false
var failures: Array[String] = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="): destination = arg.trim_prefix("--capture=")
		if arg == "--quick": quick = true
		if arg == "--interaction-only": interaction_only = true
		if arg == "--background-capture": background_capture = true
	if background_capture:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		DisplayServer.window_set_position(Vector2i(4000,4000))
	GameSession.pause_autosave_runtime()
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count = 12
	Gameplay._pending_configuration = config
	GameSession.reset_game_time()
	GameSession.reset_character_profile()
	Gameplay.complete_chapter_one()
	var shell := preload("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	add_child(shell)
	# Capture fixed presets in memory, without loading a player's personal image.
	shell._phone_view.preferences = preload("res://scripts/ui/gameplay/phone_preferences.gd").new()
	shell._phone_view.preferences.data_dir = "user://ui-review-phone-%d" % Time.get_ticks_usec()
	shell._phone_view.preferences.selected = "city"
	shell._phone_view.preferences.dimming = 0.22
	var original_scale: float = UI.text_scale
	if interaction_only:
		await _review_interaction(shell)
		return
	for id in ["place","map","profile","inventory","people","phone","journal","activities","work","club","home","health","family","digital","collection","interface"]:
		if quick and not id in ["place","profile","inventory","people","phone","journal","health","interface"]: continue
		shell.open_panel(id)
		await _capture(id, shell)
		if id == "place" and not quick:
			var original_location: String = Gameplay.simulation.state.world.location
			for room in ["apartment_hall","bathroom","kitchen"]:
				Gameplay.simulation.state.world.location = room
				shell.open_panel("place")
				await _capture("scene-"+room,shell)
			Gameplay.simulation.state.world.location = original_location
			shell.open_panel("place")
		if id == "profile" and not quick:
			for tab in ["skills", "perks"]:
				shell._select_profile_tab(tab)
				await _capture("profile-" + tab, shell)
			shell._select_profile_tab("attributes")
		if id == "phone":
			shell._phone_view._open_app("wallpapers")
			await _capture("phone-wallpapers",shell)
			shell._phone_view.preferences.selected = "rain"
			shell._phone_view._go_home()
			await _capture("phone-rain",shell)
			shell._phone_view.preferences.selected = "city"
			for app in ["contacts","messages","calendar","bank"]:
				if quick and not app in ["messages","contacts"]: continue
				shell._phone_view._open_app(app)
				await _capture("phone-"+app,shell)
			shell._phone_view.open_thread("ellie")
			Gameplay.execute("social","message",{"id":"ellie","text":"Привет! Как проходит твой день?"})
			var actor: Dictionary = Gameplay.simulation.state.social.npcs.ellie
			Gameplay.simulation.services.npc_agency._cancel(actor,"ui_review")
			actor.activity = "idle"
			actor.decision = {"committed":false}
			actor.schedule = []
			actor.pinned_until = int(Gameplay.simulation.state.clock.total_minutes)+1440
			shell._phone_view._begin_topics()
			var dialogue: Dictionary = Gameplay.simulation.services.npc_dialogue.present("ellie")
			if not dialogue.is_empty(): shell._phone_view._choose("goal",int(dialogue.turn))
			await _capture("phone-chat",shell)
			shell._phone_view._go_home()
		if not quick:
			var variants := {"activities":["activities_tab",["training","university","games"]],"work":["work_tab",["jobs","shop","channel","assets"]],"health":["health_tab",["treatment","adult_health","reproduction"]],"home":["home_tab",["properties","household"]],"journal":["journal_tab",["day","available","stories","history","achievements"]],"family":["family_tab",["duties","budget","history"]],"digital":["digital_tab",["history"]]}
			if variants.has(id):
				for tab in variants[id][1]:
					shell._choose_screen(tab,variants[id][0])
					await _capture(id+"-"+tab,shell)
			if id == "digital":
				var digital: Dictionary = Gameplay.simulation.state.digital
				var saved_pending: Dictionary = digital.pending.duplicate(true)
				var saved_serial: int = int(digital.serial)
				var operation_id := str(Gameplay.simulation.catalog.digital_operations.keys()[0])
				digital.serial = saved_serial+1
				digital.pending = {"id":operation_id,"token":digital.serial,"expires":int(Gameplay.simulation.state.clock.total_minutes)+1440}
				shell._choose_screen("tasks","digital_tab")
				await _capture("digital-approaches",shell)
				digital.pending = saved_pending
				digital.serial = saved_serial
				var workbench_checkpoint: Dictionary = Gameplay.simulation.export_snapshot()
				Gameplay.simulation.state.world.location = "bedroom"
				Gameplay.simulation.state.world.equipment = ["computer"]
				shell._choose_screen("workbench","digital_tab")
				shell._choose_screen("orders","computer_tab")
				await _capture("digital-workbench-orders",shell)
				var board: Array = Gameplay.simulation.services.computer.board()
				for offer in board:
					if bool(offer.locked): continue
					var accepted: Dictionary = Gameplay.execute("computer","take_project",{"id":offer.id})
					if accepted.ok:
						shell.open_panel("digital")
						await _capture("digital-workbench-active",shell)
					break
				Gameplay.simulation.restore_snapshot(workbench_checkpoint)
				shell.open_panel("digital")
			if id == "health":
				for tab in ["protection","family"]:
					shell._choose_screen(tab,"repro_tab")
					await _capture("health-repro-"+tab,shell)
	# Additional routes share the same modal navigation and material.
	if not quick:
		shell.open_panel("people")
		shell._show_npc_details("asuka")
		for tab in ["about","together","gifts","history"]:
			shell._choose_screen(tab,"person_tab")
			await _capture("person-"+tab,shell)
		shell._risk_actions("asuka")
		await _capture("risk",shell)
		shell.open_panel("gathering")
		await _capture("gathering",shell)
		shell.open_panel("profile")
		var growth := preload("res://scripts/ui/gameplay/growth_window.gd").new()
		shell.add_child(growth)
		for tab in ["skills","needs","habits"]:
			growth.page = tab
			growth._refresh()
			await _capture("growth-"+tab,growth)
		growth.queue_free()
		await get_tree().process_frame
		var work := preload("res://scripts/ui/gameplay/livelihood_window.gd").new()
		shell.add_child(work)
		for tab in ["jobs","orders","goals","home"]:
			work.page = tab
			work._refresh()
			await _capture("livelihood-"+tab,work)
		work.queue_free()
		await get_tree().process_frame
		var schedule := preload("res://scripts/ui/gameplay/work_schedule_window.gd").new()
		schedule.conflicts = [{"id":"computing","start":600,"end":720,"commute":30,"arrival":630,"deadline":615,"late_minutes":30,"can_attend":false},{"id":"physics","start":780,"end":900,"commute":30,"arrival":810,"deadline":795,"late_minutes":30,"can_attend":false}]
		shell.add_child(schedule)
		await _capture("work-schedule-conflict",schedule)
		schedule.queue_free()
		await get_tree().process_frame
		var story := preload("res://scripts/ui/gameplay/personal_story_window.gd").new()
		story.npc_id = "asuka"
		shell.add_child(story)
		await _capture("personal-story",story)
		story.queue_free()
		await get_tree().process_frame
		var curriculum := preload("res://scripts/ui/gameplay/curriculum_window.gd").new()
		shell.add_child(curriculum)
		await _capture("curriculum",curriculum)
		curriculum.queue_free()
		await get_tree().process_frame
		var confirm := preload("res://scripts/ui/gameplay/game_widgets.gd").confirm(shell,"Заменить сохранение?","Текущая игра займёт выбранный слот.","Сохранить",func(): pass)
		await _capture("confirmation",confirm)
		confirm.queue_free()
		await get_tree().process_frame
	shell.open_panel("place")
	shell._toggle_sections()
	await _capture("sections", shell)
	shell._toggle_sections()
	shell._queue.planning = true
	shell._queue.enqueue({"title":"Отдохнуть · 1 час", "module":"character", "operation":"rest", "args":{"minutes":60}})
	shell._queue.enqueue({"title":"Заняться хобби · 30 мин", "module":"needs", "operation":"leisure", "args":{}})
	await _capture("queue", shell)
	UI.text_scale = 1.25
	shell.theme = UI.skin()
	UI.apply_text_scale(shell)
	shell.open_panel("inventory")
	await _capture("inventory-text-125", shell)
	shell.open_panel("phone")
	shell._phone_view.open_thread("ellie")
	await _capture("phone-text-125",shell)
	shell.open_panel("interface")
	await _capture("interface-text-125", shell)
	if not quick:
		var large := preload("res://scripts/ui/gameplay/growth_window.gd").new()
		shell.add_child(large)
		await _capture("growth-text-125",large)
		large.queue_free()
		await get_tree().process_frame
	UI.text_scale = original_scale
	if quick:
		_finish()
		return
	shell.hide()
	var setup := preload("res://scenes/ui/WorldSetup.tscn").instantiate()
	add_child(setup)
	await _capture("new-game", setup)
	setup.page = 1
	setup._show_page()
	await _capture("difficulty", setup)
	setup.queue_free()
	await get_tree().process_frame
	var mirror := preload("res://scenes/ui/CharacterCreationModal.tscn").instantiate()
	add_child(mirror)
	mirror.open_with_profile(GameSession.get_character_profile(), GameSession.get_character_stat_labels(), {}, GameSession.get_character_appearance_options())
	await _capture("mirror", mirror)
	mirror._page = 1
	mirror._build_page()
	await _capture("mirror-character",mirror)
	mirror.queue_free()
	await get_tree().process_frame
	var menu := preload("res://scenes/mainMenu/main_menu.tscn").instantiate()
	add_child(menu)
	await _capture("main-menu", menu)
	menu.open_action("settings")
	await _capture("settings", menu)
	for tab in ["text","language"]:
		menu._show_settings_page(tab)
		await _capture("settings-"+tab,menu)
	menu.open_action("load_game")
	_preview_slots(menu,false)
	await _capture("load-game", menu)
	menu.menu_context = menu.MenuContext.IN_GAME
	menu._apply_menu_context()
	menu.show_overview()
	await _capture("pause-menu", menu)
	menu.open_action("save_game")
	_preview_slots(menu,true)
	await _capture("save-game", menu)
	menu.open_action("about")
	await _capture("about",menu)
	for child in menu.get_children():
		if child.get_script() == preload("res://scripts/ui/gameplay/game_window.gd"): child.queue_free()
	await get_tree().process_frame
	if ClassDB.class_exists("GDCubismUserModel"):
		menu._open_character_workshop()
		if is_instance_valid(menu._character_workshop):
			await _capture("character-workshop",menu._character_workshop)
			menu._character_workshop.queue_free()
			await get_tree().process_frame
	menu.queue_free()
	await get_tree().process_frame
	shell.show()
	shell.open_panel("place")
	var checkpoint: Dictionary = Gameplay.simulation.export_snapshot()
	Gameplay.simulation.state.social.npcs.asuka.location = Gameplay.simulation.state.world.location
	var combat := Gameplay.execute("encounters", "combat_start", {"npc":"asuka"})
	if combat.ok:
		shell.open_panel("place")
		await _capture("combat", shell)
	Gameplay.simulation.restore_snapshot(checkpoint)
	for type in ["timing","blackjack","reaction","guess","lockpick","strength","pushups"]:
		Gameplay.execute("encounters","game_start",{"type":type})
		shell.open_panel("place")
		await _capture("minigame" if type == "timing" else "minigame-"+type,shell)
		Gameplay.execute("encounters","cancel_game")
	shell.open_panel("place")
	Gameplay.simulation.state.social.npcs.asuka.location = Gameplay.simulation.state.world.location
	var conversation := preload("res://scripts/ui/gameplay/conversation_window.gd").new()
	conversation.configure("asuka", "free", shell._background.texture.resource_path)
	add_child(conversation)
	await _capture("conversation", conversation)
	if is_instance_valid(conversation._live_stage):
		var stage: Control = conversation._live_stage
		stage._toggle_categories()
		await _capture("conversation-categories",conversation)
		stage._toggle_categories()
		stage._toggle_tools()
		await _capture("conversation-utilities",conversation)
		stage._toggle_tools()
		for tab in stage._tabs:
			if str(tab.id) != stage._tab: continue
			for item in tab.get("items",[]):
				if not item.has("choices"): continue
				stage._open_folder(str(item.title))
				await _capture("conversation-submenu",conversation)
				break
			break
		stage._show_matrix()
		await _capture("conversation-matrix",conversation)
		stage._close_matrix()
		stage._show_history()
		await _capture("conversation-history",conversation)
		stage._close_detail()
	conversation.queue_free()
	await get_tree().process_frame
	Gameplay.simulation.restore_snapshot(checkpoint)
	var npc: Dictionary = Gameplay.simulation.state.social.npcs.asuka
	Gameplay.simulation.services.npc_agency._cancel(npc,"ui_review")
	npc.location = "bedroom"; npc.schedule = []; npc.activity = "rest"; npc.pinned_until = 0
	npc.needs.energy = 100.0
	Gameplay.simulation.state.player.needs.energy = 100.0
	var bond: Dictionary = Gameplay.simulation.services.npc_relationships._bond("asuka","player")
	bond.merge({"trust":80.0,"comfort":80.0,"interest":70.0},true)
	Gameplay.simulation.services.npc_relationships._project("asuka","player")
	Gameplay.execute("inventory","add",{"id":"barrier_protection","quantity":1})
	var private_time := Gameplay.execute("intimacy","begin",{"id":"asuka"})
	if private_time.ok:
		shell._refresh()
		await _capture("intimacy-invitation",shell)
		for choice in ["accept","non_reproductive","barrier","start","finish","close"]:
			var request: Dictionary = Gameplay.simulation.services.intimacy.presentation()
			Gameplay.execute("intimacy","choose",{"session":request.session,"revision":request.revision,"choice":choice})
			if choice == "non_reproductive":
				shell._refresh()
				await _capture("intimacy-decision",shell)
	shell.hide()
	Gameplay.phase = "story"
	Gameplay.begin_guide("night")
	var guide := preload("res://scripts/ui/gameplay/guided_exploration.gd").new()
	add_child(guide)
	await _capture("guided-room",guide)
	guide._toggle_journal()
	await _capture("guided-journal",guide)
	guide.queue_free()
	await get_tree().process_frame
	UI.background(self,"res://assets/textures/backgrounds/location_pack_v1/home_street_dusk.png",0.2)
	var timeline := DialogicTimeline.new()
	timeline.from_text("Город постепенно погружается в вечер. Впереди — новые знакомства и собственные планы.\nКуда отправиться сегодня?\n- Осмотреться в городе\n\tСамое время выбрать, куда отправиться.\n- Вернуться домой\n\tДома можно спокойно спланировать следующий день.")
	Dialogic.Styles.load_style("",self)
	var layout := Dialogic.start(timeline)
	await _settle_story_text("Город постепенно")
	await _capture("story-dialogue",layout)
	Dialogic.handle_next_event()
	await _settle_story_text("Куда отправиться")
	await _capture("story-choices",layout)
	var history: Control
	for child in layout.find_children("*","Control",true,false):
		if child.has_method("get_history_box") and child.has_method("show_history"): history = child; break
	if history != null:
		history.show_history()
		await _capture("story-history",layout)
		history._on_hide_history_pressed()
	UI.text_scale = 1.25
	for child in layout.get_children():
		if child.has_method("apply_export_overrides"): child.apply_export_overrides()
	await _capture("story-text-125",layout)
	UI.text_scale = original_scale
	await Dialogic.clear()
	var input_timeline := DialogicTimeline.new()
	input_timeline.from_text('[text_input text="Как к вам обращаться?" default="Алекс"]')
	layout = Dialogic.start(input_timeline)
	await get_tree().create_timer(0.4).timeout
	await _capture("story-text-input",layout)
	await Dialogic.clear()
	_finish()

func _settle_story_text(prefix: String) -> void:
	# Wait for the actual text event, including its entrance animation.
	for frame in range(360):
		for text in get_tree().get_nodes_in_group("dialogic_dialog_text"):
			if text.is_visible_in_tree() and text.get_parsed_text().begins_with(prefix):
				text.finish_text()
				for settle in range(3): await get_tree().process_frame
				if text.visible_characters >= text.get_total_character_count() or text.visible_characters == -1: return
		await get_tree().process_frame
	failures.append("Story text did not settle: "+prefix)
	push_error(failures[-1])

func _preview_slots(menu: Control, saving: bool) -> void:
	var entries: Array = []
	for i in range(6):
		entries.append({"id":"review-fixture-%d" % i,"title":"День %d · Эллизия" % (i+1),"saved_at_text":"27 октября · %02d:30" % (14+i),"is_empty":i>2,"can_primary_action":saving or i<3,"can_delete":i<3,"can_overwrite":i<3,"preview_texture":load("res://assets/textures/backgrounds/location_pack_v1/%s.png" % ["bedroom_night","home_street_dusk","hallway_night"][i%3])})
	menu.load_menu_panel.configure(1 if saving else 0,entries,[],[entries])
	menu.load_menu_panel.show_manual_section()

func _finish() -> void:
	var file := FileAccess.open(destination.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"Godot runtime; disposable test world, not a user playthrough", "viewport":str(get_viewport_rect().size), "captures":report,"failures":failures}, "\t"))
	print("UI_REVIEW_RESULT ", JSON.stringify({"captures":report.size(),"failed":failures.size(), "destination":destination}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture(id: String, surface: Node) -> void:
	if not background_capture: get_viewport().warp_mouse(Vector2(5, 5))
	for frame in range(4): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var bounds_ok := true
	if surface.has_method("open_panel") and surface._main_panel.visible:
		bounds_ok = get_viewport_rect().grow(1).encloses(surface._main_panel.get_global_rect())
	elif surface.has_method("open_panel") and surface.current_panel == "phone":
		bounds_ok = get_viewport_rect().grow(1).encloses(surface._phone_view._frame.get_global_rect())
	elif surface.has_method("open_panel") and surface.current_panel == "place":
		for control in [surface._header,surface._hero,surface._bottom]+[surface._scene_actions.panel]:
			if control.is_visible_in_tree(): bounds_ok = bounds_ok and get_viewport_rect().grow(1).encloses(control.get_global_rect())
	else:
		var modal := surface.find_child("GameWindow",true,false)
		if modal is Control: bounds_ok = get_viewport_rect().grow(1).encloses(modal.get_global_rect())
	if id.begins_with("story-"):
		for child in surface.find_children("*","Control",true,false):
			if child.is_visible_in_tree() and child.name in ["DialogTextPanel","DialogControlsPanel","ResponsePanel","TextInputPanel","HistoryBox"]:
				bounds_ok = bounds_ok and get_viewport_rect().grow(1).encloses(child.get_global_rect())
	DirAccess.make_dir_recursive_absolute(destination)
	var path := destination.path_join(id + ".png")
	var result := get_viewport().get_texture().get_image().save_png(path)
	report.append({"id":id, "path":path, "saved":result == OK, "main_window_inside_viewport":bounds_ok})
	if result != OK or not bounds_ok:
		failures.append("UI capture failed bounds/save: " + id)
		push_error(failures[-1])

func _review_interaction(shell: Control) -> void:
	var sim = Gameplay.simulation
	for id in ["asuka","ellie"]:
		var npc: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_agency._cancel(npc,"ui_review")
		npc.location = "bedroom"
		npc.activity = "idle"
		npc.schedule = []
		npc.pinned_until = int(sim.state.clock.total_minutes)+1440
	shell.open_panel("place")
	await _capture("place",shell)
	shell._dock_buttons.actions.pressed.emit()
	await _capture("bed-actions",shell)
	for page in ["people","places"]:
		shell._scene_actions.select_page(page)
		await _capture("scene-"+page,shell)
	for room in ["apartment_hall","bathroom","kitchen"]:
		sim.state.world.location = room
		shell.open_panel("place")
		shell._scene_actions.select_page("actions" if room != "apartment_hall" else "places")
		await _capture("scene-"+room,shell)
	sim.state.world.location = "bedroom"
	var clothing := ""
	for id in sim.catalog.items:
		var item: Dictionary = sim.catalog.items[id]
		if item.has("slot") and str(item.slot) != "weapon" and preload("res://scripts/mechanics/core/rules.gd").check(sim.state,item.get("requirements",{})):
			clothing = id; break
	if not clothing.is_empty(): Gameplay.execute("inventory","add",{"id":clothing})
	shell.open_panel("inventory")
	await _capture("inventory",shell)
	if not clothing.is_empty():
		sim.state.inventory.equipped[str(sim.catalog.items[clothing].slot)] = clothing
		shell._inventory_state.selected = clothing
		shell.open_panel("inventory")
		await _capture("inventory-equipped",shell)
	var scale_before: float = UI.text_scale
	UI.text_scale = 1.25
	shell.theme = UI.skin()
	UI.apply_text_scale(shell)
	shell.open_panel("inventory")
	await _capture("inventory-text-125",shell)
	shell.open_panel("place")
	shell._scene_actions.select_page("actions")
	await _capture("place-text-125",shell)
	UI.text_scale = scale_before
	shell.theme = UI.skin()
	UI.apply_text_scale(shell)
	shell.open_panel("place")
	shell._scene_actions.select_page("actions")
	shell._queue.planning = true
	shell._queue.enqueue({"title":"Отдохнуть · 1 час","module":"character","operation":"rest","args":{"minutes":60}})
	await _capture("queue",shell)
	_finish()
