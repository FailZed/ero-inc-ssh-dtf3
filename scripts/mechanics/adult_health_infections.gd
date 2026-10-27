extends "res://scripts/mechanics/core/module.gd"
## HPV strain groups, observable conditions and provider-mediated results.

func health():
	return sim.services.adult_health

func now() -> int:
	return int(sim.state.clock.total_minutes)

func seed_population(id: String) -> void:
	if id=="player": return
	for strain in health().config().hpv.strains:
		if health().unit(id+":initial_hpv:"+str(strain))<float(health().config().hpv.strains[strain].initial_fraction): acquire(id,str(strain),"initial:"+id)

func acquire(id: String, strain: String, key: String) -> void:
	if not health().adult(id) or not health().config().hpv.strains.has(strain): return
	var r: Dictionary = health().record(id)
	if r.is_empty() or r.hpv.get(strain,{}).get("status","")=="active": return
	var persistent: bool = health().unit(id+":"+key+":persistence:"+strain)<float(health().config().hpv.persistence_fraction)
	var months := 6+int(health().unit(id+":"+key+":clearance:"+strain)*19)
	var lesions: bool = strain=="low_risk" and health().unit(id+":"+key+":lesions")<float(health().config().hpv.lesion_fraction)
	r.hpv[strain] = {"status":"active","acquired":now(),"known":false,"last_result":"unknown",
		"clears_at":0 if persistent else sim.calendar.add_months(now(),months),"lesions_at":now()+43200 if lesions else 0,
		"lesions_treated":false,"persistent":persistent}
	health().log_event("hpv_acquired",{"target":id,"strain":strain})

func contact(first: String, second: String, protection: String, key: String) -> void:
	var sources := {first:health().record(first).hpv.duplicate(true),second:health().record(second).hpv.duplicate(true)}
	for pair in [[first,second],[second,first]]:
		var source := str(pair[0])
		var target := str(pair[1])
		for strain in sources[source]:
			if sources[source][strain].status!="active" or health().record(target).hpv.get(strain,{}).get("status","")=="active": continue
			var chance := float(health().config().hpv.contact_chance)
			if protection=="barrier": chance *= float(health().config().hpv.barrier_residual)
			var doses := int(health().record(target).vaccine.doses)
			chance *= float(health().config().hpv.vaccine_residual[doses])
			if health().unit(key+":"+source+":"+target+":"+str(strain))<chance: acquire(target,str(strain),key)

func refresh_symptoms(id: String) -> void:
	var r: Dictionary = health().record(id)
	for strain in r.hpv:
		var infection: Dictionary = r.hpv[strain]
		if infection.status=="active" and int(infection.lesions_at)>0 and now()>=int(infection.lesions_at) and not infection.lesions_treated: r.symptoms.visible_growths = 45

func onset(id: String, condition_id: String) -> bool:
	if not health().adult(id) or not health().config().conditions.has(condition_id): return false
	var spec: Dictionary = health().config().conditions[condition_id]
	if spec.get("requires","")=="erections" and not health().capabilities(id).erections: return false
	var r: Dictionary = health().record(id)
	if r.is_empty() or r.conditions.get(condition_id,{}).get("status","")=="active": return false
	r.conditions[condition_id] = {"status":"active","known":false,"started":now(),"severity":45+int(health().unit(id+":"+condition_id+":"+str(now()))*30),"treatment_until":0,"review_at":now()+1440}
	health()._refresh(id)
	return true

func tick_actor(id: String) -> void:
	var r: Dictionary = health().record(id)
	for strain in r.hpv:
		var infection: Dictionary = r.hpv[strain]
		if infection.status=="active" and int(infection.clears_at)>0 and now()>=int(infection.clears_at):
			infection.status = "cleared"
			health().log_event("hpv_clearance",{"target":id,"strain":strain})
	for key in r.conditions:
		var condition: Dictionary = r.conditions[key]
		if condition.status=="active" and int(condition.treatment_until)>0 and now()>=int(condition.treatment_until):
			condition.status = "resolved"
			health().log_event("treatment_finished",{"target":id,"condition":key,"text":"Назначенный курс завершён. Если симптомы сохраняются, нужен повторный осмотр."})
	if now()%1440==0:
		for key in health().config().conditions:
			var chance := float(health().config().conditions[key].daily_chance)
			if health().pregnant(id) and key in ["urinary_infection","candidiasis"]: chance *= 1.5
			if health().unit(id+":"+str(key)+":onset:"+str(now()))<chance: onset(id,str(key))
	health()._refresh(id)

func consult(id: String) -> void:
	var r: Dictionary = health().record(id)
	for condition in r.conditions.values():
		if condition.status=="active": condition.known = true
	for infection in r.hpv.values():
		if infection.status=="active" and int(infection.lesions_at)>0 and now()>=int(infection.lesions_at) and not infection.lesions_treated:
			infection.known = true
			infection.last_result = "lesions"
	r.erection.difficulties = 0
	r.consult_after = now()+1440
	r.last_consult = now()

func screen(id: String) -> void:
	var r: Dictionary = health().record(id)
	if int(health().actor(id).age)<int(health().config().hpv.hpv_test_min_age):
		var changes := false
		var high: Dictionary = r.hpv.get("high_risk",{})
		if high.get("status","")=="active" and now()-int(high.acquired)>=525600 and health().unit(id+":cell_changes")<0.15: changes = true
		r.screening = {"last":now(),"next":now()+int(health().config().hpv.screening_interval),"result":"cell_changes" if changes else "normal","followup":changes}
		health().log_event("screening",{"target":id,"text":"Цитологический скрининг выявил изменения клеток: нужен уточняющий осмотр." if changes else "Цитологический скрининг не выявил изменений клеток. Это не универсальный тест на ВПЧ."})
		return
	var positive := false
	for strain in r.hpv:
		if strain!="high_risk": continue
		var infection: Dictionary = r.hpv[strain]
		infection.known = true
		infection.last_result = "positive" if infection.status=="active" else "negative"
		positive = infection.status=="active"
	r.screening = {"last":now(),"next":now()+int(health().config().hpv.screening_interval),"result":"positive" if positive else "negative","followup":positive}
	health().log_event("screening",{"target":id,"text":"Скрининг выявил ВПЧ высокого риска. Нужен план наблюдения; это не диагноз рака." if positive else "Скрининг не выявил ВПЧ высокого риска в исследованном образце."})
