extends RefCounted
const Setup = preload("res://scripts/mechanics/setup_config.gd")
const Formulas = preload("res://scripts/mechanics/core/formulas.gd")
const Population = preload("res://scripts/mechanics/population.gd")
var t

func _init(runner) -> void:
	t = runner

func run() -> void:
	setup_and_generation()
	population_morphologies()
	formulas_and_turns()
	difficulty_branches()
	npc_decisions_and_interactions()

func setup_and_generation() -> void:
	var config := Setup.defaults()
	config.population.count = 12
	config.population.female_ratio = 0.25
	config.population.age_min = 22
	config.population.age_max = 35
	config.population.trait_spread = 0
	config.population.loyalty = 80
	config.population.stat_min = 6
	config.population.stat_max = 9
	var first := Setup.build(config)
	var second := Setup.build(config)
	t._check(first.ok and second.ok, "standalone setup creates complete worlds")
	if not first.ok or not second.ok: return
	var sim = first.data.simulation
	t._check(sim.export_snapshot() == second.data.simulation.export_snapshot(), "identical setup and seed produce the same world")
	t._check(sim.state.player.name == config.profile.full_name and sim.state.player.points == Setup.remaining_points(config), "creation applies profile and retains unspent starting points")
	var women := 0
	var bounded := true
	for npc in sim.state.social.npcs.values():
		if npc.gender == "female": women += 1
		bounded = bounded and npc.age >= 22 and npc.age <= 35 and npc.traits.loyalty == 80
		for value in npc.stats.values(): bounded = bounded and value >= 6 and value <= 9
	t._check(women == 3 and bounded, "population respects exact demographic composition and attribute ranges")
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("population", "configure", {"values": {"age_min": 17}}).ok and sim.export_snapshot() == before, "population rejects invalid age before mutation")
	config.profile.age = 17
	t._check(not Setup.build(config).ok, "character setup rejects underage profiles")
	config.profile.age = 24
	config.profile.stats.strength = 30
	config.difficulty = "hard"
	t._check(not Setup.build(config).ok, "difficulty-specific starting budget cannot be bypassed")
	config = Setup.defaults()
	t._check(Setup.point_budget(config) == 30, "normal profile uses thirty starting points")
	config.difficulty = "easy"
	t._check(Setup.point_budget(config) == 40, "easy profile uses forty starting points")
	config.difficulty = "hard"
	t._check(Setup.point_budget(config) == 20, "hard profile uses twenty starting points")
	config.difficulty = "custom"
	config.custom = {"xp": 1.8, "satiety_enabled": false, "initial_points": 25}
	config.population.count = 1
	var custom := Setup.build(config)
	t._check(custom.ok and custom.data.simulation.services.preferences.rule("xp") == 1.8 and Setup.point_budget(config) == 25, "custom setup applies validated rule overrides")

func population_morphologies() -> void:
	var config := Setup.defaults()
	config.population.count = 20
	var result := Setup.build(config)
	t._check(result.ok, "mixed population is generated independently of the main game")
	if not result.ok: return
	var sim = result.data.simulation
	var counts := {"human": 0, "semi_furry": 0, "furry": 0}
	var distinct_anatomy := true
	for id in sim.state.social.npcs:
		var descriptor: Dictionary = sim.services.appearance.descriptor(id)
		counts[descriptor.morphology] += 1
		distinct_anatomy = distinct_anatomy and (descriptor.anatomy.face == "muzzle") == (descriptor.morphology == "furry")
		distinct_anatomy = distinct_anatomy and (descriptor.anatomy.covering == "fur") == (descriptor.morphology == "furry")
		distinct_anatomy = distinct_anatomy and descriptor.anatomy.animal_ears == (descriptor.morphology != "human")
	t._check(counts == {"human": 12, "semi_furry": 5, "furry": 3} and distinct_anatomy, "population proportions and renderer descriptors distinguish all three morphologies")
	t._check(Population.morphology_counts({"count": 3}) == {"human": 2, "semi_furry": 1, "furry": 0}, "small populations use deterministic largest-remainder rounding")
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("population", "configure", {"values": {"semi_furry_ratio": 0.7, "furry_ratio": 0.5}}).ok and sim.export_snapshot() == before, "population rejects composition exceeding one hundred percent atomically")
	var id: String = sim.state.social.npcs.keys()[0]
	t._check(not sim.command("appearance", "customize", {"target": id, "features": {"morphology": "unknown"}}).ok and sim.export_snapshot() == before, "unknown morphology cannot leak into a renderer")
	t.command(sim, "appearance", "customize", {"target": id, "features": {"morphology": "semi_furry", "has_tail": false}})
	t._check(not sim.services.appearance.descriptor(id).anatomy.tail and sim.services.appearance.descriptor(id).anatomy.animal_ears, "semi-furry can have ears without a tail as in the EroInc story")
	t.command(sim, "appearance", "customize", {"target": id, "features": {"has_tail": true}})
	t._check(sim.services.appearance.descriptor(id).anatomy.tail, "optional semi-furry tail is an explicit visual feature")
	t.command(sim, "population", "configure", {"values": {"count": 1, "semi_furry_ratio": 0.0, "furry_ratio": 1.0}})
	var pure: Dictionary = t.command(sim, "population", "generate")
	t._check(pure.data.morphologies == {"human": 0, "semi_furry": 0, "furry": 1} and sim.services.appearance.descriptor(pure.data.ids[0]).anatomy.face == "muzzle", "fully furry population supports zero-human boundary without losing residents")

