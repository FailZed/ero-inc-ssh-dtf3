extends RefCounted
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
const Base = preload("res://scripts/mechanics/simulation.gd")
const Utility = preload("res://scripts/mechanics/core/utility_ai.gd")
var t

func _init(runner) -> void:
	t = runner

func _template(goal: String = "creativity") -> Dictionary:
	return {"age": 25, "home": "bedroom", "money": 100, "role": "worker",
		"personalities": ["calm"], "origins": ["local"], "goals": [goal],
		"preferences": ["books"], "schedule": [], "activities": ["read", "walk"],
		"traits": {"bravery": 60, "responsibility": 70, "sociability": 65, "romantic": 40, "loyalty": 80, "cunning": 30}}

func fresh(goal: String = "creativity", count: int = 1):
	var sim = Life.new(42, _test_catalog(goal))
	t._check(sim.configuration_error.is_empty(), "life catalog is valid: " + sim.configuration_error)
	for i in range(count):
		t.command(sim, "social", "generate", {"id": "life_%d" % i, "template": "free"})
		# Explicit novice fixture; production workers receive age-appropriate starting experience.
		sim.state.social.npcs["life_%d" % i].skills.study = 0
	t.command(sim, "npc_agency", "enable")
	var facets := {}
	for domain in sim.catalog.human_dimensions.values():
		for facet in domain.facets: facets[facet] = 50
	for i in range(count):
		var id := "life_%d" % i
		t.command(sim, "npc_personalities", "configure", {"id": id, "facets": facets})
		t.command(sim, "npc_agency", "set_aspiration", {"id": id, "goal": goal})
		sim.services.npc_agency._cancel(sim.state.social.npcs[id], "fixture_goal")
	sim.services.npc_agency._build_index()
	for i in range(count): sim.services.npc_agency._choose(sim.state.social.npcs["life_%d" % i])
	return sim

func _test_catalog(goal: String) -> Dictionary:
	# Short goals exercise completion; the shipped study catalog uses multi-day goals.
	return {"settings": {"start_minutes": 480}, "npc_templates": {"free": _template(goal)},
		"agency_aspirations": {"creativity": {"label": "Test project", "stages": [{"action": "create", "minutes": 120}, {"action": "create", "minutes": 240}, {"action": "publish", "minutes": 120}]}}}

func advance(sim, minutes: int) -> void:
	t.command(sim, "clock", "advance", {"minutes": minutes})

func run() -> void:
	curves_and_inspection()
	production_isolation()
	goals_and_prerequisites()
	needs_and_commitments()
	travel_and_interruptions()
	h04_invitations_and_tenancy()
	directed_memories_and_emotions()
	social_autonomy()
	player_influence()
	constraints_and_personality()
	validation_and_replay()
	population_study()

func curves_and_inspection() -> void:
	for kind in ["linear", "quadratic", "exponential", "sigmoid", "inverse"]:
		t._check(Utility.curve(-10, kind) >= 0 and Utility.curve(10, kind) <= 1, "utility curve stays normalized: " + kind)
	t._check(is_equal_approx(Utility.combine([0.0, 1.0], [1.0, 3.0]), 0.75), "utility weights are normalized")
	t._check(Utility.choose([{"id": "a", "score": 0.5}, {"id": "b", "score": 0.52}], "a").id == "a", "hysteresis prevents near-tie switching")
	t._check(Utility.choose([{"id": "a", "score": 1.0, "available": false}, {"id": "b", "score": 0.1}]).id == "b", "unavailable option cannot win utility")
	var sim = fresh()
	var before: Dictionary = sim.export_snapshot()
	var inspection: Dictionary = sim.services.npc_agency.inspect("life_0")
	t._check(not inspection.candidates.is_empty() and inspection.plan == ["create"], "inspection exposes action scores and a concrete goal plan")
	t._check(sim.export_snapshot() == before, "inspection changes neither world nor RNG")

