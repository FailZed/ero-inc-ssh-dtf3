extends SceneTree
const Suite = preload("res://tests/mechanics/reproduction.gd")
const Sim = preload("res://scripts/mechanics/reproductive_simulation.gd")
var checks := 0
var failures: Array[String] = []

func _check(value: bool, description: String) -> void:
	checks+=1
	if not value: failures.append(description); printerr("FAIL: ",description)

func _continue(sim, suite) -> void:
	suite.choose(sim,"finish")
	suite.choose(sim,"close")
	_check(sim.command("clock","advance",{"minutes":130}).ok,"future time commits in independent process")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	var mode:=""
	var path:=""
	for arg in args:
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
		if arg.begins_with("--file="): path=arg.trim_prefix("--file=")
	var suite:=Suite.new(self)
	if mode=="write":
		var sim=suite.fresh()
		sim.state.healthcare.family.append({"parent":"adult","partner":"player","minute":sim.state.clock.total_minutes,"care":0,"status":"dependent"})
		sim.services.family.initialize()
		sim.command("reproduction","parenthood",{"member":"family_1","decision":"relinquish","confirm":true})
		var o:Dictionary=sim.state.child_support.obligations.values()[0]
		o.arrears=120
		o.billed=120
		_check(sim.command("child_support","file_enforcement",{"id":o.id,"actor":"adult"}).ok,"fixture keeps an unfinished support collection")
		suite.ready(sim)
		suite.choose(sim,"start")
		var snapshot:Dictionary=sim.export_snapshot()
		_continue(sim,suite)
		var file:=FileAccess.open(path,FileAccess.WRITE)
		_check(file!=null,"write isolated reproduction fixture")
		if file!=null: file.store_string(JSON.stringify({"snapshot":snapshot,"expected":sim.export_snapshot()})); file.close()
	elif mode=="read":
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(data is Dictionary,"read fixture in new process")
		if data is Dictionary:
			var sim=Sim.new(987,suite.config())
			var restored:Dictionary=sim.restore_snapshot(data.snapshot)
			_check(restored.ok,"restore unfinished encounter and support in new process: "+str(restored.get("error","")))
			if restored.ok:
				_continue(sim,suite)
				_check(JSON.parse_string(JSON.stringify(sim.export_snapshot()))==data.expected,"fresh process reproduces scene, conception, birth, support, future events and RNG")
	else: _check(false,"choose write or read mode")
	print("REPRODUCTION_SNAPSHOT_RESULT ",JSON.stringify({"mode":mode,"checks":checks,"failed":failures.size()}))
	quit(0 if failures.is_empty() else 1)