func formulas_and_turns() -> void:
	t._check(is_equal_approx(Formulas.dialogue_fatigue(0, 0, 100, 1), 3.6), "School dialogue baseline matches researched reference")
	t._check(is_equal_approx(Formulas.dialogue_fatigue(100, 100, 100, 1), 2.3), "trust and erudition reduce dialogue fatigue")
	t._check(Formulas.auto_defence(0) == 0.05 and Formulas.auto_defence(100000) == 0.74, "experience defence is saturating and bounded")
	t._check(Formulas.target_switch(100000) == 0.65, "experienced target switching respects its cap")
	var forecast := Formulas.combat(10, 10, 10, 5, {"damage": 1.6, "accuracy": -0.1}, 0, 1, {"stat_scale": 4, "base_accuracy": 25})
	t._check(is_equal_approx(forecast.accuracy, 0.382) and forecast.damage == 16 and is_equal_approx(forecast.critical, 0.12512), "scaled combat formula matches an independently calculated reference")
	var sim = t.fresh()
	var neutral := float(sim.services.character.xp_multiplier())
	sim.state.player.needs.mood = 90
	t._check(sim.services.character.xp_multiplier() > neutral, "positive mood increases earned experience")
	sim.state.player.needs.mood = 10
	t._check(sim.services.character.xp_multiplier() < neutral, "low mood reduces earned experience without deleting earned progress")
	t.command(sim, "social", "generate", {"id": "opponent"})
	for id in sim.catalog.combat_moves: sim.catalog.combat_moves[id].stamina = 999
	sim.catalog.combat_moves.jab.stamina = 8
	t.command(sim, "combat", "start", {"npc": "opponent"})
	t.command(sim, "combat", "action", {"action": "end_turn"})
	t._check(sim.state.encounters.combat.phase == "defence" and sim.state.encounters.combat.log.is_empty(), "passing the turn waits for a defence decision")
	while sim.state.encounters.combat.phase == "defence": t.command(sim,"combat","action",{"action":"guard","part":"head"})
	var attacks := 0
	for entry in sim.state.encounters.combat.log:
		if entry.get("actor") == "npc" and entry.has("move"): attacks += 1
	t._check(attacks == 2 and sim.state.encounters.combat.npc_ap == 0, "NPC spends a complete four-AP turn and cannot overspend")
	t._check(not sim.services.combat.forecast("jab", "body", "unknown").ok, "combat forecast rejects a third-party attacker")

	# Two rounds with a controlled move catalog: each confirmation is one response.
	var combat: Dictionary = sim.state.encounters.combat
	combat.stamina.player = 100.0
	combat.stamina.npc = 100.0
	for id in sim.catalog.combat_moves:
		sim.catalog.combat_moves[id].knockdown = -1.0
		sim.catalog.combat_moves[id].critical = -1.0
	var before: Dictionary = sim.export_snapshot()
	for effort: float in [0.5,1.0,1.5]: sim.services.combat.forecast("jab","legs","player",effort)
	t._check(sim.export_snapshot()==before,"changing attack previews preserves the world and RNG")
	var turn := int(combat.turn)
	t.command(sim,"combat","action",{"action":"attack","move":"jab"})
	t.command(sim,"combat","action",{"action":"attack","move":"jab"})
	t._check(combat.phase=="defence" and combat.turn==turn and combat.npc_ap==4,"two two-AP attacks open defence without executing an NPC attack")
	before = sim.export_snapshot()
	t._check(not sim.command("combat","action",{"action":"attack"}).ok and sim.export_snapshot()==before,"attack is rejected atomically in the defence phase")
	combat = sim.state.encounters.combat
	var saved: Dictionary = sim.export_snapshot()
	var restored = t.fresh()
	restored.catalog = sim.catalog.duplicate(true)
	t._check(restored.restore_snapshot(saved).ok and restored.state.encounters.combat.phase=="defence","a pending defence restores through the existing snapshot")
	var response := {"action":"guard","part":"head","revision":int(combat.revision)}
	var count: int = combat.log.size()
	t.command(sim,"combat","action",response)
	t.command(restored,"combat","action",response)
	t._check(sim.export_snapshot()==restored.export_snapshot(),"the restored defence resolves the same RNG and world state")
	t._check(combat.log.size()==count+1 and combat.npc_ap==2 and combat.phase=="defence","one defence confirmation resolves exactly one NPC action")
	before = sim.export_snapshot()
	t._check(not sim.command("combat","action",response).ok and sim.export_snapshot()==before,"repeated stale confirmation cannot execute the next response")
	combat = sim.state.encounters.combat
	t.command(sim,"combat","action",{"action":"guard","part":"body"})
	t._check(combat.phase=="attack" and combat.turn==turn+1 and combat.ap==4 and combat.npc_ap==0,"the last response restores the player turn once")
	sim.catalog.combat_moves.heavy.stamina = 15
	t.command(sim,"combat","action",{"action":"attack","move":"heavy","part":"body"})
	t._check(combat.ap==1 and combat.phase=="attack","a strong attack leaves the remaining point available")
	sim.catalog.combat_moves.heavy.stamina = 999
	t.command(sim,"combat","action",{"action":"end_turn"})
	t._check(combat.phase=="defence" and combat.turn==turn+1,"passing a remaining point waits for the second round defence")
	for response_index in range(4):
		if combat.phase!="defence": break
		t.command(sim,"combat","action",{"action":"guard","part":"legs"})
	t._check(combat.turn==turn+2 and combat.ap==4,"second round returns to attack after separate responses")
	t.command(sim,"combat","action",{"action":"end_turn"})
	combat.statuses.npc.knockdown = 1
	t.command(sim,"combat","action",{"action":"guard"})
	t._check(combat.phase=="attack" and combat.log[-1].action=="stand_up","knocked-down opponent stands up without leaving defence stuck")
	t.command(sim,"combat","action",{"action":"end_turn"})
	combat.stamina.npc = 0.0
	t.command(sim,"combat","action",{"action":"guard"})
	t._check(combat.phase=="attack" and combat.log[-1].action=="recover","exhausted opponent recovers and returns control")
	t.command(sim,"combat","action",{"action":"end_turn"})
	for id in sim.catalog.combat_moves: sim.catalog.combat_moves[id].stamina = 999
	t.command(sim,"combat","action",{"action":"guard"})
	t._check(combat.phase=="attack" and combat.log[-1].action=="wait","opponent without any available move cannot lock the battle")
	t.command(sim,"combat","action",{"action":"end_turn"})
	sim.services.health.set_hp("opponent",0)
	count = combat.log.size()
	t.command(sim,"combat","action",{"action":"guard"})
	t._check(combat.status=="won" and combat.phase=="finished" and combat.npc_ap==0 and combat.log.size()==count,"incapacitated opponent cannot execute a deferred response")

