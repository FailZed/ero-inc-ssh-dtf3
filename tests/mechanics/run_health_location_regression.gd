extends SceneTree
const Main = preload("res://scripts/gameplay/main_simulation.gd")
const Access = preload("res://scripts/mechanics/care_access.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ",description)

func command(sim, module_id: String, operation: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim.command(module_id,operation,args)
	_check(result.ok,"%s.%s succeeds: %s" % [module_id,operation,str(result.get("error",""))])
	return result

func _run() -> void:
	var city = Main.new(42)
	_check(city.configuration_error.is_empty(),"city catalog validates")
	_check(str(city.catalog.location_roles.supply_shop)=="south_market" and str(city.catalog.location_roles.clinic)=="clinic","city care location roles are bound")
	city.state.world.location = "south_market"
	_check(Access.supplies_available(city,"player") and not Access.sanitary(city,"player"),"public city market sells supplies without private care")
	city.state.world.location = "campus_mens_washroom"
	_check(Access.sanitary(city,"player"),"public city washroom supports sanitary care")
	city.state.world.location = "clinic"
	_check(Access.sanitary(city,"player") and Access.supplies_available(city,"player"),"city clinic supports both care and supplies")
	preload("res://tests/mechanics/pregnancy_wellbeing.gd").new(self)._symptoms_and_care()
	preload("res://tests/mechanics/adult_health.gd").new(self)._cycle()
	var plans = preload("res://tests/mechanics/health_care_plans.gd").new(self)
	plans._completed_care()
	plans._missed_care()
	plans._window_edges()
	print("HEALTH_LOCATION_REGRESSION ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
