extends RefCounted
const Simulation = preload("res://scripts/gameplay/main_simulation.gd")
const Presentation = preload("res://scripts/gameplay/presentation.gd")

static func fixture(seed: int = 42):
	var sim = Simulation.new(seed,Presentation.extensions())
	sim.state.clock = sim.calendar.snapshot(600)
	sim.command("npc_agency","enable")
	sim.command("social","generate",{"id":"friend","age":24,"appearance":{"gender":"female","morphology":"human"}})
	var npc: Dictionary = sim.state.social.npcs.friend
	npc.gender = "female"
	npc.location = sim.state.world.location
	npc.schedule = []
	npc.pinned_until = 10000
	npc.activity = "rest"
	npc.decision = {"committed":false,"reason":"test"}
	npc.needs.energy = 100.0
	npc.needs.satiety = 100.0
	npc.needs.hygiene = 100.0
	sim.services.npc_agency._cancel(npc,"test")
	var bond: Dictionary = sim.services.npc_relationships._bond("friend","player")
	sim.services.npc_relationships._change(bond,{"trust":50,"closeness":40,"comfort":40,"affection":40})
	return sim

static func accepted_fixture():
	for seed in range(1,30):
		var sim = fixture(seed)
		var offered: Dictionary = sim.command("companion","offer",{"id":"friend","gesture":"hand"})
		if offered.ok and offered.data.accepted: return sim
	push_error("Could not arrange an accepted fixture")
	return fixture()

