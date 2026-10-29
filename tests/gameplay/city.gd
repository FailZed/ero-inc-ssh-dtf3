extends RefCounted
const City = preload("res://scripts/gameplay/city_layout.gd")
const Atmosphere = preload("res://scripts/gameplay/atmosphere.gd")
var t
func _init(runner) -> void: t = runner

func run() -> void:
	var initial_checks := int(t.checks)
	var initial_failures := int(t.failures.size())
	var original: Dictionary = t.dialogic.VAR.var_storage.World.duplicate(true)
	var sim = t.gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(1440+12*60)
	sim.state.world.location = "student_home"
	var before: Dictionary = sim.export_snapshot()
	var actor := {"id":"city_fixture","location":"riverside_cafe"}
	sim.state.world.location = "riverside_cafe"
	t.check(sim.services.npc_dialogue.local_initiative(actor),"NPC can initiate a face-to-face dialogue at the new cafe")
	sim.state.world.weather = "rain"
	actor.location = "residential_district"
	t.check(sim.services.npc_agency._destination(actor,sim.catalog.agency_actions.visit) == "riverside_cafe","NPC social outings choose shelter during rain")
	sim.restore_snapshot(before)
	for point in City.points(sim.catalog):
		var route: Dictionary = sim.services.world.route(str(point.id))
		t.check(route.ok,"city marker has an actual walkable route: " + str(point.id))
		t.check(before == sim.export_snapshot(),"route preview is pure: " + str(point.id))
		var walk: Dictionary = sim.command("world","journey",{"id":point.id})
		t.check(walk.ok and sim.state.world.location == point.id and int(sim.state.clock.total_minutes) == 2160+int(route.get("data",{}).get("minutes",0)),"journey reaches its marker and advances exactly its route time: " + str(point.id))
		sim.restore_snapshot(before)
	var crossing: Dictionary = sim.services.world.route("north_beach")
	t.check("pedestrian_bridge_north" in crossing.data.path and "pedestrian_bridge_south" in crossing.data.path,"north-bank journey crosses both ends of a bridge")
	sim.state.player.needs.energy = 0.0
	var exhausted: Dictionary = sim.export_snapshot()
	t.check(not sim.command("world","journey",{"id":"north_beach"}).ok and exhausted == sim.export_snapshot(),"exhausted travel rejects atomically")
	sim.restore_snapshot(before)
	t.check(not sim.command("world","journey",{"id":"missing_city"}).ok and before == sim.export_snapshot(),"unknown destination consumes nothing")
	sim.state.clock = sim.calendar.snapshot(1440+20*60-5)
	var closing: Dictionary = sim.export_snapshot()
	t.check(not sim.command("world","journey",{"id":"training_center"}).ok and closing == sim.export_snapshot(),"a university trip arriving after closing rejects before travel")
	sim.restore_snapshot(before)
	for pair in [[300,"morning"],[480,"day"],[1080,"sunset"],[1320,"night"],[0,"night"]]:
		for weather in ["clear","cloudy","rain","snow"]:
			var profile := Atmosphere.profile({"minute_of_day":pair[0]},weather)
			t.check(profile.period == pair[1] and profile.weather == weather and Atmosphere.profile({"minute_of_day":pair[0]},weather,true).precipitation == 0,"time/weather combinations have a profile, with no indoor precipitation: %s %s" % [pair[1],weather])
	var climates := {}
	for i in range(80):
		sim.state.clock = sim.calendar.snapshot((i+1)*60)
		sim.services.world.tick((i+1)*60)
		climates[str(sim.state.world.weather)] = true
		if sim.state.world.weather == "snow": t.check(float(sim.state.world.temperature) < 0,"snow has a subzero outdoor temperature")
	t.check(climates.size() == 4,"all four weather states occur through the actual world weather roll")
	sim.restore_snapshot(before)
	var legacy: Dictionary = before.duplicate(true)
	legacy.main_schema = 2
	legacy.catalog_hash = "unsupported-catalog"
	t.check(not sim.restore_snapshot(legacy).ok and before == sim.export_snapshot(),"outdated city snapshots are rejected")
	legacy.catalog_hash = "unknown-catalog"
	t.check(not sim.restore_snapshot(legacy).ok and before == sim.export_snapshot(),"unknown legacy catalogs are rejected without replacing the world")
	_housing()
	t.fresh_world()
	t.gameplay.complete_chapter_one()
	sim = t.gameplay.simulation
	var shell = load("res://scripts/ui/gameplay/gameplay_shell.gd").new()
	t.root.add_child(shell)
	before = sim.export_snapshot()
	shell.open_panel("map")
	await t.process_frame
	t.check(shell._city.markers.size() == 15 and not shell._main_panel.visible,"main map displays all 15 spatial markers instead of a technical destination list")
	shell._city.markers.north_beach.pressed.emit()
	t.check(before == sim.export_snapshot(),"opening the map and selecting a marker do not alter the world")
	var minutes := int(sim.services.world.route("north_beach").data.minutes)
	var session_minute := int(t.session.get_game_time_snapshot().total_minutes)
	var confirm: Button
	for button in shell._city._card.find_children("*","Button",true,false):
		if button.has_meta("city_confirm"): confirm = button
	t.check(confirm != null and not confirm.disabled,"selected map marker exposes a usable travel confirmation")
	if confirm != null: confirm.pressed.emit()
	t.check(shell.current_panel == "place" and sim.state.world.location == "north_beach" and int(t.session.get_game_time_snapshot().total_minutes) == session_minute+minutes,"actual map confirmation enters the location and advances the main clock once")
	t.check(t.dialogic.VAR.var_storage.World.gameplay.state.world.location == "north_beach","the main checkpoint retains the new map location")
	before = sim.export_snapshot()
	shell.open_panel("map")
	shell.open_panel("place")
	t.check(before == sim.export_snapshot(),"returning between a location view and map consumes no extra time")
	t.check(t.gameplay.execute("world","journey",{"id":"bedroom"}).ok,"the city route also returns through the home entrance to its rooms")
	shell.queue_free()
	await t.process_frame
	t.dialogic.VAR.var_storage.World = original
	t.session._sync_game_time_from_dialogic()
	print("CITY_RESULT ",JSON.stringify({"checks":int(t.checks)-initial_checks,"failed":int(t.failures.size())-initial_failures,"markers":15,"periods":4,"weather":4}))

