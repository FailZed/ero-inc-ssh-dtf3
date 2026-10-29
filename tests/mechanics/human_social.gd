extends RefCounted
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
const Validation = preload("res://scripts/mechanics/core/human_validation.gd")
var t

func _init(runner) -> void:
	t = runner

func world(count: int = 2):
	var template := {"age": 25, "home": "bedroom", "role": "worker", "money": 100,
		"personalities": ["calm"], "goals": ["community"], "schedule": [], "activities": [],
		"gender": "female", "attracted_to": ["female"], "traits": {"sociability": 50}}
	var sim = Life.new(551, {"settings": {"start_minutes": 480}, "npc_templates": {"human": template}})
	t._check(sim.configuration_error.is_empty(), "human catalog is valid: " + sim.configuration_error)
	t.command(sim, "npc_agency", "enable")
	for i in range(count):
		var id := "h%d" % i
		t.command(sim, "social", "generate", {"id": id, "template": "human"})
		var facets := {}
		for key in Validation.FACETS: facets[key] = 50
		t.command(sim, "npc_personalities", "configure", {"id": id, "facets": facets})
		var npc: Dictionary = sim.state.social.npcs[id]
		npc.location = "global_map"
		npc.needs.merge({"energy": 100, "satiety": 100, "hygiene": 100, "fun": 70, "social": 45}, true)
		npc.mind.aspiration = {"id": "community", "stage": 3, "milestones": 3, "progress": 0, "completed": true}
		npc.mind.completed_at = int(sim.state.clock.total_minutes)
	return sim

func act(sim, actor: String, target: String, action: String) -> void:
	for id in [actor, target]:
		var npc: Dictionary = sim.state.social.npcs[id]
		sim.services.npc_agency._cancel(npc, "test_meeting")
		npc.location = "global_map"
		npc.mind.last_social = -1440
		npc.needs.merge({"energy": 100, "satiety": 100, "hygiene": 100}, true)
	sim.services.npc_agency._build_index()
	sim.services.npc_agency._start(sim.state.social.npcs[actor], action, "global_map", target, "needs_and_personality")
	t.command(sim, "clock", "advance", {"minutes": int(sim.catalog.agency_actions[action].minutes)})

func bond(sim, a: String, b: String) -> Dictionary:
	return sim.services.npc_relationships.view(a, b)

func run() -> void:
	continuous_personalities()
	directed_relationships()
	harm_and_repair()
	boundaries_and_agreement()
	discovery_and_repetition()
	player_and_information()
	validation_and_replay()

func continuous_personalities() -> void:
	var sim = world(3)
	var p = sim.services.npc_personalities
	var npc: Dictionary = sim.state.social.npcs.h0
	var original: Dictionary = sim.export_snapshot()
	var info: Dictionary = p.describe(npc)
	t._check(info.dimensions.size() == 6 and info.facets.size() == 24, "personality has six continuous domains and all 24 facets")
	t._check(not sim.catalog.has("school_personality_map"), "School type catalog no longer drives the life runtime")
	t._check(sim.export_snapshot() == original, "reading human personality consumes no RNG and changes no world state")
	for facet in Validation.FACETS:
		t.command(sim, "npc_personalities", "configure", {"id": "h0", "facets": {facet: 0}})
		var low: Dictionary = p.profile(npc).duplicate(true)
		t.command(sim, "npc_personalities", "configure", {"id": "h0", "facets": {facet: 100}})
		t._check(low != p.profile(npc), "facet affects behavioral rules: " + facet)
		t.command(sim, "npc_personalities", "configure", {"id": "h0", "facets": {facet: 50}})
	var before: Dictionary = p.profile(npc).duplicate(true)
	npc.personality = "reliable"
	t._check(p.profile(npc) == before, "legacy label does not change the continuous personality")
	var biography: Dictionary = t.command(sim, "social_rules", "biography", {"id": "h0"})
	t._check(biography.data.personality.facets.size() == 24, "biography exposes the current personality rather than the old categorical label")
	t.command(sim, "npc_personalities", "configure", {"id": "h0", "facets": {"sociability": 100, "sincerity": 100, "prudence": 100}})
	t.command(sim, "npc_personalities", "configure", {"id": "h1", "facets": {"sociability": 0, "sincerity": 0, "fairness": 0}})
	for entry in sim.state.social.npcs.values(): entry.pinned_until = 2000
	t.command(sim, "clock", "advance", {"minutes": 120})
	t._check(float(npc.needs.social) < float(sim.state.social.npcs.h1.needs.social), "continuous sociability changes actual loneliness decay")
	t._check(p.bias(npc, "deceive") < p.bias(sim.state.social.npcs.h1, "deceive"), "honesty and caution coexist with sociability instead of selecting a single type")
	var bad := sim.export_snapshot()
	t._check(not sim.command("npc_personalities", "configure", {"id": "h0", "facets": {"sincerity": 101}}).ok and sim.export_snapshot() == bad, "out-of-range personality edit rolls back atomically")
	var choices = world(2)
	t.command(choices, "npc_personalities", "configure", {"id": "h0", "facets": {"sociability": 100, "social_boldness": 100, "liveliness": 100}})
	t.command(choices, "clock", "advance", {"minutes": 15})
	t._check(choices.state.social.npcs.h0.mind.active.action in ["connect", "joke"], "human facets reach actual autonomous decisions")

