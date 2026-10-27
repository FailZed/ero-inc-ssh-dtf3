extends RefCounted
const Formulas = preload("res://scripts/mechanics/core/formulas.gd")
var t

func _init(runner) -> void: t = runner

func run() -> void:
	time_and_supply()
	stream_and_contracts()
	social_branches()
	curves_and_npc()
	date_choices_and_interests()

func date_choices_and_interests() -> void:
	var sim = fresh()
	t.command(sim,"social","generate",{"id":"a"})
	sim.state.world.location = "global_map"
	sim.state.social.npcs.a.location = "global_map"
	sim.state.social.npcs.a.activity = "walk"
	sim.state.social.npcs.a.pinned_until = 100000
	sim.services.social.relationship("a","player").trust = 20
	sim.state.world.weather = "rain"
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("social_rules","date",{"id":"a","venue":"walk"}).ok and sim.export_snapshot() == before, "outdoor date checks weather before spending time or money")
	sim.state.world.weather = "clear"
	sim.state.economy.cash = 0
	t.command(sim,"social_rules","date",{"id":"a","venue":"walk"})
	t._check(sim.state.economy.cash == 0 and sim.state.social.npcs.a.memories.back().data.venue == "walk", "free walk is a real alternative to a paid date")
	var population = fresh()
	t.command(population,"population","configure",{"values":{"count":40}})
	t.command(population,"population","generate")
	var categories := {}
	for npc in population.state.social.npcs.values(): categories[JSON.stringify(npc.preferences)] = true
	t._check(categories.size() >= 3, "generated residents have distinct interests rather than all liking books")

func fresh():
	return t.fresh({"settings": {"start_minutes": 1920}})

func time_and_supply() -> void:
	var sim = fresh()
	t.command(sim, "preferences", "difficulty", {"id":"hard"})
	sim.state.player.needs.energy = 0
	sim.state.player.needs.mood = 35
	t.command(sim, "character", "rest", {"minutes":480})
	t._check(sim.state.player.needs.energy > 95 and not sim.services.health.record("player").collapsed and sim.state.player.needs.mood > 35, "sleep recovers continuously without causing a blackout during rest")
	t._check(not sim.resting, "rest context is cleared at transaction end")
	sim.state.world.location = "global_map"
	t.command(sim, "inventory", "buy", {"id":"meal","shop":"market","quantity":10})
	t.command(sim, "clock", "advance", {"minutes":1440})
	t._check(sim.state.economy.shop_stock.market.meal == 20, "daily food supply replenishes to catalog stock")
	var before: Dictionary = sim.export_snapshot()
	var invalid = t.fresh({"balance_rules":{"career":{"skill_scale":0}}})
	t._check(not invalid.configuration_error.is_empty(), "zero mastery scale is rejected in catalog")
	t._check(not sim.command("preferences","customize",{"values":{"npc_tactics":2}}).ok and before == sim.export_snapshot(), "invalid tactics override is atomic")

func stream_and_contracts() -> void:
	var whole = fresh()
	var split = fresh()
	whole.state.world.equipment = ["computer"]
	split.state.world.equipment = ["computer"]
	t.command(whole,"economy","stream",{"minutes":60})
	for i in range(4): t.command(split,"careers","stream",{"id":"games","minutes":15})
	t._check(whole.state.economy.channel == split.state.economy.channel and whole.state.economy.cash == split.state.economy.cash and whole.state.player.skills == split.state.player.skills, "legacy and themed streaming agree under session splitting")
	var before: Dictionary = split.export_snapshot()
	t._check(not split.command("economy","stream",{"minutes":1}).ok and before == split.export_snapshot(), "minute spam cannot bypass stream duration or generate free growth")
	whole.state.player.needs.energy = 100
	t.command(whole,"careers","stream",{"id":"games","minutes":240})
	whole.state.player.needs.energy = 100
	t.command(whole,"careers","stream",{"id":"games","minutes":60})
	t._check(not whole.command("economy","stream",{"minutes":15}).ok, "both streaming APIs share the daily six-hour limit")
	var deadline = fresh()
	deadline.state.world.equipment = ["computer"]
	deadline.state.clock = deadline.calendar.snapshot(2880 - 30)
	deadline.state.careers.workdays["stream:1"] = 330
	t.command(deadline,"careers","stream",{"id":"games","minutes":60})
	t._check(deadline.state.careers.workdays["stream:1"] == 360 and deadline.state.careers.workdays["stream:2"] == 30, "midnight stream splits its budget across actual calendar days")
	var bulk = fresh()
	var pieces = fresh()
	for sim in [bulk,pieces]:
		sim.state.world.equipment = ["computer"]
		t.command(sim,"careers","take_contract",{"id":"small_website"})
	t.command(bulk,"careers","work_contract",{"id":"small_website","minutes":20})
	for i in range(20): t.command(pieces,"careers","work_contract",{"id":"small_website","minutes":1})
	t._check(bulk.state.player.skills == pieces.state.player.skills and bulk.state.player.skills.computing == 2 and is_equal_approx(bulk.state.careers.contracts.small_website.progress, pieces.state.careers.contracts.small_website.progress), "contract work awards identical progress and XP for identical productive minutes")
	var huge = fresh()
	huge.state.world.equipment = ["computer"]
	huge.state.economy.channel.followers = 1000000
	var result: Dictionary = t.command(huge,"careers","stream",{"id":"games","minutes":60})
	t._check(result.data.income < 1000, "a large channel grows sublinearly rather than exploding in one session")

