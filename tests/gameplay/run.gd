extends SceneTree
## In-memory integration tests. Never writes or deletes a user's save slot.
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const Guide = preload("res://scripts/gameplay/guided_story.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
const Simulation = preload("res://scripts/mechanics/simulation.gd")
var checks := 0
var failures: Array[String] = []
var gameplay
var session
var dialogic

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description); printerr("FAIL: ",description)

func fresh_world(difficulty: String = "normal") -> void:
	var config := Setup.defaults()
	config.population.count = 8
	config.difficulty = difficulty
	gameplay._pending_configuration = config
	dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	session.reset_character_profile()

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	fresh_world()
	check(gameplay.simulation.configuration_error.is_empty(),"gameplay catalog validates")
	check(gameplay.simulation.state.social.npcs.size() == 8,"settings create exactly one population")
	for npc in gameplay.simulation.state.social.npcs.values(): check(npc.home == "residential_district","residents never live in player's bedroom")
	_test_story_residents()
	preload("res://tests/gameplay/portraits.gd").run(self)
	preload("res://tests/gameplay/pregnancy_visuals.gd").run(self)
	var before: Dictionary = gameplay.simulation.export_snapshot()
	check(not gameplay.execute("clock","advance",{"minutes":10}).ok,"free actions locked in chapter")
	check(before == gameplay.simulation.export_snapshot(),"locked actions consume no time or RNG")
	gameplay.set_story_date(8,31,3,20)
	gameplay.begin_guide("night")
	check(not gameplay.guided_travel("bathroom").ok,"cannot skip the corridor")
	check(gameplay.inspect_story_object("photo").ok,"optional inspection works")
	check(gameplay.story_flags.guide_stage == "night","optional inspection does not advance story")
	check(gameplay.guided_travel("apartment_hall").ok,"player walks into hallway")
	check(not gameplay.guided_travel("street").ok,"leaving at night is gated")
	check(gameplay.guided_travel("kitchen").ok,"optional kitchen exploration allowed")
	check(gameplay.inspect_story_object("kettle").ok,"optional kitchen object")
	gameplay.guided_travel("apartment_hall")
	gameplay.guided_travel("bathroom")
	var requested: Array = []
	var callback := func(timeline): requested.append(timeline)
	gameplay.story_requested.connect(callback)
	gameplay.inspect_story_object("sink")
	check(requested == ["scene_05_mirror_and_photo/"],"sink resumes mirror scene exactly once")
	check(not gameplay.inspect_story_object("sink").ok,"completed guide action is not repeatable")
	var profile: Dictionary = session.get_character_profile()
	profile.identity.full_name = "Тестовый Герой"
	profile.stats.strength = 15
	profile.stats.agility = 15
	check(session.apply_character_profile_v2(profile),"creator accepts difficulty budget")
	gameplay._on_profile_changed(session.get_character_profile())
	check(gameplay.simulation.state.player.stats.strength == 15,"creator reaches runtime stats")
	gameplay.begin_guide("return_to_bed")
	gameplay.guided_travel("apartment_hall")
	gameplay.guided_travel("bedroom")
	gameplay.inspect_story_object("wardrobe")
	check(gameplay.story_flags.guide_stage == "photo","changing pillow enables photo objective")
	gameplay.inspect_story_object("photo")
	check(requested.back() == "scene_05_mirror_and_photo/photo","photo starts flashback")
	gameplay.begin_guide("morning_dress")
	gameplay.inspect_story_object("wardrobe")
	check(gameplay.story_flags.guide_stage == "morning_wash","morning dressing is required")
	gameplay.guided_travel("apartment_hall")
	gameplay.guided_travel("bathroom")
	gameplay.inspect_story_object("sink")
	gameplay.guided_travel("apartment_hall")
	gameplay.inspect_story_object("door")
	check(requested.back() == "chapter_one/arrival","morning exit continues first day")
	check(gameplay.apply_curriculum(["computing","physics"],"running"),"curriculum records subjects and sport")
	check(not gameplay.apply_curriculum(["computing","computing"],"running"),"duplicate subjects rejected")
	gameplay.story_flags.guide_stage = ""
	gameplay.story_flags.oliver = "quiet"
	gameplay.complete_chapter_one()
	check(gameplay.phase == "free_roam","world unlocks only at chapter completion")
	check(gameplay.simulation.state.clock.month_number == 9 and gameplay.simulation.state.clock.day == 1,"world starts on script date")
	check(gameplay.simulation.state.player.points == 10,"unspent creation points carried exactly once")
	check(gameplay.simulation.state.social.npcs.oliver.gender == "male","authored Oliver gender is correct")
	check(gameplay.simulation.state.social.npcs.ellie.gender == "female","authored Ellie gender is correct")
	for id in ["asuka","oliver","ellie"]: check(gameplay.simulation.state.social.npcs[id].cohort == "learner","authored student retains their university role: " + id)
	check(gameplay.simulation.state.social.contacts.has("ellie"),"class representative becomes a contact")
	var opening: Dictionary = gameplay.simulation.export_snapshot()
	gameplay.complete_chapter_one()
	check(opening == gameplay.simulation.export_snapshot(),"chapter rewards cannot be repeated")
	check(gameplay.execute("actions","perform",{"id":"exercise"}).ok,"independent activities are available in the main game")
	check(gameplay.simulation.state.journal.quests.first_steps.objectives.practice == 1,"actual exercise advances the opening objective")
	check(gameplay.execute("actions","perform",{"id":"read"}).ok,"starting book supports an independent reading action")
	var minute := int(session.get_game_time_snapshot().total_minutes)
	check(gameplay.execute("world","travel",{"id":"apartment_hall"}).ok,"free travel enabled")
	check(session.get_game_time_snapshot().total_minutes == minute+1,"travel advances clock once")
	check(gameplay.simulation.state.clock.total_minutes == minute+1,"runtime and session clocks agree")
	check(gameplay.execute("world","travel",{"id":"global_map"}).ok,"city reachable")
	check(gameplay.execute("inventory","buy",{"id":"desk","shop":"market"}).ok,"furniture available in main economy")
	check(gameplay.execute("inventory","buy",{"id":"bandage","shop":"market"}).ok,"medicine available in main economy")
	var replay: Dictionary = gameplay.simulation.export_snapshot()
	check(not gameplay.execute("inventory","buy",{"id":"computer","quantity":999,"shop":"market"}).ok,"unaffordable trade fails")
	check(replay == gameplay.simulation.export_snapshot(),"failed main action is atomic")
	gameplay.execute("encounters","game_start",{"type":"blackjack","stake":10})
	var cash := int(gameplay.simulation.state.economy.cash)
	check(gameplay.execute("encounters","cancel_game").ok,"minigame can be abandoned")
	check(gameplay.simulation.state.economy.cash == cash,"abandoning never refunds the stake")
	var stored: Dictionary = dialogic.VAR.var_storage.World.duplicate(true)
	var state: Dictionary = gameplay.simulation.export_snapshot()
	var random_state := str(gameplay.simulation.rng.state)
	gameplay.execute("world","travel",{"id":"apartment_hall"})
	dialogic.VAR.var_storage.World = stored
	session._sync_game_time_from_dialogic()
	check(gameplay.simulation.export_snapshot() == state,"existing World restore returns whole runtime without slot edits")
	check(str(gameplay.simulation.rng.state) == random_state,"restore retains deterministic RNG")
	check(gameplay.phase == "free_roam","restoration retains unlocked phase")
	preload("res://tests/gameplay/npc_life.gd").new(self).run()
	preload("res://tests/gameplay/player_needs.gd").new(self).run()
	preload("res://tests/gameplay/systems.gd").new(self).run()
	await preload("res://tests/gameplay/dialogue.gd").new(self).run()
	_test_selected_lessons()
	if not "--skip-timelines" in OS.get_cmdline_user_args(): _test_timeline_links()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await _test_windows()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await preload("res://tests/gameplay/hud.gd").new(self).run()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await preload("res://tests/gameplay/ui_redesign.gd").new(self).run()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await preload("res://tests/gameplay/game_ui.gd").new(self).run()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await preload("res://tests/gameplay/integration_routes.gd").new(self).run()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await preload("res://tests/gameplay/city.gd").new(self).run()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await preload("res://tests/gameplay/remaining.gd").new(self).run()
	if not "--skip-windows" in OS.get_cmdline_user_args(): await preload("res://tests/gameplay/reproduction.gd").new(self).run()
	preload("res://tests/gameplay/npc_reproduction.gd").new(self).run()
	await preload("res://tests/gameplay/pregnancy_wellbeing.gd").new(self).run()
	await preload("res://tests/gameplay/adult_health.gd").new(self).run()
	preload("res://tests/gameplay/health_relationships.gd").new(self).run()
	await preload("res://tests/gameplay/health_care_plans.gd").new(self).run()
	await preload("res://tests/gameplay/care_access.gd").new(self).run()
	await preload("res://tests/gameplay/family_handoff.gd").new(self).run()
	preload("res://tests/gameplay/npc_planner.gd").new(self).run()
	gameplay.story_requested.disconnect(callback)
	print("GAMEPLAY_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _test_story_residents() -> void:
	gameplay.begin_guide("campus")
	var before: Dictionary = gameplay.simulation.export_snapshot()
	var crowd: Array = gameplay.story_crowd("campus_hall")
	check(not crowd.is_empty(),"generated population supplies students in chapter")
	check(crowd == gameplay.story_crowd("campus_hall"),"returning to a room retains its cast")
	check(gameplay.story_crowd("bedroom").is_empty(),"strangers never appear in player's home")
	check(before == gameplay.simulation.export_snapshot(),"looking at a crowd consumes no RNG or world time")
	for id in crowd:
		check(str(id).begins_with("resident_") and gameplay.simulation.state.social.npcs[id].cohort == "learner","campus interiors use existing generated students")
	if not crowd.is_empty():
		var id: String = crowd[0]
		check(not gameplay.talk_to_story_npc(id,"invalid").ok,"invalid chapter topic rejected")
		check(before == gameplay.simulation.export_snapshot(),"invalid topic leaves entire world unchanged")
		check(gameplay.talk_to_story_npc(id).ok and id in gameplay.simulation.state.social.contacts,"chapter meeting adds the same NPC to contacts")
		before = gameplay.simulation.export_snapshot()
		gameplay.talk_to_story_npc(id)
		gameplay.talk_to_story_npc(id,"directions")
		check(before == gameplay.simulation.export_snapshot(),"repeated conversation grants no extra relationship reward")
		check(gameplay.story_flags.guide_stage == "campus","random conversation cannot bypass chapter objective")
	check(not gameplay.talk_to_story_npc("lyra").ok,"childhood character is never treated as generated student")
	var Library = preload("res://scripts/portraits/npc_portrait_library.gd")
	var actor := {"id":"resident_example","gender":"female","appearance":{"morphology":"furry"}}
	var portraits := [{"id":"fox_b","gender":"female","morphology":"furry"},{"id":"human","gender":"female","morphology":"human"},{"id":"fox_man","gender":"male","morphology":"furry"},{"id":"fox_a","gender":"female","morphology":"furry"}]
	var chosen: String = Library.choose(actor,portraits)
	check(chosen in ["fox_a","fox_b"],"local portrait selection respects gender and morphology")
	portraits.reverse()
	check(chosen == Library.choose(actor,portraits),"reordering the art manifest never changes NPC portrait assignment")
	var used := {}
	used[chosen] = true
	check(Library.choose(actor,portraits,used) != chosen,"assigned faces are never reused for another NPC")
	check(Library.choose(actor,portraits,{"fox_a":true,"fox_b":true}) == "","exhausted art pool uses placeholders instead of duplicate faces")
	check(Library.choose(actor,[]) == "","empty portrait library supports placeholder graphics")

func _test_selected_lessons() -> void:
	var sim = Simulation.new(41,Names.extensions())
	check(sim.configuration_error.is_empty(),"extended lesson catalog validates")
	sim.state.clock = Simulation.calendar.snapshot(2*1440+599) # Tuesday 09:59
	preload("res://scripts/mechanics/education_schedule.gd").apply_plan(sim.state,true,["computing","statistics"])
	sim.command("clock","advance",{"minutes":182})
	check(sim.state.world.education.absences == 1,"unselected lessons cause no absences")
	var before: Dictionary = sim.export_snapshot()
	sim.state.world.location = "training_center"
	sim.state.clock = Simulation.calendar.snapshot(2*1440+660)
	check(not sim.command("world","lesson",{"id":"physics_class"}).ok,"cannot attend a subject not selected")

func _test_timeline_links() -> void:
	var directory: Dictionary = ProjectSettings.get_setting("dialogic/directories/dtl_directory")
	for key in directory:
		if not str(key) in ["chapter_one","flashback_flee"] and not str(directory[key]).begins_with("res://TimeLine/prolog/"): continue
		var timeline = load(directory[key])
		timeline.process()
		check(not timeline.events.is_empty(),"timeline parses: " + str(key))
		for event in timeline.events:
			if event is DialogicJumpEvent:
				check(event.timeline != null or not event.label_name.is_empty(),"jump resolves in " + str(key) + ": " + event.to_text())
				if not event.label_name.is_empty():
					var target_text: String = FileAccess.get_file_as_string(event.timeline.resource_path if event.timeline != null else timeline.resource_path)
					check(target_text.contains("label " + event.label_name),"jump label exists: " + event.label_name)

func _test_windows() -> void:
	fresh_world()
	gameplay.complete_chapter_one()
	var scene := Control.new()
	root.add_child(scene)
	var setup = load("res://scenes/ui/WorldSetup.tscn").instantiate()
	scene.add_child(setup)
	setup._semi.value = 100
	check(setup.configuration.population.semi_furry_ratio == 1 and setup.configuration.population.furry_ratio == 0,"world UI supports a whole semi-furry population")
	setup._semi.value = 50
	check(is_equal_approx(setup.configuration.population.furry_ratio,0.25),"leaving a full population restores both other types")
	setup._furry.value = 100
	check(setup.configuration.population.furry_ratio == 1 and setup.configuration.population.semi_furry_ratio == 0,"world UI supports a whole furry population")
	setup.configuration.population.activity_mode = "work"
	setup._show_page()
	setup.page = 1
	setup._show_page()
	setup.configuration.difficulty = "custom"
	setup._show_page()
	check(setup._next != null,"world setup builds all difficulty pages")
	setup.queue_free()
	var creator = load("res://scenes/ui/CharacterCreationModal.tscn").instantiate()
	scene.add_child(creator)
	creator.open_with_profile(session.get_character_profile(),session.get_character_stat_labels(),{},session.get_character_appearance_options())
	check(creator._portrait.is_model_loaded() and creator._shape_sliders.size() == 6, "mirror loads GG Live2D with only its six supported body controls")
	creator._set_shape(0.5, "ParamThighSize")
	check(is_equal_approx(float(creator._portrait.get_appearance().shape.ParamThighSize), 0.5) and is_equal_approx(float(creator._profile.appearance.live2d.shape.ParamThighSize), 0.5), "body slider applies a real GG morph and keeps it in the pending profile")
	creator._undo_appearance()
	check(is_equal_approx(float(creator._portrait.get_appearance().shape.ParamThighSize), 0.0), "creator undo restores the previous Live2D shape")
	creator._select_zone("face")
	creator._set_palette("hair", "copper")
	check(creator._zone == "face" and str(creator._portrait.get_appearance().palette.hair) == "copper" and creator._shape_sliders.is_empty(), "face mode offers real hair color without unsupported face sculpt controls")
	creator._page = 1
	creator._build_page()
	check(creator._portrait != null and creator._stat_values.size() == 5 and not creator._confirm.disabled,"GG mirror reflection, identity stats and confirmation remain usable")
	creator.queue_free()
	var guide = load("res://scripts/ui/gameplay/guided_exploration.gd").new()
	gameplay.phase = "story"
	gameplay.begin_guide("night")
	scene.add_child(guide)
	check(guide._objects.get_child_count() >= 4,"guided room exposes optional objects and objective")
	guide.queue_free()
	gameplay.phase = "free_roam"
	gameplay.story_flags.guide_stage = ""
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	scene.add_child(shell)
	for panel in ["place","map","profile","inventory","people","phone","journal","activities","work","club","home","health"]:
		shell.open_panel(panel)
		var rendered: bool = shell._phone_view.visible if panel == "phone" else shell._scene_actions.visible and shell._hero.visible if panel == "place" else shell._body.get_child_count() > 0
		check(rendered,"main panel renders: " + panel)
	var before_social_ui: Dictionary = gameplay.simulation.export_snapshot()
	shell._show_npc_details("asuka")
	var social_buttons: Array = shell._body.find_children("*", "Button", true, false)
	check(social_buttons.any(func(button): return button.get_meta("gameplay_action", {}).get("module", "") == "npc_agency") and shell._title.text == str(gameplay.simulation.state.social.npcs.asuka.name), "real NPC profile identifies the person and exposes goal support")
	check(before_social_ui == gameplay.simulation.export_snapshot(), "opening NPC profile leaves world state and random stream unchanged")
	var conversation = load("res://scripts/ui/gameplay/conversation_window.gd").new()
	var speaker: Dictionary = gameplay.simulation.state.social.npcs.asuka
	gameplay.simulation.services.npc_agency._cancel(speaker,"conversation_ui_fixture")
	speaker.location = gameplay.simulation.state.world.location
	speaker.schedule = []
	speaker.activity = "rest"
	speaker.pinned_until = 0
	conversation.configure("asuka", "free", "res://assets/textures/backgrounds/campus_v1/hall.tres")
	scene.add_child(conversation)
	var directed_panel: bool = conversation._relationship!=null and not conversation._relationship.text.is_empty()
	if conversation._live_stage!=null:
		directed_panel = not conversation._live_stage._stats.text.is_empty() and conversation._live_stage.session.bond()==gameplay.simulation.services.npc_relationships.view("asuka","player")
	check(directed_panel, "conversation screen shows directed relationship state")
	conversation.queue_free()
	gameplay.execute("organizations","create",{"id":"creative_collective"})
	shell.open_panel("club")
	gameplay.execute("encounters","game_start",{"type":"timing"})
	shell.open_panel("place")
	await process_frame
	gameplay.execute("encounters","cancel_game")
	shell.queue_free()
	await process_frame
	scene.queue_free()
	await process_frame
	await process_frame
