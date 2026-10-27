extends SceneTree
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const VisualState = preload("res://scripts/portraits/character_state.gd")
var checks := 0
var failures: Array[String] = []
var gameplay
var session
var dialogic

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures.append(text); printerr("FAIL: ",text)

func _run() -> void:
	gameplay = root.get_node("Gameplay")
	session = root.get_node("GameSession")
	dialogic = root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var original: Dictionary = dialogic.VAR.var_storage.get("World",{}).duplicate(true)
	_test_setup()
	_test_sandbox()
	_test_personal_stories()
	_test_all_personal_arcs()
	_test_current_validation()
	_test_visual_state()
	dialogic.VAR.var_storage.World = original
	session._sync_game_time_from_dialogic()
	print("SANDBOX_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _test_setup() -> void:
	var config := Setup.defaults()
	check(config.mode == "story" and config.content.pregnancy, "old story start stays the default")
	config.mode = "sandbox"
	config.difficulty = "hard"
	config.content.pregnancy = false
	check(Setup.validate(config).ok, "sandbox and disabled pregnancy are valid world settings")
	config.mode = "unknown"
	check(not Setup.validate(config).ok, "unknown game mode rejected")
	config.mode = "sandbox"
	config.sandbox.start_cash = -1
	check(not Setup.validate(config).ok, "invalid sandbox funds rejected")

func _test_sandbox() -> void:
	var config := Setup.defaults()
	config.mode = "sandbox"
	config.population.count = 8
	config.difficulty = "hard"
	config.content.pregnancy = false
	gameplay._pending_configuration = config
	dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	session.reset_character_profile()
	check(gameplay.is_sandbox() and gameplay.phase == "story" and gameplay.story_flags.modal == "creator", "sandbox starts at character mirror without opening the city early")
	check(not gameplay.open_sandbox().ok, "uncreated character cannot bypass mirror")
	var profile: Dictionary = session.get_character_profile()
	profile.identity.full_name = "Тестовый житель"
	check(session.apply_character_profile_v2(profile), "sandbox character can be created with existing mirror profile")
	gameplay._on_profile_changed(session.get_character_profile())
	var opened: Dictionary = gameplay.open_sandbox()
	check(opened.ok, "mirror completion opens independent sandbox: "+str(opened.get("error","")))
	var sim = gameplay.simulation
	check(gameplay.phase == "free_roam" and sim.state.world.flags.sandbox, "sandbox uses actual free-roam runtime")
	check(not sim.state.world.flags.get("chapter_one_complete",false) and sim.state.journal.quests.is_empty(), "sandbox has no fake chapter completion or mandatory plot quest")
	check(not sim.state.social.npcs.has("asuka") and sim.state.social.npcs.size() == 8, "sandbox population has no forced authored cast")
	check(sim.services.npc_agency.enabled(), "NPC life starts immediately in sandbox")
	check(sim.state.economy.cash == 250 and sim.state.housing.residence == "apartment", "sandbox starts with finite money and billable home")
	check(sim.state.inventory.items.get("meal",0) == 3 and sim.state.world.equipment == ["stove"], "survival start has supplies but no free advanced equipment")
	var before: Dictionary = sim.export_snapshot()
	check(not gameplay.open_sandbox().ok and before == sim.export_snapshot(), "sandbox startup rewards are one-time")
	gameplay.complete_chapter_one()
	gameplay._on_story_signal("chapter_one_complete")
	check(before == sim.export_snapshot(), "story completion signals cannot inject chapter rewards into sandbox")
	var water := float(sim.state.player.needs.hydration)
	check(gameplay.execute("clock","advance",{"minutes":60}).ok and sim.state.player.needs.hydration < water, "sandbox needs decay through the shared clock")
	check("pregnancy" in sim.state.preferences.disabled_tags, "pregnancy setting reaches runtime preferences")
	before = sim.export_snapshot()
	var disabled: Dictionary = gameplay.execute("lifecycle","start",{"id":"pregnancy","target":"resident_1","partner":"player"})
	check(not disabled.ok and disabled.error == "content_disabled" and before == sim.export_snapshot(), "disabled pregnancy blocks direct state start atomically")
	var replay = gameplay.make_simulation()
	check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok and replay.state.world.flags.sandbox, "sandbox and optional story data restore through main snapshot")
	check(sim.services.has("family") and sim.services.has("digital") and sim.services.has("collections") and sim.services.has("npc_stories"), "sandbox includes all installed open-world services")
	check(sim.services.world.route("north_beach").ok, "sandbox exposes city geography without story locks")

