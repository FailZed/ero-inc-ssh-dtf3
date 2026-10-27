extends RefCounted
## One spatial source for catalog routes, map markers, camera focus and home exits.
const PATH := "res://data/world/city-river-v2.json"
const ROOMS := ["bedroom", "apartment_hall", "bathroom", "kitchen"]
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func points() -> Array:
	return data().locations

static func point(id: String) -> Dictionary:
	for entry in points():
		if id in [entry.id, entry.runtime_id]: return entry
	return {}

static func home(state: Dictionary) -> String:
	return {"apartment":"student_home", "detached_house":"detached_house", "penthouse":"penthouse", "social_housing":"social_housing"}.get(str(state.housing.residence), "student_home")

static func map_location(state: Dictionary) -> String:
	return home(state) if str(state.world.location) in ROOMS else str(state.world.location)

static func apply_catalog(catalog: Dictionary) -> void:
	for entry in points():
		var id := str(entry.runtime_id)
		if not catalog.locations.has(id): catalog.locations[id] = {"routes":{}}
	for link in data().route_links:
		for id in [str(link.a), str(link.b)]:
			if not catalog.locations.has(id): catalog.locations[id] = {"routes":{}}
		catalog.locations[link.a].routes[link.b] = {"minutes":int(link.minutes)}
		catalog.locations[link.b].routes[link.a] = {"minutes":int(link.minutes)}
	# Preserve the established direct routes while adding the actual home frontage.
	catalog.locations.apartment_hall.routes.student_home = {"minutes":1}
	catalog.locations.student_home.routes.apartment_hall = {"minutes":1}
	if not catalog.locations.has("residential_district"): catalog.locations.residential_district = {"routes":{}}
	catalog.locations.residential_district.routes.global_map = {"minutes":10}
	catalog.settings.weather_types = ["clear", "cloudy", "rain", "snow"]
	var north: Dictionary = catalog.shops.market.duplicate(true) if catalog.shops.has("market") else {}
	if not north.is_empty():
		north.location = "north_shops"
		north.price_multiplier = 0.9
		catalog.shops.north_market = north
	for entry in [["detached_house",8000,600,3,14], ["penthouse",18000,1400,2,14], ["social_housing",0,0,0,4]]:
		catalog.properties[entry[0]] = {"location":entry[0], "price":entry[1], "monthly_rent":entry[2], "tenant_rent":100, "tenant_capacity":entry[3], "furniture_slots":entry[4], "sell_ratio":0.7, "room_size":[10,8]}
