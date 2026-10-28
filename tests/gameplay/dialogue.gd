extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func run() -> void:
	var game = t.gameplay
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.fresh_world()
	game.complete_chapter_one()
	var sim = game.simulation
	for npc in sim.state.social.npcs.values():
		t.check(npc.mind.has("dialogue"), "main-game resident has durable dialogue context")
		sim.services.npc_agency._cancel(npc, "test_conversation")
		npc.decision = {"committed": false}
		npc.schedule = []
		npc.pinned_until = int(sim.state.clock.total_minutes) + 1440
		npc.needs.merge({"energy": 100.0, "satiety": 100.0, "hygiene": 100.0}, true)
	var asuka: Dictionary = sim.state.social.npcs.asuka
	asuka.location = "global_map"
	asuka.activity = "idle"
	sim.state.world.location = "global_map"
	var minute := int(sim.state.clock.total_minutes)
	var result: Dictionary = game.execute("npc_dialogue", "open", {"id": "asuka"})
	t.check(result.ok and not str(result.data.utterance.text).is_empty(), "actual main entry point produces the NPC's contextual words")
	result = game.execute("npc_dialogue", "choose", {"id": "asuka", "choice": "goal", "turn": asuka.mind.dialogue.turn})
	t.check(result.ok and result.data.node == "goal" and int(t.session.get_game_time_snapshot().total_minutes) == minute + 3, "branching dialogue and main game clock agree exactly once")
	var trust := float(sim.services.npc_relationships.view("asuka", "player").trust)
	result = game.execute("npc_dialogue", "choose", {"id": "asuka", "choice": "help", "turn": asuka.mind.dialogue.turn})
	t.check(result.ok and result.data.accepted and float(sim.services.npc_relationships.view("asuka", "player").trust) > trust, "conversation help changes the same NPC relationship shown in the main UI")
	t.check(sim.services.npc_dialogue.memory(asuka) == "help", "dialogue consequences are remembered at the next meeting")
	# Through the actual security operation, not an invented dialogue flag.
	sim.rng.seed = 123
	result = game.execute("security", "steal", {"npc": "asuka"})
	t.check(result.ok and not result.data.success, "test incident actually occurs in the main game")
	result = game.execute("npc_dialogue", "open", {"id": "asuka"})
	t.check(result.ok and result.data.utterance.memory == "crime", "main-game theft changes the next actual NPC line")
	var stored: Dictionary = JSON.parse_string(JSON.stringify(t.dialogic.VAR.var_storage.World))
	var current: Dictionary = sim.services.npc_dialogue.present("asuka")
	game.execute("npc_dialogue", "close", {"id": "asuka"})
	t.dialogic.VAR.var_storage.World = stored
	t.session._sync_game_time_from_dialogic()
	t.check(game.restore_error.is_empty() and JSON.parse_string(JSON.stringify(game.simulation.services.npc_dialogue.present("asuka"))) == JSON.parse_string(JSON.stringify(current)), "normal main-game load preserves dialogue cursor, memory and line")
	if not "--skip-windows" in OS.get_cmdline_user_args():
		var scene := Control.new()
		t.root.add_child(scene)
		var window = load("res://scripts/ui/gameplay/conversation_window.gd").new()
		window.configure("asuka", "free", "res://assets/textures/backgrounds/campus_v1/hall.tres")
		scene.add_child(window)
		t.check(is_instance_valid(window._live_stage.puppet.model),"actual game conversation binds the configured MDRG Live2D stage")
		var actual: Dictionary = game.simulation.services.npc_dialogue.present("asuka")
		t.check(window._live_stage._text.text == actual.utterance.text and actual.utterance.memory == "crime", "visible conversation displays this NPC's own causal reply")
		window._dialogue_choice("feelings", int(actual.turn))
		actual = game.simulation.services.npc_dialogue.present("asuka")
		t.check(window._live_stage._text.text == actual.utterance.text and actual.node == "feelings", "visible dialogue choices advance the same runtime")
		window._close()
		await t.process_frame
		t.check(game.simulation.state.social.npcs.asuka.mind.dialogue.node == "end", "closing the UI also ends its active dialogue session")
		sim = game.simulation
		asuka = sim.state.social.npcs.asuka
		# The new city's evening social meeting place is the cafe.
		asuka.home = "riverside_cafe"
		asuka.location = "riverside_cafe"
		sim.state.world.location = "riverside_cafe"
		asuka.pinned_until = 0
		asuka.needs.social = 70
		t.check(game.execute("clock", "advance", {"minutes": 15}).ok, "main game advances to a genuine NPC initiative")
		var offers: Array = sim.services.npc_dialogue.offers()
		t.check(offers.size() == 1, "autonomous NPC approach is available to the actual main shell")
		if not offers.is_empty():
			var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
			scene.add_child(shell)
			t.check(shell._initiative_panel.visible, "main UI exposes an NPC initiative without forcing a conversation window")
			shell.open_panel("work")
			t.check(not shell._initiative_panel.visible and sim.services.npc_dialogue.offers().size() == 1, "details hide the initiative card without losing the NPC's pending offer")
			shell.open_panel("place")
			t.check(shell._initiative_panel.visible, "returning to the scene reveals the pending initiative again")
			shell._open_conversation("asuka", "free", str(offers[0].initiative))
			var invitation = shell.get_child(shell.get_child_count() - 1)
			t.check(invitation._live_stage._text.text == str(offers[0].text), "answering an initiative opens the exact pending NPC utterance")
			invitation._dialogue_choice("accept", int(asuka.mind.dialogue.turn))
			t.check(asuka.mind.dialogue.node == "feelings", "main UI accepts a grievance initiative into the relevant relationship branch")
			invitation._close()
			await t.process_frame
			shell.queue_free()
			await t.process_frame
		sim.state.world.location = "bedroom"
		if not "asuka" in sim.state.social.contacts: sim.state.social.contacts.append("asuka")
		var phone = load("res://scripts/ui/gameplay/conversation_window.gd").new()
		phone.configure("asuka", "message", "res://assets/textures/backgrounds/location_pack_v1/bedroom_night.png")
		scene.add_child(phone)
		minute = int(sim.state.clock.total_minutes)
		var location := str(asuka.location)
		var messages: int = sim.state.social.messages.size()
		phone._dialogue_choice("day", int(asuka.mind.dialogue.turn))
		t.check(phone._text.text == str(asuka.mind.dialogue.utterance.text) and asuka.mind.dialogue.channel == "message", "phone window renders the actual contextual response")
		t.check(sim.state.social.messages.size() == messages + 2 and asuka.location == location and int(t.session.get_game_time_snapshot().total_minutes) == minute + 3, "main phone reply records both sides and elapsed time without teleportation")
		phone._close()
		await t.process_frame
		scene.queue_free()
		await t.process_frame
	var config := preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count = 8
	config.content = {"romance": false, "adult": false}
	game._pending_configuration = config
	t.dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	t.session.reset_game_time()
	t.check(game.phase == "story" and "adult" in game.simulation.state.preferences.disabled_tags and "romance" in game.simulation.state.preferences.disabled_tags, "new-game content choices reach the actual world before the prologue")
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
