extends RefCounted
const H = preload("res://scripts/mechanics/core/human_validation.gd")
const V = preload("res://scripts/mechanics/core/validation.gd")
const Health = preload("res://scripts/mechanics/adult_health.gd")

static func state_error(state: Dictionary) -> String:
	if not state.has("adult_health"): return ""
	var area: Variant = state.adult_health
	if not V.fields(area,{"version":"n","rules_hash":"s","records":"d","contacts":"a","history":"a"}) or area.version!=2: return "invalid_adult_health"
	if area.rules_hash!=JSON.stringify(Health.config()).sha256_text(): return "adult_health_rules_mismatch"
	if area.records.size()>state.social.npcs.size()+1 or area.history.size()>128 or area.contacts.size()>128: return "unbounded_adult_health"
	var now := int(state.clock.total_minutes)
	for key in area.contacts:
		if not key is String or key.is_empty() or key.length()>160: return "invalid_health_contact"
	for id in area.records:
		if id!="player" and not state.social.npcs.has(id): return "unknown_adult_health_actor"
		var actor: Dictionary = state.player if id=="player" else state.social.npcs[id]
		if int(actor.get("age",0))<18: return "adult_health_adults_only"
		if id!="player":
			for memory in actor.get("memories",[]):
				if memory.get("kind","") in ["health_setback","health_support"] and not valid_social_memory(memory,state,str(id)): return "invalid_health_social_memory"
		var r: Variant = area.records[id]
		if not V.fields(r,{"created":"n","updated":"n","symptoms":"d","soiled":"b","cycle":"d","erection":"d","hpv":"d","conditions":"d","vaccine":"d","screening":"d","selfcare":"d","desire":"d"}): return "invalid_adult_health_record"
		if not r.get("care_notices") is Dictionary or r.care_notices.size()>Health.config().conditions.size()*2+3: return "invalid_care_notices"
		for key in r.care_notices:
			var allowed: Array = ["screen","vaccine","followup"]
			for condition in Health.config().conditions: allowed.append("course:"+str(condition)); allowed.append("review:"+str(condition))
			var notice: Variant = r.care_notices[key]
			if not key in allowed or not V.fields(notice,{"last":"n","snoozed_until":"n"}) or not H.integer(notice.last,-10080,now) or not H.integer(notice.snoozed_until,0,2147483647): return "invalid_care_notices"
		for key in ["created","updated"]:
			if not H.integer(r[key],0,now): return "invalid_adult_health_time"
		for key in ["last_remark","last_consult"]:
			if not H.integer(r.get(key),-10080,now): return "invalid_adult_health_time"
		for key in ["relief_until","consult_after"]:
			if not H.integer(r.get(key),0,2147483647): return "invalid_adult_health_time"
		for key in r.symptoms:
			if not Health.config().symptoms.has(key) or not H.integer(r.symptoms[key],0,100): return "invalid_adult_health_symptom"
		var d: Dictionary = r.desire
		if not V.fields(d,{"baseline":"n","libido":"n","intent":"s","satisfaction":"n","frustration":"n","last_failure":"n","failures":"n"}): return "invalid_health_desire"
		for key in ["baseline","libido","satisfaction","frustration"]:
			if not H.number(d[key],0,100): return "invalid_health_desire"
		if not d.intent in ["context","want_intimacy","not_now"] or not H.integer(d.last_failure,-10080,now) or not H.integer(d.failures,0,2147483647): return "invalid_health_desire"
		var c: Dictionary = r.cycle
		if not V.fields(c,{"active":"b","day":"n","flow":"n","product":"s","fill":"n","changed":"n","leaks":"n","last_leak":"n","supplies":"d"}): return "invalid_menstrual_state"
		if not H.integer(c.day,0,90) or not H.number(c.flow,0,5) or not H.number(c.fill,0,120) or not H.integer(c.changed,0,now) or not H.integer(c.leaks,0,2147483647) or not H.integer(c.last_leak,-10080,now): return "invalid_menstrual_value"
		if c.product!="none" and not Health.config().cycle.products.has(c.product): return "invalid_menstrual_product"
		if not V.fields(c.supplies,{"pad":"n","night_pad":"n","cup":"n"}): return "invalid_menstrual_supplies"
		for product in c.supplies:
			if not Health.config().cycle.products.has(product) or not H.integer(c.supplies[product],0,100): return "invalid_menstrual_supplies"
		var e: Dictionary = r.erection
		if not V.fields(e,{"started":"n","until":"n","painful":"b","persistent":"b","episodes":"n","last_event":"n","difficulty_until":"n","difficulties":"n"}): return "invalid_erection_state"
		if not H.integer(e.started,0,now) or not H.integer(e.last_event,-10080,now): return "invalid_erection_time"
		for key in ["until","episodes","difficulty_until","difficulties"]:
			if not H.integer(e[key],0,2147483647): return "invalid_erection_value"
		for strain in r.hpv:
			if not Health.config().hpv.strains.has(strain): return "invalid_hpv_strain"
			var infection: Variant = r.hpv[strain]
			if not V.fields(infection,{"status":"s","acquired":"n","known":"b","last_result":"s","clears_at":"n","lesions_at":"n","lesions_treated":"b","persistent":"b"}): return "invalid_hpv_state"
			if not infection.status in ["active","cleared"] or not infection.last_result in ["unknown","positive","negative","lesions","no_lesions"]: return "invalid_hpv_status"
			if not H.integer(infection.acquired,0,now): return "invalid_hpv_time"
			for field in ["clears_at","lesions_at"]:
				if not H.integer(infection[field],0,2147483647): return "invalid_hpv_time"
		for condition in r.conditions:
			if not Health.config().conditions.has(condition): return "invalid_adult_health_condition"
			var item: Variant = r.conditions[condition]
			if not V.fields(item,{"status":"s","known":"b","started":"n","severity":"n","treatment_until":"n","review_at":"n"}) or not item.status in ["active","resolved"]: return "invalid_adult_health_condition"
			if not H.integer(item.started,0,now) or not H.number(item.severity,0,100) or not H.integer(item.treatment_until,0,2147483647) or not H.integer(item.review_at,0,2147483647): return "invalid_adult_health_condition"
			var course_error := care_course_error(item,now)
			if not course_error.is_empty(): return course_error
		if not V.fields(r.vaccine,{"doses":"n","next_dose":"n"}) or not H.integer(r.vaccine.doses,0,3) or not H.integer(r.vaccine.next_dose,0,2147483647): return "invalid_hpv_vaccination"
		if not V.fields(r.screening,{"last":"n","next":"n","result":"s","followup":"b"}) or not H.integer(r.screening.last,-10080,now) or not H.integer(r.screening.next,0,2147483647) or not r.screening.result in ["none","positive","negative","cell_changes","normal","under_observation"]: return "invalid_cervical_screening"
		var job: Dictionary = r.selfcare
		if not job.is_empty():
			if id=="player" or not V.fields(job,{"operation":"s","args":"d","origin":"s","destination":"s","arrival":"n","due":"n","phase":"s","pin":"n","previous_pin":"n"}): return "invalid_adult_health_job"
			if not Health.config().actions.has(job.operation) or not job.phase in ["travel","action"] or not state.social.npcs[id].pinned_until==job.pin: return "invalid_adult_health_job"
			if not H.integer(job.arrival,0,2147483647) or not H.integer(job.due,now,2147483647) or not H.integer(job.pin,int(job.due)+1,int(job.due)+1) or not H.integer(job.previous_pin,0,2147483647): return "invalid_adult_health_job_time"
	for event in area.history:
		if not V.fields(event,{"kind":"s","minute":"n","data":"d"}) or not H.integer(event.minute,0,now): return "invalid_adult_health_history"
		if event.kind in ["setback","support"]:
			var target: String = str(event.data.get("target",""))
			var partner: String = str(event.data.get("partner",""))
			if not valid_pair(state,target,partner): return "invalid_health_social_memory"
			if event.kind=="setback" and not H.number(event.data.get("mood_loss"),1,12): return "invalid_health_social_memory"
	return ""