func production_isolation() -> void:
	var base = Base.new(77)
	var study = Life.new(77)
	t.command(base, "social", "generate", {"id": "a"})
	t.command(study, "social", "generate", {"id": "a"})
	t._check(not base.catalog.has("agency_actions") and not base.services.has("npc_agency"), "production simulation does not load the life extension")
	t._check(not study.state.social.npcs.a.has("mind"), "life extension requires explicit activation")
	advance(base, 180)
	advance(study, 180)
	t._check(base.state == study.state and str(base.rng.state) == str(study.rng.state), "inactive extension preserves existing simulation and random stream")
	var restored = Base.new(77)
	t._check(restored.restore_snapshot(base.export_snapshot()).ok, "production snapshot contract still round-trips")

func goals_and_prerequisites() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.life_0
	t._check(npc.mind.active.action == "create" and npc.mind.aspiration.progress == 0, "creative aspiration starts a real timed project")
	advance(sim, 59)
	t._check(not npc.skills.has("journalism") and npc.mind.aspiration.progress == 0, "starting an action does not grant its completion rewards")
	advance(sim, 1)
	t._check(npc.skills.journalism == 4 and npc.mind.aspiration.progress == 60, "completed project advances skill and goal")
	advance(sim, 60)
	t._check(npc.mind.aspiration.stage == 1 and npc.mind.aspiration.milestones == 1, "goal crosses a milestone exactly once")
	t._check(npc.mind.satisfaction == 12, "repeating the same daily want does not multiply its reward")
	advance(sim, 480)
	t._check(npc.mind.aspiration.completed and npc.mind.aspiration.milestones == 3, "NPC independently completes a multi-stage creative aspiration")
	var completed := int(npc.mind.aspiration.milestones)
	advance(sim, 120)
	t._check(npc.mind.aspiration.milestones == completed, "completed aspiration does not keep awarding milestones")
	advance(sim, 1800)
	t._check(not npc.mind.aspiration_history.is_empty() and npc.mind.aspiration.id != "creativity", "completed long-term goal is remembered and followed by a new aspiration")
	var prerequisite = fresh()
	var learner: Dictionary = prerequisite.state.social.npcs.life_0
	learner.mind.aspiration.stage = 2
	learner.mind.aspiration.milestones = 2
	learner.skills.clear()
	t._check(prerequisite.services.npc_agency.inspect("life_0").plan == ["create", "publish"], "planner inserts skill-building before blocked publication")
	var scores: Array = prerequisite.services.npc_agency.inspect("life_0").candidates
	for candidate in scores:
		if candidate.id == "publish": t._check(not candidate.available and candidate.blocked == "skill_prerequisite", "high-value goal cannot bypass skill prerequisite")
	var other = fresh("career")
	t._check(other.state.social.npcs.life_0.mind.active.action == "practice", "career-minded NPC prepares a skill instead of copying creative behavior")

func needs_and_commitments() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.life_0
	npc.needs.energy = 5
	advance(sim, 15)
	t._check(npc.mind.active.action == "sleep" and npc.decision.reason == "urgent_need", "exhaustion interrupts personal ambition")
	t._check(not npc.skills.has("journalism"), "interrupted project grants no unearned skill")
	advance(sim, 120)
	t._check(npc.needs.energy > 60 and npc.mind.active.action != "sleep", "NPC resumes life after satisfying emergency need")
	var work = fresh("career")
	var worker: Dictionary = work.state.social.npcs.life_0
	worker.schedule = [{"activity": "work", "location": "global_map", "hours": [480, 600], "mandatory": true}]
	advance(work, 15)
	t._check(worker.mind.active.action == "work" and worker.decision.committed, "mandatory shift takes priority over a free-time goal")
	advance(work, 105)
	t._check(worker.money == 118 and worker.skills.get("journalism",0) == 3, "shift pays only productive time after travel and stops at its closing boundary")
	var hygiene = fresh()
	hygiene.state.social.npcs.life_0.needs.hygiene = 0
	advance(hygiene, 15)
	t._check(hygiene.state.social.npcs.life_0.mind.active.action == "wash", "severely neglected hygiene causes a concrete corrective action")
	var night = fresh()
	var sleeper: Dictionary = night.state.social.npcs.life_0
	advance(night, 24 * 60)
	t._check(int(sleeper.mind.completed_actions.get("sleep", 0)) >= 3, "ambition does not replace a full night with a single short sleep")
	var shift = fresh()
	var night_worker: Dictionary = shift.state.social.npcs.life_0
	night_worker.schedule = [{"activity": "work", "location": "global_map", "hours": [1320, 120], "mandatory": true}]
	advance(shift, 14 * 60 + 15)
	t._check(night_worker.mind.active.action == "work" and night_worker.decision.reason == "schedule", "overnight shift takes priority over default bedtime")

