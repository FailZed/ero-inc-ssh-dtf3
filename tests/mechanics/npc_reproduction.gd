extends RefCounted
const Sim = preload("res://scripts/mechanics/autonomous_reproductive_simulation.gd")
const Previous = preload("res://scripts/mechanics/reproductive_simulation.gd")
var t

func _init(runner) -> void:
	t=runner

func config() -> Dictionary:
	var bio: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/reproduction.json")).reproduction_rules.simulation
	bio.merge({"conception_chance":1.0,"session_minutes":3,"exposure_minutes":5,"detection_minutes":5},true)
	var auto: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/npc_reproduction.json")).npc_reproduction_rules.simulation
	auto.merge({"scan_minutes":5,"health_minutes":5,"stage_minutes":1,"initiative_chance":1.0,"decision_delay":1,"opening_hour":0,"closing_hour":24,"pair_cooldown":10080},true)
	var female:={"age":28,"gender":"female","home":"npc_home_a","money":2000,"schedule":[],"activities":[],"role":"resident",
		"reproductive_profile":{"cycle_offset":13,"desire":"open","requires_protection":false}}
	var male:=female.duplicate(true)
	male.gender="male"
	male.home="npc_home_b"
	var result:={"settings":{"start_minutes":480},"reproduction_rules":{"simulation":bio},"npc_reproduction_rules":{"simulation":auto},
		"npc_templates":{"auto_female":female,"auto_male":male},"conditions":{"pregnancy":{"duration":100,"stages":[{"after":50}]}},
		"locations":{"npc_home_a":{"routes":{"global_map":{"minutes":5}}},"npc_home_b":{"routes":{"global_map":{"minutes":5}}},"global_map":{"routes":{"npc_home_a":{"minutes":5},"npc_home_b":{"minutes":5}}}}}
	return JSON.parse_string(JSON.stringify(result))

func fresh(partners: bool = true, extensions: Dictionary = {}):
	var setup:=config()
	setup.merge(extensions,true)
	setup=JSON.parse_string(JSON.stringify(setup))
	var sim=Sim.new(8301,setup)
	t._check(sim.configuration_error.is_empty(),"autonomous reproductive catalog validates: "+sim.configuration_error)
	t._check(sim.command("npc_agency","enable").ok,"independent NPC agency enabled")
	for pair in [["a","auto_female"],["b","auto_male"]]:
		t._check(sim.command("social","generate",{"id":pair[0],"template":pair[1]}).ok,"generate autonomous adult "+pair[0])
		var npc: Dictionary=sim.state.social.npcs[pair[0]]
		sim.services.npc_agency._cancel(npc,"initial_world")
		npc.location="global_map"
		npc.activity="rest"
		npc.schedule=[]
		npc.pinned_until=0
		npc.needs.merge({"energy":100.0,"satiety":100.0,"hygiene":100.0,"social":90.0,"fun":90.0},true)
		t._check(sim.command("npc_reproduction","configure",{"id":pair[0],"values":{"preferred_method":"none","emergency":false,"pregnancy_decision":"continue","parenthood":"retain"}}).ok,"initial personal policy "+pair[0])
	for pair in [["a","b"],["b","a"]]:
		var bond: Dictionary=sim.services.npc_relationships._bond(pair[0],pair[1])
		bond.merge({"trust":80.0,"comfort":75.0,"interest":70.0,"closeness":65.0,"affection":50.0,"consent":partners},true)
	sim.services.npc_relationships._project("a","b")
	if partners: sim.services.social.relationship("a","b").status="partner"
	sim.state.world.location="training_center"
	sim.state.economy.cash=777
	sim.state.economy.bank=111
	sim.state.inventory.items.barrier_protection=7
	return sim

func advance(sim, minutes: int) -> void:
	var now:=int(sim.state.clock.total_minutes)
	var result: Dictionary=sim.command("clock","advance",{"minutes":minutes})
	t._check(result.ok,"autonomous shared clock commits: "+str(result.get("error","")))
	t._check(int(sim.state.clock.total_minutes)==now+minutes,"background actions never recursively advance the shared clock")

