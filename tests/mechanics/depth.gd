extends RefCounted
const Extended = preload("res://scripts/mechanics/extended_simulation.gd")
const Calendar = preload("res://scripts/mechanics/core/calendar.gd")
var t
func _init(parent) -> void: t = parent

func run() -> void:
	_education()
	_clubs()
	_digital()
	_quests()

func _education() -> void:
	var sim = t.fresh({"settings":{"start_minutes":480}})
	var id: String = sim.services.education.available()[0]
	var before: Dictionary = sim.export_snapshot()
	sim.services.education.view(id)
	t._check(sim.export_snapshot() == before,"course inspection does not create progress or consume RNG")
	t.command(sim,"education","homework",{"id":id})
	before = sim.export_snapshot()
	t._check(not sim.command("world","homework",{"id":id}).ok and before == sim.export_snapshot(),"world and education share the same daily homework limit")
	var grade := int(sim.state.world.education.grade)
	t.command(sim,"education","practice",{"id":id})
	t._check(int(sim.state.world.education.grade) == grade,"practice deepens mastery without farming grades")
	t.command(sim,"education","project",{"id":id,"approach":"research"})
	before = sim.export_snapshot()
	t._check(not sim.command("education","project",{"id":id,"approach":"research"}).ok and before == sim.export_snapshot(),"project stages cannot be rushed in one day")
	for day in [1,2]:
		sim.state.clock = Calendar.snapshot(day*1440+480)
		sim.state.player.needs.energy = 100
		t.command(sim,"education","homework",{"id":id})
		before = sim.export_snapshot()
		t._check(not sim.command("education","project",{"id":id,"approach":"applied"}).ok and before == sim.export_snapshot(),"project specialization remains committed across days")
		t.command(sim,"education","project",{"id":id})
	# Attendance is normally delivered by World; isolate certificate prerequisites here.
	for index in range(3): sim.services.education.attend(id)
	t._check(sim.services.education.view(id).can_assess,"attendance, assignments and project unlock assessment together")
	before = sim.export_snapshot()
	t._check(not sim.command("education","assess",{"id":id}).ok and before == sim.export_snapshot(),"assessment requires the actual teaching location")
	sim.state.world.location = sim.catalog.lessons[id].location
	t.command(sim,"education","assess",{"id":id})
	t._check(sim.state.world.education.certificates[id] == 1 and sim.state.world.flags.get("qualified_"+str(sim.catalog.lessons[id].skill),false),"certificate creates a durable occupational qualification")
	before = sim.export_snapshot()
	t._check(not sim.command("education","assess",{"id":id}).ok and before == sim.export_snapshot(),"assessment pays once per course")
	var replay = t.fresh({"settings":{"start_minutes":480}})
	t._check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok,"subject progress and certificate survive JSON save/load")
	var bad := before.duplicate(true)
	bad.state.world.education.courses[id].project = 99
	t._check(not replay.restore_snapshot(bad).ok,"invalid project stages cannot enter a loaded world")
	sim.state.clock = Calendar.snapshot((int(sim.state.clock.day_index)+7)*1440+480)
	t.command(sim,"education","next_term",{"id":id})
	t._check(sim.services.education.view(id).certificate == 1 and sim.services.education.view(id).project == 0,"next term resets coursework while keeping qualifications")

func _club():
	var sim = t.fresh({"settings":{"start_minutes":1440+1079,"start_cash":5000}})
	t.command(sim,"social","generate",{"id":"worker"})
	var npc: Dictionary = sim.state.social.npcs.worker
	npc.schedule = []
	npc.location = "training_center"
	npc.home = "training_center"
	npc.activity = "rest"
	npc.needs.energy = 100
	npc.needs.satiety = 100
	t.command(sim,"social","relationship",{"id":"worker","changes":{"trust":60,"affinity":60}})
	t.command(sim,"organizations","create",{"id":"creative_collective"})
	t.command(sim,"organizations","recruit",{"id":"creative_collective","npc":"worker"})
	t.command(sim,"organizations","assign",{"id":"creative_collective","npc":"worker","task":"clean"})
	t.command(sim,"institutions","policy",{"id":"creative_collective","wage":60})
	return sim

