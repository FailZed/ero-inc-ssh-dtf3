extends RefCounted
const Sim = preload("res://scripts/mechanics/autonomous_reproductive_simulation.gd")
const Fixture = preload("res://tests/mechanics/reproduction.gd")
var t

func _init(runner) -> void:
	t = runner

func config() -> Dictionary:
	return {"settings":{"start_minutes":480},"npc_templates":{
		"health_female":{"age":32,"gender":"female","home":"bedroom","money":2000,"schedule":[],"activities":[],"reproductive_profile":{"cycle_offset":13}},
		"health_male":{"age":32,"gender":"male","home":"bedroom","money":2000,"schedule":[],"activities":[]}}}

func fresh():
	var sim = Sim.new(2027,config())
	t._check(sim.configuration_error.is_empty(),"adult-health fixture catalog validates")
	t._check(sim.command("npc_agency","enable").ok,"adult-health NPC agency enables")
	for sex in ["female","male"]:
		t._check(sim.command("social","generate",{"id":sex,"template":"health_"+sex}).ok,"adult-health fixture generates "+sex)
		var npc: Dictionary = sim.state.social.npcs[sex]
		sim.services.npc_agency._cancel(npc,"health_fixture")
		npc.pinned_until = 1000000
		npc.location = "bedroom"
		npc.home = "bedroom"
		npc.schedule = []
		npc.activity = "rest"
		sim.state.adult_health.records[sex].hpv = {}
	sim.state.world.location = "bathroom"
	sim.state.economy.cash = 3000
	sim.state.player.age = 32
	return sim

