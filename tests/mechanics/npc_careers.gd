extends RefCounted
## Focused occupation/calendar regressions, without the unrelated week-long benchmark.
var t
func _init(runner) -> void: t = runner

func run() -> void:
	var life = preload("res://tests/mechanics/npc_life.gd").new(t)
	for method in ["curves_and_inspection","production_isolation","goals_and_prerequisites","needs_and_commitments","travel_and_interruptions","directed_memories_and_emotions","social_autonomy","player_influence","constraints_and_personality","validation_and_replay"]:
		life.call(method)
	preload("res://tests/mechanics/npc_planner.gd").new(t).run()
	preload("res://tests/mechanics/family.gd").new(t)._care_constraints()
	preload("res://tests/mechanics/health_relationships.gd").new(t)._clinic_guards()
	preload("res://tests/mechanics/npc_reproduction.gd").new(t)._protection_and_interruption()
	_authored_assignment()

func _authored_assignment() -> void:
	var sim = preload("res://scripts/mechanics/npc_life_simulation.gd").new(59,{"settings":{"start_minutes":480},"npc_templates":{"authored_worker":{"age":40,"role":"worker","home":"bedroom","schedule":[{"activity":"work","location":"global_map","hours":[480,960],"weekdays":[1,2,3,4,5,6,7]}],"employment":{"job":"office","skill_level":2,"workplace":"global_map"}}}})
	t._check(sim.command("social","generate",{"id":"authored","template":"authored_worker"}).ok,"standalone catalog accepts an explicit authored occupation")
	t._check(sim.command("npc_agency","enable").ok,"authored occupation initializes before autonomous decisions")
	var npc: Dictionary = sim.state.social.npcs.authored
	t._check(npc.mind.employment.job=="office" and npc.skills.computing==40 and npc.schedule[0].hours==[480,960],"authored profession, skill and full shift remain authoritative")
	var before: Dictionary = sim.export_snapshot()
	var rejected: Dictionary = sim.command("social","generate",{"id":"invalid_author","template":"authored_worker","employment":{"job":"reporter","skill_level":2,"workplace":"global_map"}})
	t._check(not rejected.ok and before==sim.export_snapshot(),"conflicting template and spawn occupations reject without changing the world")
