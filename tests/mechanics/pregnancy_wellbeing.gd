extends RefCounted
const Sim = preload("res://scripts/mechanics/reproductive_simulation.gd")
const Model = preload("res://scripts/mechanics/pregnancy_wellbeing.gd")
var t

func _init(runner) -> void:
	t = runner

func config() -> Dictionary:
	return {"settings":{"start_minutes":480},"conditions":{"pregnancy":{"duration":900,"stages":[{"after":300},{"after":600}]}},
		"npc_templates":{"wellbeing_adult":{"age":26,"gender":"female","home":"bedroom","money":1000,"schedule":[],"activities":[],"reproductive_profile":{"can_gestate":true,"produces_sperm":false,"cycling":true}}}}

func fresh():
	var sim = Sim.new(801,config())
	sim.state.player.needs.merge({"bladder":100.0,"rested":100.0,"hydration":100.0},true)
	t._check(sim.configuration_error.is_empty(),"pregnancy wellbeing fixture catalog validates")
	t._check(sim.command("reproduction","configure",{"profile":{"can_gestate":true,"produces_sperm":false,"cycling":true}}).ok,"configure adult gestating player")
	t._check(sim.command("npc_agency","enable").ok,"enable NPC health autonomy")
	for id in ["adult_a","adult_b"]:
		var generated: Dictionary = sim.command("social","generate",{"id":id,"template":"wellbeing_adult","age":26})
		t._check(generated.ok,"generate adult wellbeing fixture "+id+": "+str(generated.get("error","")))
		if not sim.state.social.npcs.has(id): continue
		var npc: Dictionary = sim.state.social.npcs[id]
		npc.age = 26
		npc.gender = "female"
		npc.appearance.gender = "female"
		npc.reproductive_profile = {"can_gestate":true,"produces_sperm":false,"cycling":true}
		npc.location = "bedroom"
		npc.home = "bedroom"
		npc.schedule = []
		npc.money = 1000
		npc.pinned_until = 0
		npc.mind.boundaries.contact = true
		sim.services.npc_agency._cancel(npc,"fixture")
		npc.activity = "rest"
	sim.state.world.location = "bedroom"
	sim.state.economy.cash = 1000
	return sim

func start(sim, id: String = "player") -> void:
	t._check(sim.command("lifecycle","start",{"id":"pregnancy","target":id}).ok,"start wellbeing pregnancy for "+id)

func reject(sim, operation: String, args: Dictionary, label: String) -> void:
	var before: Dictionary = sim.export_snapshot()
	var result: Dictionary = sim.command("pregnancy_wellbeing",operation,args)
	t._check(not result.ok and before==sim.export_snapshot(),label+" is atomic")

func run() -> void:
	_rules_and_queries()
	_symptoms_and_care()
	_accidents()
	_npc_autonomy_and_dialogue()
	_snapshots_and_endings()
	_postpartum()

func _rules_and_queries() -> void:
	var sim = fresh()
	var before: Dictionary = sim.export_snapshot()
	t._check(sim.services.pregnancy_wellbeing.view().is_empty(),"no pregnancy has no symptoms")
	t._check(sim.services.pregnancy_wellbeing.conversation_line("adult_a").is_empty(),"nonpregnant NPC has no pregnancy remarks")
	t._check(before==sim.export_snapshot(),"reading absent wellbeing consumes no state or RNG")
	reject(sim,"rest",{},"nonpregnant self-care request")
	start(sim)
	var service = sim.services.pregnancy_wellbeing
	t._check(service.view().active,"new pregnancy immediately activates wellbeing")
	var condition := {"started":480,"end_time":sim.calendar.add_months(480,9)}
	for month in range(9):
		t._check(service.month(condition,sim.calendar.add_months(480,month))==month+1,"symptoms follow calendar month %d" % (month+1))
	t._check(Model.config().symptoms.size()==15,"fifteen symptom groups have authored rules")
	var valid := true
	for spec in Model.config().symptoms.values(): valid = valid and spec.months.size()==9 and spec.frequency>0 and spec.frequency<=1
	t._check(valid,"all symptom profiles cover nine months with individual susceptibility")
	before = sim.export_snapshot()
	service.view()
	service.conversation_line("player")
	t._check(before==sim.export_snapshot(),"active symptom and conversation queries are pure")

