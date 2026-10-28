extends RefCounted
const Sim = preload("res://scripts/mechanics/reproductive_simulation.gd")
const Old = preload("res://scripts/mechanics/extended_simulation.gd")
var t

func _init(runner) -> void:
	t = runner

func config() -> Dictionary:
	return {"settings":{"start_minutes":480}, "reproduction_rules":{"simulation":_fast_rules()},
		"conditions":{"pregnancy":{"duration":50,"stages":[{"after":25}]}},
		"npc_templates":{"test_adult":{"age":26,"gender":"female","home":"bedroom","money":2000,"schedule":[],"activities":[],
			"reproductive_profile":{"cycle_offset":13,"desire":"open","requires_protection":false}}}}

func _fast_rules() -> Dictionary:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/reproduction.json")).reproduction_rules.simulation
	rules.conception_chance = 1.0
	rules.exposure_minutes = 5
	rules.detection_minutes = 5
	rules.session_minutes = 3
	rules.invitation_minutes = 60
	rules.cooldown_minutes = 0
	return rules

func fresh():
	var sim = Sim.new(2026, config())
	t._check(sim.configuration_error.is_empty(), "reproductive catalog validates: " + sim.configuration_error)
	t._check(sim.command("npc_agency","enable").ok, "human agency enabled for encounter fixture")
	t._check(sim.command("social","generate",{"id":"adult","template":"test_adult"}).ok,"generate adult reproductive fixture")
	var npc: Dictionary = sim.state.social.npcs.adult
	sim.services.npc_agency._cancel(npc,"test")
	npc.location = "bedroom"
	npc.schedule = []
	npc.pinned_until = 0
	npc.activity = "rest"
	var b: Dictionary = sim.services.npc_relationships._bond("adult","player")
	b.merge({"trust":75.0,"comfort":65.0,"interest":70.0,"closeness":60.0},true)
	sim.services.npc_relationships._project("adult","player")
	sim.state.economy.cash = 3000
	t._check(sim.command("reproduction","preference",{"desire":"avoid","requires_protection":false}).ok,"player can state pregnancy avoidance independently of protection")
	return sim

func choose(sim, choice: String, extra: Dictionary = {}) -> Dictionary:
	var a: Dictionary = sim.state.intimacy.active
	if a.is_empty():
		t._check(false,"encounter exists before choice " + choice)
		return {"ok":false,"error":"no_fixture_session"}
	var args := {"session":a.id,"revision":a.revision,"choice":choice}
	args.merge(extra,true)
	var result: Dictionary = sim.command("intimacy","choose",args)
	t._check(result.ok,"encounter choice " + choice + ": " + str(result.get("error","")))
	return result

func ready(sim, protection: String = "unprotected", kind: String = "pregnancy_possible") -> void:
	t._check(sim.command("intimacy","begin",{"id":"adult"}).ok,"begin consensual adult encounter")
	choose(sim,"accept")
	choose(sim,kind)
	choose(sim,protection,{"risk_acknowledged":true})

func complete(sim, protection: String = "unprotected", kind: String = "pregnancy_possible") -> void:
	ready(sim,protection,kind)
	choose(sim,"start")
	choose(sim,"finish")
	choose(sim,"close")

func _same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func reject(sim, module_id: String, operation: String, args: Dictionary, label: String) -> void:
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command(module_id,operation,args)
	t._check(not result.ok and _same(before,sim.export_snapshot()),label + " is atomic")

func run() -> void:
	_accidental_pregnancy()
	_protection_and_interruptions()
	_physiology_and_treatments()
	_decisions_and_support()
	_snapshots()
	_parental_roles()
	_support_lifetime()

