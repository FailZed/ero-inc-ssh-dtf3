extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	var id := str(sim.state.social.npcs.keys()[0])
	var npc: Dictionary = sim.state.social.npcs[id]
	sim.services.npc_agency._cancel(npc,"health_relationships_fixture")
	npc.location = "residential_district"
	npc.activity = "rest"
	npc.pinned_until = 0
	npc.schedule = []
	npc.appearance.has_penis = true
	npc.needs.energy = 100.0
	npc.needs.mood = 60.0
	sim.state.world.location = npc.location
	var bond: Dictionary = sim.services.npc_relationships._bond(id,"player")
	bond.merge({"trust":75.0,"comfort":65.0,"interest":70.0,"closeness":60.0},true)
	var health = sim.services.adult_health
	health.synchronize()
	health.record(id).erection.difficulty_until = int(sim.state.clock.total_minutes)+180
	t.check(not health.try_intimacy("player",id),"main runtime records actual physiological setback")
	t.check(health.relationships.worry(id,"player")>0,"main runtime retains worry toward the actual player partner")
	health.record(id).desire.frustration = 30.0
	var minute := int(sim.state.clock.total_minutes)
	var result: Dictionary = t.gameplay.execute("npc_relationships","interact",{"id":id,"action":"cooperate"})
	t.check(result.ok and result.data.get("accepted",false),"main player help uses the canonical accepted relationship action")
	t.check(int(sim.state.clock.total_minutes)==minute+int(sim.catalog.agency_actions.cooperate.minutes),"main help spends one actual action duration")
	t.check(health.relationships.worry(id,"player")==0 and float(health.record(id).desire.frustration)<29,"main player help relieves partner-specific worry and frustration")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	t.check(sim.restore_snapshot(snapshot).ok,"main current-schema world restores new emotional memory")
	t.dialogic.VAR.var_storage.World = original
	t.fresh_world()