func _personal_world(id: String = "oliver"):
	var sim = gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(2240)
	sim.state.housing = gameplay.simulation.state.housing.duplicate(true)
	sim.state.world.equipment = ["computer","stove"]
	sim.state.economy.cash = 5000
	sim.state.player.skills.computing = 100
	sim.command("npc_agency","enable")
	sim.command("social","generate",{"id":id,"age":23})
	var npc: Dictionary = sim.state.social.npcs[id]
	npc.location = sim.state.world.location
	npc.home = "bedroom"
	npc.schedule = []
	npc.activity = "rest"
	npc.pinned_until = int(sim.state.clock.total_minutes) + 10080
	sim.command("social","contact",{"id":id})
	sim.services.npc_relationships._bond(id,"player").trust = 30.0
	sim.services.npc_relationships._project(id,"player")
	sim.command("inventory","add",{"id":"book"})
	sim.command("inventory","add",{"id":"grain","quantity":3})
	sim.command("inventory","add",{"id":"vegetable","quantity":3})
	return sim

func _test_personal_stories() -> void:
	var sim = _personal_world()
	var before: Dictionary = sim.export_snapshot()
	var view: Dictionary = sim.services.npc_stories.present("oliver")
	check(view.arc == "oliver" and view.node == "intro" and before == sim.export_snapshot(), "personal story preview is pure and selects authored individual chain")
	check(sim.command("npc_stories","start",{"id":"oliver"}).ok, "known trusted NPC can start personal arc")
	check(sim.command("npc_stories","choose",{"id":"oliver","node":"intro","choice":"help"}).ok, "personal conversation advances to real-world objective")
	before = sim.export_snapshot()
	check(not sim.command("npc_stories","choose",{"id":"oliver","node":"intro","choice":"help"}).ok and before == sim.export_snapshot(), "stale personal dialogue choice cannot advance or pay twice")
	check(sim.command("actions","perform",{"id":"read"}).ok and sim.state.npc_stories.arcs.oliver.node == "return_one", "actual reading advances Oliver's personal arc")
	var replay = gameplay.make_simulation()
	check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok, "partially completed personal arc restores")
	var choice := {"id":"oliver","node":"return_one","choice":"modest"}
	check(sim.command("npc_stories","choose",choice).ok and replay.command("npc_stories","choose",choice).ok, "personal arc offers a small independent ending")
	check(JSON.parse_string(JSON.stringify(sim.export_snapshot())) == JSON.parse_string(JSON.stringify(replay.export_snapshot())), "personal ending rewards and memory reproduce after restore")
	check(sim.state.npc_stories.arcs.oliver.status == "completed" and sim.state.npc_stories.arcs.oliver.rewarded, "personal story ends once with actual relationship and XP reward")
	before = sim.export_snapshot()
	check(not sim.command("npc_stories","choose",choice).ok and before == sim.export_snapshot(), "completed personal ending cannot farm rewards")
	var bad := before.duplicate(true)
	bad.state.npc_stories.arcs.oliver.node = "missing"
	check(not sim.restore_snapshot(bad).ok and before == sim.export_snapshot(), "malformed personal story rejected atomically")

func _test_visual_state() -> void:
	var actor := {"age":23,"health":100,"needs":{"energy":100,"mood":60,"hygiene":100},"appearance":{},"injuries":{}}
	var normal := VisualState.describe(actor)
	check(normal.labels.is_empty() and normal.expression == "neutral", "healthy character has neutral visual state")
	actor.needs.energy = 10
	actor.needs.hygiene = 5
	actor.injuries.head = 25
	actor.appearance.pregnancy_stage = 3
	var before := actor.duplicate(true)
	var state := VisualState.describe(actor)
	check(state.tired and state.dirty > 0 and state.wounded and state.pregnancy == 3, "visual description combines needs, injury and pregnancy stage")
	check(before == actor and state.expression == "concern", "visual state never changes character data")
	actor.injuries = {"head":0,"arms":0}
	actor.needs.energy = 100
	check(not VisualState.describe(actor).wounded, "healed zero-value injury record does not leave a wounded portrait")

