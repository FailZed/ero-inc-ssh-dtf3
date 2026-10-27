extends RefCounted
var t

func _init(runner) -> void:
	t=runner

func _button(shell, module_id: String, operation: String, choice: String = "") -> Button:
	for button in shell._body.find_children("*","Button",true,false):
		var m: Dictionary=button.get_meta("gameplay_action",{})
		if m.get("module","")==module_id and m.get("operation","")==operation and (choice.is_empty() or m.get("args",{}).get("choice","")==choice): return button
	return null

func run() -> void:
	var before_checks:int=t.checks
	var original:Dictionary=t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim=t.gameplay.simulation
	sim.state.world.location="bedroom"
	sim.state.economy.cash=2000
	sim.state.player.needs.energy=100.0
	var npc:Dictionary=sim.state.social.npcs.asuka
	sim.services.npc_agency._cancel(npc,"reproduction_ui_fixture")
	npc.location="bedroom"
	npc.schedule=[]
	npc.activity="rest"
	npc.pinned_until=0
	npc.needs.energy=100.0
	var bond:Dictionary=sim.services.npc_relationships._bond("asuka","player")
	bond.merge({"trust":80.0,"comfort":80.0,"interest":70.0},true)
	sim.services.npc_relationships._project("asuka","player")
	sim.command("inventory","add",{"id":"barrier_protection","quantity":1})
	var shell=load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	t.root.add_child(shell)
	await t.process_frame
	shell.selected_npc="asuka"
	var before:Dictionary=sim.export_snapshot()
	shell.open_panel("npc")
	t.check(before==sim.export_snapshot(),"previewing encounter invitation does not mutate world or RNG")
	var invitation:Button=_button(shell,"intimacy","begin")
	t.check(invitation!=null and not invitation.disabled,"NPC profile exposes playable intimacy invitation")
	var hooks:Array=[]
	var callback:=func(request): hooks.append(request.duplicate(true))
	t.gameplay.intimacy_scene_requested.connect(callback)
	if invitation!=null and not invitation.disabled: invitation.pressed.emit()
	for choice in ["accept","non_reproductive","barrier","start","finish","close"]:
		shell._refresh()
		var button:Button=_button(shell,"intimacy","choose",choice)
		t.check(button!=null and not button.disabled,"real encounter UI exposes valid step: "+choice)
		if button!=null and not button.disabled: button.pressed.emit()
	t.check(sim.state.intimacy.active.is_empty() and sim.state.intimacy.history.size()==1,"main UI closes encounter exactly once")
	t.check(sim.state.reproduction.exposures.is_empty(),"non-reproductive UI choice never creates a pregnancy")
	t.check(hooks.size()==6 and hooks[4].hook=="intimacy.private_scene","scene plugin receives six committed, revisioned connection points")
	t.gameplay.intimacy_scene_requested.disconnect(callback)
	before=sim.export_snapshot()
	shell.open_panel("health")
	t.check(before==sim.export_snapshot(),"reproductive health UI and clinical previews are read-only")
	t.check(_button(shell,"world","journey")!=null,"health screen supplies a route to actual clinic")
	var old:Dictionary=sim.export_snapshot()
	old.main_schema=4
	old.erase("reproduction_schema")
	old.catalog_hash="unsupported-catalog"
	for key in ["reproduction","intimacy","child_support"]: old.state.erase(key)
	var original_old:Dictionary=old.duplicate(true)
	var restored=t.gameplay.make_simulation()
	t.check(not restored.restore_snapshot(old).ok,"outdated main schema is rejected")
	t.check(old==original_old,"legacy snapshot input remains unchanged")
	t.check(restored.export_snapshot().main_schema==preload("res://scripts/gameplay/main_simulation.gd").MAIN_SCHEMA,"new main snapshots declare the current main schema")
	shell.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World=original
	t.session._sync_game_time_from_dialogic()
	print("REPRODUCTIVE_UI_RESULT ",JSON.stringify({"checks":int(t.checks)-before_checks,"hooks":hooks.size()}))