func directed_relationships() -> void:
	var sim = world()
	t.command(sim, "npc_agency", "experience", {"id": "h0", "kind": "betrayed", "other": "h1"})
	t._check(float(bond(sim, "h0", "h1").trust) == -32 and float(bond(sim, "h1", "h0").trust) == 0, "betrayal damages the victim's view without forcing reciprocal distrust")
	t._check(bond(sim, "h0", "h1").stage == "strained" and bond(sim, "h1", "h0").stage == "stranger", "two people can assign different meanings to the same relationship")
	var separate = world()
	act(separate, "h0", "h1", "cooperate")
	var recipient := bond(separate, "h1", "h0")
	var helper := bond(separate, "h0", "h1")
	t._check(float(recipient.trust) > float(helper.trust) and float(recipient.care_balance) < 0 and float(helper.care_balance) > 0, "real help produces asymmetric trust and tracks who gives and receives care")
	t._check(int(separate.state.clock.total_minutes) == 540 and int(separate.state.social.npcs.h0.mind.completed_actions.get("cooperate", 0)) == 1, "help takes a full hour and completes through the agency runtime")

func harm_and_repair() -> void:
	var sim = world()
	t.command(sim, "npc_agency", "experience", {"id": "h1", "kind": "betrayed", "other": "h0"})
	var trust: float = bond(sim, "h1", "h0").trust
	act(sim, "h0", "h1", "apologize")
	t._check(bond(sim, "h1", "h0").acknowledged and float(bond(sim, "h1", "h0").trust) == trust and float(bond(sim, "h1", "h0").grievance) == 40, "apology acknowledges harm without erasing grievance or restoring trust")
	t._check(sim.services.npc_relationships.blocked("h0", "h1", "apologize") == "no_unacknowledged_harm", "repeating apologies cannot farm relationship gains")
	act(sim, "h0", "h1", "cooperate")
	var once: float = bond(sim, "h1", "h0").grievance
	act(sim, "h0", "h1", "support")
	t._check(float(bond(sim, "h1", "h0").grievance) == once and bond(sim, "h1", "h0").good_days.size() == 1, "trust repair counts distinct reliable days, not action spam")
	for npc in sim.state.social.npcs.values(): npc.pinned_until = 10000
	t.command(sim, "clock", "advance", {"minutes": 1440})
	t._check(float(bond(sim, "h1", "h0").grievance) == once, "waiting does not erase unresolved harm")
	for npc in sim.state.social.npcs.values(): npc.pinned_until = 0
	act(sim, "h0", "h1", "cooperate")
	t._check(bond(sim, "h1", "h0").good_days.size() == 2 and float(bond(sim, "h1", "h0").trust) < 0, "reliable help on another day improves a damaged relationship gradually")
	var fixed: Dictionary = sim.export_snapshot()
	t.command(sim, "npc_agency", "experience", {"id": "h1", "kind": "misled", "other": "h0"})
	t._check(not bond(sim, "h1", "h0").acknowledged and bond(sim, "h1", "h0").good_days.is_empty(), "new deception breaks the repair process")
	t._check(fixed.state.social.npcs.h1.psychology == sim.state.social.npcs.h1.psychology, "temporary emotional experiences do not rewrite stable personality")

