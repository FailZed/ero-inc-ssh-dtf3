extends RefCounted
const Fixture = preload("res://tests/mechanics/adult_health.gd")
const Homes = preload("res://tests/mechanics/care_homes_sim.gd")
const Access = preload("res://scripts/mechanics/care_access.gd")
var t

func _init(runner) -> void: t = runner

func fresh(player_parent: bool = true):
	var config: Dictionary = Fixture.new(t).config()
	config.settings.start_minutes = 600
	var sim = Homes.new(2027,config)
	t._check(sim.configuration_error.is_empty(),"two-house clinical/family fixture configures")
	sim.state.npc_reproduction.enabled = false
	sim.state.economy.cash = 10000
	var starter: Dictionary = sim.catalog.settings.home_rooms.duplicate(true)
	sim.catalog.properties.apartment.rooms = starter
	for kind in starter:
		var place: Dictionary = sim.catalog.locations[starter[kind]]
		place.kind = "private_room"
		place.room_kind = str(kind)
		place.residence_property_id = "apartment"
	var rooms := {"hall":"river_hall","bedroom":"river_bedroom","bathroom":"river_bathroom","kitchen":"river_kitchen"}
	sim.catalog.properties.river_home = {"location":"river_hall","price":1000,"monthly_rent":60,"tenant_rent":0,"tenant_capacity":2,"furniture_slots":8,"rooms":rooms}
	for kind in rooms:
		sim.catalog.locations[rooms[kind]] = {"kind":"private_room","room_kind":str(kind),"residence_property_id":"river_home","routes":{}}
		if kind!="hall":
			sim.catalog.locations[rooms[kind]].routes.river_hall = {"minutes":1}
			sim.catalog.locations.river_hall.routes[rooms[kind]] = {"minutes":1}
	sim.catalog.locations.global_map.routes.river_hall = {"minutes":10}
	sim.catalog.locations.river_hall.routes.global_map = {"minutes":10}
	t._check(sim.command("housing","rent",{"id":"apartment"}).ok and sim.command("housing","move_in",{"id":"apartment"}).ok,"household begins in its actual acquired starter home")
	t._check(sim.command("npc_agency","enable").ok,"household planner enables")
	for id in ["male","female"]:
		t._check(sim.command("social","generate",{"id":id,"template":"health_"+id}).ok,"adult guardian is generated: "+id)
		var npc: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_agency._cancel(npc,"homes_fixture")
		npc.location = "bedroom"
		npc.home = "bedroom"
		npc.schedule = []
		npc.activity = "rest"
		npc.pinned_until = 1000000
		for need in npc.needs: npc.needs[need] = 100.0
	sim.state.healthcare.family.append({"parent":"male","partner":"player" if player_parent else "female","minute":600,"care":0,"status":"dependent"})
	sim.services.family.initialize()
	return sim

func member(sim) -> Dictionary: return sim.state.family.members.family_1

func advance(sim, minutes: int) -> void:
	t._check(sim.command("clock","advance",{"minutes":minutes}).ok,"household shares actual elapsed travel/care time")

func run() -> void:
	_player_move()
	_npc_move()
	_private_ownership()

