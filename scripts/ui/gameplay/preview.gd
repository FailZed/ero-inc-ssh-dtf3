extends Control
## Development scene: native windows, same presenters and commands as the main game.
var _mode := "guided"
var _capture_control: Control
func _ready() -> void:
	GameSession.pause_autosave_runtime()
	var destination := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): _mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--capture="): destination = arg.trim_prefix("--capture=")
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count = 16
	Gameplay._pending_configuration = config
	GameSession.reset_game_time()
	GameSession.reset_character_profile()
	match _mode:
		"city-matrix": add_child(preload("res://scripts/ui/world/weather_matrix.gd").new())
		"dialogue":
			preload("res://scripts/ui/gameplay/ui_factory.gd").background(self,"res://assets/textures/backgrounds/campus_v1/hall.tres",0.14)
			var timeline := DialogicTimeline.new()
			timeline.from_text("join Асука center\nАсука: Здесь легко заблудиться в первый день. Если захочешь, после занятий покажу тебе клубную комнату.\n- Спросить о клубе\n\tАсука: Мы готовим костюмы к фестивалю. Заходи, познакомлю с остальными.\n- Расспросить об университете\n\tАсука: Для начала найдём твою аудиторию.\n- Попрощаться\n\tАсука: Тогда увидимся после занятий.")
			Dialogic.start(timeline)
			for frame in range(240):
				await get_tree().process_frame
				if Dialogic.current_state == DialogicGameHandler.States.AWAITING_CHOICE: break
				if Dialogic.current_event_idx < 0 or Dialogic.current_event_idx >= Dialogic.current_timeline_events.size(): continue
				var event = Dialogic.current_timeline_events[Dialogic.current_event_idx]
				if event is DialogicTextEvent:
					if event.state == DialogicTextEvent.States.REVEALING: Dialogic.Text.skip_text_reveal()
					elif event.state == DialogicTextEvent.States.DONE: event.advance.emit()
		"faces": add_child(preload("res://scripts/ui/gameplay/face_study.gd").new())
		"setup": add_child(preload("res://scenes/ui/WorldSetup.tscn").instantiate())
		"difficulty":
			var setup := preload("res://scenes/ui/WorldSetup.tscn").instantiate()
			add_child(setup)
			setup.page = 1
			setup._show_page()
		"mirror":
			var mirror := preload("res://scenes/ui/CharacterCreationModal.tscn").instantiate()
			add_child(mirror)
			mirror.open_with_profile(GameSession.get_character_profile(),GameSession.get_character_stat_labels(),{},GameSession.get_character_appearance_options())
		"curriculum": add_child(preload("res://scripts/ui/gameplay/curriculum_window.gd").new())
		"guided","campus","resident":
			Gameplay.begin_guide("night" if _mode == "guided" else "campus")
			var exploration := preload("res://scripts/ui/gameplay/guided_exploration.gd").new()
			add_child(exploration)
			if _mode == "resident":
				var crowd: Array = Gameplay.story_crowd("campus_hall")
				if not crowd.is_empty(): exploration._open_resident(str(crowd[0]))
		_:
			var profile := GameSession.get_character_profile()
			profile.identity.full_name = "Алекс Ривер"
			if _mode == "hud-heroine":
				profile.identity.full_name = "Александра Ривер"
				profile.appearance.gender = "female"
			GameSession.apply_character_profile_v2(profile)
			Gameplay._on_profile_changed(GameSession.get_character_profile())
			Gameplay.complete_chapter_one()
			if _mode.begins_with("city-"):
				var pieces := _mode.split("-")
				var sim = Gameplay.simulation
				var hour := int({"morning":6,"day":12,"sunset":19,"night":23}.get(pieces[1],12))
				sim.state.clock = sim.calendar.snapshot(int(sim.state.clock.total_minutes)-int(sim.state.clock.minute_of_day)+hour*60)
				sim.state.world.weather = pieces[2]
				sim.state.world.location = "student_home" if pieces.size() < 4 else pieces[3]
			if _mode in ["people", "npc"]: Gameplay.execute("clock", "advance", {"minutes": 180})
			var shell := preload("res://scripts/ui/gameplay/gameplay_shell.gd").new()
			add_child(shell)
			shell.open_panel("map" if _mode == "map" else "people" if _mode == "people" else "place")
			if _mode.begins_with("city-") and _mode.split("-").size() < 4:
				shell.open_panel("map")
				shell._city.select("north_beach")
			if _mode == "hud-detail": _capture_control = shell._hero
			if _mode == "npc": shell._show_npc_details("asuka")
			if _mode == "sections": shell._toggle_sections()
			if _mode.begins_with("ui-"):
				var panel_id := _mode.trim_prefix("ui-")
				if panel_id == "queue":
					shell._queue.planning = true
					shell._queue.enqueue({"title":"Отдохнуть · 1 час", "module":"character", "operation":"rest", "args":{"minutes":60}})
					shell._queue.enqueue({"title":"Заняться хобби · 30 мин", "module":"needs", "operation":"leisure", "args":{}})
				else: shell.open_panel(panel_id)
			if _mode == "hud-hidden": shell._toggle_hud()
			if _mode.begins_with("systems-") or _mode.begins_with("integration-"):
				# Controlled world fixtures, using the same services and native windows.
				var sim = Gameplay.simulation
				if _mode.begins_with("integration-"):
					sim.state.world.equipment = ["computer", "stove"]
					sim.state.player.needs.social = 25.0
					sim.state.player.needs.fun = 35.0
					for id in ["asuka", "ellie"]:
						var person: Dictionary = sim.state.social.npcs[id]
						sim.services.npc_agency._cancel(person, "integration_capture")
						person.location = "bedroom"
						person.schedule = []
						person.activity = "idle"
						person.decision = {"committed":false}
						person.pinned_until = int(sim.state.clock.total_minutes) + 1440
						var bond: Dictionary = sim.services.npc_relationships._bond(id, "player")
						bond.trust = 30.0
						bond.comfort = 40.0
						sim.services.npc_relationships._project(id, "player")
					if _mode == "integration-condition":
						Gameplay.execute("clock", "advance", {"minutes":840})
						for need in sim.state.player.needs: sim.state.player.needs[need] = 80.0
						sim.state.world.location = "global_map"
						Gameplay.execute("character", "substance", {"id":"stimulant"})
						shell.open_panel("health")
					elif _mode == "integration-company":
						shell._gathering_guests.assign(["asuka", "ellie"])
						shell.open_panel("gathering")
					else:
						Gameplay.execute("social_rules", "promise", {"id":"asuka", "promise":"complete_project"})
						Gameplay.execute("economy", "project", {"id":"website_order", "minutes":60})
						shell.open_panel("journal" if _mode == "integration-journal" else "work")
				elif _mode == "systems-health":
					sim.state.player.needs.merge({"energy":24.0, "hydration":12.0, "rested":8.0, "fun":28.0, "hygiene":35.0}, true)
					shell.open_panel("health")
				elif _mode == "systems-work":
					sim.state.world.equipment = ["computer", "stove"]
					sim.services.social.execute("contact", {"id":"asuka"})
					sim.command("social", "appointment", {"id":"asuka", "minute":int(sim.state.clock.total_minutes)+30, "location":"global_map"})
					shell.open_panel("work")
				elif _mode == "systems-club":
					sim.command("organizations", "create", {"id":"creative_collective"})
					for id in ["asuka", "ellie"]:
						var person: Dictionary = sim.state.social.npcs[id]
						sim.services.npc_agency._cancel(person, "systems_capture")
						person.schedule = []
						person.activity = "idle"
						person.decision = {"committed":false}
						person.pinned_until = int(sim.state.clock.total_minutes)+1440
						sim.command("social", "contact", {"id":id})
						sim.services.npc_relationships._bond(id, "player").trust = 20.0
						sim.command("organizations", "recruit", {"id":"creative_collective", "npc":id})
					sim.command("institutions", "election", {"id":"creative_collective", "candidates":["asuka","ellie"]})
					shell.open_panel("club")
			if _mode == "hud-needs":
				# Presentation fixture only, never applied to an existing game or save.
				Gameplay.simulation.state.player.needs.merge({"health": 64.0, "energy": 19.0, "hydration": 35.0, "satiety": 22.0, "hygiene": 57.0, "bladder": 15.0, "rested": 42.0, "fun": 63.0, "social": 77.0}, true)
				Gameplay.simulation.state.player.xp = 58
				Gameplay.simulation.state.social.messages.append({"id": Gameplay.simulation.state.social.next_message_id, "npc": "ellie", "text": "Загляни в сообщения", "incoming": true, "read": false, "minute": int(Gameplay.simulation.state.clock.total_minutes)})
				Gameplay.simulation.state.social.next_message_id += 1
				shell._refresh()
			if _mode in ["conversation", "conversation-memory", "initiative", "message", "adult"]:
				# Controlled development world; every line and action is produced by the real runtime.
				var sim = Gameplay.simulation
				for npc in sim.state.social.npcs.values():
					sim.services.npc_agency._cancel(npc, "dialogue_capture")
					npc.schedule = []
					npc.decision = {"committed": false}
					npc.pinned_until = int(sim.state.clock.total_minutes) + 1440
				var actor: Dictionary = sim.state.social.npcs.asuka
				actor.location = "global_map"
				actor.home = "global_map"
				actor.activity = "idle"
				actor.needs.merge({"energy": 100.0, "satiety": 100.0, "hygiene": 100.0, "social": 70.0}, true)
				sim.state.world.location = "global_map"
				if not "asuka" in sim.state.social.contacts: sim.state.social.contacts.append("asuka")
				if _mode == "conversation-memory":
					sim.rng.seed = 123
					Gameplay.execute("security", "steal", {"npc": "asuka"})
				if _mode in ["initiative", "message"]:
					actor.pinned_until = 0
					if _mode == "message": sim.state.world.location = "bedroom"
					Gameplay.execute("clock", "advance", {"minutes": 15})
					shell.open_panel("phone" if _mode == "message" else "place")
					if _mode == "message":
						var offers: Array = sim.services.npc_dialogue.offers()
						if not offers.is_empty(): shell._open_conversation("asuka", "message", str(offers[0].initiative))
				else:
					shell.open_panel("place")
					shell._open_npc("asuka")
					var window = shell.get_child(shell.get_child_count() - 1)
					if _mode == "adult":
						window._dialogue_choice("more", int(actor.mind.dialogue.turn))
						window._dialogue_choice("adult", int(actor.mind.dialogue.turn))
					else: window._dialogue_choice("feelings" if _mode == "conversation-memory" else "goal", int(actor.mind.dialogue.turn))
	if not destination.is_empty():
		get_viewport().warp_mouse(Vector2(10, 10))
		for i in range(8): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if is_instance_valid(_capture_control):
			# Capture the actual Control's screen region, without a separate UI mockup.
			var region := _capture_control.get_global_rect().grow(12)
			var factor := Vector2(image.get_size()) / get_viewport_rect().size
			var pixels := Rect2i(Rect2(region.position * factor, region.size * factor))
			image = image.get_region(pixels.intersection(Rect2i(Vector2i.ZERO, image.get_size())))
		DirAccess.make_dir_recursive_absolute(destination)
		image.save_png(destination.path_join(_mode+".png"))
		print("CAPTURED ",_mode)
		get_tree().quit()
