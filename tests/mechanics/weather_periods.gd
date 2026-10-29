extends SceneTree

const Simulation = preload("res://scripts/mechanics/simulation.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL: ", description)

func _run() -> void:
	var sim = Simulation.new(42, {"settings": {"start_minutes": 720}})
	_check(sim.configuration_error.is_empty(), "weather fixture is valid")
	var initial_weather := str(sim.state.world.weather)
	var initial_temperature := int(sim.state.world.temperature)
	sim.state.world.heat = 10.0
	_check(sim.command("clock", "advance", {"minutes": 60}).ok, "first hour advances")
	_check(str(sim.state.world.weather) == initial_weather and int(sim.state.world.temperature) == initial_temperature, "weather and temperature persist for the first hour")
	_check(is_equal_approx(float(sim.state.world.heat), 9.0), "heat still decays hourly")
	_check(sim.command("clock", "advance", {"minutes": 300}).ok, "weather period reaches its boundary")
	_check(str(sim.state.world.weather) in sim.catalog.settings.weather_types, "boundary weather remains configured")
	var period_weather := str(sim.state.world.weather)
	var period_temperature := int(sim.state.world.temperature)
	var snapshot := sim.export_snapshot()
	_check(sim.command("clock", "advance", {"minutes": 60}).ok, "next hour advances")
	_check(str(sim.state.world.weather) == period_weather and int(sim.state.world.temperature) == period_temperature, "boundary weather persists for the next hour")
	var restored = Simulation.new(42, {"settings": {"start_minutes": 720}})
	_check(restored.restore_snapshot(snapshot).ok, "weather period restores from snapshot")
	_check(str(restored.state.world.weather) == period_weather and int(restored.state.world.temperature) == period_temperature, "snapshot retains weather and temperature")
	print("WEATHER_PERIODS_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
