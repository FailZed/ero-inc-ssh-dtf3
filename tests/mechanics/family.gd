extends RefCounted
const Extended = preload("res://scripts/mechanics/extended_simulation.gd")
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
var t

func _init(parent) -> void:
	t = parent

func _config() -> Dictionary:
	return {"settings":{"start_minutes":480}, "conditions":{"pregnancy":{"duration":120,"stages":[{"after":60}]}}}

func fresh():
	var sim = Extended.new(42, _config())
	t._check(sim.configuration_error.is_empty(), "family runtime catalog compiles and validates")
	t._check(sim.command("social", "generate", {"id":"parent","name":"Родитель","age":28}).ok, "generate adult parent")
	sim.state.social.npcs.parent.home = "bedroom"
	sim.state.social.npcs.parent.location = "bedroom"
	sim.state.social.npcs.parent.schedule = []
	sim.state.social.npcs.parent.pinned_until = 100000
	sim.state.economy.cash = 1000
	return sim

func birth(sim) -> void:
	t._check(sim.command("lifecycle", "start", {"id":"pregnancy", "target":"parent", "partner":"player"}).ok, "existing family-state entry remains usable")
	t._check(sim.command("clock", "advance", {"minutes":120}).ok, "birth passes through common time transaction")

func run() -> void:
	var sim = fresh()
	birth(sim)
	t._check(sim.state.healthcare.family.size() == 1 and sim.state.family.members.size() == 1, "completed pregnancy creates exactly one family member")
	t._check(sim.state.social.npcs.size() == 1, "child is never inserted into adult social/romantic population")
	var member: Dictionary = sim.state.family.members.family_1
	t._check(member.stage == "infant" and member.parents == ["parent", "player"], "newborn retains parents and life stage")
	sim.command("clock", "advance", {"minutes":2})
	t._check(sim.state.family.members.size() == 1, "later ticks do not duplicate a birth")
	t._check(sim.command("family", "rename", {"id":"family_1", "name":"Мира"}).ok, "family name is editable")
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("family", "assign", {"id":"family_1", "need":"food", "caregiver":"stranger"}).ok and before == sim.export_snapshot(), "invalid caregiver rejected atomically")
	t._check(sim.command("family", "deposit", {"amount":100}).ok and sim.state.family.budget == 100, "household reserve transfers real money")
	member = sim.state.family.members.family_1
	member.needs.food = 20.0
	var minute := int(sim.state.clock.total_minutes)
	t._check(sim.command("family", "care", {"id":"family_1", "action":"feed"}).ok, "player can feed the child at home")
	t._check(sim.state.clock.total_minutes == minute + 20 and member.needs.food >= 75 and sim.state.family.budget == 97, "care consumes one duration and real supplies, then restores hunger")
	before = sim.export_snapshot()
	t._check(not sim.command("family", "care", {"id":"family_1", "action":"feed"}).ok and before == sim.export_snapshot(), "care repetition does not farm development or bonds")
	sim.state.world.location = "global_map"
	before = sim.export_snapshot()
	t._check(not sim.command("family", "care", {"id":"family_1", "action":"play"}).ok and before == sim.export_snapshot(), "care cannot be performed remotely")
	sim.state.world.location = "bedroom"
	t._check(sim.command("family", "support", {"id":"family_1"}).ok, "paid support can cover parents' other obligations")
	before = sim.export_snapshot()
	t._check(not sim.command("family", "support", {"id":"family_1"}).ok and before == sim.export_snapshot(), "active support cannot be bought twice")
	var replay = Extended.new(1, _config())
	t._check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok, "family state survives JSON restoration")
	sim.command("clock", "advance", {"minutes":180})
	replay.command("clock", "advance", {"minutes":180})
	t._check(_same(sim.export_snapshot(), replay.export_snapshot()), "family expenses, needs and future RNG reproduce after loading")
	for corrupt in ["needs", "task", "birth", "caregiver"]:
		var bad: Dictionary = sim.export_snapshot()
		match corrupt:
			"needs": bad.state.family.members.family_1.needs.food = -1
			"task": bad.state.family.members.family_1.task = {"action":"invalid", "caregiver":"player", "due":100000}
			"birth": bad.state.healthcare.family[0].minute = "invalid"
			"caregiver": bad.state.family.members.family_1.assignments.food = "stranger"
		before = sim.export_snapshot()
		t._check(not sim.restore_snapshot(bad).ok and before == sim.export_snapshot(), "malformed family snapshot is rejected without changing live world: " + corrupt)
	var old = Life.new(42, _config())
	var old_snapshot: Dictionary = old.export_snapshot()
	t._check(replay.restore_snapshot(old_snapshot).ok and replay.state.family.members.is_empty(), "exact previous catalog gains an empty family section in memory")
	t._check(not old_snapshot.state.has("family"), "old snapshot object is never rewritten by migration")
	birth(sim)
	t._check(sim.state.family.members.size() == 2, "completed family state permits a later sibling")
	_autonomous_care()
	_care_constraints()
	_stages_and_school()