func travel_and_interruptions() -> void:
	var sim = fresh("community", 2)
	var first: Dictionary = sim.state.social.npcs.life_0
	var second: Dictionary = sim.state.social.npcs.life_1
	second.location = "global_map"
	second.mind.active = {}
	first.mind.active = {}
	advance(sim, 15)
	t._check(first.location == "bedroom" and first.mind.active.phase == "travel", "NPC does not teleport to its social destination")
	advance(sim, 15)
	t._check(first.location == "global_map", "travel moves the NPC only after travel time")
	var pinned = fresh()
	var guest: Dictionary = pinned.state.social.npcs.life_0
	guest.pinned_until = 600
	guest.location = "global_map"
	advance(pinned, 60)
	t._check(guest.location == "global_map" and guest.mind.active.is_empty() and not guest.skills.has("journalism"), "player invitation interrupts work without teleporting or awarding it")
	advance(pinned, 60)
	t._check(not guest.mind.active.is_empty(), "NPC replans when external invitation ends")
	var poor = fresh()
	var hungry: Dictionary = poor.state.social.npcs.life_0
	hungry.money = 0
	hungry.needs.satiety = 0
	advance(poor, 45)
	t._check(hungry.needs.satiety > 15 and hungry.money == 0, "subsistence fallback avoids endless hunger without creating money")

