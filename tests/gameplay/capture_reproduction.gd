extends SceneTree
## Actual native frames from a prepared test world; no user save is opened or changed.
var directory := "E:/GoDot/.research/school-0.981/reproduction-2026-10-27/captures"

func _initialize() -> void:
	call_deferred("_run")

func _capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(directory.path_join(name+".png")) != OK:
		printerr("FAIL: capture ",name)
		quit(1)

func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy": quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	var gameplay=root.get_node("Gameplay")
	var session=root.get_node("GameSession")
	var dialogic=root.get_node("Dialogic")
	session.pause_autosave_runtime()
	var config:=preload("res://scripts/mechanics/setup_config.gd").defaults()
	config.population.count=8
	gameplay._pending_configuration=config
	dialogic.clear(DialogicGameHandler.ClearFlags.FULL_CLEAR)
	session.reset_game_time()
	session.reset_character_profile()
	gameplay.complete_chapter_one()
	var sim=gameplay.simulation
	sim.state.world.location="bedroom"
	sim.state.economy.cash=1800
	var npc:Dictionary=sim.state.social.npcs.asuka
	sim.services.npc_agency._cancel(npc,"capture_fixture")
	npc.location="bedroom"
	npc.activity="rest"
	npc.schedule=[]
	npc.pinned_until=0
	npc.needs.energy=100.0
	var bond:Dictionary=sim.services.npc_relationships._bond("asuka","player")
	bond.merge({"trust":80.0,"comfort":70.0,"interest":65.0},true)
	sim.services.npc_relationships._project("asuka","player")
	sim.state.inventory.items.barrier_protection=1
	sim.services.reproduction.record("asuka").requires_protection=false
	sim.services.reproduction.record("player").requires_protection=false
	sim.command("intimacy","begin",{"id":"asuka"})
	var a:Dictionary=sim.state.intimacy.active
	sim.command("intimacy","choose",{"session":a.id,"revision":a.revision,"choice":"accept"})
	a=sim.state.intimacy.active
	sim.command("intimacy","choose",{"session":a.id,"revision":a.revision,"choice":"pregnancy_possible"})
	var shell=load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	root.add_child(shell)
	await process_frame
	DisplayServer.window_set_size(Vector2i(1366,768))
	shell.open_panel("npc")
	await _capture("protection")
	a=sim.state.intimacy.active
	sim.command("intimacy","interrupt",{"session":a.id,"revision":a.revision})
	sim.command("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true,"cycle_offset":13}})
	shell.open_panel("health")
	await _capture("health")
	sim.state.healthcare.family.append({"parent":"asuka","partner":"player","minute":sim.state.clock.total_minutes,"care":0,"status":"dependent"})
	sim.services.family.initialize()
	sim.state.family.members.family_1.name="Мира"
	sim.command("reproduction","parenthood",{"member":"family_1","decision":"relinquish","confirm":true})
	var o:Dictionary=sim.state.child_support.obligations.values()[0]
	o.arrears=120
	o.billed=120
	shell.open_panel("family")
	await _capture("support")
	print("REPRODUCTION_CAPTURE_RESULT ",JSON.stringify({"directory":directory,"audio":AudioServer.get_driver_name(),"size":[1366,768]}))
	quit(0)
