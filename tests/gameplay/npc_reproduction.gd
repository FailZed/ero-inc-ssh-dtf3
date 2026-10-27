extends RefCounted
const Previous = preload("res://scripts/mechanics/reproductive_simulation.gd")
const City = preload("res://scripts/gameplay/city_layout.gd")
const Names = preload("res://scripts/gameplay/presentation.gd")
var t

func _init(runner) -> void:
	t=runner

func run() -> void:
	var start_checks:int=t.checks
	var original:Dictionary=t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim=t.gameplay.simulation
	t.check(sim.services.has("npc_reproduction") and sim.services.npc_reproduction.enabled(),"main game automatically runs independent NPC reproductive life")
	for pair in [["auto_a","female"],["auto_b","male"]]:
		var template:={"age":29,"gender":pair[1],"home":"residential_district","money":1000,"schedule":[],"activities":[],"role":"resident",
			"reproductive_profile":{"desire":"open","requires_protection":false}}
		t.check(sim.services.social.generate_from_template(pair[0],{},template).ok,"main runtime creates independent adult "+pair[0])
		var npc:Dictionary=sim.state.social.npcs[pair[0]]
		sim.services.npc_agency._cancel(npc,"npc_integration_fixture")
		npc.location="residential_district"
		npc.activity="rest"
		npc.pinned_until=0
		npc.needs.merge({"energy":100.0,"satiety":100.0,"hygiene":100.0,"social":90.0,"fun":90.0},true)
		sim.command("npc_reproduction","configure",{"id":pair[0],"values":{"preferred_method":"none","emergency":false}})
	for pair in [["auto_a","auto_b"],["auto_b","auto_a"]]:
		sim.services.npc_relationships._bond(pair[0],pair[1]).merge({"trust":80.0,"comfort":75.0,"interest":70.0,"closeness":65.0,"affection":50.0,"consent":true},true)
	sim.services.npc_relationships._project("auto_a","auto_b")
	sim.services.social.relationship("auto_a","auto_b").status="partner"
	t.gameplay._bind_npc_art()
	var foreground:Array=[]
	var background:Array=[]
	var on_front:=func(request): foreground.append(request)
	var on_background:=func(event):
		if event.kind=="npc_intimacy_scene_requested": background.append(event)
	t.gameplay.intimacy_scene_requested.connect(on_front)
	sim.domain_event.connect(on_background)
	# Keep the production probability; enough evening opportunities are observed without forcing a choice.
	var minute:=int(sim.state.clock.total_minutes)
	t.check(t.gameplay.execute("clock","advance",{"minutes":120}).ok,"main game's shared time advances NPC background meetings")
	t.check(int(sim.state.clock.total_minutes)==minute+120,"main background life never doubles the player's elapsed time")
	t.check(not background.is_empty() and foreground.is_empty(),"NPC scene hooks remain background and never request player scene controls")
	t.check(sim.state.intimacy.active.is_empty(),"main player encounter state remains free while NPCs interact")
	t.gameplay.intimacy_scene_requested.disconnect(on_front)
	sim.domain_event.disconnect(on_background)
	var stored:Dictionary=t.dialogic.VAR.var_storage.World.duplicate(true)
	var expected:Dictionary=sim.export_snapshot()
	t.gameplay.execute("clock","advance",{"minutes":15})
	t.dialogic.VAR.var_storage.World=stored
	t.session._sync_game_time_from_dialogic()
	t.check(t.gameplay.simulation.export_snapshot()==expected,"World restoration retains NPC background state and RNG")
	var outdated: Dictionary = sim.export_snapshot()
	outdated.main_schema = 6
	var unchanged := outdated.duplicate(true)
	var restored = t.gameplay.make_simulation()
	t.check(not restored.restore_snapshot(outdated).ok,"previous main schema is unsupported")
	t.check(outdated == unchanged,"rejecting an outdated snapshot leaves the input unchanged")
	t.check(restored.export_snapshot().main_schema == preload("res://scripts/gameplay/main_simulation.gd").MAIN_SCHEMA,"current main state declares its supported schema")
	t.dialogic.VAR.var_storage.World=original
	t.session._sync_game_time_from_dialogic()
	print("NPC_REPRODUCTIVE_MAIN_RESULT ",JSON.stringify({"checks":int(t.checks)-start_checks,"background_hooks":background.size(),"foreground_hooks":foreground.size()}))
