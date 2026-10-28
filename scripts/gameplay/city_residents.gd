extends RefCounted
## First authored city pair occupies reserved slots of the ordinary population.
## Called by MainSimulation's population hook inside one Simulation.command.
const PATH := "res://data/world/city-residents.json"
const Rules = preload("res://scripts/mechanics/core/rules.gd")
const Check = preload("res://scripts/mechanics/core/validation.gd")
const Population = preload("res://scripts/mechanics/population.gd")
const Employment = preload("res://scripts/mechanics/npc_employment.gd")
const Graph = preload("res://scripts/gameplay/city_graph.gd")
const MARKER := "city_residents"

static func _load_data() -> Dictionary:
	var file := FileAccess.open(PATH,FileAccess.READ)
	if file == null: return Rules.fail("city_residents_unreadable")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary: return Rules.fail("city_residents_json")
	var data: Dictionary = parser.data
	if data.get("schema") != 1 or not data.get("residents") is Array: return Rules.fail("city_residents_schema")
	for group in ["templates","npc_story_arcs","strings","outcomes","revisits"]:
		if not data.get(group) is Dictionary: return Rules.fail("city_residents_schema")
	if data.residents.size()!=2: return Rules.fail("city_residents_pair_required")
	var ids := {}
	for actor: Variant in data.residents:
		if not Check.fields(actor,{"id":"s","name":"s","age":"n","gender":"s","template":"s","story_arc":"s"}): return Rules.fail("city_residents_definition")
		if ids.has(actor.id) or actor.id.is_empty() or actor.name.is_empty() or actor.gender!="female" or float(actor.age)!=int(actor.age) or int(actor.age)<18: return Rules.fail("city_residents_definition")
		ids[actor.id] = true
		if not Check.fields(data.templates.get(actor.template),{"role":"s","home":"s","schedule":"a","employment":"d"}): return Rules.fail("city_residents_template")
	return Rules.ok(data)

static func apply_catalog(catalog: Dictionary) -> Dictionary:
	var loaded := _load_data()
	if not loaded.ok: return loaded
	var data: Dictionary = loaded.data
	var definitions := {}
	if data.residents.size() != 2: return Rules.fail("city_residents_pair_required")
	for actor: Variant in data.residents:
		if not Check.fields(actor,{"id":"s","name":"s","age":"n","gender":"s","template":"s","story_arc":"s"}): return Rules.fail("city_residents_definition")
		if definitions.has(actor.id) or str(actor.id).is_empty() or actor.gender != "female" or float(actor.age) != int(actor.age) or int(actor.age) < 18: return Rules.fail("city_residents_definition")
		if not data.templates.has(actor.template): return Rules.fail("city_residents_template")
		if not str(actor.story_arc).is_empty() and not data.npc_story_arcs.has(actor.story_arc): return Rules.fail("city_residents_story_binding")
		var template: Dictionary = data.templates[actor.template]
		if not Check.fields(template,{"home":"s","schedule":"a","employment":"d"}): return Rules.fail("city_residents_template")
		if not catalog.locations.has(template.home): return Rules.fail("city_residents_home_missing")
		var stub := {"age":int(actor.age),"home":template.home,"biography":{"role":template.get("role","")},"schedule":template.schedule}
		var assignment := Employment.assignment_error(template.employment,catalog,stub)
		if not assignment.is_empty(): return Rules.fail(assignment)
		definitions[actor.id] = actor.duplicate(true)
	for locale in ["ru","en"]:
		if not data.strings.get(locale) is Dictionary: return Rules.fail("city_residents_strings")
		for key in data.strings.ru:
			if not data.strings[locale].get(key) is String: return Rules.fail("city_residents_strings")
	for arc_id in data.npc_story_arcs:
		if catalog.npc_story_arcs.has(arc_id) and catalog.npc_story_arcs[arc_id] != data.npc_story_arcs[arc_id]: return Rules.fail("city_residents_arc_collision")
	# All checks above precede catalog mutation. MainSimulation validates the merged arcs.
	catalog.npc_story_arcs.merge(data.npc_story_arcs.duplicate(true),true)
	catalog.city_resident_definitions = definitions
	catalog.city_resident_templates = data.templates.duplicate(true)
	catalog.city_story_strings = data.strings.duplicate(true)
	catalog.city_story_outcomes = data.outcomes.duplicate(true)
	catalog.city_story_revisits = data.revisits.duplicate(true)
	return Rules.ok()

