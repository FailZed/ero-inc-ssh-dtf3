extends RefCounted
## Single main-city data source and semantic queries. The mechanics laboratory has its own catalog.
const Graph = preload("res://scripts/gameplay/city_graph.gd")
const Rules = preload("res://scripts/mechanics/core/rules.gd")
static var _source: Dictionary = {}

static func source() -> Dictionary:
	if _source.is_empty():
		var loaded := Graph.load_graph()
		if not loaded.ok:
			push_error("City graph: " + str(loaded))
			return {}
		_source = loaded.data
	return _source

static func data(catalog: Dictionary) -> Dictionary:
	return catalog.city_graph

static func point(catalog: Dictionary, id: String) -> Dictionary:
	return Graph.location(data(catalog), id)

static func points(catalog: Dictionary) -> Array:
	var result: Array = []
	var ids: Array = data(catalog).locations.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = data(catalog).locations[id]
		if entry.map.marker: result.append(entry)
	return result

static func active_property(state: Dictionary) -> String:
	var property_id := str(state.housing.residence)
	if property_id.is_empty() and state.world.flags.get("city_story_home", false): return "apartment"
	return property_id

static func home(catalog: Dictionary, state: Dictionary) -> String:
	return Graph.home_frontage(data(catalog), active_property(state))

static func home_room(catalog: Dictionary, state: Dictionary, kind: String) -> String:
	return Graph.home_room(data(catalog), active_property(state), kind)

static func room_kind(catalog: Dictionary, id: String) -> String:
	return str(catalog.locations.get(id, {}).get("room_kind", ""))

static func is_home_room(catalog: Dictionary, state: Dictionary, id: String) -> bool:
	var entry: Dictionary = catalog.locations.get(id, {})
	return entry.get("kind") == "private_room" and entry.get("residence_property_id") == active_property(state)

static func map_location(catalog: Dictionary, state: Dictionary) -> String:
	var id := str(state.world.location)
	var entry := point(catalog, id)
	if entry.is_empty(): return ""
	if entry.kind == "private_room":
		return Graph.home_frontage(data(catalog), str(entry.residence_property_id))
	if entry.kind == "service_interior":
		var policy: Dictionary = data(catalog).access_policies[entry.access_policy_id]
		return str(data(catalog).services[policy.service_id].public_frontage_location_id)
	if entry.kind == "private_residence": return str(entry.get("public_frontage_location_id", ""))
	if not entry.map.marker and not str(entry.building_id).is_empty():
		return str(data(catalog).buildings[entry.building_id].entry_location_id)
	return id

static func install_home(catalog: Dictionary, actor_id: String) -> Dictionary:
	var existing := Graph.private_home_for_actor(data(catalog), actor_id)
	if not existing.is_empty(): return Rules.ok({"id":existing})
	var made := Graph.resident_home_records(data(catalog), actor_id)
	if not made.ok: return made
	var records: Dictionary = made.data
	records.location.generated_home = true
	records.location.private = true
	records.location.public = false
	records.location.facilities = ["private_home","sanitary_private","toilet"]
	records.location.toilet = true
	records.location.public_frontage_location_id = str(records.route.from_id)
	var graph := data(catalog)
	graph.locations[records.location.id] = records.location
	graph.buildings[records.building.id] = records.building
	graph.access_policies[records.policy_id] = records.access_policy
	graph.routes.append(records.route)
	catalog.locations[records.location.id] = records.location.duplicate(true)
	catalog.locations[records.location.id].routes = {records.route.from_id:{"minutes":records.route.minutes,"cost":records.route.cost}}
	catalog.locations[records.route.from_id].routes[records.location.id] = {"minutes":records.route.minutes,"cost":records.route.cost}
	return Rules.ok({"id":str(records.location.id)})

static func dynamic_home_owners(catalog: Dictionary) -> Array:
	var result: Array = []
	for entry in data(catalog).locations.values():
		if entry.get("generated_home",false): result.append(str(entry.owner_actor_id))
	return result

