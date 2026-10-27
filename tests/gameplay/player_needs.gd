extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func run() -> void:
	var sim = t.gameplay.make_simulation()
	t.check(sim.state.player.needs.has_all(["health", "energy", "hydration", "satiety", "hygiene", "bladder", "rested", "fun", "social"]), "main simulation owns all nine HUD resources before the UI is created")
	sim.state.player.needs.energy = 20.0
	sim.state.player.needs.rested = 40.0
	sim.command("clock", "advance", {"minutes": 15})
	t.check(is_equal_approx(float(sim.state.player.needs.energy), 35.0) and sim.state.player.needs.rested < 40.0, "stamina recovers with world time while the separate sleep need declines")
	var before: Dictionary = sim.export_snapshot()
	t.check(not sim.command("needs", "drink").ok and before == sim.export_snapshot(), "drinking without a water source fails atomically")
	sim.state.world.location = "bathroom"
	sim.state.player.needs.hydration = 20.0
	sim.state.player.needs.bladder = 30.0
	sim.state.player.needs.hygiene = 40.0
	var minute := int(sim.state.clock.total_minutes)
	t.check(sim.command("needs", "drink").ok and int(sim.state.clock.total_minutes) == minute + 2, "drinking consumes exactly two world minutes")
	t.check(sim.state.player.needs.hydration > 60 and sim.state.player.needs.bladder < 30, "water restores hydration and increases the need for a toilet")
	minute = int(sim.state.clock.total_minutes)
	t.check(sim.command("needs", "toilet").ok and int(sim.state.clock.total_minutes) == minute + 5, "toilet action consumes exactly five world minutes")
	t.check(sim.state.player.needs.bladder == 100.0 and sim.state.player.needs.hygiene < 40.0, "toilet restores comfort and leaves hygiene as a separate need")
	sim.state.world.location = "bedroom"
	sim.state.player.needs.fun = 20.0
	t.check(sim.command("needs", "leisure").ok and sim.state.player.needs.fun > 50.0, "a leisure activity actually satisfies leisure")
	sim.state.player.needs.rested = 10.0
	sim.state.player.needs.energy = 80.0
	t.check(sim.command("character", "rest", {"minutes": 60}).ok and sim.state.player.needs.rested < 10.0 and sim.state.player.needs.energy == 100.0, "ordinary rest recovers stamina while the separate sleep need still declines")
	sim.state.player.needs.energy = 60.0
	t.check(sim.command("actions", "perform", {"id": "exercise"}).ok and sim.state.player.needs.energy <= 55.0, "exercise spends stamina without passive recovery cancelling its cost")
	sim.state.player.needs.energy = 0.0
	before = sim.export_snapshot()
	t.check(not sim.command("actions", "perform", {"id": "exercise"}).ok and before == sim.export_snapshot(), "unaffordable exercise rolls back all needs and time")
	sim.state.player.needs.rested = 100.0
	sim.command("clock", "advance", {"minutes": 15})
	t.check(is_equal_approx(float(sim.state.player.needs.energy), 15.0), "a failed exertion never disables subsequent passive stamina recovery")
	sim.command("inventory", "add", {"id": "book"})
	sim.state.player.needs.fun = 20.0
	sim.state.player.needs.energy = 60.0
	t.check(sim.command("actions", "perform", {"id": "read"}).ok and sim.state.player.needs.fun > 30.0 and sim.state.player.needs.energy <= 58.0, "reading the existing book satisfies leisure and spends stamina through the real action")
	sim.command("social", "generate", {"id": "needs_friend", "template": "resident"})
	sim.command("social", "contact", {"id": "needs_friend"})
	sim.state.social.npcs.needs_friend.activity = "idle"
	sim.state.social.npcs.needs_friend.decision = {"committed": false}
	sim.state.player.needs.social = 20.0
	t.check(sim.command("social", "call", {"id": "needs_friend", "text": "Как дела?"}).ok and sim.state.player.needs.social > 30.0, "an actual phone call satisfies communication")
	before = sim.export_snapshot()
	sim.command("social", "read", {"id": "needs_friend"})
	t.check(sim.state.player.needs == before.state.player.needs, "reading messages never fills communication or recovers stamina")
	var replay = t.gameplay.make_simulation()
	t.check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok, "all new needs survive JSON snapshot restoration")
	sim.command("clock", "advance", {"minutes": 30})
	replay.command("clock", "advance", {"minutes": 30})
	# JSON converts integral numbers to floats; compare both runs in persisted form.
	t.check(JSON.parse_string(JSON.stringify(sim.export_snapshot())) == JSON.parse_string(JSON.stringify(replay.export_snapshot())), "continued need decay and stamina recovery remain deterministic after loading")
	var invalid: Dictionary = sim.export_snapshot()
	invalid.state.player.needs.hydration = "invalid"
	before = sim.export_snapshot()
	t.check(not sim.restore_snapshot(invalid).ok and sim.export_snapshot() == before, "corrupt added needs are rejected without mutating the live state")
