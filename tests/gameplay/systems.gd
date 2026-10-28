extends RefCounted
## Cross-system regressions in an in-memory main-game world, never user slots.
const Policy = preload("res://scripts/gameplay/action_policy.gd")
const Rules = preload("res://scripts/mechanics/core/rules.gd")
var t

class RejectingSimulation extends "res://scripts/gameplay/main_simulation.gd":
	func after_command(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> Dictionary:
		var processed := super.after_command(module_id, operation, args, result, before)
		return Rules.fail("late_test_rejection") if module_id == "actions" and operation == "perform" else processed

func _init(runner) -> void:
	t = runner

func _new():
	return t.gameplay.make_simulation()

func _same(a: Dictionary, b: Dictionary) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func run() -> void:
	_transactions()
	_work_and_locations()
	_sleep_and_conditions()
	_combat_and_games()
	_social_and_commitments()
	_clubs_and_housing()
	_daily_loop()

func _transactions() -> void:
	var sim = _new()
	var failures: Array[String] = []
	for id in sim.services:
		var before: Dictionary = sim.export_snapshot()
		var result: Dictionary = sim.command(str(id), "unknown_test_operation")
		if result.ok or before != sim.export_snapshot() or not sim.action_context.is_empty(): failures.append(str(id))
	t.check(failures.is_empty(), "every registered main-game service rejects unknown commands atomically: " + str(failures))
	print("SYSTEMS_AUDIT ", JSON.stringify({"services":sim.services.keys(), "atomic_rejection":failures.is_empty()}))
	sim.command("inventory", "add", {"id":"book"})
	sim.state.player.needs.fun = 20.0
	var seen := {"fun": 0.0}
	var callback := func(module_id, operation, _result):
		if module_id == "actions" and operation == "perform": seen.fun = float(sim.state.player.needs.fun)
	sim.committed.connect(callback)
	sim.command("actions", "perform", {"id":"read"})
	sim.committed.disconnect(callback)
	t.check(float(seen.fun) > 30.0, "commit observers see the final leisure reward, not an intermediate state")
	var rejected := RejectingSimulation.new()
	rejected.command("inventory", "add", {"id":"book"})
	rejected.state.player.needs.fun = 20.0
	var before: Dictionary = rejected.export_snapshot()
	var observer := {"commits":0}
	rejected.committed.connect(func(_m, _o, _r): observer.commits += 1)
	t.check(not rejected.command("actions", "perform", {"id":"read"}).ok, "a late cross-system rejection is returned to the caller")
	t.check(rejected.export_snapshot() == before and observer.commits == 0 and rejected.action_context.is_empty(), "late failure rolls back rewards, needs, time and RNG before any commit notification")

func _work_and_locations() -> void:
	var sim = _new()
	sim.state.world.equipment = ["computer", "stove"]
	for action in [["economy","work",{"id":"freelance"}], ["economy","project",{"id":"website_order","minutes":30}], ["economy","stream",{"id":"games","minutes":15}], ["world","homework",{}]]:
		sim.state.player.needs.energy = 80.0
		var minute := int(sim.state.clock.total_minutes)
		var result: Dictionary = sim.command(action[0], action[1], action[2])
		t.check(result.ok and sim.state.player.needs.energy < 80.0 and int(sim.state.clock.total_minutes) > minute, "work and study spend stamina without hidden recovery: " + str(action[0]) + "." + str(action[1]))
	sim.state.world.location = "global_map"
	for action in [["economy","work",{"id":"freelance"}], ["world","shower",{}], ["needs","sleep",{}], ["world","homework",{}]]:
		var before: Dictionary = sim.export_snapshot()
		t.check(not sim.command(action[0], action[1], action[2]).ok and before == sim.export_snapshot(), "location restriction is enforced by the domain and rolls back: " + str(action[1]))
	sim.command("inventory", "add", {"id":"grain"})
	sim.command("inventory", "add", {"id":"vegetable"})
	var before: Dictionary = sim.export_snapshot()
	t.check(not sim.command("inventory", "craft", {"id":"vegetable_meal"}).ok and before == sim.export_snapshot(), "installed stove cannot be used remotely from the city")
	sim.state.world.location = "kitchen"
	sim.state.player.needs.energy = 80.0
	t.check(sim.command("inventory", "craft", {"id":"vegetable_meal"}).ok and sim.state.player.needs.energy < 80.0, "actual cooking consumes ingredients, world time and stamina in the kitchen")
	sim.state.player.needs.satiety = 20.0
	var minute := int(sim.state.clock.total_minutes)
	t.check(sim.command("inventory", "use", {"id":"meal"}).ok and int(sim.state.clock.total_minutes) == minute + 5 and sim.state.player.needs.satiety > 50.0, "eating restores hunger through a five-minute action, not an instant inventory exploit")

func _sleep_and_conditions() -> void:
	var sim = _new()
	sim.state.player.needs.rested = 20.0
	sim.state.player.needs.energy = 30.0
	sim.command("character", "rest", {"minutes":15})
	t.check(sim.state.player.needs.rested < 20.0 and sim.state.player.needs.energy > 30.0, "taking a break restores stamina without pretending that the player slept")
	var slept := float(sim.state.player.needs.rested)
	t.check(sim.command("needs", "nap").ok and sim.state.player.needs.rested > slept, "an explicit nap restores the separate sleep need")
	t.check(sim.command("needs", "sleep", {"minutes":480}).ok and sim.state.player.needs.rested == 100.0, "a full night can actually satisfy sleep")
	sim.services.health.record("player").unconscious_until = int(sim.state.clock.total_minutes) + 60
	t.check(sim.command("needs", "sleep", {"minutes":120}).ok, "explicit sleep remains available during medical recovery")
	var split = _new()
	var whole = _new()
	split.state.player.needs.rested = 20.0
	whole.state.player.needs.rested = 20.0
	whole.command("needs", "sleep", {"minutes":120})
	for i in range(4): split.command("needs", "sleep", {"minutes":30})
	t.check(whole.state.player.needs == split.state.player.needs and str(whole.rng.state) == str(split.rng.state), "splitting the same sleep action does not create extra need recovery or RNG draws")
	var tired = _new()
	tired.state.player.needs.rested = 0.0
	tired.state.player.needs.hydration = 0.0
	var ideal = _new()
	t.check(tired.services.needs.learning_factor() < ideal.services.needs.learning_factor() and tired.services.needs.recovery_factor() < ideal.services.needs.recovery_factor(), "dehydration and sleep loss have real learning and recovery consequences")
	tired.command("character", "train", {"skill":"study", "xp":100})
	ideal.command("character", "train", {"skill":"study", "xp":100})
	t.check(int(tired.state.player.level) < int(ideal.state.player.level), "sleep and hydration affect actual progression, not just a descriptive tooltip")
	var health := float(tired.state.player.needs.health)
	var mood := float(tired.state.player.needs.mood)
	tired.command("clock", "advance", {"minutes":60})
	t.check(tired.state.player.needs.health < health and tired.state.player.needs.mood < mood, "neglected needs apply gradual health and mood consequences over real world time")
	var before: Dictionary = tired.export_snapshot()
	tired.services.needs.condition()
	t.check(before == tired.export_snapshot(), "condition and remedy inspection is pure")
	var notices: Array = []
	sim = _new()
	sim.domain_event.connect(func(event):
		if event.kind == "player_need_critical": notices.append(event.data.need))
	sim.state.player.needs.hydration = 19.0
	sim.command("clock", "advance", {"minutes":1})
	sim.command("clock", "advance", {"minutes":10})
	t.check(notices.count("hydration") == 1, "a persistent critical need warns once, not every minute")
	var restored = _new()
	restored.restore_snapshot(sim.export_snapshot())
	t.check(restored.state.player.need_warnings.hydration, "warning hysteresis survives an ordinary snapshot restore")
	sim.state.world.location = "bathroom"
	sim.command("needs", "drink")
	t.check(not sim.state.player.need_warnings.hydration and sim.state.player.needs.hydration >= 40.0, "genuine recovery resets the warning only after the recovery threshold")
	var bad: Dictionary = sim.export_snapshot()
	bad.state.player.need_warnings["invented_need"] = true
	before = sim.export_snapshot()
	t.check(not sim.restore_snapshot(bad).ok and before == sim.export_snapshot(), "corrupt persistent warning state is rejected atomically")

func _combat_and_games() -> void:
	var sim = _new()
	sim.command("social", "generate", {"id":"opponent", "template":"resident"})
	var npc: Dictionary = sim.state.social.npcs.opponent
	npc.location = sim.state.world.location
	npc.pinned_until = 0
	sim.state.player.needs.energy = 36.0
	npc.needs.energy = 18.0
	t.check(sim.command("combat", "start", {"npc":"opponent"}).ok and sim.state.encounters.combat.stamina.player == 36.0 and sim.state.encounters.combat.stamina.npc == 18.0, "combat starts from both actors' actual stamina, without a free refill")
	var minute := int(sim.state.clock.total_minutes)
	sim.command("combat", "action", {"action":"attack", "move":"jab"})
	t.check(sim.state.player.needs.energy < 36.0 and sim.state.encounters.combat.stamina.player == sim.state.player.needs.energy, "a combat attack changes the same resource the HUD displays")
	sim.command("combat", "action", {"action":"end_turn"})
	while sim.state.encounters.combat.phase == "defence": sim.command("combat","action",{"action":"guard"})
	t.check(int(sim.state.clock.total_minutes) == minute + 1 and npc.location == sim.state.world.location, "completed combat rounds consume world time while the opponent remains in the encounter")
	var replay = _new()
	t.check(replay.restore_snapshot(sim.export_snapshot()).ok and replay.state.encounters.combat.stamina.player == replay.state.player.needs.energy, "mid-combat stamina and encounter state survive loading together")
	var without_schema: Dictionary = sim.export_snapshot()
	without_schema.erase("main_schema")
	var before_rejection: Dictionary = replay.export_snapshot()
	t.check(not replay.restore_snapshot(without_schema).ok and before_rejection == replay.export_snapshot(), "snapshots missing the current main schema are rejected atomically")
	var corrupt: Dictionary = sim.export_snapshot()
	corrupt.state.encounters.combat.stamina.player = 100.0
	var unchanged: Dictionary = replay.export_snapshot()
	t.check(not replay.restore_snapshot(corrupt).ok and unchanged == replay.export_snapshot(), "a mismatched shared resource in a current snapshot is rejected atomically")
	corrupt = sim.export_snapshot()
	corrupt.main_schema = 999
	t.check(not replay.restore_snapshot(corrupt).ok and unchanged == replay.export_snapshot(), "a save from a newer main-game schema is rejected without altering the current world")
	sim.state.player.stats.agility = 100
	for i in range(20):
		if sim.state.encounters.combat.status != "active": break
		sim.command("combat", "action", {"action":"guard" if sim.state.encounters.combat.phase == "defence" else "escape"})
	t.check(sim.state.encounters.combat.status != "active" and npc.pinned_until == 0, "ending a fight releases the NPC to their own schedule")
	sim = _new()
	sim.state.player.needs.fun = 20.0
	sim.command("encounters", "game_start", {"type":"guess"})
	var secret := int(sim.state.encounters.game.secret)
	minute = int(sim.state.clock.total_minutes)
	t.check(sim.command("encounters", "game_input", {"value":secret}).ok and int(sim.state.clock.total_minutes) == minute + 5 and sim.state.player.needs.fun > 25.0, "a finished discrete mini-game consumes time and grants leisure once")
	var before: Dictionary = sim.export_snapshot()
	t.check(not sim.command("encounters", "game_input", {"value":secret}).ok and before == sim.export_snapshot(), "a terminal mini-game cannot be replayed for free leisure or rewards")

func _social_and_commitments() -> void:
	var sim = _new()
	sim.command("npc_agency", "enable")
	sim.command("social", "generate", {"id":"friend", "template":"resident"})
	var npc: Dictionary = sim.state.social.npcs.friend
	npc.location = sim.state.world.location
	var clean: float = sim.services.npc_relationships.response_bias("player", "friend", "connect")
	var bond: Dictionary = sim.services.npc_relationships.view("friend", "player")
	sim.state.player.needs.hygiene = 0.0
	t.check(sim.services.npc_relationships.response_bias("player", "friend", "connect") < clean and sim.services.npc_relationships.view("friend", "player") == bond, "poor hygiene affects immediate reception without inventing lasting moral harm")
	npc.location = "global_map"
	t.check(is_equal_approx(sim.services.npc_relationships.response_bias("player", "friend", "connect"), clean), "physical hygiene penalties are not applied to remote reception")
	sim.command("social", "contact", {"id":"friend"})
	npc.activity = "sleep"
	var sleeping_before: Dictionary = sim.export_snapshot()
	t.check(not sim.command("social", "call", {"id":"friend", "text":"Как дела?"}).ok and sleeping_before == sim.export_snapshot(), "a sleeping NPC cannot be called for free communication rewards")
	npc.activity = "idle"
	npc.decision = {"committed":false}
	sim.state.player.skills.study = 10
	var before: Dictionary = sim.export_snapshot()
	t.check(not sim.command("social_rules", "promise", {"id":"friend", "promise":"read_book"}).ok and before == sim.export_snapshot(), "an already completed task cannot be used as a new promise")
	sim.state.player.skills.study = 0
	t.check(sim.command("social_rules", "promise", {"id":"friend", "promise":"read_book"}).ok, "a future promise can be made through the real social service")
	sim.command("inventory", "add", {"id":"book"})
	sim.command("actions", "perform", {"id":"read"})
	t.check(sim.command("social_rules", "fulfill", {"id":"friend", "promise":"read_book"}).ok, "performing the promised activity enables the real fulfillment and relationship consequence")
	var now := int(sim.state.clock.total_minutes)
	sim.state.social.appointments.append({"npc":"friend", "minute":now+30, "location":"global_map", "status":"pending"})
	before = sim.export_snapshot()
	var conflicts := Policy.commitments(sim.state, now+60)
	t.check(conflicts.size() == 1 and conflicts[0].kind == "appointment" and before == sim.export_snapshot(), "long-action commitment warnings are accurate and do not advance the world")
	t.check(Policy.commitments(sim.state, now+15).is_empty(), "short actions do not warn about a later appointment they cannot overlap")

func _daily_loop() -> void:
	var sim = _new()
	sim.state.world.equipment = ["computer", "stove"]
	sim.command("inventory", "add", {"id":"book"})
	sim.command("inventory", "add", {"id":"grain", "quantity":4})
	sim.command("inventory", "add", {"id":"vegetable", "quantity":4})
	sim.command("organizations", "create", {"id":"creative_collective"})
	sim.command("organizations", "project", {"id":"creative_collective", "project":"exhibition"})
	sim.command("economy", "deposit", {"amount":50})
	var failed: Array[String] = []
	var start := int(sim.state.clock.total_minutes)
	for day in range(2):
		var routine := [
			["needs","sleep",{"minutes":480}],
			["world","travel",{"id":"apartment_hall"}], ["world","travel",{"id":"bathroom"}],
			["needs","toilet",{}], ["world","shower",{}], ["needs","drink",{}],
			["world","travel",{"id":"apartment_hall"}], ["world","travel",{"id":"kitchen"}],
			["inventory","craft",{"id":"vegetable_meal"}], ["inventory","use",{"id":"meal"}],
			["world","travel",{"id":"apartment_hall"}], ["world","travel",{"id":"bedroom"}],
			["economy","work",{"id":"freelance"}], ["actions","perform",{"id":"read"}],
			["needs","leisure",{}], ["character","rest",{"minutes":30}]]
		for action in routine:
			var result: Dictionary = sim.command(action[0], action[1], action[2])
			if not result.ok: failed.append(str(action[1]) + ":" + str(result.error))
		var restored = _new()
		if not restored.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok: failed.append("restore")
		elif not _same(restored.export_snapshot(), sim.export_snapshot()): failed.append("roundtrip")
	t.check(failed.is_empty(), "two connected daily routines with cooking, needs, work, growth, bank, club and daily reload complete: " + str(failed))
	t.check(int(sim.state.clock.total_minutes) > start + 1200 and sim.state.economy.cash > 200 and sim.state.player.skills.computing > 0 and sim.state.player.skills.study > 0, "the connected loop advances one world and produces real money and growth")

func _clubs_and_housing() -> void:
	var sim = _new()
	sim.command("npc_agency", "enable")
	for id in ["club_a", "club_b"]:
		sim.command("social", "generate", {"id":id, "template":"resident"})
		var actor: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_agency._cancel(actor, "systems_fixture")
		actor.location = sim.state.world.location
		actor.activity = "idle"
		actor.schedule = []
		actor.decision = {"committed":false}
		actor.pinned_until = int(sim.state.clock.total_minutes) + 2000
		sim.command("social", "contact", {"id":id})
	sim.command("organizations", "create", {"id":"creative_collective"})
	var a: Dictionary = sim.state.social.npcs.club_a
	var b: Dictionary = sim.state.social.npcs.club_b
	sim.services.npc_relationships._bond("club_a", "player").trust = 20.0
	b.biography.goal = "career"
	sim.command("npc_agency", "set_aspiration", {"id":"club_b", "goal":"wellbeing"})
	sim.services.npc_agency._cancel(b, "systems_fixture")
	b.activity = "idle"
	b.decision = {"committed":false}
	var before: Dictionary = sim.export_snapshot()
	t.check(not sim.command("organizations", "recruit", {"id":"creative_collective", "npc":"club_b"}).ok and before == sim.export_snapshot(), "NPCs can refuse club membership when neither their goals nor relationship supports it")
	sim.services.npc_relationships._bond("club_b", "player").trust = 20.0
	t.check(sim.command("organizations", "recruit", {"id":"creative_collective", "npc":"club_a"}).ok and sim.command("organizations", "recruit", {"id":"creative_collective", "npc":"club_b"}).ok, "willing acquaintances can join the club through real commands")
	# Failed commands replace the state with its rolled-back copy. Reacquire fixtures.
	a = sim.state.social.npcs.club_a
	b = sim.state.social.npcs.club_b
	a.stats.charisma = 100
	a.traits.responsibility = 100
	b.stats.charisma = 1
	b.traits.responsibility = 1
	sim.command("institutions", "election", {"id":"creative_collective", "candidates":["club_a","club_b"]})
	before = sim.export_snapshot()
	t.check(not sim.command("institutions", "vote", {"id":"creative_collective", "npc":"club_a", "candidate":"club_b"}).ok and before == sim.export_snapshot(), "the player cannot cast a ballot on an NPC's behalf")
	var minute := int(sim.state.clock.total_minutes)
	t.check(sim.command("institutions", "hold_vote", {"id":"creative_collective"}).ok and int(sim.state.clock.total_minutes) == minute + 30, "convening a club vote consumes thirty world minutes")
	var group: Dictionary = sim.state.organizations.creative_collective
	t.check(group.election.status == "completed" and group.election.winner == "club_a" and group.election.votes.size() == 2, "members choose their own leader using qualities and relationships rather than player-assigned votes")
	sim.command("institutions", "election", {"id":"creative_collective", "candidates":["club_a","club_b"]})
	b = sim.state.social.npcs.club_b
	b.activity = "sleep"
	sim.command("institutions", "hold_vote", {"id":"creative_collective"})
	t.check(group.election.status == "active" and not group.election.votes.has("club_b"), "sleeping club members are not forced to vote")
	before = sim.export_snapshot()
	t.check(not sim.command("institutions", "resolve_election", {"id":"creative_collective"}).ok and before == sim.export_snapshot(), "the player cannot close a vote before all remaining members have voted")
	var replay = _new()
	t.check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok, "partial ballots and remaining voters survive loading")
	b = sim.state.social.npcs.club_b
	b.activity = "idle"
	replay.state.social.npcs.club_b.activity = "idle"
	sim.command("institutions", "hold_vote", {"id":"creative_collective"})
	replay.command("institutions", "hold_vote", {"id":"creative_collective"})
	t.check(_same(sim.export_snapshot(), replay.export_snapshot()), "the remaining ballots and resulting leader are reproducible after loading")
	a = sim.state.social.npcs.club_a
	a.needs.energy = 100.0
	var productive: float = sim.services.institutions.productivity(group, "club_a")
	a.needs.energy = 0.0
	t.check(sim.services.institutions.productivity(group, "club_a") < productive, "club work accounts for the NPC's real needs rather than unlimited contributions")
	sim.state.economy.cash = 2500
	sim.command("housing", "buy", {"id":"apartment"})
	sim.services.npc_relationships._bond("club_b", "player").trust = 0.0
	before = sim.export_snapshot()
	t.check(not sim.command("housing", "tenant", {"id":"apartment", "npc":"club_b"}).ok and before == sim.export_snapshot(), "housing cannot move an unwilling low-trust NPC into the player's apartment")
	sim.services.npc_relationships._bond("club_b", "player").trust = 20.0
	t.check(sim.command("housing", "tenant", {"id":"apartment", "npc":"club_b"}).ok and sim.state.housing.properties.apartment.tenants.has("club_b"), "a willing trusted NPC can move in through the existing housing system")