static func apply_catalog(catalog: Dictionary) -> Dictionary:
	var graph := source().duplicate(true)
	if graph.is_empty(): return Rules.fail("city_graph_unavailable")
	var errors := Graph.activation_errors(graph)
	if not errors.is_empty(): return {"ok":false,"error":"city_graph_not_ready","details":errors}
	catalog.city_graph = graph
	catalog.locations = Graph.catalog_locations(graph)
	catalog.location_roles = {"trade":"south_trade_street","study":"campus_study_room","supply_shop":"south_market","clinic":"clinic"}
	catalog.settings.weather_types = ["clear","cloudy","rain","snow"]
	for id in catalog.locations:
		var entry: Dictionary = catalog.locations[id]
		entry["public"] = entry.kind == "public_exterior" or entry.kind == "service_interior"
		entry["facilities"] = []
		if entry.kind == "private_residence": entry.private = true; entry.facilities = ["private_home","sanitary_private","toilet"]
		if entry.get("room_kind","") == "bathroom" or id in ["clinic","campus_mens_washroom"]: entry.facilities = ["toilet","sink","sanitary_private"]
		if entry.get("room_kind","") == "kitchen": entry.facilities = ["sink"]
		if id in ["south_market","north_market","clinic"]: entry.facilities.append("supplies")
		if "toilet" in entry.facilities: entry.toilet = true
	for property_id in graph.home_units:
		var unit: Dictionary = graph.home_units[property_id]
		for kind in unit.room_ids:
			catalog.locations[unit.room_ids[kind]].private = true
	for property_id in ["detached_house","penthouse","social_housing"]:
		var prices: Dictionary = {"detached_house":[8000,600,3,14],"penthouse":[18000,1400,2,14],"social_housing":[0,0,0,4]}
		var spec: Array = prices[property_id]
		catalog.properties[property_id] = {"location":Graph.home_room(graph,property_id,"hall"),"price":spec[0],"monthly_rent":spec[1],"tenant_rent":100,"tenant_capacity":spec[2],"furniture_slots":spec[3],"sell_ratio":0.7,"room_size":[10,8]}
	catalog.properties.apartment.location = "apartment_hall"
	var binding: Dictionary = graph.capability_bindings
	for id in binding.jobs:
		var entry: Dictionary = binding.jobs[id]
		if entry.scope == "actor_home":
			catalog.livelihood_rules.jobs[id].home_room_kind = entry.player_room_kind
			catalog.livelihood_rules.jobs[id].location = Graph.home_room(graph,"apartment",entry.player_room_kind)
		else: catalog.livelihood_rules.jobs[id].location = entry.target_location_id
	for id in binding.skill_practice:
		var entry: Dictionary = binding.skill_practice[id]
		catalog.skills[id].locations = entry.fixed_location_ids.duplicate()
		catalog.skills[id].home_room_kinds = entry.actor_home_room_kinds.duplicate()
	catalog.lessons = preload("res://scripts/mechanics/education_schedule.gd").lessons(binding.lessons)
	for id in catalog.training_programs:
		if id in binding.sports: catalog.training_programs[id].location = binding.sports[id]
		elif id == "cinema": catalog.training_programs[id].location = "campus_auditorium"
		elif id == "speech": catalog.training_programs[id].location = "campus_training_hall"
		elif id == "reading": catalog.training_programs[id].home_room_kind = "bedroom"; catalog.training_programs[id].erase("location")
	for id in catalog.jobs:
		catalog.jobs[id].home_room_kind = "bedroom"
		catalog.jobs[id].erase("location")
	for id in catalog.professions:
		if catalog.locations.get(str(catalog.professions[id].get("location","")),{}).get("kind") == "private_room":
			catalog.professions[id].home_room_kind = str(catalog.locations[catalog.professions[id].location].room_kind)
	if catalog.professions.has("retail"): catalog.professions.retail.location = "south_market"
	for id in binding.shops:
		if catalog.shops.has(id): catalog.shops[id].location = binding.shops[id].target_location_id
	if not catalog.shops.has("north_market"):
		catalog.shops.north_market = catalog.shops.market.duplicate(true)
		catalog.shops.north_market.location = "north_market"
		catalog.shops.north_market.price_multiplier = 0.9
	for id in catalog.shops:
		var service_id := str(catalog.shops[id].location) + "_service"
		if graph.services.has(service_id):
			catalog.shops[id].hours = graph.services[service_id].hours.duplicate()
			catalog.shops[id].weekdays = graph.services[service_id].weekdays.duplicate()
	for id in catalog.agency_actions:
		var action: Dictionary = catalog.agency_actions[id]
		if str(action.get("destination","")) == "home": continue
		action.destination = "campus_study_room" if id == "study" else "south_trade_street"
	for id in catalog.npc_templates:
		var template: Dictionary = catalog.npc_templates[id]
		for block in template.get("schedule",[]):
			block.location = "campus_study_room" if block.get("activity") == "study" else "south_trade_street"
	for id in catalog.npc_activities:
		if id in ["walk","socialize"]: catalog.npc_activities[id].locations = ["south_trade_street","city_park","riverside_cafe_front","north_shops"]
		elif id == "paid_work": catalog.npc_activities[id].locations = ["south_market","north_market","riverside_cafe"]
		elif id == "train": catalog.npc_activities[id].locations = ["campus_gym","city_park"]
		elif id == "read": catalog.npc_activities[id].home_activity = true
	if catalog.has("date_activities"):
		catalog.date_activities.walk.locations = ["south_promenade","city_park","north_beach"]
		catalog.date_activities.cinema.locations = ["campus_auditorium"]
	if catalog.has("dialogue_biography"):
		catalog.dialogue_biography.homes = {"residential_district":"в жилых дворах","pharmacy_house":"рядом с аптекой"}
	for entry in graph.locations.values():
		if entry.kind == "private_residence" and not entry.has("public_frontage_location_id"):
			var front := "residential_district"
			if entry.owner_actor_id == "asuka": front = "asuka_home_door"
			elif entry.owner_actor_id == "oliver": front = "oliver_home_entry"
			entry.public_frontage_location_id = front
			catalog.locations[entry.id].public_frontage_location_id = front
	return Rules.ok()
