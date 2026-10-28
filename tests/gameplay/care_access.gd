extends RefCounted
var t

func _init(runner) -> void: t = runner

func button(shell, module: String, operation: String) -> Button:
	for item in shell._body.find_children("*","Button",true,false):
		var action: Dictionary = item.get_meta("gameplay_action",{})
		if action.get("module","")==module and action.get("operation","")==operation: return item
	return null

func run() -> void:
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	t.session.pause_autosave_runtime()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	var sim = t.gameplay.simulation
	for id in sim.state.social.npcs:
		sim.services.npc_planner.interrupt(str(id),"clinic_ui_fixture")
		sim.state.social.npcs[id].pinned_until = 1000000
	sim.state.npc_reproduction.enabled = false
	sim.state.world.location = "clinic"
	sim.state.economy.cash = 1000
	var late := int(sim.state.clock.day_index)*1440+1195
	if late<int(sim.state.clock.total_minutes): late += 1440
	preload("res://tests/gameplay/health_care_plans.gd").new(t).set_time(sim,late)
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	t.root.add_child(shell)
	shell._screen_state.health_tab = "adult_health"
	shell.open_panel("health")
	var before: Dictionary = sim.export_snapshot()
	shell._refresh()
	t.check(before==sim.export_snapshot(),"clinical interval probes preserve live state and RNG")
	var consult := button(shell,"adult_health","consult")
	t.check(consult!=null and consult.disabled and consult.tooltip_text.contains("до закрытия"),"actual consultation button explains insufficient service time")
	var denied: Dictionary = t.gameplay.execute("adult_health","consult")
	t.check(not denied.ok and denied.error=="clinic_visit_window" and before==sim.export_snapshot(),"main command rejects a late visit without time or funds")
	var configured: Dictionary = t.gameplay.execute("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true}})
	t.check(configured.ok,"main fixture supports prenatal care")
	t.check(t.gameplay.execute("lifecycle","start",{"id":"pregnancy","target":"player"}).ok,"main fixture creates actual pregnancy state")
	shell._screen_state.health_tab = "treatment"
	shell._refresh()
	var prenatal := button(shell,"health","prenatal_care")
	t.check(prenatal!=null and prenatal.disabled,"actual prenatal examination button shares the late-visit restriction")
	preload("res://tests/gameplay/health_care_plans.gd").new(t).set_time(sim,late+1440-25)
	shell._refresh()
	prenatal = button(shell,"health","prenatal_care")
	t.check(prenatal!=null and not prenatal.disabled,"prenatal visit fitting exactly before closing is available")
	var minute := int(sim.state.clock.total_minutes)
	var cash := int(sim.state.economy.cash)
	if prenatal!=null and not prenatal.disabled: prenatal.pressed.emit()
	t.check(sim.state.clock.total_minutes==minute+30 and sim.state.economy.cash==cash-30,"real prenatal button spends thirty minutes and one fee")
	t.check(sim.state.conditions["player:pregnancy"].care==10 and sim.state.conditions["player:pregnancy"].next_care==minute+30+1440,"main examination grants completed care and its actual cooldown")
	t.check(t.session.get_game_time_snapshot().total_minutes==sim.state.clock.total_minutes,"medical completion and session clocks stay synchronized")
	t.check(sim.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok,"current world restores the completed clinical visit")
	shell.free()
	t.dialogic.VAR.var_storage.World = original
	t.fresh_world()
