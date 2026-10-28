extends RefCounted
const Main = preload("res://scripts/gameplay/main_simulation.gd")
const Facets = preload("res://scripts/mechanics/core/human_validation.gd")
var t
func _init(parent) -> void: t = parent
func fresh():
	var template := {"age":25,"home":"bedroom","role":"worker","money":100,"personalities":["calm"],"goals":["community"],"schedule":[],"activities":[],"gender":"female","attracted_to":["female"],"traits":{"sociability":50}}
	var sim = Main.new(551,{"npc_templates":{"pressure_test":template},"antagonism_rules":{"interval":181,"chance":1.0}})
	sim.state.clock = sim.calendar.snapshot(480)
	sim.state.economy.cash = 1000
	t.check(sim.command("npc_agency","enable",{}).ok,"pressure fixture enables actual NPC life")
	for id in ["bully","victim","friend","bystander"]:
		t.check(sim.command("social","generate",{"id":id,"template":"pressure_test"}).ok,"pressure NPC generated: "+id)
		var facets := {}
		for key in Facets.FACETS: facets[key] = 50
		if id == "bully": facets.merge({"sincerity":0,"fairness":0,"greed_avoidance":0,"gentleness":0,"forgivingness":0,"social_boldness":100},true)
		else: facets.merge({"fairness":100,"sincerity":100,"gentleness":100,"forgivingness":100,"greed_avoidance":100,"social_boldness":100 if id == "friend" else 10},true)
		sim.command("npc_personalities","configure",{"id":id,"facets":facets,"values":{"benevolence":0 if id == "bully" else 100,"achievement":100 if id == "bully" else 0}})
		var npc: Dictionary = sim.state.social.npcs[id]
		npc.location = "city_park"; npc.activity = "rest"; npc.mind.active = {}; npc.pinned_until = 0
		npc.needs.energy = 100
		sim.state.social.contacts.append(id)
	sim.state.world.location = "city_park"
	sim.state.world.flags.chapter_one_complete = true
	sim.state.antagonism.next_check = 99999
	return sim
func snapshot(sim) -> Dictionary: return JSON.parse_string(JSON.stringify(sim.export_snapshot()))
func stage(sim,kind: String,target: String = "player") -> String:
	var r: Dictionary = sim.command("antagonism","stage",{"id":"bully","kind":kind,"target":target})
	t.check(r.ok,"stage "+kind+": "+str(r.get("error","")))
	if not r.ok: return ""
	for npc in sim.state.social.npcs.values(): npc.pinned_until = int(sim.state.clock.total_minutes)+15000
	return str(r.data.id)
func act(sim,id: String,choice: String,ally: String = "") -> Dictionary:
	var r: Dictionary = sim.command("antagonism","respond",{"id":id,"choice":choice,"ally":ally})
	t.check(r.ok,"response "+choice+": "+str(r.get("error","")))
	return r
func refused(sim,id: String,choice: String) -> void:
	var before := snapshot(sim)
	t.check(not sim.command("antagonism","respond",{"id":id,"choice":choice}).ok and snapshot(sim) == before,"rejected response is atomic: "+choice)
func run() -> void:
	_motives()
	_money_and_evidence()
	_harm_and_support()
	_slander_and_sabotage()
	_dialogue_and_restore()

func _motives() -> void:
	var sim = fresh()
	var before := snapshot(sim)
	t.check(sim.services.antagonism.disposition("bully").dominance > sim.services.antagonism.disposition("friend").dominance,"individual facets produce different hostile motives")
	t.check(sim.services.antagonism.opportunity("friend","player","extortion").blocked == "insufficient_motive","a helpful NPC does not become a predator merely because a victim is available")
	sim.services.antagonism.inspect()
	t.check(before == snapshot(sim),"pressure inspection does not create bonds or consume RNG")
	var forecast: Dictionary = sim.services.planning.forecast([{"module":"clock","operation":"advance","args":{"minutes":10}}])
	t.check(forecast.ok and forecast.data.complete and forecast.data.social_risk_unmodelled and before==snapshot(sim),"planner remains usable and explicitly excludes new unpredictable attacks without revealing RNG")
	sim.state.world.location = "bedroom"
	t.check(sim.services.antagonism.opportunity("bully","player","intimidation").blocked == "no_opportunity","hostile NPC cannot reach into an unrelated home")
	sim.state.world.location = "city_park"
	sim.state.world.flags.chapter_one_complete = false
	t.check(not sim.command("antagonism","stage",{"id":"bully","kind":"intimidation"}).ok,"hostile free-play does not interrupt the prologue")
	sim.state.world.flags.chapter_one_complete = true
	sim.state.antagonism.next_check = 0
	sim.state.clock = sim.calendar.snapshot(542)
	t.check(sim.command("clock","advance",{"minutes":1}).ok and sim.state.antagonism.cases.size()==1,"autonomous scheduler selects and begins a motivated local threat")
	t.check(sim.state.social.messages.size()>0,"threat produces a visible phone notice before damage")

func _money_and_evidence() -> void:
	var sim = fresh()
	var id := stage(sim,"extortion")
	var cash := int(sim.state.economy.cash); var npc_cash := int(sim.state.social.npcs.bully.money)
	act(sim,id,"pay")
	t.check(sim.state.economy.cash==cash-45 and sim.state.social.npcs.bully.money==npc_cash+45,"extortion transfers real money rather than minting a reward")
	t.check(sim.state.antagonism.actors.bully.impunity==20,"payment teaches the extorter that pressure is profitable")
	refused(sim,id,"pay")
	sim = fresh(); id = stage(sim,"intimidation")
	refused(sim,id,"report")
	act(sim,id,"document")
	refused(sim,id,"document")
	var energy := float(sim.state.player.needs.energy)
	sim.state.player.needs.energy = 0
	refused(sim,id,"investigate")
	sim.state.player.needs.energy = energy
	act(sim,id,"investigate")
	var before := snapshot(sim)
	var replay = fresh(); t.check(replay.restore_snapshot(before).ok,"threat and evidence restore through JSON")
	act(sim,id,"report"); act(replay,id,"report")
	t.check(snapshot(sim)==snapshot(replay),"institutional response replays with saved RNG")
	refused(sim,id,"report")

