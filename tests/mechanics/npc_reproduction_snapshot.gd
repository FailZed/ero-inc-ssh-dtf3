extends SceneTree
const Suite = preload("res://tests/mechanics/npc_reproduction.gd")
const Sim = preload("res://scripts/mechanics/autonomous_reproductive_simulation.gd")
var checks:=0
var failures:Array[String]=[]

func _check(value: bool, description: String) -> void:
	checks+=1
	if not value: failures.append(description); printerr("FAIL: ",description)

func _initialize() -> void:
	var mode:=""
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--file="): path=arg.trim_prefix("--file=")
	var suite:=Suite.new(self)
	if mode=="write":
		var cases:Array=[]
		for kind in ["encounter","clinic","support","routine"]:
			var sim=suite.debt_fixture() if kind=="support" else suite.fresh()
			var config:Dictionary=suite.config()
			var future:=150
			match kind:
				"encounter": suite.advance(sim,2)
				"clinic":
					sim.services.reproduction.record("a").desire="avoid"
					sim.command("npc_reproduction","configure",{"id":"a","values":{"pregnancy_decision":"auto"}})
					suite.advance(sim,60)
				"support":
					config.child_support_rules={"simulation":sim.catalog.child_support_rules.simulation.duplicate(true)}
					future=90
				"routine":
					sim.command("preferences","content_tag",{"id":"romance","enabled":false})
					sim.services.reproduction.record("a").desire="avoid"
					sim.state.social.npcs.a.inventory.contraceptive_pill=4
					sim.command("npc_reproduction","configure",{"id":"a","values":{"preferred_method":"pill"}})
					suite.advance(sim,1440)
					future=60
			var snapshot:Dictionary=sim.export_snapshot()
			suite.advance(sim,future)
			cases.append({"kind":kind,"config":config,"snapshot":snapshot,"future":future,"expected":sim.export_snapshot()})
		var file:=FileAccess.open(path,FileAccess.WRITE)
		_check(file!=null,"write independent NPC fixtures")
		if file!=null: file.store_string(JSON.stringify(cases)); file.close()
	elif mode=="read":
		var cases:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(cases is Array,"read fixtures in fresh process")
		if cases is Array:
			for item in cases:
				var sim=Sim.new(77,item.config)
				var result:Dictionary=sim.restore_snapshot(item.snapshot)
				_check(result.ok,"restore independent NPC "+str(item.kind)+": "+str(result.get("error","")))
				if not result.ok: continue
				suite.advance(sim,int(item.future))
				_check(suite.same(sim.export_snapshot(),item.expected),"exact continuation of independent NPC "+str(item.kind)+", money, items and RNG")
	else: _check(false,"choose independent NPC snapshot mode")
	print("NPC_REPRODUCTION_SNAPSHOT_RESULT ",JSON.stringify({"mode":mode,"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