func _test_current_validation() -> void:
	var sim = _personal_world("newcomer")
	var old: Dictionary = sim.export_snapshot()
	old.main_schema = 6
	var unchanged: Dictionary = sim.export_snapshot()
	check(not sim.restore_snapshot(old).ok and unchanged == sim.export_snapshot(), "outdated main schema rejected without migration")
	sim = _personal_world("newcomer")
	sim.command("npc_stories","start",{"id":"newcomer"})
	sim.command("npc_stories","choose",{"id":"newcomer","node":"intro","choice":"help"})
	var before: Dictionary = sim.export_snapshot()
	var corrupt := before.duplicate(true)
	corrupt.state.npc_stories.arcs.newcomer.history[0].choice = "invented_choice"
	check(not sim.restore_snapshot(corrupt).ok and before == sim.export_snapshot(), "invented personal choice history rejected atomically")
	corrupt = before.duplicate(true)
	corrupt.state.npc_stories.arcs.newcomer.goal = {"count":1,"ids":["not_a_goal_location"]}
	check(not sim.restore_snapshot(corrupt).ok and before == sim.export_snapshot(), "invalid unique goal tokens rejected atomically")
	corrupt = before.duplicate(true)
	corrupt.state.erase("npc_stories")
	check(not sim.restore_snapshot(corrupt).ok and before == sim.export_snapshot(), "current catalog cannot silently discard missing personal story state")

func _test_all_personal_arcs() -> void:
	for id in ["asuka","oliver","ellie","neighbor","maker","newcomer"]:
		var sim = _personal_world(id)
		check(sim.command("npc_stories","start",{"id":id}).ok, "personal arc can start: " + id)
		sim.command("npc_stories","choose",{"id":id,"node":"intro","choice":"help"})
		check(_do_goal(sim,id,"task_one"), "first personal goal has actual playable route: " + id)
		sim.state.social.npcs[id].location = sim.state.world.location
		sim.state.social.npcs[id].activity = "rest"
		check(sim.command("npc_stories","choose",{"id":id,"node":"return_one","choice":"continue"}).ok, "personal arc has a second stage: " + id)
		check(_do_goal(sim,id,"task_two"), "second personal goal has actual playable route: " + id)
		sim.state.social.npcs[id].location = sim.state.world.location
		sim.state.social.npcs[id].activity = "rest"
		check(sim.command("npc_stories","choose",{"id":id,"node":"return_two","choice":"finish"}).ok, "full personal ending is reachable: " + id)
		check(sim.state.npc_stories.arcs[id].ending == "shared_end", "personal arc records chosen full ending: " + id)

func _do_goal(sim, id: String, node_id: String) -> bool:
	var goal: Dictionary = sim.catalog.npc_story_arcs[id].nodes[node_id].goal
	var result: Dictionary = {}
	if goal.has("locations"):
		for location in goal.locations:
			result = sim.command("world","journey",{"id":location})
			if not result.ok: return false
	elif goal.module == "digital":
		for attempt in range(8):
			sim.state.digital.cooldowns = {}
			sim.command("digital","scan",{"id":"training"})
			if sim.state.digital.pending.is_empty(): return false
			result = sim.command("digital","resolve",{"id":"training","token":sim.state.digital.pending.token})
			if result.ok and result.data.success: break
	else:
		if goal.module in ["inventory","needs","economy","world"]:
			sim.state.world.location = "kitchen" if goal.module == "inventory" else "bedroom"
		if goal.module in ["npc_relationships","social"]: sim.state.social.npcs[id].location = sim.state.world.location
		var args := {"id":goal.get("id",id)}
		if goal.has("action"): args.action = goal.action
		if goal.has("item"): args.item = goal.item
		if goal.module == "economy": args.id = "website_order"; args.minutes = 30
		for attempt in range(8):
			result = sim.command(goal.module,goal.operation,args)
			if not result.ok or result.data.get("accepted",true): break
	return result.ok and sim.state.npc_stories.arcs[id].node == sim.catalog.npc_story_arcs[id].nodes[node_id].done