func h04_invitations_and_tenancy() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.life_0
	sim.services.npc_agency._cancel(npc,"h04_fixture")
	npc.location = "global_map"
	npc.activity = "create"
	npc.pinned_until = 0
	var work_started := int(sim.state.clock.total_minutes)
	npc.mind.active = {"action":"create","phase":"action","destination":"global_map","partner":"","reason":"needs_and_personality","started":work_started,"due":work_started+30}
	var skills_before: Dictionary = npc.skills.duplicate(true)
	sim.services.social.relationship("life_0","player").trust = 25.0
	var origin := str(npc.location)
	var route: Dictionary = sim.services.npc_agency._route(npc,origin,str(sim.state.world.location))
	var started := int(sim.state.clock.total_minutes)
	var accepted: Dictionary = t.command(sim,"social","invite",{"id":"life_0","minutes":60})
	t._check(accepted.ok and npc.location == origin and npc.activity == "appointment_travel", "remote invitation begins a real journey without teleporting")
	t._check(npc.skills==skills_before, "the interrupted NPC action grants no early skill reward")
	var visit: Dictionary = sim.state.social.appointments.back()
	t._check(int(visit.minute)==started+int(route.minutes) and int(npc.pinned_until)==int(visit.minute)+61 and npc.mind.active.is_empty(), "invitation reserves travel and visit through the existing planner")
	var pending: Dictionary = sim.export_snapshot()
	var restored = fresh()
	t._check(restored.restore_snapshot(pending).ok, "pending invitation survives snapshot restore")
	var malformed: Dictionary = pending.duplicate(true)
	malformed.state.social.appointments.back().erase("kind")
	var restored_before: Dictionary = restored.export_snapshot()
	t._check(not restored.restore_snapshot(malformed).ok and restored.export_snapshot()==restored_before, "duration without invitation kind is rejected atomically on restore")
	malformed = pending.duplicate(true)
	malformed.state.social.appointments.back().duration = -1
	t._check(not restored.restore_snapshot(malformed).ok and restored.export_snapshot()==restored_before, "invalid invitation duration is rejected atomically on restore")
	advance(sim,int(route.minutes)-1)
	t._check(npc.location == origin, "guest stays at the origin until travel completes")
	advance(sim,1)
	t._check(npc.location == sim.state.world.location and visit.status == "pending", "guest arrives through the planner and remains for the booked visit")
	advance(sim,60)
	t._check(visit.status == "met" and int(npc.pinned_until)<=int(sim.state.clock.total_minutes), "invitation ends after the requested duration and releases the reservation")
	advance(restored,int(route.minutes)+60)
	t._check(restored.export_snapshot()==sim.export_snapshot(), "restored pending invitation replays the same arrival and completion")

	var left = fresh()
	var leaving_guest: Dictionary = left.state.social.npcs.life_0
	left.services.npc_agency._cancel(leaving_guest,"h04_fixture")
	leaving_guest.location = "global_map"
	leaving_guest.activity = "rest"
	leaving_guest.pinned_until = 0
	left.services.social.relationship("life_0","player").trust = 25.0
	t.command(left,"social","invite",{"id":"life_0","minutes":60})
	t.command(left,"world","travel",{"id":"apartment_hall"})
	t.command(left,"world","travel",{"id":"global_map"})
	advance(left,1)
	t._check(left.state.social.appointments.back().status=="cancelled" and int(leaving_guest.pinned_until)<=int(left.state.clock.total_minutes), "player departure cancels and releases the pending invitation")

	var busy = fresh()
	var guest: Dictionary = busy.state.social.npcs.life_0
	busy.services.npc_agency._cancel(guest,"h04_fixture")
	guest.location = "global_map"
	guest.activity = "rest"
	guest.pinned_until = 0
	busy.services.social.relationship("life_0","player").trust = 25.0
	var clock: Dictionary = busy.state.clock
	guest.schedule = [{"activity":"work","location":"global_map","hours":[int(clock.minute_of_day)+30,int(clock.minute_of_day)+90],"weekdays":[int(clock.weekday)],"mandatory":true}]
	var before: Dictionary = busy.export_snapshot()
	var rng_before: int = busy.rng.state
	var rejected: Dictionary = busy.command("social","invite",{"id":"life_0","minutes":60})
	t._check(not rejected.ok and rejected.error=="invitation_calendar_conflict" and busy.export_snapshot()==before and busy.rng.state==rng_before, "calendar conflict rejects invitation without changing state or RNG")

	var long_visit = fresh()
	var long_guest: Dictionary = long_visit.state.social.npcs.life_0
	long_visit.services.npc_agency._cancel(long_guest,"h04_fixture")
	long_guest.location = "global_map"
	long_guest.activity = "rest"
	long_guest.pinned_until = 0
	long_visit.services.social.relationship("life_0","player").trust = 25.0
	var long_route: Dictionary = long_visit.services.npc_agency._route(long_guest,"global_map",str(long_visit.state.world.location))
	accepted = long_visit.command("social","invite",{"id":"life_0","minutes":1440})
	t._check(not long_route.is_empty() and int(long_route.minutes)>0 and accepted.ok,"24-hour invitation accepts nonzero travel time")
	var future = fresh()
	var future_guest: Dictionary = future.state.social.npcs.life_0
	future.services.npc_agency._cancel(future_guest,"h04_fixture")
	future_guest.location = "global_map"
	future_guest.activity = "rest"
	future_guest.pinned_until = 0
	future.services.social.relationship("life_0","player").trust = 25.0
	var tomorrow := int(future.state.clock.weekday)%7+1
	future_guest.schedule = [{"activity":"work","location":"global_map","hours":[495,555],"weekdays":[tomorrow],"mandatory":true}]
	before = future.export_snapshot()
	rng_before = future.rng.state
	rejected = future.command("social","invite",{"id":"life_0","minutes":1440})
	t._check(not rejected.ok and rejected.error=="invitation_calendar_conflict" and future.export_snapshot()==before and future.rng.state==rng_before,"24-hour invitation checks next-day obligation and return travel atomically")

	var home = fresh()
	home.state.economy.cash = 5000
	t.command(home,"housing","buy",{"id":"apartment"})
	var tenant: Dictionary = home.state.social.npcs.life_0
	home.services.npc_agency._cancel(tenant,"h04_fixture")
	tenant.home = "global_map"
	tenant.location = "bedroom"
	tenant.activity = "rest"
	tenant.pinned_until = 0
	var now := int(home.state.clock.total_minutes)
	tenant.mind.active = {"action":"rest","phase":"action","destination":"bedroom","partner":"","reason":"needs_and_personality","started":now,"due":now+15}
	t.command(home,"housing","tenant",{"id":"apartment","npc":"life_0"})
	t.command(home,"housing","remove_tenant",{"id":"apartment","npc":"life_0"})
	t._check(tenant.home=="global_map" and tenant.location=="bedroom" and not tenant.mind.active.is_empty(), "tenancy ends without teleporting or discarding an active task")
	advance(home,15)
	t._check(tenant.location=="bedroom" and tenant.mind.active.get("phase","")=="travel", "former tenant finishes the task before agency plans travel to the original home")
	advance(home,30)
	t._check(tenant.location=="global_map", "former tenant follows the existing route out of the private residence")