func events(sim, kind: String) -> Array:
	return sim.state.npc_reproduction.history.filter(func(h): return h.kind==kind)

func same(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))

func run() -> void:
	_complete_family()
	_protection_and_interruption()
	_decisions()
	_supplies_and_health()
	_relationships()
	_snapshots()
	_parallel_and_clinical_replay()
	_routine_contraception()
	_support_collection()
	_emergency_and_public_care()
	_reservation_validation()

func _complete_family() -> void:
	var sim=fresh()
	var before: Dictionary=sim.export_snapshot()
	t._check(sim.command("npc_reproduction","inspect").ok and before==sim.export_snapshot(),"inspecting autonomous decisions is read-only and consumes no RNG")
	advance(sim,150)
	t._check(sim.state.intimacy.active.is_empty() and sim.state.intimacy.history.is_empty(),"NPC-to-NPC encounters never occupy the player's scene protocol")
	t._check(sim.state.reproduction.exposures.size()==1,"autonomous couple creates exactly one reproductive exposure")
	var exposure: Dictionary=sim.state.reproduction.exposures.values()[0]
	t._check(exposure.target=="a" and exposure.partner=="b" and not exposure.intended,"unprotected NPC encounter can cause an unplanned pregnancy without a family plan")
	t._check(sim.state.reproduction.pregnancies.values()[0].status=="born","NPC pregnancy reaches birth using only shared clock advancement")
	t._check(sim.state.family.members.size()==1 and sim.state.family.members.family_1.parents==["a","b"],"birth creates the correct two NPC parents")
	t._check(sim.state.family.members.family_1.home=="npc_home_a","NPC child lives at its guardian's actual home")
	t._check(int(sim.services.reproduction.view("a").recovery_until)>int(sim.state.clock.total_minutes) and not sim.services.reproduction.view("a").fertile_window,"birth resets the gestator's cycle and preserves a real recovery interval")
	t._check(sim.state.economy.cash==777 and sim.state.economy.bank==111 and sim.state.inventory.items.barrier_protection==7 and sim.state.world.location=="training_center","NPC family life never spends player money or inventory or moves the player")
	t._check(not events(sim,"job_completed").filter(func(e): return e.data.kind=="prenatal_care").is_empty(),"NPC gestator travels to paid prenatal care while player is elsewhere")
	var member: Dictionary=sim.state.family.members.family_1
	member.needs.food=20.0
	advance(sim,60)
	t._check(member.needs.food>20 and not sim.state.family.history.filter(func(e): return e.kind=="care").is_empty(),"NPC guardians reserve real time and supply care after birth")