func _accidental_pregnancy() -> void:
	var sim = fresh()
	var before: Dictionary = sim.export_snapshot()
	sim.services.reproduction.view("adult")
	sim.services.intimacy.blocked("adult")
	t._check(before == sim.export_snapshot(),"inspection never creates records or consumes RNG")
	complete(sim)
	t._check(sim.state.reproduction.exposures.size()==1,"single completion records exactly one unprotected exposure")
	t._check(sim.state.conditions.is_empty(),"encounter does not bypass conception timing with direct family start")
	t._check(sim.command("clock","advance",{"minutes":5}).ok,"pending conception uses shared time")
	var p: Dictionary = sim.services.reproduction.pregnancy("adult")
	t._check(not p.is_empty() and not p.intended,"unplanned pregnancy occurs while neither participant wants a child")
	t._check(sim.state.conditions.has("adult:pregnancy"),"conception enters existing pregnancy lifecycle")
	sim.command("clock","advance",{"minutes":5})
	t._check(p.known,"pregnancy becomes discoverable and notifies once")
	reject(sim,"reproduction","pregnancy_decision",{"target":"adult","decision":"terminate"},"player cannot submit another patient's decision")
	t._check(sim.command("reproduction","pregnancy_decision",{"target":"adult","actor":"adult","decision":"continue"}).ok,"NPC decision can be supplied by its own scene/agency actor")
	sim.command("clock","advance",{"minutes":45})
	t._check(sim.state.reproduction.pregnancies.values()[0].status=="born" and sim.state.family.members.size()==1,"pregnancy completes through existing birth and family runtime")
	t._check(sim.state.social.npcs.size()==1,"children never enter adult romantic population")

func _protection_and_interruptions() -> void:
	var sim = fresh()
	sim.state.inventory.items.barrier_protection=1
	ready(sim,"barrier")
	var a: Dictionary = sim.state.intimacy.active
	var stale := {"session":a.id,"revision":a.revision,"choice":"start"}
	choose(sim,"start")
	t._check(not sim.state.inventory.items.has("barrier_protection"),"protection consumes exactly one owned item")
	reject(sim,"intimacy","choose",stale,"duplicate scene callback")
	choose(sim,"finish")
	t._check(sim.state.reproduction.exposures.values()[0].chance < 1.0,"barrier reduces but does not erase risk")
	choose(sim,"close")
	t._check(sim.state.reproduction.exposures.size()==1,"aftercare cannot repeat reproductive consequence")
	sim=fresh()
	ready(sim)
	choose(sim,"start")
	choose(sim,"stop")
	t._check(sim.state.reproduction.exposures.is_empty(),"withdrawal before completion creates no exposure")
	sim=fresh()
	ready(sim)
	choose(sim,"start")
	var id: String = sim.state.intimacy.active.id
	t._check(sim.command("preferences","content_tag",{"id":"romance","enabled":false}).ok,"content preference may interrupt immediately")
	t._check(sim.state.intimacy.active.is_empty() and sim.state.reproduction.exposures.is_empty(),"disabled romance releases session and grants no consequence")
	reject(sim,"intimacy","choose",{"session":id,"revision":5,"choice":"finish"},"callback after interruption")
	sim=fresh()
	sim.services.reproduction.record("adult").requires_protection=true
	t._check(sim.command("intimacy","begin",{"id":"adult"}).ok,"invitation is distinct from protection agreement")
	choose(sim,"accept")
	choose(sim,"pregnancy_possible")
	a=sim.state.intimacy.active
	reject(sim,"intimacy","choose",{"session":a.id,"revision":a.revision,"choice":"unprotected","risk_acknowledged":true},"NPC required protection cannot be overridden by player acknowledgement")
	sim=fresh()
	complete(sim,"unprotected","non_reproductive")
	t._check(sim.state.reproduction.exposures.is_empty(),"non-reproductive encounter has no conception consequence")
	sim=fresh()
	ready(sim)
	choose(sim,"start")
	sim.state.social.npcs.adult.location="global_map"
	sim.command("clock","advance",{"minutes":1})
	t._check(sim.state.intimacy.active.is_empty(),"participant leaving interrupts on next common tick")
	sim=fresh()
	sim.state.world.location="global_map"
	reject(sim,"intimacy","begin",{"id":"adult"},"remote encounter")
	sim=fresh()
	sim.state.social.npcs.adult.health=20
	reject(sim,"intimacy","begin",{"id":"adult"},"participant needing recovery")