func directed_memories_and_emotions() -> void:
	var sim = fresh("community", 2)
	var first: Dictionary = sim.state.social.npcs.life_0
	var second: Dictionary = sim.state.social.npcs.life_1
	t.command(sim, "npc_agency", "experience", {"id": "life_0", "kind": "betrayed", "other": "life_1"})
	t._check(first.mind.sentiments.life_1.value < 0 and not second.mind.sentiments.has("life_0"), "sentiment is directed rather than forced reciprocal")
	t._check(first.mind.emotion.id == "hurt" and first.mind.fears.has("rejection"), "betrayal produces a persistent emotion and fear")
	first.pinned_until = 10000
	second.pinned_until = 10000
	advance(sim, 1440)
	t._check(first.mind.emotion.id != "hurt" and first.mind.sentiments.has("life_1"), "immediate emotion expires before long-term memory")
	for i in range(70): sim.services.npc_agency.observe("life_0", "gift", {})
	t._check(first.mind.history.size() <= 48 and first.mind.moodlets.size() <= 12 and first.mind.sentiments.player.value <= 100, "long-running memory and repeated emotions stay bounded")
	var forecast = fresh()
	var before: float = forecast.services.social_rules.conversation_forecast("life_0", "talk").data.chance
	t.command(forecast, "npc_agency", "experience", {"id": "life_0", "kind": "betrayed", "other": "player"})
	t._check(forecast.services.social_rules.conversation_forecast("life_0", "talk").data.chance < before, "memory of the player changes existing conversation outcomes")

func social_autonomy() -> void:
	var neighbors = fresh("community", 3)
	advance(neighbors, 180)
	t._check(not neighbors.state.social.relationships.is_empty(), "lonely neighbors leave separate homes and create actual opportunities to meet")
	var sim = fresh("community", 4)
	for npc in sim.state.social.npcs.values():
		npc.location = "global_map"
		npc.mind.active = {}
	advance(sim, 720)
	var interactions := 0
	var connected := 0
	for npc in sim.state.social.npcs.values():
		interactions += int(npc.mind.completed_actions.get("connect", 0)) + int(npc.mind.completed_actions.get("support", 0))
		if not npc.mind.sentiments.is_empty(): connected += 1
	t._check(interactions > 0 and connected >= 2 and not sim.state.social.relationships.is_empty(), "NPCs build relationships and social memories without the player")
	for key in sim.state.social.relationships:
		var participants := str(key).split("|")
		t._check(participants[0] != participants[1], "autonomous social interaction never targets self")
	var alone = fresh("community")
	advance(alone, 60)
	t._check(alone.state.social.npcs.life_0.mind.aspiration.progress == 0 and alone.state.social.relationships.is_empty(), "an isolated NPC cannot invent social goal progress or phantom friends")

func player_influence() -> void:
	var sim = fresh()
	var npc: Dictionary = sim.state.social.npcs.life_0
	sim.services.social.relationship("life_0", "player").trust = 20
	var progress := int(npc.mind.aspiration.progress)
	t.command(sim, "npc_agency", "encourage", {"id": "life_0"})
	t._check(npc.mind.sentiments.player.value > 0 and npc.mind.aspiration.progress == progress, "encouragement affects motivation without fabricating achievement")
	var before: Dictionary = sim.export_snapshot()
	t._check(not sim.command("npc_agency", "encourage", {"id": "life_0"}).ok and before == sim.export_snapshot(), "encouragement cannot be farmed repeatedly on the same day")

