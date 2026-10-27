extends RefCounted
const Extended = preload("res://scripts/mechanics/extended_simulation.gd")
var t
func _init(parent) -> void:
	t = parent

func fresh(seed_value: int = 42):
	var sim = Extended.new(seed_value, {"settings":{"start_minutes":480}})
	sim.state.world.equipment = ["computer", "stove"]
	sim.state.economy.cash = 1000
	sim.state.player.skills.computing = 150
	return sim

func run() -> void:
	for bad in [{"family_actions":{"feed":{"label":"bad","minutes":20,"energy":3,"cost":-5,"needs":{"food":10},"stages":["infant"]}}}, {"digital_operations":{"broken":{"label":"bad"}}}, {"gallery_entries":{"bad":{"label":"bad","image":"https://example.invalid/remote.png","text":"bad","requirements":{}}}}]:
		var invalid = Extended.new(1, bad)
		t._check(not invalid.configuration_error.is_empty() and not invalid.command("clock","advance",{"minutes":1}).ok, "malformed extended catalog cannot run commands")
	var sim = fresh()
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("digital", "resolve", {"id":"training", "token":0}).ok and before == sim.export_snapshot(), "digital operation requires actual prepared report")
	var minute := int(sim.state.clock.total_minutes)
	t._check(sim.command("digital", "scan", {"id":"training"}).ok and int(sim.state.clock.total_minutes) == minute + 15, "digital preparation spends fifteen world minutes")
	before = sim.export_snapshot()
	t._check(not sim.command("digital", "scan", {"id":"bank"}).ok and before == sim.export_snapshot(), "a pending task cannot be replaced by another scan")
	t._check(not sim.command("digital", "resolve", {"id":"training", "token":99}).ok and before == sim.export_snapshot(), "stale digital token is rejected before RNG")
	var replay = fresh(1)
	t._check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok, "prepared digital report can be loaded")
	var args := {"id":"training", "token":sim.state.digital.pending.token}
	var result: Dictionary = sim.command("digital", "resolve", args)
	var replay_result: Dictionary = replay.command("digital", "resolve", args)
	t._check(result.ok and result == replay_result, "digital outcome reproduces from a saved preparation")
	t._check(JSON.parse_string(JSON.stringify(sim.export_snapshot())) == JSON.parse_string(JSON.stringify(replay.export_snapshot())), "digital reward, skill XP, clock and RNG reproduce exactly")
	t._check(int(sim.state.clock.total_minutes) == minute + 45 and sim.state.digital.history.size() == 1, "digital resolution spends actual duration and records one outcome")
	before = sim.export_snapshot()
	t._check(not sim.command("digital", "resolve", args).ok and before == sim.export_snapshot(), "completed report cannot be paid twice")
	sim.state.world.location = "global_map"
	before = sim.export_snapshot()
	t._check(not sim.command("digital", "scan", {"id":"recovery"}).ok and before == sim.export_snapshot(), "installed home computer cannot be used from the street")
	sim = fresh()
	sim.command("preferences", "content_tag", {"id":"crime", "enabled":false})
	before = sim.export_snapshot()
	t._check(not sim.command("digital", "scan", {"id":"grades"}).ok and before == sim.export_snapshot(), "disabled crime content blocks risky digital operation")
	t._check(sim.command("digital", "scan", {"id":"recovery"}).ok, "legal digital work remains enabled by crime filter")
	var expired := int(sim.state.digital.pending.expires)
	t._check(sim.command("clock", "advance", {"minutes":1440}).ok and sim.state.digital.pending.is_empty() and int(sim.state.clock.total_minutes) == expired, "prepared reports expire at their actual deadline")
	for seed_value in range(10):
		sim = fresh(seed_value)
		sim.command("digital", "scan", {"id":"bank"})
		result = sim.command("digital", "resolve", {"id":"bank", "token":sim.state.digital.pending.token})
		t._check(result.ok and (result.data.success or sim.state.security.fine > 0) and sim.state.digital.trace > 0, "risky game operation commits income or an actual fine: %d" % seed_value)
		before = sim.export_snapshot()
		t._check(not sim.command("digital", "scan", {"id":"bank"}).ok and before == sim.export_snapshot(), "success and failure both impose operation cooldown: %d" % seed_value)
	sim = fresh()
	sim.command("social", "generate", {"id":"neighbor"})
	for seed_value in range(10):
		sim.rng.seed = seed_value
		sim.state.digital.cooldowns = {}
		sim.command("digital", "scan", {"id":"directory"})
		result = sim.command("digital", "resolve", {"id":"directory", "token":sim.state.digital.pending.token})
		if result.ok and result.data.success: break
	t._check("neighbor" in sim.state.digital.leads and not "neighbor" in sim.state.social.contacts, "catalog lead does not forge personal contact or relationship")
	_collections()
	_content()

func _collections() -> void:
	var sim = fresh()
	var before: Dictionary = sim.export_snapshot()
	var entries: Array = sim.services.collections.entries()
	t._check(entries.size() == 5 and before == sim.export_snapshot(), "reading collection is a pure query")
	t._check(not sim.command("collections", "view", {"id":"progress"}).ok and before == sim.export_snapshot(), "locked gallery entry cannot be viewed")
	sim.command("character", "gain_xp", {"amount":100})
	sim.command("events", "claim_achievement", {"id":"first_level"})
	t._check("progress" in sim.state.collection.unlocked, "existing achievement unlocks actual collection entry")
	var minute := int(sim.state.clock.total_minutes)
	var rng_state: int = sim.rng.state
	t._check(sim.command("collections", "view", {"id":"progress"}).ok and "progress" in sim.state.collection.seen, "unlocked gallery entry is viewable and remembers viewing")
	t._check(int(sim.state.clock.total_minutes) == minute and sim.rng.state == rng_state, "viewing gallery consumes no gameplay time or RNG")
	var bad: Dictionary = sim.export_snapshot()
	bad.state.collection.seen.append("unknown")
	before = sim.export_snapshot()
	t._check(not sim.restore_snapshot(bad).ok and before == sim.export_snapshot(), "unknown collection data is rejected atomically")

func _content() -> void:
	var sim = fresh()
	t._check(sim.configuration_error.is_empty() and sim.catalog.recipes.size() == 9 and sim.catalog.perks.size() == 18, "expanded content catalog has nine recipes and eighteen functional perks")
	sim.command("inventory", "add", {"id":"grain", "quantity":2})
	sim.command("inventory", "add", {"id":"milk", "quantity":2})
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("inventory", "craft", {"id":"pilaf"}).ok and before == sim.export_snapshot(), "advanced recipe is gated by actual cooking development")
	var result: Dictionary = sim.command("inventory", "craft", {"id":"porridge"})
	t._check(result.ok and sim.state.player.skills.get("cooking",0) > 0 and sim.state.inventory.items.grain == 1, "new recipe actually consumes ingredients and trains cooking")