func _advance_to(sim, minute: int) -> void:
	while sim.state.clock.total_minutes < minute:
		t.command(sim, "clock", "advance", {"minutes": mini(43200, minute - int(sim.state.clock.total_minutes))})

func difficulty_branches() -> void:
	var easy = t.fresh()
	t.command(easy, "preferences", "difficulty", {"id": "easy"})
	easy.state.player.needs.satiety = 1
	easy.services.health.injure("player", "arms", 20)
	t.command(easy, "clock", "advance", {"minutes": 60})
	t._check(easy.state.player.needs.satiety == 1 and easy.state.player.injuries.is_empty(), "easy rules disable hunger consumption and limb damage")
	var hard = t.fresh()
	t.command(hard, "preferences", "difficulty", {"id": "hard"})
	hard.services.health.injure("player", "arms", 20)
	t._check(hard.state.player.injuries.arms == 20, "hard rules retain full limb damage")
	hard.state.player.needs.energy = 0
	t.command(hard, "clock", "advance", {"minutes": 180})
	t._check(hard.services.health.record("player").get("unconscious_until", 0) > hard.state.clock.total_minutes, "hard exhaustion creates an actual recovery period")
	t._check(not hard.command("activities", "practice", {"id": "strength"}).ok, "unconscious player cannot perform unrelated actions")
	t.command(hard, "character", "rest", {"minutes": 120})
	t._check(hard.state.player.needs.energy > 20, "rest completes blackout and restores usable energy")
	var custom_before: Dictionary = easy.export_snapshot()
	t._check(not easy.command("preferences", "customize", {"values": {"xp": -1}}).ok and easy.export_snapshot() == custom_before, "invalid custom difficulty is rolled back")
	var renter = t.fresh({"settings": {"start_cash": 500}})
	t.command(renter, "preferences", "difficulty", {"id": "hard"})
	t.command(renter, "housing", "rent", {"id": "apartment"})
	t.command(renter, "housing", "move_in", {"id": "apartment"})
	renter.state.economy.cash = 0
	_advance_to(renter, renter.calendar.add_months(int(renter.state.clock.total_minutes), 2))
	t._check(renter.state.housing.residence.is_empty() and renter.state.housing.properties.apartment.get("evicted", false), "hard rental debt eventually causes eviction while retaining the debt")
	t._check(not renter.command("housing", "move_in", {"id": "apartment"}).ok, "eviction cannot be bypassed by moving back in")
	var student = t.fresh({"settings": {"start_minutes": 0}, "lessons": {"daily": {"hours": [0, 1], "weekdays": [1,2,3,4,5,6,7]}}})
	_advance_to(student, 8 * 1440)
	t._check(student.state.world.education.get("expelled", false), "repeated missed classes cause a distinct disciplinary state")
	t.command(student, "character", "rest", {"minutes":120})
	t.command(student, "world", "homework")
	t.command(student, "world", "appeal")
	t._check(not student.state.world.education.expelled and student.state.world.education.absences == 0, "prepared appeal provides a paid path back into education")