func female(sim) -> void:
	t._check(sim.command("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true,"cycle_offset":0}}).ok,"configure cycling adult")

func reject(sim, operation: String, args: Dictionary, text: String) -> void:
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command("adult_health",operation,args)
	t._check(not result.ok and before==sim.export_snapshot(),text+" rejects atomically")

func run() -> void:
	_cycle()
	_erections_and_desire()
	_actual_intimacy_failure()
	_hpv_contacts()
	_clinic()
	_npc_and_snapshots()
	_npc_clinic()

func _cycle() -> void:
	var sim = fresh()
	female(sim)
	var health = sim.services.adult_health
	var before: Dictionary = sim.export_snapshot()
	health.view()
	health.conversation_line("female",true)
	t._check(before==sim.export_snapshot(),"adult-health and desire queries are read-only")
	t._check(health.view().cycle.active,"menstrual state follows existing reproductive cycle")
	t._check(sim.command("clock","advance",{"minutes":30}).ok,"unprotected menstruation advances")
	t._check(health.view().soiled and health.view().cycle.leaks==1,"menstrual leakage changes clothing and is counted")
	t._check(sim.command("adult_health","cleanup").ok and not health.view().soiled,"changing clothes clears menstrual soiling")
	t._check(sim.command("adult_health","change_product",{"product":"pad"}).ok,"pad can be changed in a private facility")
	var supplies := int(health.record("player").cycle.supplies.pad)
	t._check(supplies==5 and health.view().cycle.fill==0,"changing a pad consumes stock and resets capacity")
	t._check(sim.command("clock","advance",{"minutes":30}).ok and not health.view().soiled,"fresh product prevents ordinary immediate leakage")
	health.record("player").cycle.fill = 100.0
	health.record("player").cycle.last_leak = -10080
	t._check(sim.command("clock","advance",{"minutes":15}).ok and health.view().soiled,"saturated protection can leak")
	sim.state.world.location = "global_map"
	t._check(sim.command("adult_health","buy_products",{"product":"cup"}).ok,"reusable product can be purchased")
	t._check(sim.command("adult_health","change_product",{"product":"cup"}).ok,"reusable product can be equipped")
	var cup_stock := int(health.record("player").cycle.supplies.cup)
	t._check(sim.command("adult_health","change_product",{"product":"cup"}).ok and health.record("player").cycle.supplies.cup==cup_stock,"emptying reusable protection does not consume another cup")
	t._check(sim.command("lifecycle","start",{"id":"pregnancy","target":"player"}).ok and not health.view().cycle.active,"pregnancy suppresses menstruation and period leakage")
	reject(sim,"vaccinate",{},"vaccination deferred during pregnancy")

func _erections_and_desire() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	var record: Dictionary = health.record("player")
	var profile: Dictionary = sim.services.reproduction.view().duplicate(true)
	var mood := float(sim.state.player.needs.mood)
	t._check(health.start_erection("player"),"adult spontaneous erection can occur")
	t._check(sim.services.reproduction.view()==profile and sim.state.player.needs.mood==mood,"ordinary erection changes neither reproductive wishes nor mood")
	t._check(not health.start_erection("female"),"erection episodes respect anatomy capability")
	t._check(sim.command("clock","advance",{"minutes":15}).ok and health.view().erection.until==0,"ordinary episode ends on its own")
	t._check(health.start_erection("player",true,true),"authored prolonged painful episode can start")
	t._check(sim.command("clock","advance",{"minutes":240}).ok and health.view().urgent,"prolonged episode raises urgent-care flag")
	t._check(sim.command("adult_health","rest").ok and health.view().urgent,"rest cannot cure a persistent pathological episode")
	reject(sim,"emergency",{},"urgent treatment away from clinic")
	sim.state.world.location = "clinic"
	sim.state.economy.cash = 0
	t._check(sim.command("adult_health","emergency").ok and not health.view().urgent,"urgent clinic care resolves episode without a money gate")
	sim.state.economy.cash = 1000
	t._check(sim.command("adult_health","desire",{"intent":"not_now"}).ok and health.intimate_blocked("player")=="adult_health_no_desire","explicit lack of desire prevents a new encounter")
	var failures := int(record.desire.failures)
	t._check(sim.command("adult_health","desire",{"intent":"want_intimacy"}).ok,"player can state desire independently of physical capability")
	t._check(record.desire.failures==failures,"changing wishes is not treated as a physiological failure")
	reject(sim,"desire",{"intent":"invalid"},"invalid intention")

func _actual_intimacy_failure() -> void:
	var helper = Fixture.new(t)
	var sim = helper.fresh()
	var health = sim.services.adult_health
	sim.state.inventory.items.barrier_protection = 2
	helper.ready(sim,"barrier")
	var r: Dictionary = health.record("player")
	r.desire.intent = "want_intimacy"
	r.erection.difficulty_until = int(sim.state.clock.total_minutes)+180
	var mood := float(sim.state.player.needs.mood)
	var partner_mood := float(sim.state.social.npcs.adult.needs.mood)
	helper.choose(sim,"start")
	t._check(sim.state.intimacy.active.is_empty() and sim.state.intimacy.history[-1].reason=="adult_health_difficulty","actual encounter stops when a physiological difficulty prevents it")
	t._check(sim.state.player.needs.mood<mood and sim.state.social.npcs.adult.needs.mood<partner_mood,"wanted but unsuccessful intimacy lowers both participants' mood")
	t._check(r.desire.frustration>0 and r.desire.failures==1,"failure records frustration and unmet desire")
	t._check(sim.state.reproduction.exposures.is_empty() and sim.state.inventory.items.barrier_protection==2,"failed start causes no conception exposure and consumes no unused barrier")
	var after := float(sim.state.player.needs.mood)
	health.try_intimacy("player","adult")
	t._check(sim.state.player.needs.mood==after,"repeated immediate failure cannot stack the mood penalty")

func _hpv_contacts() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	health.infections.acquire("male","high_risk","fixture")
	t._check(health.view("male").diagnoses.is_empty() and not health.view("male").has("hpv"),"asymptomatic hidden HPV is absent from public health projection")
	var key := ""
	for index in range(1000):
		var candidate := "contact_"+str(index)
		var value: float = health.unit(candidate+":male:player:high_risk")
		if value>=0.09 and value<0.20: key=candidate; break
	t._check(not key.is_empty(),"stable contact fixture lies between protected and unprotected risks")
	var clone = Sim.new(0,config())
	t._check(clone.restore_snapshot(JSON.parse_string(JSON.stringify(sim.export_snapshot()))).ok,"contact comparison restores exact world")
	health.contact("male","player","unprotected",key)
	clone.services.adult_health.contact("male","player","barrier",key)
	t._check(health.record("player").hpv.get("high_risk",{}).get("status","")=="active","HPV can transmit between two male adults without a reproductive pairing")
	t._check(clone.services.adult_health.record("player").hpv.is_empty(),"barrier reduces HPV risk independently of pregnancy protection")
	var before: Dictionary = sim.export_snapshot()
	health.contact("male","player","unprotected",key)
	t._check(before==sim.export_snapshot(),"one encounter cannot apply infection and satisfaction twice")
	t._check(float(health.config().hpv.barrier_residual)>0,"barrier protection does not claim complete HPV prevention")
	sim.state.social.npcs.male.age = 17
	var contacts: int = sim.state.adult_health.contacts.size()
	health.contact("male","player","unprotected","forbidden_contact")
	t._check(sim.state.adult_health.contacts.size()==contacts,"adult-health contacts exclude minors")

func _clinic() -> void:
	var sim = fresh()
	female(sim)
	var health = sim.services.adult_health
	sim.state.world.location = "clinic"
	health.infections.acquire("player","high_risk","screen_fixture")
	t._check(sim.command("adult_health","consult").ok and health.view().diagnoses.is_empty(),"ordinary consultation cannot diagnose asymptomatic high-risk HPV")
	t._check(sim.command("adult_health","vaccinate").ok and health.record("player").hpv.high_risk.status=="active","vaccination prevents future infection but does not clear existing HPV")
	reject(sim,"vaccinate",{},"premature next vaccine dose")
	t._check(sim.command("adult_health","screen").ok and health.view().screening.result=="positive","age-appropriate cervical HPV screen detects infection")
	t._check(health.view().diagnoses.size()==1 and health.view().screening.followup,"positive HPV screen leads to observation rather than cancer diagnosis")
	reject(sim,"screen",{},"repeat screening before due date")
	t._check(sim.command("adult_health","followup").ok and not health.view().screening.followup,"provider follow-up records a continuing observation plan")
	health.record("player").hpv.high_risk.clears_at = int(sim.state.clock.total_minutes)+15
	t._check(sim.command("clock","advance",{"minutes":15}).ok and health.record("player").hpv.high_risk.status=="cleared","HPV may become undetectable without a magical antiviral cure")
	t._check(health.view().diagnoses.size()==1,"hidden viral clearance is not automatically revealed to patient")
	health.record("player").screening.next = 0
	t._check(sim.command("adult_health","screen").ok and health.view().screening.result=="negative" and health.view().diagnoses.is_empty(),"follow-up screen can confirm a negative result")
	health.infections.onset("player","candidiasis")
	t._check(not health.view().symptom_list.is_empty() and health.view().diagnoses.is_empty(),"common irritation is symptomatic before provider diagnosis")
	health.record("player").consult_after = 0
	t._check(sim.command("adult_health","consult").ok,"provider evaluates common symptoms")
	t._check(sim.command("adult_health","treat",{"condition":"candidiasis"}).ok,"diagnosed candidiasis uses a scheduled course")
	t._check(health.record("player").conditions.candidiasis.status=="active","course does not cure symptoms instantly")
	var finish := int(health.record("player").conditions.candidiasis.treatment_until)
	while int(sim.state.clock.total_minutes)<finish:
		var minutes := mini(1440,finish-int(sim.state.clock.total_minutes))
		t._check(sim.command("clock","advance",{"minutes":minutes}).ok,"scheduled course advances")
	t._check(health.record("player").conditions.candidiasis.status=="resolved","scheduled condition treatment completes")
	var male_sim = fresh()
	male_sim.state.world.location = "clinic"
	reject(male_sim,"screen",{},"universal HPV screening for a patient without a cervix")

func _npc_and_snapshots() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	var npc: Dictionary = sim.state.social.npcs.female
	npc.pinned_until = 0
	health.record("female").soiled = true
	t._check(sim.command("clock","advance",{"minutes":15}).ok and not health.record("female").selfcare.is_empty(),"NPC autonomously reserves a private cleanup break")
	t._check(sim.command("clock","advance",{"minutes":10}).ok and not health.record("female").soiled and health.record("female").selfcare.is_empty(),"NPC completes personal care without player participation")
	var snapshot: Dictionary = sim.export_snapshot()
	var clone = Sim.new(0,config())
	t._check(clone.restore_snapshot(JSON.parse_string(JSON.stringify(snapshot))).ok,"adult physiology and medical records restore from JSON")
	t._check(sim.command("clock","advance",{"minutes":30}).ok and clone.command("clock","advance",{"minutes":30}).ok,"restored adult-health world advances")
	t._check(JSON.parse_string(JSON.stringify(sim.state.adult_health))==JSON.parse_string(JSON.stringify(clone.state.adult_health)) and sim.rng.state==clone.rng.state,"restoration preserves symptoms, libido, infections and future outcomes")
	for field in ["libido","frustration"]:
		var corrupt: Dictionary = sim.export_snapshot()
		corrupt.state.adult_health.records.player.desire[field] = -1
		var before: Dictionary = clone.export_snapshot()
		t._check(not clone.restore_snapshot(corrupt).ok and before==clone.export_snapshot(),"corrupt adult-health "+field+" rejects without altering live world")

func _npc_clinic() -> void:
	var sim = fresh()
	var health = sim.services.adult_health
	var npc: Dictionary = sim.state.social.npcs.male
	npc.pinned_until = 0
	npc.location = "bathroom"
	sim.services.npc_agency._cancel(npc,"clinic_fixture")
	npc.activity = "rest"
	npc.mind.boundaries.contact = true
	health.infections.acquire("male","low_risk","lesion_fixture")
	health.record("male").hpv.low_risk.lesions_at = int(sim.state.clock.total_minutes)
	health._refresh("male")
	t._check(sim.command("npc_dialogue","open",{"id":"male"}).ok,"symptomatic NPC can begin an ordinary conversation")
	t._check(sim.command("clock","advance",{"minutes":15}).ok and health.record("male").selfcare.is_empty(),"routine clinic scheduler respects an ongoing conversation")
	t._check(sim.command("npc_dialogue","close",{"id":"male"}).ok,"NPC conversation closes before scheduling medical trip")
	npc.location = "clinic"
	npc.pinned_until = 0
	npc.activity = "rest"
	sim.services.npc_agency._cancel(npc,"clinic_fixture")
	t._check(sim.command("clock","advance",{"minutes":120}).ok,"NPC has time for provider consultation and treatment")
	t._check(health.record("male").hpv.low_risk.known and health.record("male").hpv.low_risk.lesions_treated,"NPC independently obtains diagnosis and lesion treatment")
	t._check(health.record("male").hpv.low_risk.status=="active","NPC lesion procedure does not pretend to eradicate HPV")