func social_branches() -> void:
	var sim = fresh()
	t.command(sim,"social","generate",{"id":"a"})
	t.command(sim,"social","generate",{"id":"b"})
	var npc: Dictionary = sim.state.social.npcs.a
	npc.location = sim.state.world.location
	npc.activity = "rest"
	npc.pinned_until = 100000
	var initial: Dictionary = sim.services.social_rules.conversation_forecast("a","talk")
	sim.state.player.stats.charisma = 100
	var high: Dictionary = sim.services.social_rules.conversation_forecast("a","talk")
	t._check(high.data.chance > initial.data.chance and high.data.chance < 0.97, "charisma improves conversation with diminishing returns instead of guaranteeing success")
	sim.services.social.relationship("a","player").fear = 80
	t._check(sim.services.social_rules.conversation_forecast("a","talk").data.chance < high.data.chance, "fear changes conversation even with high charisma")
	sim.services.social.relationship("a","player").fear = 0
	t.command(sim,"inventory","add",{"id":"book","quantity":4})
	for i in range(3): t.command(sim,"social","gift",{"id":"a","item":"book"})
	var affinity := float(sim.services.social.relationship("a","player").affinity)
	t.command(sim,"social","gift",{"id":"a","item":"book"})
	t._check(sim.services.social.relationship("a","player").affinity == affinity and npc.inventory.book == 4, "additional gifts still transfer ownership but cannot farm relationship rewards")
	t._check(not sim.command("social_rules","apologize",{"id":"a"}).ok, "apologies without a new incident grant no free trust")
	npc = sim.state.social.npcs.a # A rejected command restores an independent state tree.
	npc.needs.mood = 10
	t._check(sim.services.social_rules.conversation_forecast("a","listen").data.branch == "stressed", "listening responds to an NPC's actual mood")
	t.command(sim,"preferences","content_tag",{"id":"romance","enabled":false})
	t._check(not sim.command("social","interact",{"id":"a","action":"flirt"}).ok, "private romance branches respect content settings")
	t.command(sim,"preferences","content_tag",{"id":"romance","enabled":true})
	sim.services.social.relationship("a","player").trust = 25
	t.command(sim,"social_rules","date",{"id":"a"})
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("social_rules","date",{"id":"a"}).ok and sim.export_snapshot() == before, "repeated dates within twenty-four hours are rejected without charging")
	npc = sim.state.social.npcs.a
	npc.activity = "work"
	npc.decision.committed = true
	t._check(not sim.command("social","invite",{"id":"a"}).ok, "an invitation cannot teleport an NPC out of mandatory work")
	var due := int(sim.state.clock.total_minutes) + 100
	t.command(sim,"social","appointment",{"id":"a","minute":due,"location":"global_map"})
	t._check(not sim.command("social","appointment",{"id":"b","minute":due+10,"location":"global_map"}).ok, "player cannot promise overlapping meetings to different NPCs")

func curves_and_npc() -> void:
	var sim = fresh()
	var small = fresh()
	var large = fresh()
	for subject in [small,large]: t.command(subject,"preferences","difficulty",{"id":"hard"})
	for i in range(10): t.command(small,"character","gain_xp",{"amount":1})
	t.command(large,"character","gain_xp",{"amount":10})
	t._check(small.state.player.xp == large.state.player.xp and small.state.player.xp == 9, "fractional XP carry preserves hard difficulty and prevents rounding exploits")
	t._check(sim.services.activities.attribute_threshold(5) == 100 and sim.services.activities.attribute_threshold(50) == 900, "attribute training stays quick early and slows smoothly for specialists")
	t._check(Formulas.career_pay(1,{}) == 1 and Formulas.career_pay(100,{}) == 2.5, "career pay retains bounded promotion rewards")
	t._check(Formulas.mastery(0) == 0 and Formulas.mastery(200) == 0.5 and Formulas.mastery(1000000) < 1, "skill mastery is monotone and saturating")
	t.command(sim,"social","generate",{"id":"a"})
	var npc: Dictionary = sim.state.social.npcs.a
	npc.activity = "sleep"
	npc.needs.energy = 35
	t._check(sim.services.npc_behavior.plan(npc).activity == "sleep", "NPC finishes a useful block of sleep instead of oscillating each hour")
	npc.needs.energy = 80
	t._check(sim.services.npc_behavior.plan(npc).activity != "sleep", "a rested NPC returns to its daytime schedule")
	npc.location = "global_map"
	npc.activities = ["walk"]
	var repeated: Array = sim.services.npc_behavior.candidates(npc, "walk")
	var novel: Array = sim.services.npc_behavior.candidates(npc, "read")
	t._check(is_equal_approx(float(repeated[0].weight) * 2, float(novel[0].weight)), "leisure scoring remembers the previous activity rather than the new schedule placeholder")
	npc.location = sim.state.world.location
	t.command(sim,"combat","start",{"npc":"a"})
	t.command(sim,"combat","action",{"action":"stance","id":"aggressive"})
	t.command(sim,"combat","action",{"action":"attack","move":"jab"})
	t._check(sim.state.encounters.combat.ap == 1, "stance switching has a real action-point opportunity cost")
	t._check(not sim.services.combat.forecast("jab","body","player",-1).ok, "combat preview rejects invalid effort just like the actual action")