func npc_decisions_and_interactions() -> void:
	var sim = t.fresh({"settings": {"start_minutes": 480}, "npc_templates": {"worker": {"role": "worker", "activities": ["socialize"], "schedule": [{"location": "global_map", "activity": "work"}]}}})
	t.command(sim, "social", "generate", {"id": "worker", "template": "worker"})
	var npc: Dictionary = sim.state.social.npcs.worker
	t.command(sim, "clock", "advance", {"minutes": 60})
	t._check(npc.activity == "work" and npc.money == 112, "mandatory work takes priority over leisure and pays only for active work")
	npc.needs.energy = 10
	t.command(sim, "clock", "advance", {"minutes": 60})
	t._check(npc.activity == "sleep" and npc.location == npc.home and npc.needs.energy > 10, "urgent rest overrides ordinary work and recovers energy")
	npc.needs.energy = 80
	npc.needs.satiety = 10
	npc.inventory.meal = 1
	t.command(sim, "clock", "advance", {"minutes": 60})
	t._check(npc.activity == "eat" and not npc.inventory.has("meal") and npc.needs.satiety > 50, "NPC food action consumes actual owned food")
	var social = t.fresh()
	t.command(social, "social", "generate", {"id": "reader"})
	var forecast: Dictionary = social.services.social_rules.conversation_forecast("reader", "discuss_books")
	t._check(forecast.data.branch == "shared_interest" and forecast.data.success.affinity == 6, "private conversation branch responds to NPC preferences")
	t.command(social, "social", "relationship", {"id": "reader", "changes": {"trust": -10}})
	social.state.social.npcs.reader.traits.responsibility = 90
	forecast = social.services.social_rules.conversation_forecast("reader", "offer_help")
	t._check(forecast.data.branch == "distrust", "ordered private branches resolve distrust before general personality")
	var result: Dictionary = t.command(social, "social", "interact", {"id": "reader", "action": "offer_help"})
	t._check(result.data.branch == "distrust" and result.data.text_token == "conversation.help.cautious", "interaction publishes the chosen content token without coupling to a dialogue scene")