func _harm_and_support() -> void:
	var sim = fresh()
	var id := stage(sim,"intimidation","victim")
	var c: Dictionary = sim.state.antagonism.cases[id]
	t.check(c.witnesses.any(func(w): return w.id=="friend" and w.stance=="support") and c.witnesses.any(func(w): return w.id=="bystander" and w.stance=="silent"),"brave support and frightened silence coexist among witnesses")
	var hp := float(sim.state.social.npcs.victim.health)
	t.check(sim.command("clock","advance",{"minutes":360}).ok,"NPC-on-NPC threat reaches its deadline")
	t.check(sim.state.social.npcs.victim.health < hp and sim.state.social.npcs.victim.injuries.has("body"),"unopposed violence causes actual health loss and injury")
	t.check(sim.services.npc_relationships.view("victim","bully").grievance>0,"victim remembers this particular aggressor")
	act(sim,id,"document"); act(sim,id,"investigate"); act(sim,id,"expose")
	t.check(sim.state.social.npcs.victim.health < hp,"later exposure does not magically heal injury")
	sim = fresh()
	sim.state.social.npcs.bystander.psychology.values.benevolence = 0
	sim.services.npc_relationships._bond("bystander","bully").trust = 30
	id = stage(sim,"intimidation")
	t.check(sim.command("clock","advance",{"minutes":360}).ok and sim.state.antagonism.cases[id].loss==9,"present accomplice increases actual harm while the supporter mitigates it")
	sim = fresh(); id = stage(sim,"extortion")
	sim.services.npc_relationships._bond("friend","player").trust = 30
	act(sim,id,"ally","friend")
	t.check(sim.state.antagonism.cases[id].ally=="friend","trusted willing ally participates in this specific conflict")
	refused(sim,id,"ally")
	sim.state.world.location = "bedroom"
	act(sim,id,"evade")
	t.check(sim.state.antagonism.cases[id].status=="resolved" and sim.state.antagonism.cases[id].loss==0,"leaving the encounter provides a real escape")
	sim = fresh(); id = stage(sim,"intimidation")
	sim.command("preferences","content_tag",{"id":"conflict","enabled":false})
	t.check(sim.command("clock","advance",{"minutes":360}).ok and sim.state.antagonism.cases[id].status=="cancelled","disabling conflict cancels a pending consequence")

func _slander_and_sabotage() -> void:
	var sim = fresh()
	sim.services.npc_relationships.harm("bully","player",80,"fixture_grievance")
	var id := stage(sim,"slander")
	t.check(sim.command("clock","advance",{"minutes":720}).ok,"rumor campaign reaches its audience")
	t.check(sim.services.antagonism.rumor_penalty("friend","player")>0,"rumor changes reception only among its actual audience")
	act(sim,id,"document"); act(sim,id,"investigate"); act(sim,id,"expose")
	t.check(sim.services.antagonism.rumor_penalty("friend","player")==0 and sim.services.npc_relationships.view("friend","bully").grievance>0,"proof clears the rumor and identifies its source to witnesses")
	sim = fresh()
	sim.state.world.flags.chapter_one_complete = false
	sim.state.world.location = "bedroom"; sim.state.world.equipment = ["computer"]
	var project := ""
	for offer in sim.services.computer.board():
		if not offer.locked:
			project = str(offer.id); break
	t.check(sim.command("computer","take_project",{"id":project}).ok,"sabotage has an actual accepted project")
	sim.state.world.flags.chapter_one_complete = true; sim.state.world.location = "city_park"
	id = stage(sim,"sabotage")
	var quality := float(sim.state.computer.projects[project].quality)
	t.check(sim.command("clock","advance",{"minutes":720}).ok,"project sabotage resolves")
	t.check(sim.state.computer.projects[project].quality==quality-12 and sim.state.computer.projects[project].bugs==1,"sabotage affects actual acceptance criteria")
	var saved := snapshot(sim)
	var restored = fresh()
	t.check(restored.restore_snapshot(saved).ok,"resolved sabotage and damaged project restore together")

func _dialogue_and_restore() -> void:
	var sim = fresh()
	var id := stage(sim,"extortion")
	t.check(sim.command("npc_dialogue","open",{"id":"bully","channel":"message"}).ok,"threat contact can be opened in existing phone UI")
	var view: Dictionary = sim.services.npc_dialogue.present("bully")
	var choice := "pressure:"+id+":document"
	t.check(view.choices.any(func(row): return row.id == choice),"existing conversation offers response buttons without a new UI screen")
	t.check(sim.command("npc_dialogue","choose",{"id":"bully","choice":choice,"turn":view.turn}).ok,"phone choice executes real evidence action")
	t.check(sim.state.antagonism.cases[id].documented,"phone response persists evidence")
	var before := snapshot(sim)
	t.check(not sim.command("npc_dialogue","choose",{"id":"bully","choice":choice,"turn":view.turn}).ok and snapshot(sim)==before,"stale phone choice cannot repeat a response")
	for field in ["evidence","actor","deadline"]:
		var bad := snapshot(sim)
		bad.state.antagonism.cases[id][field] = {"evidence":99,"actor":"unknown","deadline":0}[field]
		t.check(not sim.restore_snapshot(bad).ok and snapshot(sim)==before,"corrupt pressure save is rejected atomically: "+field)