func _player_move() -> void:
	var sim = fresh()
	var child := member(sim)
	child.needs.attention = 20.0
	child.assignments.attention = "player"
	sim.state.social.npcs.male.pinned_until = 0
	t._check(sim.command("family","delegate",{"id":"family_1","need":"attention","caregiver":"male"}).ok,"care starts in the old household before moving")
	var assignments: Dictionary = child.assignments.duplicate(true)
	t._check(sim.command("housing","buy",{"id":"river_home"}).ok,"new home is actually acquired")
	var minute := int(sim.state.clock.total_minutes)
	for destination in ["apartment_hall","global_map","river_hall"]:
		t._check(sim.command("world","travel",{"id":destination}).ok,"player follows the actual route to "+destination)
	t._check(int(sim.state.clock.total_minutes)==minute+16 and child.home=="bedroom" and not child.task.is_empty(),"travel alone neither relocates the family address nor completes unfinished care")
	t._check(sim.command("housing","move_in",{"id":"river_home"}).ok,"completed household move selects the acquired destination")
	t._check(child.home=="river_bedroom" and sim.state.world.location=="river_hall","family address synchronizes to the actual new home without another person teleporting")
	t._check(child.task.is_empty() and child.needs.attention==20 and child.bonds.is_empty() and child.assignments==assignments,"old-home task is cancelled without result or permanent reassignment")
	t._check(sim.state.social.npcs.male.location=="bedroom","the co-guardian stays at its real old location")
	sim.state.social.npcs.male.pinned_until = 1000000
	var before: Dictionary = sim.export_snapshot()
	var options: Array = sim.services.family.care_options("family_1","attention")
	t._check(options.size()==1 and not options[0].available and options[0].reason=="family_helper_not_home" and before==sim.export_snapshot(),"care alternatives do not turn a remote guardian into a present helper")
	child.needs.food = 20.0
	t._check(sim.command("family","care",{"id":"family_1","action":"feed"}).ok and child.needs.food==80,"player can perform actual family care in another room of the new home")
	var health = sim.services.adult_health
	health.infections.onset("player","contact_irritation")
	health.record("player").conditions.contact_irritation.known = true
	health.plans.begin("player","contact_irritation")
	advance(sim,1440)
	t._check(sim.command("world","travel",{"id":"river_bathroom"}).ok,"player actually enters the new bathroom")
	t._check(Access.sanitary(sim,"player") and sim.services.pregnancy_wellbeing.care.toilet_available("player"),"adult and pregnancy hygiene recognize the new real bathroom")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var clone = Homes.new(1,Fixture.new(t).config())
	clone.catalog = sim.catalog.duplicate(true)
	t._check(clone.restore_snapshot(snapshot).ok,"moved household and unfinished clinical plan restore")
	var supplies := int(health.record("player").conditions.contact_irritation.course.supplies)
	t._check(sim.command("adult_health","care_step",{"condition":"contact_irritation"}).ok,"prescribed home care works at the new address")
	t._check(clone.command("adult_health","care_step",{"condition":"contact_irritation"}).ok,"restored home care uses the same real address")
	t._check(health.record("player").conditions.contact_irritation.course.supplies==supplies-1,"home care consumes exactly one real course supply")
	t._check(JSON.parse_string(JSON.stringify(sim.export_snapshot()))==JSON.parse_string(JSON.stringify(clone.export_snapshot())),"moved family, supplies, care and future RNG replay identically")

func _npc_move() -> void:
	var sim = fresh(false)
	t._check(sim.command("housing","buy",{"id":"river_home"}).ok,"NPC family destination is acquired")
	var npc: Dictionary = sim.state.social.npcs.male
	t._check(sim.command("housing","tenant",{"id":"river_home","npc":"male"}).ok,"guardian's new residence is assigned through existing housing")
	sim.services.family.synchronize_homes()
	t._check(member(sim).home=="bedroom" and npc.location=="bedroom","new residence alone does not claim guardian arrival or move the family")
	npc.pinned_until = 0
	var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),str(npc.home))
	sim.services.npc_agency._start(npc,"rest",str(npc.home),"","household_move")
	t._check(npc.location=="bedroom" and npc.mind.active.get("phase","")=="travel","NPC move begins a reserved real journey")
	advance(sim,int(route.minutes))
	t._check(npc.location=="river_hall" and member(sim).home=="river_hall","NPC family follows its residential guardian only after actual arrival")
	var before: Dictionary = sim.export_snapshot()
	sim.services.family.synchronize_homes()
	t._check(before==sim.export_snapshot(),"repeated synchronization adds no relocation, cost or reward")

func _private_ownership() -> void:
	var sim = fresh(false)
	sim.catalog.locations.own_unit = {"kind":"private_residence","owner_actor_id":"male","residence_property_id":"shared_building","routes":{}}
	sim.catalog.locations.foreign_unit = {"kind":"private_residence","owner_actor_id":"female","residence_property_id":"shared_building","routes":{}}
	sim.state.social.npcs.male.home = "own_unit"
	t._check(sim.is_actor_home_location("male","own_unit") and not sim.is_actor_home_location("male","foreign_unit"),"matching building/property metadata never grants another NPC's private home")
	sim.state.social.npcs.male.home = "foreign_unit"
	t._check(not sim.is_actor_home_location("male","foreign_unit"),"a contradictory home reference cannot override the actual private owner")
	sim.catalog.locations.foreign_unit.toilet = true
	sim.state.social.npcs.male.location = "foreign_unit"
	t._check(not Access.sanitary(sim,"male"),"sanitary capability does not override another NPC's private ownership")