func boundaries_and_agreement() -> void:
	var sim = world()
	t.command(sim, "npc_relationships", "boundary", {"id": "h1", "boundary": "romance", "allowed": false})
	t._check(sim.services.npc_relationships.blocked("h0", "h1", "court") == "romantic_boundary", "recipient's stated boundary overrides personality and attraction")
	for entry in sim.services.npc_agency.inspect("h0").candidates:
		if entry.id == "court": t._check(not entry.available, "autonomy cannot select a forbidden romantic interaction")
	t.command(sim, "npc_relationships", "boundary", {"id": "h1", "boundary": "romance", "allowed": true})
	t._check(sim.services.npc_relationships.blocked("h0", "h1", "invite_relationship") == "relationship_not_ready", "attraction compatibility alone does not create a partnership")
	# Prepare established directed bonds; invitation still travels through real timed action.
	for pair in [["h0", "h1"], ["h1", "h0"]]:
		var established: Dictionary = sim.services.npc_relationships._bond(pair[0], pair[1])
		established.merge({"trust": 65.0, "affection": 55.0, "comfort": 60.0, "interest": 60.0, "closeness": 60.0}, true)
	sim.rng.seed = 1
	act(sim, "h0", "h1", "invite_relationship")
	var relation: Dictionary = sim.services.social.relationship("h0", "h1")
	t._check(relation.status == "partner" and bond(sim, "h0", "h1").consent and bond(sim, "h1", "h0").consent, "partnership forms only through an accepted mutual agreement")
	t.command(sim, "npc_relationships", "separate", {"id": "h1", "other": "h0"})
	t._check(sim.services.social.relationship("h0", "h1").status == "separated", "either person can end the relationship")
	var filtered = world()
	filtered.state.preferences.disabled_tags.append("romance")
	t._check(filtered.services.npc_relationships.blocked("h0", "h1", "court") == "content_disabled", "human social model respects romance filters")
	filtered.services.npc_agency._start(filtered.state.social.npcs.h0, "cooperate", "global_map", "h1", "needs_and_personality")
	t.command(filtered, "npc_relationships", "boundary", {"id": "h1", "boundary": "contact", "allowed": false})
	t._check(filtered.state.social.npcs.h0.mind.active.is_empty(), "changing a contact boundary cancels an ongoing meeting")
	var declined = world()
	for pair in [["h0", "h1"], ["h1", "h0"]]:
		declined.services.npc_relationships._bond(pair[0], pair[1]).merge({"trust": 65.0, "comfort": 60.0, "interest": 60.0, "closeness": 60.0}, true)
	declined.rng.seed = 123
	act(declined, "h0", "h1", "invite_relationship")
	t._check(not bond(declined, "h1", "h0").consent and declined.services.npc_relationships.blocked("h0", "h1", "court") == "romantic_boundary", "a refused proposal creates a real cooldown rather than automatic persistence")
	t._check(float(bond(declined, "h1", "h0").trust) == 65, "a respectful refused proposal does not punish the recipient with lost trust")

func discovery_and_repetition() -> void:
	var sim = world()
	t._check(bond(sim, "h0", "h1").known_interests.is_empty() and sim.services.npc_relationships.known_alignment(sim.state.social.npcs.h0, sim.state.social.npcs.h1) == 0.5, "strangers cannot read each other's hidden interests or values")
	act(sim, "h0", "h1", "cooperate")
	t._check(bond(sim, "h1", "h0").known_interests.size() == 1 and bond(sim, "h1", "h0").known_values.is_empty(), "shared activity reveals one interest rather than the entire personality")
	var trust: float = bond(sim, "h1", "h0").trust
	act(sim, "h0", "h1", "cooperate")
	t._check(float(bond(sim, "h1", "h0").trust) == trust, "repeating the same helpful action too soon has no additional relationship reward")
	for i in range(4): act(sim, "h0", "h1", "cooperate")
	t._check(float(bond(sim, "h1", "h0").gain_used) <= 8 and float(bond(sim, "h1", "h0").trust) <= 4, "daily gains have a pair-specific shared budget")
	var incoming: Dictionary = sim.services.npc_relationships._bond("h1", "h0")
	incoming.trust = 20.0
	sim.rng.seed = 42
	act(sim, "h0", "h1", "share_values")
	t._check(bond(sim, "h1", "h0").known_values.size() == 1, "a deep conversation discloses one value")