func constraints_and_personality() -> void:
	var sim = fresh("community", 3)
	for npc in sim.state.social.npcs.values():
		npc.location = "global_map"
		npc.mind.active = {}
	var first: Dictionary = sim.state.social.npcs.life_0
	t.command(sim, "npc_personalities", "configure", {"id": "life_0", "facets": {"patience": 0, "gentleness": 0}})
	t.command(sim, "npc_agency", "experience", {"id": "life_0", "kind": "betrayed", "other": "life_1"})
	var candidates: Array = sim.services.npc_agency.inspect("life_0").candidates
	var dispute := {}
	for candidate in candidates:
		if candidate.id == "dispute": dispute = candidate
	t._check(dispute.get("available", false) and dispute.partner == "life_1", "angry NPC can confront the person associated with a grievance")
	t.command(sim, "npc_personalities", "configure", {"id": "life_0", "facets": {"patience": 100, "gentleness": 100}})
	for candidate in sim.services.npc_agency.inspect("life_0").candidates:
		if candidate.id == "dispute": t._check(float(candidate.score) < float(dispute.score), "patience reduces the same confrontational choice without imposing a stereotype")
	t.command(sim, "npc_personalities", "configure", {"id": "life_0", "facets": {"patience": 0, "gentleness": 0}})
	first.mind.aspiration.stage = 3
	first.mind.aspiration.milestones = 3
	first.mind.aspiration.completed = true
	first.mind.completed_at = int(sim.state.clock.total_minutes)
	advance(sim, 45)
	t._check(int(first.mind.completed_actions.get("dispute", 0)) > 0 and float(sim.services.social.relationship("life_0", "life_1").trust) < 0, "remembered grievance can cause an actual autonomous conflict and relationship consequence")
	sim.state.preferences.disabled_tags.append("conflict")
	for candidate in sim.services.npc_agency.inspect("life_0").candidates:
		if candidate.id == "dispute": t._check(not candidate.available and candidate.blocked == "content_disabled", "autonomous conflict respects the existing content filter")
	var filtered = fresh("community", 2)
	for npc in filtered.state.social.npcs.values():
		npc.location = "global_map"
		npc.mind.active = {}
	filtered.services.npc_agency._start(filtered.state.social.npcs.life_0, "dispute", "global_map", "life_1", "needs_and_personality")
	filtered.state.preferences.disabled_tags.append("conflict")
	advance(filtered, 30)
	t._check(not filtered.state.social.npcs.life_0.mind.completed_actions.has("dispute"), "disabling content also cancels an already-started autonomous conflict")
	var closed = fresh()
	closed.state.world.weather = "rain"
	for candidate in closed.services.npc_agency.inspect("life_0").candidates:
		if candidate.id == "walk": t._check(not candidate.available and candidate.blocked == "weather", "NPC checks weather before choosing an outdoor pastime")
	var gate = Life.new(42, {"settings": {"start_minutes": 480}, "npc_templates": {"free": _template("community")},
		"locations": {"bedroom": {"routes": {"apartment_hall": {"minutes": 1, "cost": 20, "requirements": {"path": "npc.money", "op": "gte", "value": 200}}}}}})
	t.command(gate, "social", "generate", {"id": "a", "template": "free"})
	t.command(gate, "npc_agency", "enable")
	for candidate in gate.services.npc_agency.inspect("a").candidates:
		if candidate.id == "walk": t._check(not candidate.available and candidate.blocked == "unreachable", "route requirements apply to NPC movement too")
	gate.state.social.npcs.a.money = 250
	var route: Dictionary = gate.services.npc_agency._route(gate.state.social.npcs.a, "bedroom", "global_map")
	t._check(route.get("cost", 0) == 20 and route.get("minutes", 0) >= 15, "NPC route accounts for travel funds and elapsed time")
	t.command(gate, "npc_agency", "set_aspiration", {"id": "a", "goal": "wellbeing"})
	t._check(gate.state.social.npcs.a.money == 230 and gate.state.social.npcs.a.location == "bedroom", "paid route charges once when travel actually starts")
	advance(gate, 15)
	t._check(gate.state.social.npcs.a.money == 230 and gate.state.social.npcs.a.location == "global_map", "arrival does not charge the same route again")
	var alternatives = Life.new(42, {"settings": {"start_minutes": 1920}, "npc_templates": {"free": _template()},
		"locations": {"bedroom": {"routes": {"global_map": {"minutes": 1, "cost": 90}, "apartment_hall": {"minutes": 1}}},
			"apartment_hall": {"routes": {"global_map": {"minutes": 1, "cost": 20}}},
			"global_map": {"routes": {"training_center": {"minutes": 1, "cost": 20}}}}})
	t.command(alternatives, "social", "generate", {"id": "a", "template": "free"})
	t.command(alternatives, "npc_agency", "enable")
	var affordable: Dictionary = alternatives.services.npc_agency._route(alternatives.state.social.npcs.a, "bedroom", "training_center")
	t._check(affordable.get("cost", 0) == 40, "planner keeps a slower affordable route when the fastest intermediate route exhausts the travel budget")