func _protection_and_interruption() -> void:
	var sim=fresh()
	for id in ["a","b"]:
		sim.services.reproduction.record(id).requires_protection=true
		sim.state.social.npcs[id].inventory.barrier_protection=1
	advance(sim,24)
	var outcomes:=events(sim,"encounter_ended")
	t._check(outcomes.size()==1 and outcomes[0].data.protection=="barrier","NPCs choose actual owned protection without consulting player")
	t._check(sim.state.social.npcs.a.inventory.get("barrier_protection",0)==0 and sim.state.social.npcs.b.inventory.barrier_protection==1,"one NPC-owned item is consumed exactly once")
	t._check(sim.state.reproduction.exposures.values()[0].chance<1.0,"shared protective factor reduces NPC conception risk")
	sim=fresh()
	for id in ["a","b"]:
		sim.services.reproduction.record(id).requires_protection=true
		sim.state.social.npcs[id].money=0
	advance(sim,30)
	t._check(sim.state.reproduction.exposures.is_empty() and events(sim,"encounter_ended")[0].data.protection=="non_reproductive","lack of protection never overrides either NPC's stated boundary")
	sim=fresh()
	advance(sim,1)
	t._check(sim.state.npc_reproduction.sessions.size()==1,"autonomous invitation reserves both NPCs")
	t._check(sim.command("npc_relationships","boundary",{"id":"a","boundary":"romance","allowed":false}).ok,"NPC can change its own current romantic boundary")
	t._check(sim.state.npc_reproduction.sessions.is_empty() and sim.state.social.npcs.a.pinned_until==0 and sim.state.social.npcs.b.pinned_until==0,"withdrawal releases both reservations immediately")
	advance(sim,20)
	t._check(sim.state.reproduction.exposures.is_empty(),"interrupted NPC encounter awards no unperformed reproductive consequence")
	sim=fresh()
	sim.state.social.npcs.a.schedule=[{"activity":"work","location":"global_map","hours":[480,600],"weekdays":[int(sim.state.clock.weekday)]}]
	advance(sim,20)
	t._check(events(sim,"encounter_started").is_empty(),"NPC intimacy cannot replace a compulsory shift")
	sim=fresh()
	sim.command("preferences","content_tag",{"id":"romance","enabled":false})
	advance(sim,30)
	t._check(events(sim,"encounter_started").is_empty() and sim.state.reproduction.exposures.is_empty(),"romance filter applies to NPC-to-NPC autonomy")

func _decisions() -> void:
	var sim=fresh()
	sim.services.reproduction.record("a").desire="avoid"
	sim.command("npc_reproduction","configure",{"id":"a","values":{"pregnancy_decision":"auto"}})
	advance(sim,150)
	t._check(sim.state.reproduction.pregnancies.size()==1 and sim.state.reproduction.pregnancies.values()[0].status=="terminated","NPC independently decides and completes termination in the clinic")
	t._check(sim.state.family.members.is_empty() and sim.state.economy.cash==777,"NPC termination creates no child and never charges the player")
	t._check(sim.services.reproduction.view("a").recovery_until>int(sim.state.clock.total_minutes),"NPC recovery starts at actual procedure completion")
	sim=fresh()
	sim.command("npc_reproduction","configure",{"id":"a","values":{"pregnancy_decision":"adoption","parenthood":"decline"}})
	sim.command("npc_reproduction","configure",{"id":"b","values":{"parenthood":"decline"}})
	advance(sim,150)
	t._check(sim.state.family.members.family_1.custody=="adoption" and sim.state.family.members.family_1.guardians.is_empty(),"NPC adoption decision transfers custody at birth")
	t._check(sim.state.child_support.obligations.is_empty(),"formal NPC adoption is distinct from unpaid parental obligations")
	sim=fresh()
	sim.command("npc_reproduction","configure",{"id":"a","values":{"pregnancy_decision":"adoption","parenthood":"decline"}})
	advance(sim,150)
	var member: Dictionary=sim.state.family.members.family_1
	t._check(member.guardians==["b"] and member.home=="npc_home_b","willing second parent keeps care when gestator declines; child moves to guardian's address")
	t._check(sim.state.child_support.obligations.size()==1,"NPC relinquishing direct care remains liable for child support")
	var obligation: Dictionary=sim.state.child_support.obligations.values()[0]
	t._check(obligation.payer=="a" and obligation.recipient=="b","child support parties are actual NPC parents")
	# A prepared calendar boundary isolates monthly billing, without simulating a month of unrelated needs.
	sim.state.clock=sim.calendar.snapshot(int(obligation.next_due)-1)
	advance(sim,61)
	obligation=sim.state.child_support.obligations.values()[0]
	t._check(obligation.billed==120 and obligation.paid==120 and obligation.arrears==0,"NPC-to-NPC monthly support transfers real debtor funds autonomously")