func _symptoms_and_care() -> void:
	var sim = fresh()
	start(sim)
	var service = sim.services.pregnancy_wellbeing
	var record: Dictionary = sim.state.pregnancy_wellbeing.records.player
	var initial_bladder := float(sim.state.player.needs.bladder)
	t._check(sim.command("clock","advance",{"minutes":15}).ok,"pregnancy symptoms tick in main runtime")
	t._check(sim.state.player.needs.bladder<initial_bladder-0.5,"pregnancy urgency consumes actual player bladder comfort")
	sim.state.world.location = "global_map"
	reject(sim,"toilet",{},"toilet in an unavailable location")
	record = sim.state.pregnancy_wellbeing.records.player
	sim.state.world.location = "bathroom"
	t._check(sim.command("pregnancy_wellbeing","toilet").ok and service.view().bladder==100,"pregnancy toilet action restores bladder comfort")
	record.soiled = true
	t._check(sim.command("pregnancy_wellbeing","cleanup").ok and not record.soiled,"self-care cleans up without altering pregnancy")
	t._check(sim.command("pregnancy_wellbeing","rest").ok and record.relief_until>sim.state.clock.total_minutes,"quiet rest provides temporary symptom relief")
	record.soiled = true
	t._check(sim.command("world","shower").ok and not sim.state.pregnancy_wellbeing.records.player.soiled,"ordinary shower integrates with pregnancy hygiene")
	sim.state.world.location = "global_map"
	var cash := int(sim.state.economy.cash)
	t._check(sim.command("pregnancy_wellbeing","supplies").ok and record.supplies==3 and sim.state.economy.cash==cash-6,"hygiene supplies cost money and are finite")
	reject(sim,"checkup",{},"prenatal consultation outside clinic")
	record = sim.state.pregnancy_wellbeing.records.player
	sim.state.world.location = "clinic"
	t._check(sim.command("pregnancy_wellbeing","checkup").ok and int(record.relief_until)>sim.state.clock.total_minutes,"clinic uses actual prenatal care transaction")
	reject(sim,"checkup",{},"repeated prenatal consultation")
	reject(sim,"cleanup",{"target":"adult_a"},"player cannot force another adult's personal care")

func _accidents() -> void:
	var sim = fresh()
	start(sim)
	var record: Dictionary = sim.state.pregnancy_wellbeing.records.player
	sim.state.player.needs.bladder = 0
	var hygiene := float(sim.state.player.needs.hygiene)
	t._check(sim.command("clock","advance",{"minutes":15}).ok,"full bladder resolves through world clock")
	t._check(record.accidents==1 and record.soiled,"unprotected episode marks clothing for cleanup")
	t._check(sim.state.player.needs.hygiene<hygiene and sim.state.player.needs.bladder>0,"episode changes hygiene and relieves some urgency")
	sim.state.player.needs.bladder = 0
	t._check(sim.command("clock","advance",{"minutes":15}).ok and record.accidents==1,"episode cooldown prevents notification flooding")
	record.last_accident = -10080
	record.supplies = 1
	record.soiled = false
	t._check(sim.command("clock","advance",{"minutes":15}).ok,"protected episode resolves")
	t._check(record.accidents==2 and not record.soiled and record.supplies==0,"absorbent protection is consumed and preserves clothing")
	t._check(sim.state.pregnancy_wellbeing.history.filter(func(event): return event.kind=="accident").size()==2,"episodes have a bounded event history")
	t._check(sim.services.pregnancy_wellbeing.conversation_line("player",true).symptom=="incontinence","personal conversation can explicitly describe a recent incontinence problem")