func _autonomous_care() -> void:
	var sim = fresh()
	birth(sim)
	sim.command("npc_agency", "enable")
	var npc: Dictionary = sim.state.social.npcs.parent
	var member: Dictionary = sim.state.family.members.family_1
	npc.pinned_until = 0
	npc.location = "bedroom"
	npc.activity = "rest"
	npc.needs.energy = 90.0
	npc.needs.satiety = 90.0
	member.needs.hygiene = 20.0
	# Start between AI decision boundaries; family must reserve actual caregiver time.
	sim.services.family._autonomy(member)
	t._check(member.task.get("caregiver", "") == "parent" and npc.pinned_until > int(sim.state.clock.total_minutes), "assigned NPC starts and reserves actual care work")
	var snapshot: Dictionary = sim.export_snapshot()
	var replay = Extended.new(1, _config())
	t._check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(snapshot))).ok, "unfinished NPC care is saved")
	sim.command("clock", "advance", {"minutes":15})
	replay.command("clock", "advance", {"minutes":15})
	t._check(member.needs.hygiene > 70 and member.task.is_empty(), "NPC finishes care once after its duration")
	t._check(_same(sim.export_snapshot(), replay.export_snapshot()), "unfinished care continues identically in restored world")

func _stages_and_school() -> void:
	var sim = fresh()
	birth(sim)
	var born := int(sim.state.family.members.family_1.born)
	for pair in [[12,"toddler"], [36,"child"], [144,"teen"], [216,"adult"]]:
		var threshold: int = sim.calendar.add_months(born, int(pair[0]))
		sim.state.clock = sim.calendar.snapshot(threshold - threshold % 60 + 60)
		sim.services.family.tick(int(sim.state.clock.total_minutes))
		t._check(sim.state.family.members.family_1.stage == pair[1], "family stage follows calendar months: " + str(pair[1]))
	var member: Dictionary = sim.state.family.members.family_1
	t._check(member.milestones.size() == 5 and sim.state.social.npcs.size() == 1, "milestones fire once; grown family member remains outside romance population")
	# Separate school fixture so the production clock never runs backwards.
	sim = fresh()
	birth(sim)
	member = sim.state.family.members.family_1
	var school_time: int = sim.calendar.add_months(int(member.born), 73)
	while int(sim.calendar.snapshot(school_time).weekday) > 5: school_time += 1440
	school_time -= school_time % 1440
	sim.state.clock = sim.calendar.snapshot(school_time + 14 * 60)
	sim.services.family.tick(int(sim.state.clock.total_minutes))
	t._check(member.school_days == 1 and member.school_progress > 0, "school attendance has a calendar-based daily result")

func _care_constraints() -> void:
	var sim = fresh()
	birth(sim)
	var member: Dictionary = sim.state.family.members.family_1
	var npc: Dictionary = sim.state.social.npcs.parent
	npc.pinned_until = 0
	npc.location = "bedroom"
	npc.activity = "rest"
	npc.needs.energy = 90.0
	member.needs.hygiene = 20.0
	var minute := int(sim.state.clock.minute_of_day)
	npc.schedule = [{"location":"global_map","activity":"work","hours":[minute+5,minute+65],"weekdays":[int(sim.state.clock.weekday)]}]
	sim.services.family._autonomy(member)
	t._check(member.task.is_empty(), "care never starts across an imminent mandatory shift")
	npc.schedule = []
	sim.services.family._autonomy(member)
	t._check(not member.task.is_empty(), "available co-parent starts the same care after schedule conflict is removed")
	npc.location = "global_map"
	sim.command("clock", "advance", {"minutes":15})
	t._check(member.task.is_empty() and member.needs.hygiene <= 20, "interrupted care grants no remote or unperformed reward")
	sim.state.economy.cash = 0
	sim.state.family.budget = 0
	var day := int(sim.state.clock.day_index)
	sim.state.clock = sim.calendar.snapshot(day * 1440 + 1439)
	sim.command("clock", "advance", {"minutes":1})
	t._check(sim.state.family.arrears == 6 and sim.state.economy.cash == 0, "unpaid daily family cost becomes bounded debt rather than negative cash")
	var old = Life.new(42, _config())
	old.command("social","generate",{"id":"parent","age":28})
	old.state.clock = old.calendar.snapshot(old.calendar.add_months(480, 24))
	old.state.healthcare.family.append({"parent":"parent","partner":"player","minute":480,"care":0,"status":"dependent"})
	var replay = Extended.new(1, _config())
	t._check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(old.export_snapshot()))).ok and replay.state.family.members.family_1.stage == "toddler", "historical family results migrate directly to their current age stage")
	t._check(replay.command("clock","advance",{"minutes":1}).ok, "migrated historical birth continues with a valid family state")

func _same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))
