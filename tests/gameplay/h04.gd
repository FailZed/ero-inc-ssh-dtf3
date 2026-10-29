extends SceneTree
## Focused Main14 city-access regression; runs only in an isolated project.
const Main = preload("res://scripts/gameplay/main_simulation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)

func _run() -> void:
	var sim = Main.new(42)
	check(sim.configuration_error.is_empty(),"Main14 catalog validates: "+sim.configuration_error)
	var generated: Dictionary = sim.command("social","generate",{"id":"h04_guest"})
	check(generated.ok,"Main14 creates an ordinary city resident: "+str(generated.get("error","")))
	if not generated.ok:
		_finish()
		return
	var enabled: Dictionary = sim.command("npc_agency","enable")
	check(enabled.ok,"Main14 agency enables: "+str(enabled.get("error","")))
	if not enabled.ok:
		_finish()
		return
	var npc: Dictionary = sim.state.social.npcs.h04_guest
	sim.services.npc_agency._cancel(npc,"h04_fixture")
	npc.location = npc.home
	npc.activity = "rest"
	npc.pinned_until = 0
	npc.schedule = []
	sim.state.world.location = sim.player_home()
	sim.services.social.relationship("h04_guest","player").trust = 25.0
	check(npc.home.begins_with("city_resident_home_") and npc.home!=sim.player_home(),"ordinary resident starts in a distinct private home")
	var origin := str(npc.location)
	var invited: Dictionary = sim.command("social","invite",{"id":"h04_guest","minutes":60})
	check(invited.ok,"Main14 private-home invitation finds a route: "+str(invited.get("error","")))
	if invited.ok:
		check(npc.location==origin and npc.activity=="appointment_travel","Main14 invite starts travel without teleporting")
		var arrival := int(invited.data.arrival)-int(sim.state.clock.total_minutes)
		var advanced: Dictionary = sim.command("clock","advance",{"minutes":arrival})
		check(advanced.ok and npc.location==sim.player_home(),"ordinary resident reaches player's bedroom on the booked minute")
		advanced = sim.command("clock","advance",{"minutes":40})
		check(advanced.ok and sim.services.social_rules._has_commitment(npc),"Main14 guest remains committed after the ordinary 30-minute window")
		advanced = sim.command("clock","advance",{"minutes":20})
		check(advanced.ok and sim.state.social.appointments.back().status=="met","Main14 visit completes at its booked duration")
		check(not sim.services.social_rules._has_commitment(npc),"completed invitation no longer blocks guest availability")
		# Keep the real city-resident home as the tenancy return destination.
		var original_home := str(npc.home)
		sim.state.housing.properties.apartment = {"owned":true,"equipment":{},"tenants":[],"next_bill":45000,"arrears":0,"rent_income":0,"tenant_arrears":{},"original_homes":{}}
		sim.services.npc_relationships._bond("h04_guest","player").trust = 25.0
		var tenant: Dictionary = sim.command("housing","tenant",{"id":"apartment","npc":"h04_guest"})
		check(tenant.ok and npc.home==str(sim.catalog.properties.apartment.location),"Main14 tenant takes the apartment's configured home: "+str(tenant.get("error","")))
		if tenant.ok:
			var removed: Dictionary = sim.command("housing","remove_tenant",{"id":"apartment","npc":"h04_guest"})
			check(removed.ok and npc.home==original_home and npc.location==sim.player_home(),"Main14 removal restores real home without teleporting")
			var route: Dictionary = sim.services.npc_agency._route(npc,str(npc.location),original_home)
			check(not route.is_empty() and int(route.minutes)>0,"former tenant can route out through the private hall")
			if not route.is_empty():
				sim.services.npc_agency._cancel(npc,"h04_egress_fixture")
				sim.state.preferences.disabled_tags.append("adult")
				sim.services.npc_agency._start(npc,"rest",original_home,"","h04_egress")
				check(npc.mind.active.get("phase","")=="travel","former tenant begins the existing NPC travel task: "+str(npc.mind.active))
				advanced = sim.command("clock","advance",{"minutes":int(route.minutes)+15})
				check(advanced.ok and npc.location==original_home,"former tenant reaches the original city-resident home: actual="+str(npc.location)+" expected="+original_home+" active="+str(npc.mind.active)+" history="+str(npc.mind.history.slice(-3)))
				check(not sim.services.world.actor_availability("apartment_hall","h04_guest",int(sim.state.clock.total_minutes)).ok and not sim.services.world.actor_availability("bedroom","h04_guest",int(sim.state.clock.total_minutes)).ok,"former tenant cannot re-enter the player's private rooms after leaving")
				var other: Dictionary = sim.command("social","generate",{"id":"h04_other"})
				check(other.ok and not sim.services.world.actor_availability(str(sim.state.social.npcs.h04_other.home),"h04_guest",int(sim.state.clock.total_minutes)).ok,"former tenant gains no access to another resident's private home")
	_finish()

func _finish() -> void:
	print("H04_MAIN_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