func _housing() -> void:
	var sim = t.gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(1440+12*60)
	sim.state.economy.cash = 20000
	var before: Dictionary = sim.export_snapshot()
	t.check(not sim.command("housing","buy",{"id":"detached_house"}).ok and before == sim.export_snapshot(),"city property purchase requires the actual agency")
	sim.state.world.location = "real_estate_agency"
	t.check(sim.command("housing","buy",{"id":"detached_house"}).ok,"agency sells the two-storey house through the main housing service")
	var minute := int(sim.state.clock.total_minutes)
	var route: Dictionary = sim.services.world.route("detached_house")
	t.check(sim.command("housing","move_in",{"id":"detached_house"}).ok and sim.state.world.location == "apartment_hall" and int(sim.state.clock.total_minutes) == minute+int(route.data.minutes)+1,"moving home walks to its frontage before entering")
	t.check(sim.command("world","travel",{"id":"detached_house"}).ok,"the new home's exit returns to the right map marker")
	t.check(not sim.services.world.routes_for("student_home").has("apartment_hall"),"old home cannot enter the new home's shared interior")
	t.check(sim.command("world","travel",{"id":"apartment_hall"}).ok,"acquired home can be entered again")
	t.check(sim.command("housing","sell",{"id":"detached_house"}).ok and sim.state.world.location == "detached_house","selling the occupied home leaves the hero outside")
	sim.state.world.location = "real_estate_agency"
	sim.state.economy.cash = 0
	before = sim.export_snapshot()
	t.check(not sim.command("housing","rent",{"id":"social_housing"}).ok and before == sim.export_snapshot(),"social housing cannot be obtained by bypassing eligibility with a free rent command")
	sim.state.world.flags.student_home_lost = true
	t.check(sim.command("housing","emergency",{"id":"social_housing"}).ok,"homeless penniless hero can receive social housing at the agency")
	t.check(sim.command("housing","move_in",{"id":"social_housing"}).ok and "stove" in sim.state.world.equipment,"emergency home has a usable kitchen and a real entrance")
	sim.state.world.location = "real_estate_agency"
	sim.state.clock = sim.calendar.snapshot(23*60)
	before = sim.export_snapshot()
	t.check(not sim.command("housing","rent",{"id":"penthouse"}).ok and before == sim.export_snapshot(),"the agency closes at night without charging a failed lease")
	# Exercise the real rent tick rather than manufacturing an eviction flag.
	sim = t.gameplay.make_simulation()
	sim.state.clock = sim.calendar.snapshot(1440+720)
	sim.state.economy.cash = 20000
	sim.command("housing","rent",{"id":"apartment"})
	sim.command("housing","move_in",{"id":"apartment"})
	sim.state.world.location = "bedroom"
	sim.state.economy.cash = 0
	sim.command("preferences","customize",{"values":{"eviction_enabled":true,"rent_enabled":true}})
	var home: Dictionary = sim.state.housing.properties.apartment
	home.arrears = int(sim.catalog.properties.apartment.monthly_rent)*10
	home.next_bill = int(sim.state.clock.total_minutes)+1
	t.check(sim.command("clock","advance",{"minutes":1}).ok and sim.state.housing.residence.is_empty() and sim.state.world.location == "student_home","actual eviction places the hero outside the old home")
	t.check(not sim.services.world.route("bedroom").ok,"evicted hero cannot walk back into the old interior")
	t.check(sim.command("world","journey",{"id":"real_estate_agency"}).ok and sim.command("housing","emergency",{"id":"social_housing"}).ok,"an actual eviction leads to the playable emergency housing route")