static func population_plan(settings: Dictionary, random_seed: int) -> Dictionary:
	# Public settings still accept 1..200. Only the internal remainder may be zero.
	if not Population.valid(settings): return Rules.fail("invalid_population_settings")
	var loaded := _load_data()
	if not loaded.ok: return loaded
	var config := Population.defaults()
	config.merge(settings,true)
	var requested := int(config.count)
	var women := int(round(requested*float(config.female_ratio)))
	var counts := Population.morphology_counts(config)
	var pool: Array[String] = []
	for morphology in Population.MORPHOLOGIES:
		for index in range(int(counts[morphology])): pool.append(str(morphology))
	var residents: Array[Dictionary] = []
	for actor: Dictionary in loaded.data.residents:
		if config.activity_mode == "study" or women <= residents.size(): continue
		if int(actor.age) < int(config.age_min) or int(actor.age) > int(config.age_max): continue
		var slot := posmod((str(random_seed)+":"+str(actor.id)).hash(),pool.size())
		var morphology: String = pool[slot]
		pool.remove_at(slot)
		var record := actor.duplicate(true)
		record.appearance = {"morphology":morphology,"gender":actor.gender,"body_type":"slim","face_id":"soft","hair_style":"long","hair_color":"dark"}
		residents.append(record)
	var remaining := requested-residents.size()
	var random_settings := config.duplicate(true)
	random_settings.count = remaining
	if remaining > 0:
		var residual := {"human":0,"semi_furry":0,"furry":0}
		for morphology in pool: residual[morphology] += 1
		random_settings.female_ratio = float(women-residents.size())/remaining
		random_settings.semi_furry_ratio = float(residual.semi_furry)/remaining
		random_settings.furry_ratio = float(residual.furry)/remaining
	return Rules.ok({"requested_count":requested,"random_settings":random_settings,"residents":residents,"full_morphologies":counts})

static func _template(catalog: Dictionary, record: Dictionary, settings: Dictionary, random_seed: int) -> Dictionary:
	var result: Dictionary = catalog.npc_templates.resident.duplicate(true)
	result.merge(catalog.city_resident_templates[record.template].duplicate(true),true)
	result.gender = str(record.gender)
	result.stat_min = settings.stat_min
	result.stat_max = settings.stat_max
	result.traits = {}
	var spread := int(settings.trait_spread)
	for trait_id in Population.TRAITS:
		var offset := posmod((str(random_seed)+":"+str(record.id)+":"+str(trait_id)).hash(),spread*2+1)-spread
		result.traits[trait_id] = clampi(int(settings[trait_id])+offset,0,100)
	return result

static func preflight(sim, settings: Dictionary, random_seed: int) -> Dictionary:
	var planned := population_plan(settings,random_seed)
	if not planned.ok: return planned
	var config := Population.defaults()
	config.merge(settings,true)
	var plan: Dictionary = planned.data
	var marker: Variant = sim.state.world.flags.get(MARKER)
	if marker != null:
		var marker_error := state_error(sim.state,sim.catalog)
		if not marker_error.is_empty(): return Rules.fail(marker_error)
		if int(marker.requested_count)!=int(plan.requested_count) or int(marker.seed)!=random_seed: return Rules.fail("city_residents_configuration_changed")
		return Rules.ok({"already_seeded":true,"plan":plan})
	if sim.services.npc_agency.enabled(): return Rules.fail("city_residents_seed_after_agency")
	var graph_result := Graph.load_graph()
	if not graph_result.ok: return graph_result
	var graph: Dictionary = graph_result.data
	var regular := 0
	for id in sim.state.social.npcs:
		if str(id).begins_with("resident_") and str(id).trim_prefix("resident_").is_valid_int(): regular += 1
	if regular != int(plan.random_settings.count): return Rules.fail("city_residents_population_mismatch")
	if sim.state.social.npcs.size()+plan.residents.size() > 500: return Rules.fail("population_limit")
	for record: Dictionary in plan.residents:
		if sim.state.social.npcs.has(record.id): return Rules.fail("city_residents_id_collision")
		if not sim.catalog.get("city_resident_definitions",{}).has(record.id): return Rules.fail("city_residents_catalog_missing")
		var declared: Dictionary = sim.catalog.city_resident_definitions[record.id]
		for field in ["id","name","age","gender","template","story_arc"]:
			if declared[field]!=record[field]: return Rules.fail("city_residents_definition_changed")
		var template := _template(sim.catalog,record,config,random_seed)
		var stub := {"age":record.age,"home":template.home,"biography":{"role":template.role},"schedule":template.schedule}
		var assignment := Employment.assignment_error(template.employment,sim.catalog,stub)
		if not assignment.is_empty(): return Rules.fail(assignment)
		var actor := {"id":record.id,"duty_location_ids":[template.employment.workplace]}
		for place in [str(template.home),str(template.employment.workplace)]:
			if not sim.catalog.locations.has(place): return Rules.fail("city_residents_location_missing")
			var entry := Graph.can_enter(graph,place,actor,600,1)
			if not entry.ok: return Rules.fail("city_residents_access:"+str(entry.error))
		if not _connected(sim.catalog,graph,str(template.home),str(template.employment.workplace),actor): return Rules.fail("city_residents_home_unreachable")
	return Rules.ok({"already_seeded":false,"plan":plan,"settings":config})

