extends SceneTree
const Main = preload("res://scripts/gameplay/main_simulation.gd")
const Residents = preload("res://scripts/gameplay/city_residents.gd")
const Population = preload("res://scripts/mechanics/population.gd")
const City = preload("res://scripts/gameplay/city_layout.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize():
	var sim = Main.new(124)
	check(sim.configuration_error.is_empty(),"catalog "+sim.configuration_error)
	if failures>0: quit(1); return
	check(sim.validate_state(sim.state).ok,"initial state")
	var settings := Population.defaults()
	check(sim.command("population","configure",{"values":settings}).ok,"configure")
	var generated: Dictionary = sim.command("population","generate")
	print("GENERATED=",generated)
	check(generated.ok,"population generate")
	if not generated.ok: quit(1); return
	check(sim.state.social.npcs.size()==36 and sim.state.population.batches==1,"exact N one batch")
	check(sim.state.population.settings.count==36,"requested setting preserved")
	var women := 0
	var morph := {"human":0,"semi_furry":0,"furry":0}
	for npc in sim.state.social.npcs.values():
		if npc.gender == "female": women += 1
		morph[npc.appearance.morphology] += 1
	check(women==18,"female quota")
	check(morph==Population.morphology_counts(settings),"morph quota")
	check(not sim.services.npc_agency.enabled(),"story agency disabled")
	var own := "resident_south_grocer"
	var home := str(sim.state.social.npcs.get(own,{}).get("home",""))
	check(sim.services.world.actor_availability(home,own,480).ok,"owner enters own home")
	check(not sim.services.world.actor_availability(home,"player",480).ok,"player cannot enter other home")
	check(sim.services.world.actor_availability("riverside_cafe_front","player",0).ok,"public front night")
	check(not sim.services.world.actor_availability("riverside_cafe","player",0).ok,"closed cafe room")
	check(not sim.services.world.actor_availability("clinic","player",0).ok,"ordinary closed clinic")
	var path: Dictionary = sim.services.world.route_from("student_home","campus_courtyard",660)
	print("CAMPUS=",path)
	check(path.ok and path.data.minutes==14,"campus fourteen minutes")
	scan_catalog(sim.catalog,"catalog")
	spatial_consumers()
	var snapshot: Dictionary = sim.export_snapshot()
	var restored = Main.new(124)
	var restored_result: Dictionary = restored.restore_snapshot(snapshot)
	print("RESTORE=",restored_result)
	check(restored_result.ok,"dynamic catalog restore")
	check(restored.export_snapshot()==snapshot,"snapshot equality no reseed")
	var before: Dictionary = sim.export_snapshot()
	check(not sim.command("population","configure",{"values":{"count":0}}).ok,"reject external zero")
	check(sim.export_snapshot()==before,"reject rollback RNG and state")
	check(sim.command("npc_agency","enable").ok,"enable autonomy once")
	check(sim.state.social.npcs[own].mind.employment.job == "south_grocer","real south job")
	var small = Main.new(125)
	settings.count=2
	settings.female_ratio=1.0
	check(small.command("population","configure",{"values":settings}).ok,"small configure")
	var pair: Dictionary = small.command("population","generate")
	print("PAIR=",pair)
	check(pair.ok and small.state.social.npcs.size()==2 and small.state.population.batches==1,"zero internal residual")
	check(small.state.population.settings.count==2,"N2 settings unchanged")
	for config in [{"female_ratio":0.0},{"activity_mode":"study"},{"age_min":18,"age_max":22}]:
		var c := Population.defaults(); c.merge(config,true)
		var plan := Residents.population_plan(c,125)
		check(plan.ok and plan.data.residents.is_empty(),"ineligible "+str(config))
	print("CITY_SMOKE checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)

func scan_catalog(value: Variant, path: String):
	if value is Dictionary:
		for key in value: scan_catalog(value[key],path+"."+str(key))
	elif value is Array:
		for index in value.size(): scan_catalog(value[index],path+"["+str(index)+"]")
	elif value is String and value in ["global_map","training_center"]:
		print("OBSOLETE ",path,"=",value)

func spatial_consumers():
	var presentation = preload("res://scripts/gameplay/presentation.gd")
	var extensions: Dictionary = presentation.extensions()
	extensions.settings={"start_minutes":600}
	var sim = Main.new(131,extensions)
	check(sim.configuration_error.is_empty(),"presentation catalog "+sim.configuration_error)
	for id in sim.catalog.skills: sim.state.player.skills[id]=1000
	for id in sim.catalog.city_graph.capability_bindings.jobs:
		var job: Dictionary = sim.catalog.livelihood_rules.jobs[id]
		var bind: Dictionary = sim.catalog.city_graph.capability_bindings.jobs[id]
		if bind.scope == "actor_home": continue
		var route: Dictionary = sim.services.world.route_from("student_home",str(job.location),int(job.hours[0]),false)
		check(route.ok,"job path "+id)
	for id in sim.catalog.lessons:
		var lesson: Dictionary = sim.catalog.lessons[id]
		check(sim.catalog.locations.has(lesson.location),"lesson venue "+id)
	for binding in sim.catalog.city_graph.story_bindings:
		if binding.status == "outside_present_graph": continue
		var ids: Array = binding.get("target_location_ids",[]).duplicate()
		if binding.has("target_location_id"): ids.append(binding.target_location_id)
		for id in ids: check(sim.catalog.locations.has(id),"authored place "+str(binding.id))
	sim.state.world.location="south_trade_street"
	var shop_trip: Dictionary = sim.command("world","journey",{"id":"south_market"})
	check(shop_trip.ok,"actual south shop journey "+str(shop_trip))
	var bought: Dictionary = sim.command("inventory","buy",{"id":"meal","shop":"market","quantity":1})
	check(bought.ok,"shop buy at actual interior "+str(bought))
	var shift = Main.new(132,{"settings":{"start_minutes":600}})
	shift.state.world.location=str(shift.catalog.livelihood_rules.jobs.shop_assistant.location)
	shift.state.player.skills.sales=1000
	preload("res://scripts/mechanics/education_schedule.gd").apply_plan(shift.state,false,[])
	var worked: Dictionary = shift.command("livelihood","work",{"id":"shop_assistant","interactive":false})
	check(worked.ok,"actual workplace shift "+str(worked))
	var lesson_sim = Main.new(133,{"settings":{"start_minutes":2040}})
	lesson_sim.state.world.location=str(lesson_sim.catalog.lessons.common_day.location)
	var attended: Dictionary = lesson_sim.command("world","lesson",{"id":"common_day"})
	check(attended.ok,"actual common lesson "+str(attended))
	var urgent = Main.new(134,{"settings":{"start_minutes":10}})
	urgent.state.world.location="clinic_forecourt"
	urgent.services.adult_health.synchronize()
	var health: Dictionary = urgent.services.adult_health.record("player")
	health.erection.persistent=true
	health.erection.painful=true
	health.erection.started=0
	health.erection.until=600
	urgent.state.clock=urgent.calendar.snapshot(300)
	check(urgent.services.adult_health.view("player").urgent,"clinical urgent fixture")
	check(urgent.services.world.route("clinic").ok,"urgent clinic route at night")
	var emergency_trip: Dictionary = urgent.command("world","journey",{"id":"clinic"})
	check(emergency_trip.ok,"actual emergency entrance "+str(emergency_trip))