func _supplies_and_health() -> void:
	var sim=fresh()
	for id in ["a","b"]: sim.services.reproduction.record(id).requires_protection=true
	var stock:=int(sim.catalog.shops.market.stock.barrier_protection)
	advance(sim,8)
	t._check(sim.state.social.npcs.a.inventory.get("barrier_protection",0)>0 and sim.state.social.npcs.b.inventory.get("barrier_protection",0)>0,"NPCs buy protection from an actual shop before relying on it")
	t._check(int(sim.state.economy.shop_stock.market.barrier_protection)<stock,"NPC purchase reduces shared shop inventory")
	t._check(sim.state.economy.cash==777 and sim.state.inventory.items.barrier_protection==7,"NPC supply purchases leave player funds and supplies untouched")
	sim=fresh()
	sim.command("npc_reproduction","configure",{"id":"a","values":{"preferred_method":"iud"}})
	advance(sim,90)
	t._check(sim.services.reproduction.view("a").method=="iud","NPC installs preferred long-term contraception at a real clinical visit")
	t._check(sim.state.economy.cash==777,"clinical contraception uses the NPC's wallet")
	sim=fresh()
	sim.command("npc_reproduction","configure",{"id":"b","values":{"procedure":"vasectomy"}})
	advance(sim,130)
	t._check(sim.services.reproduction.view("b").sterilization=="vasectomy","explicit NPC permanent-care policy completes a timed clinical procedure")

func _relationships() -> void:
	var sim=fresh(false)
	advance(sim,120)
	t._check(not events(sim,"courtship_started").is_empty(),"NPC relationship initiative runs without player social commands")
	t._check(sim.services.social.relationship("a","b").status=="partner","mutual relationship agreement uses existing directed relationship runtime")
	t._check(sim.state.social.relationships.keys().all(func(key): return not "player" in str(key).split("|")),"NPC relationship development does not fabricate bonds with player")

func _snapshots() -> void:
	var sim=fresh()
	advance(sim,2)
	var snapshot: Dictionary=JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var replay=Sim.new(9,config())
	t._check(replay.restore_snapshot(snapshot).ok,"two reserved NPCs in transit survive JSON restoration")
	advance(sim,148)
	advance(replay,148)
	t._check(same(sim.export_snapshot(),replay.export_snapshot()),"restored NPC encounter, choices, conception, clinical care and birth reproduce identical future RNG")
	var before: Dictionary=sim.export_snapshot()
	for bad_case in ["policy","reservation","plan"]:
		var bad: Dictionary=before.duplicate(true)
		match bad_case:
			"policy": bad.state.npc_reproduction.policies.a.enabled="invalid"
			"reservation": bad.state.npc_reproduction.sessions={"x":{"a":"player"}}
			"plan": bad.state.npc_reproduction.decisions.values()[0].care="injected"
		t._check(not sim.restore_snapshot(bad).ok and before==sim.export_snapshot(),"invalid autonomous snapshot is rejected atomically: "+bad_case)
	var previous=Previous.new(7,config())
	var legacy: Dictionary=previous.export_snapshot()
	t._check(legacy.catalog_hash==JSON.stringify(sim.previous_autonomy_catalog).sha256_text(),"previous snapshot hash is reconstructed from the actual previous runtime")
	t._check(replay.restore_snapshot(legacy).ok and replay.state.npc_reproduction.sessions.is_empty(),"exact previous reproductive snapshot gains empty autonomous state in memory")
	t._check(not legacy.state.has("npc_reproduction"),"migration never rewrites the supplied old snapshot object")