func validation_and_replay() -> void:
	var sim = fresh("community", 3)
	advance(sim, 137)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var restored = Life.new(999, _test_catalog("community"))
	t._check(restored.restore_snapshot(snapshot).ok, "life simulation restores intents, emotions and RNG through JSON")
	advance(sim, 720)
	for i in range(12): advance(restored, 60)
	var expected: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var actual: Dictionary = JSON.parse_string(JSON.stringify(restored.export_snapshot()))
	if expected != actual:
		var differences: Array = []
		_differences(expected, actual, "snapshot", differences)
		print("NPC_LIFE_REPLAY_DIFFERENCES ", JSON.stringify(differences))
	t._check(expected == actual, "bulk time and split time produce identical autonomous life after restore")
	var before: Dictionary = restored.export_snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid.state.social.npcs.life_0.mind.aspiration.stage = 999
	t._check(not restored.restore_snapshot(invalid).ok and restored.export_snapshot() == before, "malformed goal stage is rejected atomically")
	invalid = before.duplicate(true)
	invalid.state.social.npcs.life_0.mind.sentiments.ghost = {"value": 5, "expires": 10000, "kind": "friendship"}
	t._check(not restored.restore_snapshot(invalid).ok, "snapshot cannot introduce sentiments toward nonexistent residents")
	var bad = Life.new(1, {"agency_rules": {"simulation": {"decision_minutes": 0}}})
	t._check(not bad.configuration_error.is_empty(), "invalid AI cadence is caught before simulation")
	var invalid_action = Life.new(1, {"agency_actions": {"broken": {"label": "bad", "minutes": 30, "destination": "nowhere", "restore": {}, "traits": {}, "emotion": "calm", "base": 0.5}}})
	t._check(not invalid_action.configuration_error.is_empty(), "catalog rejects nonexistent action destinations")

func _differences(a: Variant, b: Variant, path: String, result: Array) -> void:
	if result.size() >= 8 or a == b: return
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): result.append({"path": path + "." + str(key), "missing": true})
			else: _differences(a[key], b[key], path + "." + str(key), result)
	elif a is Array and b is Array:
		if a.size() != b.size(): result.append({"path": path, "lengths": [a.size(), b.size()]})
		for i in range(mini(a.size(), b.size())): _differences(a[i], b[i], path + "." + str(i), result)
	else:
		result.append({"path": path, "expected": a, "actual": b})

func population_study() -> void:
	var sim = Life.new(128, {"settings": {"start_minutes": 480}})
	t.command(sim, "npc_agency", "enable")
	t.command(sim, "population", "configure", {"values": {"count": 100}})
	t.command(sim, "population", "generate")
	var started := Time.get_ticks_msec()
	advance(sim, 7 * 1440)
	var elapsed := Time.get_ticks_msec() - started
	var actions := {}
	var milestones := 0
	for npc in sim.state.social.npcs.values():
		for action in npc.mind.completed_actions: actions[action] = int(actions.get(action, 0)) + int(npc.mind.completed_actions[action])
		milestones += int(npc.mind.aspiration.milestones)
	t._check(sim.state.social.npcs.size() == 100 and actions.size() >= 7 and milestones > 0, "100 residents sustain distinct needs, work, projects and goals for a full week")
	t._check(sim.validate_state(sim.state).ok, "population remains structurally valid after autonomous week")
	print("NPC_LIFE_BENCHMARK ", JSON.stringify({"npcs": 100, "days": 7, "milliseconds": elapsed, "actions": actions, "milestones": milestones}))
