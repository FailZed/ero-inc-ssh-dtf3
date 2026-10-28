extends SceneTree
const Main = preload("res://scripts/gameplay/main_simulation.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); print("FAIL ",label)

func fixture(seed_value: int = 42):
	var template := {"age":28,"home":"bedroom","money":100,"role":"worker","personalities":["calm"],
		"origins":["local"],"goals":["wellbeing"],"preferences":["books"],"schedule":[],"activities":["read","walk"],
		"traits":{"bravery":60,"responsibility":70,"sociability":80,"romantic":40,"loyalty":80,"cunning":30}}
	var sim = Main.new(seed_value,{"settings":{"start_minutes":720},"npc_templates":{"event_fixture":template}})
	check(sim.configuration_error.is_empty(),"main catalog "+sim.configuration_error)
	for id in ["event_a","event_b"]:
		check(sim.command("social","generate",{"id":id,"template":"event_fixture"}).ok,"generate "+id)
	check(sim.command("npc_agency","enable").ok,"real autonomous owners enabled")
	for id in ["event_a","event_b"]:
		var npc: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_agency._cancel(npc,"fixture_setup")
		npc.schedule=[]; npc.location="city_park"; npc.activity="rest"; npc.pinned_until=0
		npc.decision={"committed":false,"reason":"fixture"}
		for need in npc.needs: npc.needs[need]=100.0
		npc.psychology.facets.sociability=100.0
		npc.psychology.facets.sentimentality=100.0
		check(sim.command("social","contact",{"id":id}).ok,"contact "+id)
	var bond: Dictionary = sim.services.npc_relationships._bond("event_a","event_b")
	bond.trust=40.0; bond.affection=40.0; bond.closeness=40.0
	bond=sim.services.npc_relationships._bond("event_b","event_a")
	bond.trust=40.0; bond.affection=40.0; bond.closeness=40.0
	sim.services.npc_relationships._project("event_a","event_b")
	sim.state.world.location="residential_district"
	return sim

func phone_case() -> void:
	var sim = fixture()
	for npc in sim.state.social.npcs.values(): npc.pinned_until=2000
	var money: int = sim.state.economy.cash
	check(sim.services.events.offer_phone("event_a"),"authored NPC initiative creates real source message")
	var offers: Array = sim.services.events.random_offers("event_a")
	check(offers.size()==1,"phone offer visible")
	if offers.is_empty(): return
	var key := str(offers[0].id)
	var source: Dictionary = sim.state.social.messages.back()
	check(source.incoming and source.meaning=="busy_short_reply" and source.event_instance==key,"typed source identity")
	var before: Dictionary = sim.export_snapshot()
	sim.services.events.random_offers("event_a")
	check(sim.export_snapshot()==before,"preview never mutates state or RNG")
	var start := int(sim.state.clock.total_minutes)
	var chosen: Dictionary = sim.command("events","random_choose",{"id":key,"choice":"a"})
	check(chosen.ok,"clarification command commits "+str(chosen))
	if not chosen.ok: return
	check(int(sim.state.clock.total_minutes)==start+4,"clarification exactly four minutes")
	check(sim.state.social.messages.size()==2,"one source and one outgoing; no instant reply")
	check(sim.state.social.messages.back().in_reply_to==source.id,"outgoing bound to exact source")
	check(sim.state.economy.cash==money,"no event money reward or charge")
	before=sim.export_snapshot()
	check(not sim.command("events","random_choose",{"id":key,"choice":"a"}).ok,"duplicate selection refused")
	check(sim.export_snapshot()==before,"duplicate rolls back state and RNG")
	var restored = Main.new(42,{"settings":{"start_minutes":720},"npc_templates":{"event_fixture":{"age":28,"home":"bedroom","money":100,"role":"worker","personalities":["calm"],"origins":["local"],"goals":["wellbeing"],"preferences":["books"],"schedule":[],"activities":["read","walk"],"traits":{"bravery":60,"responsibility":70,"sociability":80,"romantic":40,"loyalty":80,"cunning":30}}}})
	check(restored.restore_snapshot(before).ok,"restore awaiting real correlated reply")
	for i in 12:
		if sim.state.journal.random_events.phone[key].status=="replied": break
		check(sim.command("clock","advance",{"minutes":15}).ok,"real clock advances reply owner")
	check(sim.state.journal.random_events.phone[key].status=="replied","NPC actually answers later")
	var incoming: Dictionary = sim.state.social.messages.back()
	check(incoming.incoming and incoming.in_reply_to==chosen.data.message_id,"incoming reply bound to actual outgoing")
	check(sim.command("events","random_choose",{"id":key,"choice":"b"}).ok,"reply may be left until later")
	var closed: Dictionary = sim.export_snapshot()
	check(not sim.command("events","random_choose",{"id":key,"choice":"a"}).ok,"completed followup not replayed")
	check(sim.export_snapshot()==closed,"completed followup refusal unchanged")
	check(sim.services.events.offer_phone("event_b"),"second contact has separate source")
	var second: Dictionary = sim.services.events.random_offers("event_b")[0]
	start=int(sim.state.clock.total_minutes)
	check(sim.command("events","random_choose",{"id":second.id,"choice":"leave"}).ok,"player declines optional event")
	check(sim.state.clock.total_minutes==start,"decline takes zero minutes")

func npc_case() -> void:
	var sim = fixture(1)
	var a: Dictionary = sim.state.social.npcs.event_a
	var b: Dictionary = sim.state.social.npcs.event_b
	var funds := [sim.state.economy.cash,a.money,b.money]
	for attempt in 2:
		for retry in 20:
			sim.services.npc_agency._start(a,"connect","city_park","event_b","ordinary_autonomy")
			if not sim.state.journal.random_events.visits.is_empty(): break
		check(not sim.state.journal.random_events.visits.is_empty(),"real willing pair reserved "+str(attempt))
		sim.services.npc_agency._cancel(a,"confirmed_schedule_interruption")
		var history: Array = sim.state.journal.random_events.pairs["event_a|event_b"].cancellations
		check(history.size()==attempt+1,"one genuine cancellation fact "+str(attempt))
		sim.services.npc_agency._cancel(b,"duplicate_cleanup")
		check(history.size()==attempt+1,"reciprocal cleanup does not duplicate fact")
	var due := int(sim.state.clock.total_minutes)+15-posmod(int(sim.state.clock.total_minutes),15)
	a.pinned_until=due; b.pinned_until=due
	var elapsed: Dictionary = sim.command("clock","advance",{"minutes":due-int(sim.state.clock.total_minutes)})
	check(elapsed.ok,"actual planner reaches event opportunity "+str(elapsed))
	var cases: Dictionary = sim.state.journal.random_events.npc_cases
	check(cases.size()==1,"NPC-only event occurs automatically from real cancellations")
	if cases.is_empty(): return
	var key := str(cases.keys()[0]); var event: Dictionary = cases[key]
	print("NPC_EVENT ",JSON.stringify(event))
	check(event.source_ids[0]!=event.source_ids[1],"two distinct factual sources")
	check(sim.services.events.random_offers().is_empty(),"private NPC event not offered to player")
	check([sim.state.economy.cash,a.money,b.money]==funds,"NPC event does not touch any wallet")
	check(event.choice=="a" and event.status=="proposal","accepted autonomous visit selected by real decision")
	if event.status!="proposal" or event.choice!="a": return
	var saved: Dictionary = sim.export_snapshot()
	check(sim.restore_snapshot(saved).ok,"restore timed NPC proposal")
	check(sim.command("clock","advance",{"minutes":6}).ok,"six minute proposal runs in shared clock")
	event=sim.state.journal.random_events.npc_cases[key]
	check(event.status=="visiting","actual owner starts agreed visit")
	a=sim.state.social.npcs.event_a; b=sim.state.social.npcs.event_b
	check(a.mind.active.partner=="event_b" and int(a.mind.active.due)-int(a.mind.active.started)==30,"existing thirty-minute connect owner controls visit")
	saved=sim.export_snapshot()
	check(sim.restore_snapshot(saved).ok,"restore in-flight NPC owner action")
	var step: int = sim.services.npc_agency.rules().decision_minutes
	var finish: int = int(a.mind.active.due)+posmod(-int(a.mind.active.due),step)
	check(sim.command("clock","advance",{"minutes":finish-int(sim.state.clock.total_minutes)}).ok,"actual owner finishes NPC visit at its decision boundary")
	print("NPC_END ",JSON.stringify(sim.state.journal.random_events.npc_cases[key])," A=",JSON.stringify(sim.state.social.npcs.event_a.mind.active)," VISITS=",JSON.stringify(sim.state.journal.random_events.visits))
	check(sim.state.journal.random_events.npc_cases[key].status in ["completed","declined"],"matched real social outcome completes once")
	saved=sim.export_snapshot()
	check(sim.restore_snapshot(saved).ok,"restore completed NPC event")
	check(sim.export_snapshot()==saved,"restore does not replay social gain")
	var facts: Dictionary = sim.state.journal.random_events.pairs["event_a|event_b"]
	check(not str(facts.handled).is_empty(),"resolved incident retains consumed source fingerprint")
	facts.cooldown=0
	sim.state.journal.random_events.next_npc=0
	var next_opportunity: int = int(sim.state.clock.total_minutes)+15
	for npc in sim.state.social.npcs.values():
		sim.services.npc_agency._cancel(npc,"fixture_no_new_incident")
		npc.pinned_until=next_opportunity
	check(sim.command("clock","advance",{"minutes":15}).ok,"next eligible boundary without a new cancellation")
	check(sim.state.journal.random_events.npc_cases.size()==1,"same cancelled visits cannot spawn new event after cooldown removal")

func natural_and_guards() -> void:
	var sim = fixture(91)
	for npc in sim.state.social.npcs.values(): npc.pinned_until=2200
	for i in 8:
		if not sim.services.events.random_offers().is_empty(): break
		check(sim.command("clock","advance",{"minutes":120}).ok,"natural event opportunity")
	check(not sim.services.events.random_offers().is_empty(),"unforced phone event occurs during ordinary time advancement")
	var blocked = fixture(2)
	blocked.state.social.npcs.event_a.mind.boundaries.contact=false
	check(not blocked.services.events.offer_phone("event_a"),"contact refusal prevents initiative")
	check(not blocked.services.events.pair_available("event_a","event_b",30),"NPC contact boundary respected")
	var fresh = Main.new(1)
	check(not fresh.services.events.enabled() and fresh.services.events.random_offers().is_empty(),"no random events before autonomy/prologue gate")
	var damaged: Dictionary = blocked.export_snapshot()
	damaged.state.journal.random_events.phone.bad={"status":"offered","npc":"unknown","source":1,"outgoing":0,"reply":0,"created":0,"expires":900,"due":0}
	check(not blocked.restore_snapshot(damaged).ok,"invalid event target rejected on restore")
	damaged=blocked.export_snapshot()
	damaged.state.journal.random_events.serial=-1
	check(not blocked.restore_snapshot(damaged).ok,"negative identity counter rejected")
	damaged=blocked.export_snapshot()
	damaged.state.journal.random_events.visits.bad={"id":"visit:1","status":"active","a":"event_a","b":"event_b","started":720,"due":750,"instance":""}
	check(not blocked.restore_snapshot(damaged).ok,"orphan or mismatched visit rejected")

func npc_decline() -> void:
	var sim = fixture(2)
	var a: Dictionary = sim.state.social.npcs.event_a
	var b: Dictionary = sim.state.social.npcs.event_b
	for attempt in 2:
		for retry in 20:
			sim.services.npc_agency._start(a,"connect","city_park","event_b","ordinary_autonomy")
			if not sim.state.journal.random_events.visits.is_empty(): break
		sim.services.npc_agency._cancel(a,"actual_interruption")
	a.pinned_until=735; b.pinned_until=735
	var before_a: Dictionary = sim.services.npc_relationships.view("event_a","event_b")
	check(sim.command("clock","advance",{"minutes":15}).ok,"autonomous refusal opportunity")
	var event: Dictionary = sim.state.journal.random_events.npc_cases.values()[0]
	check(event.status=="declined","recipient really may refuse NPC proposal")
	check(a.mind.active.is_empty() and b.mind.active.is_empty(),"declined proposal never starts or pins a forced visit")
	check(sim.services.npc_relationships.view("event_a","event_b").affection==before_a.affection,"refusal has no invented relation reward")

func ui_case() -> void:
	var sim = fixture(41)
	for npc in sim.state.social.npcs.values(): npc.pinned_until=2000
	check(sim.services.events.offer_phone("event_a"),"UI fixture uses real source owner")
	var offer: Dictionary = sim.services.events.random_offers("event_a")[0]
	var card := preload("res://scripts/ui/gameplay/random_event_offer.gd").new()
	card.size=Vector2(320,500)
	root.add_child(card)
	var results: Array = []
	card.setup(offer,func(id: String, choice: String): results.append(sim.command("events","random_choose",{"id":id,"choice":choice})))
	await process_frame
	var buttons := card.find_children("*","Button",true,false)
	check(buttons.size()==3,"actual phone card has two decisions and refusal")
	check(str(buttons[0].get_meta("phone_focus","")).contains(str(offer.id)),"phone focus key preserves exact instance")
	var start: int = sim.state.clock.total_minutes
	buttons[0].pressed.emit()
	check(results.size()==1 and results[0].ok,"real UI button invokes committed event choice")
	check(sim.state.clock.total_minutes==start+4,"UI path consumes owner time once")
	var saved: Dictionary=sim.export_snapshot()
	buttons[0].pressed.emit()
	check(results.size()==2 and not results[1].ok and sim.export_snapshot()==saved,"stale UI callback cannot replay message or time")
	card.queue_free()

func reset_and_restore() -> void:
	var sim = fixture(30)
	for npc in sim.state.social.npcs.values(): npc.pinned_until=2000
	check(sim.services.events.offer_phone("event_a"),"reset fixture has a genuine live event")
	var saved: Dictionary=sim.export_snapshot()
	sim.reset()
	check(sim.state.journal.has("random_events") and sim.state.journal.random_events.serial==0,"reset creates clean book through installed owner")
	var settings: Dictionary=preload("res://scripts/mechanics/population.gd").defaults()
	settings.count=2
	check(sim.command("population","configure",{"values":settings}).ok,"reset then configure remains valid")
	check(sim.command("population","generate").ok,"reset then generate remains valid")
	check(sim.restore_snapshot(saved).ok,"restore original event-bearing snapshot after reset")
	check(sim.export_snapshot()==saved,"restore exact preserves all instances instead of reinitializing")

func _initialize() -> void:
	phone_case()
	npc_case()
	natural_and_guards()
	npc_decline()
	reset_and_restore()
	await ui_case()
	print("RANDOM_EVENTS_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