func _npc_autonomy_and_dialogue() -> void:
	var sim = fresh()
	start(sim,"adult_a")
	var npc: Dictionary = sim.state.social.npcs.adult_a
	var record: Dictionary = sim.state.pregnancy_wellbeing.records.adult_a
	record.bladder = 15.0
	npc.pinned_until = 0
	sim.services.npc_agency._cancel(npc,"fixture")
	t._check(sim.command("clock","advance",{"minutes":15}).ok and not record.selfcare.is_empty(),"NPC reserves its own toilet break without player input")
	t._check(sim.command("clock","advance",{"minutes":5}).ok and record.selfcare.is_empty() and record.bladder==100,"NPC completes bathroom break and releases reservation")
	record.soiled = true
	t._check(sim.command("clock","advance",{"minutes":10}).ok,"NPC notices hygiene discomfort")
	t._check(sim.command("clock","advance",{"minutes":10}).ok and not record.soiled,"NPC privately changes and cleans up")
	npc.pinned_until = 0
	npc.location = "bedroom"
	npc.activity = "rest"
	sim.services.npc_agency._cancel(npc,"fixture")
	var line: Dictionary = sim.services.pregnancy_wellbeing.conversation_line("adult_a")
	t._check(not line.is_empty() and not str(line.text).contains("беремен"),"symptom line does not reveal an unknown pregnancy")
	t._check(sim.command("npc_dialogue","open",{"id":"adult_a"}).ok,"ordinary dialogue opens for symptomatic adult")
	var d: Dictionary = npc.mind.dialogue
	t._check(sim.command("npc_dialogue","choose",{"id":"adult_a","choice":"day","turn":d.turn}).ok,"ordinary daily conversation includes wellbeing")
	t._check(npc.mind.dialogue.utterance.has("wellbeing_line") and npc.mind.dialogue.utterance.text.contains(str(line.text)),"NPC actually voices current symptoms through conversation UI contract")
	record.last_remark = -10080
	npc.pinned_until = 0
	npc.activity = "rest"
	var other: Dictionary = sim.state.social.npcs.adult_b
	other.location = "bedroom"
	other.pinned_until = int(sim.state.clock.total_minutes)+100
	other.activity = "rest"
	t._check(sim.command("clock","advance",{"minutes":15}).ok,"autonomous symptom conversation advances")
	t._check(sim.state.pregnancy_wellbeing.history.any(func(event): return event.kind=="remark" and event.data.listener=="adult_b"),"pregnant NPC speaks to nearby adult without player participation")
	t._check(sim.state.pregnancy_wellbeing.history.any(func(event): return event.kind=="reply" and event.data.target=="adult_b"),"nearby NPC answers with practical support")

func _snapshots_and_endings() -> void:
	var sim = fresh()
	start(sim)
	var before: Dictionary = sim.export_snapshot()
	var clone = Sim.new(0,config())
	t._check(clone.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok,"wellbeing survives a JSON save/load round trip")
	t._check(sim.command("clock","advance",{"minutes":30}).ok and clone.command("clock","advance",{"minutes":30}).ok,"restored pregnancy advances")
	t._check(JSON.parse_string(JSON.stringify(sim.state.pregnancy_wellbeing))==JSON.parse_string(JSON.stringify(clone.state.pregnancy_wellbeing)) and sim.rng.state==clone.rng.state,"restoration retains deterministic symptoms, episodes and game RNG")
	var corrupt: Dictionary = sim.export_snapshot()
	corrupt.state.pregnancy_wellbeing.records.player.bladder = -1
	before = clone.export_snapshot()
	t._check(not clone.restore_snapshot(corrupt).ok and before==clone.export_snapshot(),"invalid wellbeing snapshot is rejected atomically")
	sim.state.conditions["player:pregnancy"].status = "completed"
	t._check(sim.command("clock","advance",{"minutes":1}).ok and not sim.services.pregnancy_wellbeing.view().active,"ending pregnancy clears ongoing symptoms")
	t._check(sim.services.pregnancy_wellbeing.view().symptoms.is_empty(),"ended pregnancy has no stale discomfort modifiers")

func _postpartum() -> void:
	var sim = fresh()
	start(sim,"adult_a")
	var record: Dictionary = sim.state.pregnancy_wellbeing.records.adult_a
	var finish := int(sim.state.conditions["adult_a:pregnancy"].end_time)
	t._check(sim.command("clock","advance",{"minutes":finish-int(sim.state.clock.total_minutes)}).ok,"pregnancy reaches actual lifecycle birth")
	t._check(sim.services.pregnancy_wellbeing.view("adult_a").phase=="postpartum","birth transitions maternal symptoms into postpartum recovery")
	t._check(int(record.postpartum_until)==int(sim.state.clock.total_minutes)+60480,"postpartum recovery has its own six-week game timer")
	record.postpartum_until = int(sim.state.clock.total_minutes)+1
	t._check(sim.command("clock","advance",{"minutes":1}).ok and not sim.services.pregnancy_wellbeing.view("adult_a").active,"postpartum symptoms finish when recovery timer expires")
	var snapshot: Dictionary = sim.export_snapshot()
	sim.services.pregnancy_wellbeing.view("adult_a")
	t._check(snapshot==sim.export_snapshot(),"completed maternal recovery remains read-only in UI")
