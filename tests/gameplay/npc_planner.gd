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
	sim.services.npc_agency._cancel(npc,"planner_main_fixture")
	npc.pinned_until = 0
	npc.schedule = []
	npc.activity = "rest"
	npc.location = "residential_district"
	var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),"riverside_cafe")
	t.check(not route.is_empty() and int(route.get("minutes",0))>0,"main planner resolves a real city route")
	if not route.is_empty():
		var due := int(sim.state.clock.total_minutes)+30+int(route.minutes)
		t.check(t.gameplay.execute("social","appointment",{"id":id,"minute":due,"location":"riverside_cafe"}).ok,"main UI command books an NPC obligation")
		sim.state.world.location = "riverside_cafe"
		t.check(t.gameplay.execute("clock","advance",{"minutes":30}).ok,"main clock reaches NPC departure")
		t.check(npc.location=="residential_district" and sim.state.social.appointments[-1].get("journey",{}).get("phase","")=="travel","main meeting keeps NPC at actual journey origin until arrival")
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
		t.check(sim.restore_snapshot(snapshot).ok,"main world restores in-flight planner reservation")
		t.check(t.gameplay.execute("clock","advance",{"minutes":int(route.minutes)}).ok,"main clock completes the actual city journey")
		t.check(sim.state.social.appointments[-1].status=="met" and sim.state.social.npcs[id].location=="riverside_cafe","main meeting settles after actual arrival")
	t.dialogic.VAR.var_storage.World = original
	t.fresh_world()