static func _connected(catalog: Dictionary, graph: Dictionary, start: String, goal: String, actor: Dictionary) -> bool:
	var queue: Array[String] = [start]
	var seen := {}
	seen[start] = true
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == goal: return true
		for target in catalog.locations[current].get("routes",{}):
			if seen.has(target) or not Graph.can_enter(graph,str(target),actor,600,1).ok: continue
			seen[target] = true
			queue.append(str(target))
	return false

static func seed(sim, settings: Dictionary, random_seed: int) -> Dictionary:
	var ready := preflight(sim,settings,random_seed)
	if not ready.ok: return ready
	if ready.data.already_seeded: return Rules.ok({"ids":sim.state.world.flags[MARKER].ids.duplicate(),"already_seeded":true})
	var plan: Dictionary = ready.data.plan
	var ids: Array[String] = []
	# The enclosing population.generate command provides state/RNG/event rollback.
	for record: Dictionary in plan.residents:
		var template := _template(sim.catalog,record,ready.data.settings,random_seed)
		var args := {"name":record.name,"age":record.age,"appearance":record.appearance.duplicate(true)}
		var created: Dictionary = sim.services.social.generate_from_template(str(record.id),args,template)
		if not created.ok: return created
		var npc: Dictionary = sim.state.social.npcs[record.id]
		npc.biography.story_arc = str(record.story_arc)
		npc.biography.city_cast_id = "first_trade_loop"
		ids.append(str(record.id))
	sim.state.world.flags[MARKER] = {"version":1,"complete":true,"requested_count":int(plan.requested_count),"seed":random_seed,"ids":ids}
	return Rules.ok({"ids":ids,"already_seeded":false})

static func state_error(state: Dictionary, catalog: Dictionary) -> String:
	if not state.world.flags.has(MARKER): return ""
	var marker: Variant = state.world.flags[MARKER]
	if not Check.fields(marker,{"version":"n","complete":"b","requested_count":"n","seed":"n","ids":"a"}) or marker.version!=1 or not marker.complete: return "invalid_city_residents_marker"
	if int(marker.requested_count)!=float(marker.requested_count) or int(marker.requested_count)<1 or int(marker.requested_count)>200: return "invalid_city_residents_marker"
	if int(marker.seed)!=float(marker.seed): return "invalid_city_residents_marker"
	if marker.ids.size()>2: return "invalid_city_residents_marker"
	var seen := {}
	for id: Variant in marker.ids:
		if not id is String or seen.has(id) or not catalog.get("city_resident_definitions",{}).has(id) or not state.social.npcs.has(id): return "invalid_city_residents_marker"
		seen[id] = true
		var npc: Dictionary = state.social.npcs[id]
		if npc.biography.get("city_cast_id","")!="first_trade_loop" or npc.biography.get("story_arc")!=catalog.city_resident_definitions[id].story_arc: return "invalid_city_resident_binding"
	for id in state.social.npcs:
		if state.social.npcs[id].biography.get("city_cast_id","")=="first_trade_loop" and not seen.has(id): return "invalid_city_residents_marker"
	return ""