func _clubs() -> void:
	var sim = _club()
	var group: Dictionary = sim.state.organizations.creative_collective
	var money := int(sim.state.social.npcs.worker.money)
	var budget := int(group.budget)
	t.command(sim,"clock","advance",{"minutes":1})
	t._check(group.work.sessions.has("worker") and int(group.budget) == budget-60 and int(sim.state.social.npcs.worker.money) == money,"hourly club wage is reserved, not paid before work")
	t.command(sim,"clock","advance",{"minutes":30})
	t._check(int(group.work.sessions.get("worker",{}).get("worked",0)) == 30,"club progress follows actual minutes at the workplace")
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var replay = t.fresh({"settings":{"start_minutes":1440+1079,"start_cash":5000}})
	t._check(replay.restore_snapshot(checkpoint).ok,"in-progress club work survives JSON restore")
	t.command(sim,"organizations","assign",{"id":"creative_collective","npc":"worker","task":"idle"})
	t.command(replay,"organizations","assign",{"id":"creative_collective","npc":"worker","task":"idle"})
	t._check(int(group.budget) == budget-30 and int(sim.state.social.npcs.worker.money) == money+30,"interruption pays completed half-hour and refunds the remaining reservation")
	t._check(JSON.parse_string(JSON.stringify(sim.export_snapshot())) == JSON.parse_string(JSON.stringify(replay.export_snapshot())),"interrupted club shift replays exactly after a save")
	t._check(group.work.sessions.is_empty() and not group.work.history.is_empty() and group.work.history.back().worked == 30,"assignment change closes the prior session once")
	var continued = t.fresh({"settings":{"start_minutes":1440+1079,"start_cash":5000}})
	t._check(continued.restore_snapshot(checkpoint).ok,"restore club schedule with JSON numeric weekdays")
	t.command(continued,"clock","advance",{"minutes":30})
	t._check(continued.state.organizations.creative_collective.work.history.any(func(entry): return entry.worked == 60 and entry.paid == 60),"saved club work finishes and pays the agreed hourly wage")

	sim = _club()
	sim.state.social.npcs.worker.schedule = [{"hours":[1080,1200],"weekdays":[1],"location":"training_center","activity":"study"}]
	t.command(sim,"clock","advance",{"minutes":31})
	t._check(sim.state.organizations.creative_collective.work.sessions.is_empty(),"mandatory education takes priority over optional club production")

func _digital() -> void:
	var sim = Extended.new(17,{"settings":{"start_minutes":480}})
	sim.state.world.equipment.append("computer")
	sim.state.player.skills.computing = 150
	var before: Dictionary = sim.export_snapshot()
	var careful: Dictionary = sim.services.digital.preview("recovery","careful").data
	var fast: Dictionary = sim.services.digital.preview("recovery","fast").data
	t._check(careful.minutes > fast.minutes and careful.chance > fast.chance and careful.reward < fast.reward and careful.trace_scale < fast.trace_scale,"digital strategies trade time and reward for chance and trace")
	t._check(sim.export_snapshot() == before,"digital strategy preview is pure")
	t.command(sim,"digital","scan",{"id":"recovery"})
	before = sim.export_snapshot()
	t._check(not sim.command("digital","resolve",{"id":"recovery","token":sim.state.digital.pending.token,"approach":"invented"}).ok and sim.export_snapshot() == before,"invalid strategy preserves prepared report and RNG")
	var found := false
	for seed_value in range(100):
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		var roll := probe.randf()
		var chance := float(sim.services.digital.preview("recovery","fast").data.chance)
		if roll >= chance and roll < chance+0.15:
			sim.rng.seed = seed_value
			found = true
			break
	t._check(found,"fixture selects a reproducible partial-result draw")
	var result: Dictionary = t.command(sim,"digital","resolve",{"id":"recovery","token":sim.state.digital.pending.token,"approach":"fast"})
	t._check(result.data.partial and not result.data.success and int(result.data.reward) == floori(float(fast.reward)*0.25),"partial digital result pays only one quarter")
	t._check(not sim.state.world.flags.get("digital_job_completed",false),"partial work does not claim the full-success milestone")

func _quests() -> void:
	var extensions := {"quests":{"test_commitment":{"objectives":{"study":2},"bindings":{"study":[{"module":"education","operation":"practice","different_days":true}]},"rewards":[{"kind":"money","amount":25}]}}}
	var sim = t.fresh(extensions)
	var id: String = sim.services.education.available()[0]
	t.command(sim,"events","start_quest",{"id":"test_commitment"})
	t.command(sim,"education","practice",{"id":id})
	sim.command("education","practice",{"id":id})
	t._check(sim.state.journal.quests.test_commitment.objectives.study == 1,"failed/repeated commands do not farm quest progress")
	sim.state.clock = Calendar.snapshot((int(sim.state.clock.day_index)+1)*1440+480)
	t.command(sim,"education","practice",{"id":id})
	t._check(sim.state.journal.quests.test_commitment.status == "completed","actual activity across different days completes the quest")
	var cash := int(sim.state.economy.cash)
	t.command(sim,"events","claim_quest",{"id":"test_commitment"})
	t._check(sim.state.economy.cash == cash+25 and not sim.command("events","claim_quest",{"id":"test_commitment"}).ok,"quest reward pays exactly once")
	var before: Dictionary = sim.export_snapshot()
	var replay = t.fresh(extensions)
	t._check(replay.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok,"quest uniqueness markers survive JSON restore")
	before.state.journal.quests.test_commitment.seen.study.append("forged")
	t._check(not replay.restore_snapshot(before).ok,"oversized uniqueness history is rejected")