func player_and_information() -> void:
	var sim = world()
	sim.state.world.location = "global_map"
	var before := int(sim.state.clock.total_minutes)
	t.command(sim, "social", "interact", {"id": "h0", "action": "offer_help"})
	t._check(int(sim.state.clock.total_minutes) == before + 60 and float(bond(sim, "h0", "player").trust) > 0, "existing player interaction entry point uses timed directed social actions")
	t._check(sim.state.social.npcs.h0.mind.sentiments.has("player"), "player's helpful action also produces a real emotional memory")
	t.command(sim, "npc_agency", "experience", {"id": "h0", "kind": "betrayed", "other": "player"})
	var trust: float = bond(sim, "h0", "player").trust
	for i in range(5): sim.services.social.change_relationship("h0", "player", {"trust": 50, "affinity": 50})
	t._check(float(bond(sim, "h0", "player").trust) == trust, "legacy gift/reward paths cannot buy back trust after betrayal")
	var liar = world()
	liar.services.npc_personalities.social_success(liar.state.social.npcs.h0, liar.state.social.npcs.h1, "deceive")
	var original: Dictionary = liar.export_snapshot()
	liar.services.npc_agency._cancel(liar.state.social.npcs.h1, "verify")
	liar.state.social.npcs.h1.location = "bedroom"
	liar.services.npc_agency._start(liar.state.social.npcs.h1, "verify", "bedroom", "", "needs_and_personality")
	t.command(liar, "clock", "advance", {"minutes": 30})
	t._check(float(bond(liar, "h1", "h0").grievance) == 25 and float(bond(liar, "h0", "h1").grievance) == 0, "checking a false claim creates a directed grievance against its source")
	t._check(original.state.social.npcs.h1.mind.claims[0].checked == false and liar.state.social.npcs.h1.mind.claims[0].checked, "verification consumes actual time before knowledge changes")

func validation_and_replay() -> void:
	var sim = world(4)
	act(sim, "h0", "h1", "cooperate")
	var before: Dictionary = sim.export_snapshot()
	for mutation in ["facet", "target", "consent", "future", "knowledge"]:
		var bad: Dictionary = before.duplicate(true)
		match mutation:
			"facet": bad.state.social.npcs.h0.psychology.facets.sincerity = NAN
			"target": bad.state.social.npcs.h0.mind.bonds.ghost = bad.state.social.npcs.h0.mind.bonds.h1.duplicate(true)
			"consent": bad.state.social.relationships["h0|h1"].status = "partner"
			"future": bad.state.social.npcs.h0.mind.bonds.h1.last_contact = 999999
			"knowledge": bad.state.social.npcs.h0.mind.bonds.h1.known_values.secret = 10
		t._check(not sim.restore_snapshot(bad).ok and sim.export_snapshot() == before, "invalid social state is rejected atomically: " + mutation)
	var restored = Life.new(90, {"settings": {"start_minutes": 480}, "npc_templates": {"human": sim.catalog.npc_templates.human}})
	t._check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(before))).ok, "facets, boundaries, agreements and directed bonds round-trip through JSON")
	t.command(sim, "clock", "advance", {"minutes": 720})
	for i in range(12): t.command(restored, "clock", "advance", {"minutes": 60})
	var expected: Dictionary = JSON.parse_string(JSON.stringify(sim.export_snapshot()))
	var actual: Dictionary = JSON.parse_string(JSON.stringify(restored.export_snapshot()))
	if expected != actual:
		var differences: Array = []
		load("res://tests/mechanics/npc_life.gd").new(t)._differences(expected, actual, "snapshot", differences)
		print("HUMAN_REPLAY_DIFFERENCES ", JSON.stringify(differences))
	t._check(expected == actual, "mixed social autonomy replays identically after restore with split time")
	var large = world(40)
	for i in range(1, 40): large.services.npc_relationships.harm("h0", "h%d" % i, 1, "test")
	t._check(large.state.social.npcs.h0.mind.bonds.size() <= 32 and large.validate_state(large.state).ok, "directed social memory stays bounded with many acquaintances")
