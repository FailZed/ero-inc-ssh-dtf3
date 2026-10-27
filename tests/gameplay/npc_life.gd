extends RefCounted
const Social = preload("res://scripts/gameplay/social_presentation.gd")
var t
var game
var session

func _init(runner) -> void:
	t = runner
	game = t.gameplay
	session = t.session

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.fresh_world()
	game.complete_chapter_one()
	var sim = game.simulation
	t.check(sim.services.has("npc_relationships") and sim.services.npc_agency.enabled(), "main game automatically enables directed NPC life when the city opens")
	for npc in sim.state.social.npcs.values():
		t.check(npc.has("mind") and npc.psychology.facets.size() == 24, "every main-game resident and authored adult has a goal and a continuous personality")
		t.check(int(npc.mind.updated_at) == int(sim.state.clock.total_minutes), "script date jumps do not age new NPCs through months of unsimulated time")
	t.check(float(Social.bond(sim, "asuka").trust) == 15, "chapter relationship facts carry into directed feelings")
	t.check(sim.state.social.npcs.ellie.mind.aspiration.id == "mastery" and sim.state.social.npcs.ellie.schedule[0].activity == "study", "authored university characters pursue their own goals and real study commitments")
	var before: Dictionary = sim.export_snapshot()
	Social.life(sim, "asuka")
	Social.bond(sim, "asuka")
	for action in Social.ACTIONS: Social.preview(sim, "asuka", action)
	t.check(before == sim.export_snapshot(), "social UI data and availability forecasts consume no world time, RNG or relationship state")
	for npc in sim.state.social.npcs.values():
		sim.services.npc_agency._cancel(npc, "test_city_meeting")
		npc.location = "global_map"
		npc.schedule = []
		npc.needs.social = 5.0
		npc.mind.aspiration = {"id": "community", "stage": 0, "progress": 0, "milestones": 0, "completed": false}
	sim.services.npc_agency._build_index()
	t.check(game.execute("clock", "advance", {"minutes": 180}).ok, "waiting in the actual game advances the whole NPC population")
	var social_actions := 0
	var bonds := 0
	for npc in sim.state.social.npcs.values():
		bonds += npc.mind.bonds.size()
		for action in ["connect", "cooperate", "support", "joke"]: social_actions += int(npc.mind.completed_actions.get(action, 0))
	t.check(social_actions > 0 and bonds > 3, "NPCs actually meet and build directed relationships without the player selecting their actions")
	var changes: Array = []
	var callback := func(): changes.append(true)
	game.changed.connect(callback)
	var previous := int(sim.state.clock.total_minutes)
	session.advance_game_time(30)
	t.check(int(sim.state.clock.total_minutes) == previous + 30 and int(session.get_game_time_snapshot().total_minutes) == previous + 30, "session-driven time advances NPC life exactly once")
	t.check(changes.size() == 1, "one external time change refreshes game screens once")
	game.changed.disconnect(callback)
	# Actual player action, with an available partner and the same rules as the UI.
	var npc: Dictionary = sim.state.social.npcs.asuka
	sim.services.npc_agency._cancel(npc, "test_player_meeting")
	npc.activity = "rest"
	npc.location = "global_map"
	sim.state.world.location = "global_map"
	npc.decision = {"committed": false, "reason": "test_player_meeting"}
	npc.needs.merge({"energy": 100.0, "satiety": 100.0, "hygiene": 100.0}, true)
	npc.pinned_until = int(sim.state.clock.total_minutes) + 1440
	var trust := float(Social.bond(sim, "asuka").trust)
	previous = int(sim.state.clock.total_minutes)
	t.check(game.execute("social", "interact", {"id": "asuka", "action": "offer_help"}).ok, "ordinary main-game conversation entry point performs real help")
	t.check(int(sim.state.clock.total_minutes) == previous + 60 and float(Social.bond(sim, "asuka").trust) > trust, "player help consumes time and changes the NPC's directed trust")
	t.check(npc.mind.sentiments.has("player"), "the player's action leaves an emotional memory")
	t.check(not game.log_entries().is_empty(), "social consequences appear in the real game journal")
	sim.rng.seed = 123
	var witness: Dictionary = sim.state.social.npcs.ellie
	sim.services.npc_agency._cancel(witness, "test_witness")
	witness.location = "global_map"
	witness.activity = "rest"
	witness.pinned_until = int(sim.state.clock.total_minutes) + 1440
	t.check(game.execute("security", "steal", {"npc": "asuka"}).ok, "crime uses the main game's actual rules")
	t.check(float(Social.bond(sim, "asuka").grievance) > 0 and float(Social.bond(sim, "asuka").trust) < trust, "a detected theft causes personal grievance and distrust")
	t.check(float(Social.bond(sim, "ellie").trust) < 10 and witness.mind.sentiments.has("player"), "a nearby witness also reacts to the player's observed misconduct")
	t.check(game.execute("social_rules", "apologize", {"id": "asuka"}).ok and Social.bond(sim, "asuka").acknowledged, "the actual apology button acknowledges the harm")
	t.check(float(Social.bond(sim, "asuka").grievance) > 0, "the main interface cannot erase an incident with one apology")
	var grievance := float(Social.bond(sim, "asuka").grievance)
	t.check(game.execute("combat", "start", {"npc": "asuka"}).ok, "main-game conflict can enter an actual combat encounter")
	sim.state.player.stats.agility = 100
	sim.rng.seed = 1
	for i in range(20):
		if sim.state.encounters.combat.status != "active": break
		t.check(game.execute("combat", "action", {"action": "escape"}).ok, "combat escape resolves through the actual encounter")
	t.check(sim.state.encounters.combat.status != "active" and float(Social.bond(sim, "asuka").grievance) > grievance, "a combat encounter leaves a directed emotional and relationship consequence")
	var stored: Dictionary = JSON.parse_string(JSON.stringify(t.dialogic.VAR.var_storage.World))
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	game.execute("clock", "advance", {"minutes": 30})
	t.dialogic.VAR.var_storage.World = stored
	session._sync_game_time_from_dialogic()
	t.check(game.restore_error.is_empty(), "the ordinary load path accepts the new world snapshot")
	t.check(snapshot == JSON.parse_string(JSON.stringify(game.simulation.export_snapshot())), "ordinary World restore retains goals, decisions, personality, bonds, grievances and RNG")
	t.check(game.simulation.services.npc_agency.enabled(), "NPC life continues enabled after restoring the world")
	# Settings select a population tendency, rather than silently using old six traits.
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count = 8
	config.personality.extraversion = 100
	config.personality.spread = 0
	game._pending_configuration = config
	t.dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	game.complete_chapter_one()
	for resident in game.simulation.state.social.npcs.values():
		if not str(resident.id).begins_with("resident_"): continue
		t.check(game.simulation.services.npc_personalities.describe(resident).dimensions.extraversion == 100, "new-game personality settings reach generated residents")
	t.dialogic.VAR.var_storage.World = original
	session._sync_game_time_from_dialogic()