func _physiology_and_treatments() -> void:
	var sim = fresh()
	var r: Dictionary = sim.services.reproduction.view("adult")
	t._check(r.phase=="ovulation" and r.fertile_window,"configured cycle has observable ovulation and fertile interval")
	sim.services.reproduction.record("adult").cycle_offset=0
	t._check(sim.services.reproduction.view("adult").phase=="menstruation" and sim.services.reproduction.risk("player","adult").chance==0,"menstruation follows cycle rather than pregnancy desire")
	sim.services.reproduction.record("adult").cycle_offset=13
	sim.services.reproduction.record("adult").infertile=true
	t._check(sim.services.reproduction.risk("player","adult").chance==0 and sim.services.reproduction.view("adult").cycling,"infertility prevents conception without deleting the cycle")
	sim=fresh()
	sim.state.world.location="clinic"
	reject(sim,"reproduction","procedure",{"id":"tubal_ligation","confirm":true},"incompatible sterilization")
	reject(sim,"reproduction","procedure",{"id":"vasectomy"},"unconfirmed permanent procedure")
	t._check(sim.command("reproduction","procedure",{"id":"vasectomy","confirm":true}).ok,"vasectomy is a paid clinical operation")
	t._check(not sim.services.reproduction.view("player").sterile,"vasectomy has delayed effectiveness")
	sim.state.clock=sim.calendar.snapshot(int(sim.services.reproduction.record("player").effective_at))
	t._check(sim.services.reproduction.view("player").sterile,"effective vasectomy prevents later conception")
	reject(sim,"reproduction","procedure",{"id":"vasectomy","confirm":true},"duplicate permanent procedure")
	sim=fresh()
	sim.state.world.location="clinic"
	sim.state.social.npcs.adult.location="clinic"
	t._check(sim.command("reproduction","procedure",{"target":"adult","actor":"adult","id":"tubal_ligation","confirm":true}).ok,"gestational actor can choose tubal ligation")
	t._check(sim.services.reproduction.risk("player","adult").chance==0 and sim.services.reproduction.view("adult").cycling,"tubal ligation retains menstruation while preventing conception")
	sim=fresh()
	sim.state.world.location="clinic"
	sim.state.social.npcs.adult.location="clinic"
	t._check(sim.command("reproduction","contraception",{"target":"adult","actor":"adult","method":"iud"}).ok,"long-term contraception requires clinic, compatible patient and funds")
	t._check(not sim.services.reproduction.view("adult").method_active,"contraception respects activation delay")
	sim.state.clock=sim.calendar.snapshot(int(sim.services.reproduction.record("adult").method_effective))
	t._check(sim.services.reproduction.view("adult").method_active,"long-term method becomes active through shared clock")
	sim=fresh()
	complete(sim)
	sim.state.social.npcs.adult.inventory.emergency_contraception=1
	t._check(sim.command("reproduction","emergency",{"target":"adult","actor":"adult"}).ok,"emergency contraception consumes patient's actual inventory")
	t._check(sim.state.reproduction.exposures.values()[0].emergency and sim.state.reproduction.exposures.values()[0].chance<1.0,"emergency method modifies pending risk rather than terminating pregnancy")
	reject(sim,"reproduction","emergency",{"target":"adult","actor":"adult"},"repeated emergency risk reduction")
	sim=fresh()
	sim.state.player.appearance.gender="female"
	sim.command("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true}})
	sim.state.inventory.items.contraceptive_pill=3
	t._check(sim.command("reproduction","contraception",{"method":"pill"}).ok,"regular contraception consumes one real dose")
	reject(sim,"reproduction","contraception",{"method":"pill"},"repeat daily dose")
	t._check(sim.command("clock","advance",{"minutes":1440}).ok,"contraception time advances")
	t._check(not sim.services.reproduction.view("player").method_active,"missed regular contraception is not indefinitely effective")

func _pregnant():
	var sim=fresh()
	complete(sim)
	sim.command("clock","advance",{"minutes":10})
	return sim

func _decisions_and_support() -> void:
	var sim=_pregnant()
	sim.state.world.location="clinic"
	sim.state.social.npcs.adult.location="clinic"
	t._check(sim.command("reproduction","pregnancy_decision",{"target":"adult","actor":"adult","decision":"terminate","confirm":true}).ok,"confirmed termination completes with payment and recovery")
	t._check(sim.state.family.members.is_empty() and sim.state.healthcare.family.is_empty() and not sim.state.conditions.has("adult:pregnancy"),"termination creates no birth or child")
	reject(sim,"reproduction","pregnancy_decision",{"target":"adult","actor":"adult","decision":"terminate","confirm":true},"duplicate termination")
	sim=_pregnant()
	t._check(sim.command("reproduction","pregnancy_decision",{"target":"adult","actor":"adult","decision":"adoption"}).ok,"adoption can be selected before birth")
	sim.command("clock","advance",{"minutes":45})
	t._check(sim.state.family.members.family_1.guardians.is_empty() and sim.state.family.members.family_1.custody=="adoption","formal adoption keeps lineage and transfers custody")
	t._check(sim.state.child_support.obligations.is_empty(),"formal adoption does not create parental support obligation")
	reject(sim,"family","care",{"id":"family_1","action":"feed"},"care after custody was transferred")
	sim=_pregnant()
	sim.command("clock","advance",{"minutes":45})
	t._check(sim.command("reproduction","parenthood",{"member":"family_1","decision":"relinquish","confirm":true}).ok,"parent can relinquish direct caregiving")
	t._check(not "player" in sim.state.family.members.family_1.guardians and sim.state.child_support.obligations.size()==1,"relinquishing care retains biological parentage and opens support obligation")
	var o: Dictionary=sim.state.child_support.obligations.values()[0]
	sim.state.clock=sim.calendar.snapshot(int(o.next_due))
	sim.services.child_support.tick(int(sim.state.clock.total_minutes)-int(sim.state.clock.total_minutes)%60+60)
	t._check(o.arrears==120 and o.billed==120,"calendar monthly support bills once")
	var billed:int=o.billed
	sim.services.child_support.tick(int(sim.state.clock.total_minutes)-int(sim.state.clock.total_minutes)%60+60)
	t._check(o.billed==billed,"repeated same due tick cannot duplicate support debt")
	var cash:int=sim.state.economy.cash
	var recipient_cash:int=sim.state.social.npcs.adult.money
	t._check(sim.command("child_support","pay",{"id":o.id,"amount":50}).ok,"support payment is accepted from its actual payer")
	t._check(sim.state.economy.cash==cash-50 and sim.state.social.npcs.adult.money==recipient_cash+50 and o.arrears==70,"support money moves to real recipient and reduces only paid debt")
	reject(sim,"child_support","pay",{"id":o.id,"amount":1000},"payment beyond actual arrears")
	o=sim.state.child_support.obligations.values()[0]
	t._check(sim.command("child_support","file_enforcement",{"id":o.id,"actor":"adult"}).ok,"recipient may file for collection of existing arrears")
	sim.state.clock=sim.calendar.snapshot(int(o.enforcement_due)+60)
	sim.services.child_support.tick(int(sim.state.clock.total_minutes)-int(sim.state.clock.total_minutes)%60)
	t._check(o.order and o.arrears==0 and o.paid==o.billed,"collection transfers available money, never creates a payment from nothing")

func _snapshots() -> void:
	var sim=fresh()
	ready(sim)
	choose(sim,"start")
	var snapshot:Dictionary=JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var replay=Sim.new(9,config())
	t._check(replay.restore_snapshot(snapshot).ok,"unfinished scene protocol restores through JSON")
	choose(sim,"finish")
	choose(replay,"finish")
	t._check(_same(sim.export_snapshot(),replay.export_snapshot()),"restored encounter consumes same time, exposure and RNG once")
	choose(sim,"close")
	choose(replay,"close")
	snapshot=JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	t._check(replay.restore_snapshot(snapshot).ok,"pending conception restores before resolution")
	sim.command("clock","advance",{"minutes":10})
	replay.command("clock","advance",{"minutes":10})
	t._check(_same(sim.export_snapshot(),replay.export_snapshot()),"conception and detection have identical future after loading")
	for bad_case in ["probability","profile","pregnancy","support","session"]:
		var bad:Dictionary=sim.export_snapshot()
		match bad_case:
			"probability":bad.state.reproduction.exposures.values()[0].chance=2
			"profile":bad.state.reproduction.records.player.cycle_days=0
			"pregnancy":bad.state.reproduction.pregnancies.values()[0].partner="missing"
			"support":bad.state.child_support.obligations={"x":{"arrears":-5}}
			"session":bad.state.intimacy.active={"stage":"injected"}
		var before:Dictionary=sim.export_snapshot()
		t._check(not sim.restore_snapshot(bad).ok and before==sim.export_snapshot(),"corrupt reproductive snapshot rejected atomically: "+bad_case)
	var old=Old.new(1,config())
	var legacy:Dictionary=old.export_snapshot()
	var current:Dictionary=replay.export_snapshot()
	t._check(not replay.restore_snapshot(legacy).ok and current==replay.export_snapshot(),"superseded extended snapshot is rejected without conversion")
	t._check(not legacy.state.has("reproduction"),"old snapshot input remains untouched")

func _parental_roles() -> void:
	var sim=_pregnant()
	t._check(sim.command("reproduction","pregnancy_response",{"target":"adult","response":"decline_parenthood"}).ok,"other parent can decline direct care before birth")
	sim.command("clock","advance",{"minutes":45})
	t._check(sim.state.family.members.family_1.guardians==["adult"] and sim.state.child_support.obligations.size()==1,"prenatal refusal produces real custody and support obligation at birth")
	sim=fresh()
	t._check(sim.command("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true,"cycle_offset":13}}).ok,"player may have a gestational reproductive profile")
	t._check(sim.command("reproduction","configure",{"target":"adult","actor":"adult","profile":{"can_gestate":false,"produces_sperm":true,"cycling":false}}).ok,"reproductive capability is separate from gender identity")
	complete(sim)
	sim.command("clock","advance",{"minutes":10})
	t._check(not sim.services.reproduction.pregnancy("player").is_empty(),"player pregnancy works in the same accidental conception chain")
	sim=fresh()
	sim.command("reproduction","preference",{"desire":"want","requires_protection":false})
	sim.command("reproduction","preference",{"target":"adult","actor":"adult","desire":"want","requires_protection":false})
	complete(sim,"unprotected","plan_pregnancy")
	sim.command("clock","advance",{"minutes":10})
	t._check(sim.services.reproduction.pregnancy("adult").intended,"mutually wanted conception is recorded separately from accidental conception")

func _support_lifetime() -> void:
	var sim=_pregnant()
	sim.command("clock","advance",{"minutes":45})
	sim.command("reproduction","parenthood",{"member":"family_1","decision":"relinquish","confirm":true})
	var old:Dictionary=sim.state.child_support.obligations.values()[0]
	old.arrears=120
	old.billed=120
	var old_id:String=old.id
	sim.state.economy.cash=20
	sim.state.economy.bank=30
	t._check(sim.command("child_support","autopay",{"id":old.id,"enabled":true}).ok,"payer may opt into regular support transfers")
	var before:int=sim.state.social.npcs.adult.money
	sim.state.clock=sim.calendar.snapshot(600)
	sim.services.child_support.tick(600)
	t._check(old.arrears==70 and old.paid==50 and sim.state.economy.cash==0 and sim.state.economy.bank==0 and sim.state.social.npcs.adult.money==before+50,"insolvent payer transfers available cash and bank money while preserving unpaid debt")
	t._check(sim.command("reproduction","parenthood",{"target":"adult","actor":"adult","member":"family_1","decision":"relinquish","confirm":true}).ok,"other parent can relinquish direct care independently")
	t._check(sim.state.family.members.family_1.custody=="public_care" and sim.state.family.members.family_1.guardians.is_empty(),"no remaining guardian transfers care to public services")
	t._check(sim.state.child_support.obligations[old_id].arrears==70 and not sim.state.child_support.obligations[old_id].active,"custody change preserves earlier creditor and arrears")
	t._check(sim.state.child_support.obligations.size()==3,"both parents acquire separate future obligations to new guardian")
	var member:Dictionary=sim.state.family.members.family_1
	var adult_time:int=sim.calendar.add_months(int(member.born),216)
	sim.state.clock=sim.calendar.snapshot(adult_time+60)
	sim.services.family._update_stage(member)
	sim.services.child_support.tick(int(sim.state.clock.total_minutes)-int(sim.state.clock.total_minutes)%60)
	t._check(sim.state.child_support.obligations.values().all(func(o): return not o.active),"new support accrual ends at the child's adult threshold")
	t._check(sim.state.child_support.obligations[old_id].arrears==70,"adult threshold does not forgive existing support debt")
