extends "res://scripts/mechanics/housing.gd"
const City = preload("res://scripts/gameplay/city_layout.gd")
const Graph = preload("res://scripts/gameplay/city_graph.gd")
const CITY_PROPERTIES := ["detached_house","penthouse","social_housing"]

func emergency_available() -> bool:
	var housing: Dictionary = sim.state.housing
	return housing.residence.is_empty() and (housing.properties.get("apartment",{}).get("evicted",false) or sim.state.world.flags.get("student_home_lost",false)) and int(sim.state.economy.cash) < 600 and not housing.properties.has("social_housing") and not sim.state.world.flags.get("social_housing_granted",false)

func execute(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id",""))
	if id in CITY_PROPERTIES and operation in ["rent","buy","emergency"]:
		if sim.state.world.location != "real_estate_agency": return Rules.fail("agency_required")
		if not sim.services.world.is_open({"hours":[540,1080]}): return Rules.fail("agency_closed")
		if id == "social_housing":
			if operation != "emergency" or not emergency_available(): return Rules.fail("social_housing_ineligible")
			var granted := super.execute("rent",args)
			if granted.ok:
				sim.state.housing.properties.social_housing.equipment.stove = 1
				sim.state.world.flags.social_housing_granted = true
				emit_event("social_housing_granted",{})
			return granted
	if City.data(sim.catalog).home_units.has(id) and operation == "move_in":
		var property: Dictionary = sim.state.housing.properties.get(id,{})
		if property.is_empty() or property.get("evicted",false): return Rules.fail("property_not_acquired")
		var frontage := Graph.home_frontage(City.data(sim.catalog),id)
		if frontage.is_empty(): return Rules.fail("unknown_property")
		var travel: Dictionary = sim.services.world.execute("journey",{"id":frontage})
		if not travel.ok: return travel
		var entered: Dictionary = sim.advance(1)
		if not entered.ok: return entered
	var previous_home := City.home(sim.catalog,sim.state)
	var had_home: bool = not sim.state.housing.residence.is_empty()
	var was_inside: bool = sim.is_player_home_location(str(sim.state.world.location))
	var result := super.execute(operation,args)
	if result.ok and id == "social_housing" and operation == "end_lease": sim.state.world.flags.social_housing_granted = true
	if result.ok and operation == "move_in": sim.state.world.flags.city_story_home = false
	if result.ok and had_home and sim.state.housing.residence.is_empty():
		sim.state.world.flags.city_story_home = false
		if was_inside:
			sim.state.world.previous_location = sim.state.world.location
			sim.state.world.location = previous_home
	return result

func tick(minute: int) -> void:
	var previous_home := City.home(sim.catalog,sim.state)
	var had_home: bool = not sim.state.housing.residence.is_empty()
	var previous_location := str(sim.state.world.location)
	var was_inside: bool = sim.is_player_home_location(previous_location)
	super.tick(minute)
	if had_home and sim.state.housing.residence.is_empty():
		sim.state.world.flags.student_home_lost = true
		sim.state.world.flags.city_story_home = false
		sim.state.world.location = previous_home if was_inside else previous_location
		sim.state.world.previous_location = previous_location