static func care_course_error(condition: Dictionary, now: int) -> String:
	var course: Variant = condition.get("course")
	if not course is Dictionary: return "invalid_care_course"
	if course.is_empty(): return "invalid_care_course" if int(condition.treatment_until)>0 else ""
	if not V.fields(course,{"started":"n","required":"n","completed":"n","supplies":"n","missed":"n","missed_since_review":"n","last_performed":"n","next_due":"n","finish_after":"n","starting_severity":"n","review_required":"b","review_pending":"b"}): return "invalid_care_course"
	if not condition.known or not H.integer(course.started,0,now) or not H.integer(course.last_performed,int(course.started),now): return "invalid_care_course"
	if not H.integer(course.required,1,64) or not H.integer(course.completed,1,int(course.required)) or not H.integer(course.supplies,0,int(course.required)) or int(course.supplies)+int(course.completed)!=int(course.required): return "invalid_care_course_progress"
	if not H.integer(course.missed,0,2147483647) or not H.integer(course.missed_since_review,0,int(Health.config().care_plans.misses_before_review)) or int(course.missed_since_review)>int(course.missed): return "invalid_care_course_progress"
	if not H.integer(course.next_due,0,2147483647) or not H.integer(course.finish_after,int(course.started),2147483647) or int(condition.treatment_until)!=int(course.finish_after) or not H.integer(course.starting_severity,0,100): return "invalid_care_course_time"
	if (int(course.completed)==int(course.required))!=(int(course.next_due)==0): return "invalid_care_course_time"
	if course.review_required and (not course.review_pending or int(course.missed_since_review)<int(Health.config().care_plans.misses_before_review)): return "invalid_care_review"
	if condition.status=="resolved" and (int(course.completed)<int(course.required) or now<int(course.finish_after)): return "invalid_care_course_progress"
	return ""

static func valid_pair(state: Dictionary, first: String, second: String) -> bool:
	if first==second: return false
	for id in [first,second]:
		var actor: Dictionary = state.player if id=="player" else state.social.npcs.get(id,{})
		if int(actor.get("age",0))<18: return false
	return true

static func valid_social_memory(memory: Variant, state: Dictionary, owner: String) -> bool:
	if not V.fields(memory,{"kind":"s","minute":"n","data":"d"}) or not H.integer(memory.minute,0,int(state.clock.total_minutes)): return false
	if not valid_pair(state,owner,str(memory.data.get("partner",""))): return false
	return memory.kind!="health_setback" or H.number(memory.data.get("mood_loss"),1,12)
