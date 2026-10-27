extends RefCounted
var t

func _init(runner) -> void:
	t = runner

func button(shell, operation: String) -> Button:
	for item in shell._body.find_children("*","Button",true,false):
		var action: Dictionary = item.get_meta("gameplay_action",{})
		if action.get("module","")=="adult_health" and action.get("operation","")==operation: return item
	return null

func run() -> void:
	var initial := int(t.checks)
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	sim.state.world.location = "bathroom"
	sim.state.economy.cash = 2000
	sim.state.player.age = 32
	t.check(t.gameplay.execute("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true,"cycle_offset":0}}).ok,"main adult-health profile initializes")
	var health = sim.services.adult_health
	health.record("player").soiled = true
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	t.root.add_child(shell)
	shell._screen_state.health_tab = "adult_health"
	shell.open_panel("health")
	var before: Dictionary = sim.export_snapshot()
	shell._refresh()
	t.check(before==sim.export_snapshot(),"health panel probes preserve actual mood, libido and pathogen state")
	for operation in ["rest","cleanup","change_product","buy_products","consult","screen","vaccinate","treat_lesions"]:
		t.check(button(shell,operation)!=null,"main health UI exposes "+operation)
	var cleanup := button(shell,"cleanup")
	t.check(cleanup!=null and not cleanup.disabled,"main cleanup button is usable")
	if cleanup!=null and not cleanup.disabled: cleanup.pressed.emit()
	t.check(not health.view().soiled,"main cleanup button updates real adult-health state")
	for frame in range(2): await t.process_frame
	var preference: OptionButton
	for item in shell._body.find_children("*","OptionButton",true,false):
		if item.item_count==3 and item.get_item_metadata(2)=="not_now": preference = item; break
	t.check(preference!=null,"main UI offers an explicit intimacy intention")
	var mood := float(sim.state.player.needs.mood)
	if preference!=null:
		preference.select(2)
		preference.item_selected.emit(2)
	t.check(health.view().desire.intent=="not_now" and sim.state.player.needs.mood==mood,"declaring no desire does not cause a failure mood penalty")
	for frame in range(3): await t.process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var path := "res://docs/mechanics/verification/adult-health-2026-10-27"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
		t.root.get_texture().get_image().save_png(path+"/health-panel.png")
	shell.free()
	t.dialogic.VAR.var_storage.World = original
	t.fresh_world()
	print("ADULT_HEALTH_MAIN_UI_RESULT ",JSON.stringify({"checks":int(t.checks)-initial,"main_ui":true}))
