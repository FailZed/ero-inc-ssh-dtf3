extends "res://scripts/mechanics/core/module.gd"

func health():
	return sim.services.adult_health

func refresh(id: String) -> void:
	var r: Dictionary = health().record(id)
	var c: Dictionary = r.cycle
	var was_active: bool = c.active
	var reproductive: Dictionary = sim.services.reproduction.view(id)
	var now := int(sim.state.clock.total_minutes)
	var recovering: bool = int(reproductive.recovery_until)>now or sim.state.get("pregnancy_wellbeing",{}).get("records",{}).get(id,{}).get("phase","")=="postpartum"
	var menstruates: bool = health().capabilities(id).menstruates and not health().pregnant(id) and not recovering
	c.active = menstruates and reproductive.phase=="menstruation"
	if was_active and not c.active:
		c.product = "none"
		c.fill = 0.0
	c.day = int(reproductive.cycle_day) if menstruates else 0
	c.flow = 0.0
	if c.active:
		var patterns: Array = health().config().cycle.flow_pattern
		var index := mini(patterns.size()-1,int(c.day)-1)
		var heavy: bool = health().unit(id+":heavy_periods")<float(health().config().cycle.heavy_fraction)
		c.flow = float(patterns[index])*(1.8 if heavy else 1.0)
		var severity := clampi(roundi(25+health().unit(id+":cramps")*45),0,90)
		r.symptoms.period_cramps = severity
		r.symptoms.cycle_fatigue = roundi(severity*0.65)
		if heavy: r.symptoms.heavy_flow = 75
	elif menstruates and int(c.day)>int(reproductive.cycle_days)-5:
		if health().unit(id+":pms")<0.7:
			r.symptoms.premenstrual_discomfort = 25+int(health().unit(id+":pms_level")*35)
			r.symptoms.cycle_headache = 15+int(health().unit(id+":headache_level")*25)
	else:
		c.fill = 0.0

func tick_actor(id: String, minutes: int) -> void:
	var r: Dictionary = health().record(id)
	var c: Dictionary = r.cycle
	if not c.active or minutes<=0: return
	var products: Dictionary = health().config().cycle.products
	var absorbency := float(products.get(str(c.product),{}).get("absorbency",0.45))
	c.fill = snappedf(minf(120,float(c.fill)+float(c.flow)*minutes/maxf(0.1,absorbency)),0.0001)
	var now := int(sim.state.clock.total_minutes)
	var overdue: bool = c.product!="none" and now-int(c.changed)>=int(products[c.product].change_minutes)
	var leaking: bool = (c.product=="none" and float(c.fill)>=30) or float(c.fill)>=100 or overdue
	if leaking and now-int(c.last_leak)>=int(health().config().cycle.leak_cooldown):
		c.last_leak = now
		c.leaks += 1
		r.soiled = true
		health().adjust(id,"hygiene",-8)
		health().adjust(id,"mood",-2)
		health().log_event("menstrual_leak",{"target":id,"text":"Средство гигиены не справилось с выделениями. Нужны уединение, замена средства и смена одежды."})

func change(id: String, product: String) -> Dictionary:
	if not health().capabilities(id).menstruates: return Rules.fail("menstrual_capability_required")
	var r: Dictionary = health().record(id)
	if not health().config().cycle.products.has(product): return Rules.fail("unknown_menstrual_product")
	if int(r.cycle.supplies.get(product,0))<1: return Rules.fail("missing_menstrual_product")
	if product!="cup": r.cycle.supplies[product] -= 1
	r.cycle.product = product
	r.cycle.fill = 0.0
	r.cycle.changed = int(sim.state.clock.total_minutes)
	return Rules.ok()