func _parallel_and_clinical_replay() -> void:
	var sim=fresh()
	for pair in [["c","auto_female"],["d","auto_male"]]:
		sim.command("social","generate",{"id":pair[0],"template":pair[1]})
		var npc: Dictionary=sim.state.social.npcs[pair[0]]
		sim.services.npc_agency._cancel(npc,"initial_parallel_world")
		npc.location="global_map"
		npc.activity="rest"
		npc.pinned_until=0
		sim.command("npc_reproduction","configure",{"id":pair[0],"values":{"preferred_method":"none","emergency":false,"pregnancy_decision":"continue","parenthood":"retain"}})
	for pair in [["c","d"],["d","c"]]:
		sim.services.npc_relationships._bond(pair[0],pair[1]).merge({"trust":80.0,"comfort":75.0,"interest":70.0,"closeness":65.0,"affection":50.0,"consent":true},true)
	sim.services.npc_relationships._project("c","d")
	sim.services.social.relationship("c","d").status="partner"
	advance(sim,2)
	t._check(sim.state.npc_reproduction.sessions.size()==2,"independent NPC couples can reserve parallel private encounters")
	var snapshot: Dictionary=JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var replay=Sim.new(1,config())
	t._check(replay.restore_snapshot(snapshot).ok,"parallel NPC bookings restore without player participation")
	advance(sim,148)
	advance(replay,148)
	t._check(same(sim.export_snapshot(),replay.export_snapshot()) and sim.state.family.members.size()==2,"parallel conceptions and births preserve the same future after loading")
	sim=fresh()
	sim.services.reproduction.record("a").desire="avoid"
	sim.command("npc_reproduction","configure",{"id":"a","values":{"pregnancy_decision":"auto"}})
	advance(sim,60)
	t._check(sim.state.npc_reproduction.jobs.has("a") and sim.state.npc_reproduction.jobs.a.kind=="terminate","NPC books a timed clinical decision after discovering unwanted pregnancy")
	snapshot=JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	replay=Sim.new(1,config())
	t._check(replay.restore_snapshot(snapshot).ok,"unfinished NPC clinical procedure survives loading")
	advance(sim,90)
	advance(replay,90)
	t._check(same(sim.export_snapshot(),replay.export_snapshot()),"restored clinical choice charges the same NPC once and preserves exact future")
	sim=fresh()
	sim.command("npc_reproduction","configure",{"id":"a","values":{"preferred_method":"iud"}})
	advance(sim,10)
	sim.state.social.npcs.a.money=0
	advance(sim,60)
	t._check(sim.services.reproduction.view("a").method=="none" and sim.state.social.npcs.a.money>=0,"insolvent clinical completion does not apply a free procedure or negative payment")
	t._check(not events(sim,"job_interrupted").filter(func(h): return h.data.reason=="insufficient_funds").is_empty(),"failed timed care records its own rollback while world time stays advanced")

func _routine_contraception() -> void:
	var sim=fresh()
	sim.command("preferences","content_tag",{"id":"romance","enabled":false})
	sim.services.reproduction.record("a").desire="avoid"
	sim.state.social.npcs.a.inventory.contraceptive_pill=4
	sim.command("npc_reproduction","configure",{"id":"a","values":{"preferred_method":"pill"}})
	for day in range(3): advance(sim,1440)
	advance(sim,30)
	t._check(sim.services.reproduction.view("a").method_active,"autonomous daily doses preserve continuous activation despite health polling interval")
	var purchased:=0
	for event in events(sim,"supply_bought"):
		if event.data.npc=="a" and event.data.item=="contraceptive_pill": purchased+=int(event.data.quantity)
	var doses: int=sim.state.reproduction.history.filter(func(h): return h.kind=="contraception" and h.data.target=="a" and h.data.method=="pill").size()
	t._check(doses>=4 and int(sim.state.social.npcs.a.inventory.get("contraceptive_pill",0))==4+purchased-doses,"autonomous regular contraception consumes exactly the actual daily doses, including restocking")

func debt_fixture():
	var support: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/reproduction.json")).child_support_rules.simulation
	support.enforcement_delay=30
	var sim=fresh(true,{"child_support_rules":{"simulation":support}})
	# Prepare a shared calendar boundary with the same support rules, then use only autonomous filing/collection.
	sim.command("npc_reproduction","configure",{"id":"b","values":{"parenthood":"decline"}})
	sim.state.social.npcs.b.money=0
	advance(sim,150)
	var o: Dictionary=sim.state.child_support.obligations.values()[0]
	var minute:=int(o.next_due)
	minute+=posmod(-minute,60)
	sim.state.clock=sim.calendar.snapshot(minute-1)
	for npc in sim.state.social.npcs.values():
		sim.services.npc_agency._cancel(npc,"calendar_boundary_fixture")
		npc.mind.updated_at=minute-1
		npc.needs.merge({"energy":100.0,"satiety":100.0,"hygiene":100.0,"social":90.0,"fun":90.0},true)
		npc.activity="rest"
		npc.pinned_until=0
		npc.location=npc.home
		npc.decision={"committed":false,"reason":"calendar_boundary_fixture"}
	advance(sim,1)
	return sim

func _support_collection() -> void:
	var sim=debt_fixture()
	var o: Dictionary=sim.state.child_support.obligations.values()[0]
	t._check(o.arrears==120 and o.paid==0,"insolvent NPC payer accumulates real support debt")
	advance(sim,60)
	o=sim.state.child_support.obligations.values()[0]
	t._check(o.order and int(o.enforcement_due)==0,"NPC recipient autonomously files, pays and obtains collection order")
	t._check(not events(sim,"job_completed").filter(func(h): return h.data.kind=="support_case").is_empty(),"collection filing consumes recipient's own booked time")
	sim.state.social.npcs.b.money=50
	advance(sim,60)
	o=sim.state.child_support.obligations.values()[0]
	t._check(o.paid==50 and o.arrears==70,"new NPC income is partially collected without forgiving remaining debt")
	t._check(sim.state.economy.cash==777 and sim.state.economy.bank==111,"NPC support enforcement has no player financial participant")

func _emergency_and_public_care() -> void:
	var sim=fresh()
	sim.command("npc_reproduction","configure",{"id":"a","values":{"parenthood":"decline"}})
	sim.command("npc_reproduction","configure",{"id":"b","values":{"parenthood":"decline"}})
	advance(sim,150)
	t._check(sim.state.family.members.family_1.custody=="public_care" and sim.state.family.members.family_1.guardians.is_empty(),"both NPC parents may decline direct care without erasing biological parentage")
	t._check(sim.state.child_support.obligations.size()==2 and sim.state.child_support.obligations.values().all(func(o): return o.recipient=="public_care"),"both NPC parents owe support when public services take over care")
	sim=fresh()
	sim.catalog.reproduction_rules.simulation.exposure_minutes=120
	sim.services.reproduction.record("a").desire="avoid"
	sim.state.social.npcs.a.psychology.facets.prudence=80
	sim.state.social.npcs.a.inventory.emergency_contraception=1
	sim.command("npc_reproduction","configure",{"id":"a","values":{"emergency":true}})
	advance(sim,35)
	var e: Dictionary=sim.state.reproduction.exposures.values()[0]
	t._check(e.emergency and float(e.chance)<1.0,"NPC autonomously acts on a recent unplanned risk before conception resolves")
	t._check(not sim.state.social.npcs.a.inventory.has("emergency_contraception") and sim.state.economy.cash==777,"NPC emergency action consumes own real supplies and no player funds")

func _reservation_validation() -> void:
	var sim=fresh()
	advance(sim,2)
	var before:Dictionary=sim.export_snapshot()
	for field in ["actor","pin","time","scope","disabled"]:
		var bad:Dictionary=before.duplicate(true)
		var session:Dictionary=bad.state.npc_reproduction.sessions.values()[0]
		match field:
			"actor":session.a="player"
			"pin":bad.state.social.npcs.a.pinned_until=0
			"time":session.next_step=-1
			"scope":session.scope="player"
			"disabled":bad.state.npc_reproduction.policies.a.enabled=false
		t._check(not sim.restore_snapshot(bad).ok and before==sim.export_snapshot(),"corrupt NPC reservation cannot affect live world: "+field)
	t._check(sim.command("npc_reproduction","disable").ok and sim.state.npc_reproduction.sessions.is_empty(),"disabling background autonomy releases reservations without consequences")
	advance(sim,60)
	t._check(sim.state.reproduction.exposures.is_empty(),"disabled background encounter cannot complete later")
