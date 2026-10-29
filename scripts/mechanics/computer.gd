extends "res://scripts/mechanics/core/module.gd"
## Main-game computer workplace. All tasks are fictional game state, never executable code.
const Check = preload("res://scripts/mechanics/core/validation.gd")
const Stages := ["design","build","test"]

static func defaults() -> Dictionary:
	return {"version":1,"tracks":{"programmer":0,"hacker":0,"streamer":0},"specializations":{},"upgrades":{},"projects":{},"portfolio":[],"hack":{},"broadcast":{},"broadcasts":[],"lessons":{},"history":[],"serial":0,"sponsor_until":0}

func initialize() -> void:
	if not sim.state.has("computer"): sim.state.computer = defaults()

func rules() -> Dictionary: return sim.catalog.computer_rules
func _now() -> int: return int(sim.state.clock.total_minutes)
func _state() -> Dictionary: return sim.state.computer
func level(track: String) -> int: return mini(5,1+int(_state().tracks.get(track,0))/100)
func _upgrade(id: String) -> int: return int(_state().upgrades.get(id,0))
func _specialization(track: String) -> String: return str(_state().specializations.get(track,""))

func blocked() -> String:
	if not "computer" in sim.state.world.equipment: return "missing_computer"
	if not sim.is_player_home_location(str(sim.state.world.location)) or sim.room_kind(str(sim.state.world.location)) != "bedroom": return "computer_desk_required"
	if sim.state.housing.residence.is_empty() and (sim.state.world.flags.get("chapter_one_complete",false) or sim.state.world.flags.get("student_home_lost",false)): return "no_current_home"
	return ""

func _idle() -> bool: return _state().hack.is_empty() and _state().broadcast.is_empty() and sim.state.digital.pending.is_empty()
func _gain(track: String, xp: int) -> void: _state().tracks[track] = mini(100000,int(_state().tracks[track])+xp)
func _log(kind: String, details: Dictionary) -> void:
	_state().history.append({"kind":kind,"minute":_now(),"details":details.duplicate(true)})
	while _state().history.size() > 32: _state().history.pop_front()
	emit_event("computer_"+kind,details)

func board() -> Array:
	var ids: Array = rules().projects.keys()
	ids.sort()
	var result: Array = []
	var day := int(sim.state.clock.day_index)
	for index in range(3):
		var type := str(ids[posmod(int(sim._initial_seed)+day+index*2,ids.size())])
		var spec: Dictionary = rules().projects[type].duplicate(true)
		spec.id = "%d:%d" % [day,index]
		spec.type = type
		spec.accepted = _state().projects.has(spec.id)
		spec.locked = float(sim.state.player.skills.get("computing",0)) < float(spec.skill)
		result.append(spec)
	return result

func project_view(id: String) -> Dictionary:
	var p: Dictionary = _state().projects.get(id,{})
	if p.is_empty(): return {}
	var result := p.duplicate(true)
	result.id = id
	result.label = rules().projects[p.type].label
	result.brief = rules().projects[p.type].brief
	result.stage = Stages[int(p.step)] if int(p.step) < 3 else "delivery"
	result.choices = rules().project_choices.get(result.stage,{}).duplicate(true)
	for choice in result.choices:
		result.choices[choice].minutes = duration("project_step",{"step":result.stage,"choice":choice})
		result.choices[choice].energy = result.choices[choice].minutes*0.12
	result.ready = int(p.step) == 3 and float(p.quality) >= 60 and int(p.bugs) <= 1 and p.status == "active"
	result.remaining_minutes = maxi(0,int(p.deadline)-_now())
	result.estimated_pay = _project_pay(p)
	result.can_revise = p.status == "active" and int(p.step) == 3 and int(p.revisions) < 2
	return result

func _project_pay(project: Dictionary) -> int:
	return roundi(float(rules().projects[project.type].pay)*(0.7+float(project.quality)*0.005)*(1.0-0.05*int(project.revisions)))

func inspect() -> Dictionary:
	var tracks: Array = []
	for id in rules().tracks:
		tracks.append({"id":id,"label":rules().tracks[id].label,"xp":_state().tracks[id],"level":level(str(id)),"next_level_xp":level(str(id))*100 if level(str(id)) < 5 else 0,"specialization":_specialization(str(id))})
	var projects: Array = []
	for id in _state().projects: projects.append(project_view(str(id)))
	var upgrades: Array = []
	for id in rules().upgrades:
		var row: Dictionary = rules().upgrades[id].duplicate(true)
		row.id = id; row.level = _upgrade(str(id)); row.price = int(row.cost)*(int(row.level)+1)
		row.available = int(row.level) < int(row.max_level) and int(sim.state.economy.cash) >= int(row.price)
		upgrades.append(row)
	var lessons: Dictionary = rules().lessons.duplicate(true)
	for id in lessons: lessons[id].available = int(_state().lessons.get(id,-1)) != int(sim.state.clock.day_index)
	var sponsors: Dictionary = rules().sponsors.duplicate(true)
	for id in sponsors:
		sponsors[id].available = int(sim.state.economy.channel.followers) >= int(sponsors[id].followers) and _now() >= int(_state().sponsor_until)
		sponsors[id].next_available = int(_state().sponsor_until)
	var topics: Dictionary = sim.catalog.stream_topics.duplicate(true)
	for id in topics: topics[id].modifiers = stream_modifiers(str(id))
	var stream: Dictionary = _state().broadcast.duplicate(true)
	if not stream.is_empty():
		stream.event = rules().stream_events[int(stream.events[int(stream.step)])].duplicate(true)
		stream.event.erase("best")
		stream.erase("events")
		stream.choices = rules().stream_choices.duplicate(true)
	var hack: Dictionary = _state().hack.duplicate(true)
	if not hack.is_empty():
		hack.scenario = rules().hack_scenarios[int(hack.step)].duplicate(true)
		hack.choices = rules().hack_choices.duplicate(true)
	return {"blocked":blocked(),"busy":not _idle(),"tracks":tracks,"board":board(),"projects":projects,"portfolio":_state().portfolio.duplicate(true),"upgrades":upgrades,"specializations":rules().specializations.duplicate(true),"lessons":lessons,"formats":rules().formats.duplicate(true),"sponsors":sponsors,"topics":topics,"operations":sim.services.digital.execute("inspect",{}).data.operations,"hack":hack,"broadcast":stream,"broadcasts":_state().broadcasts.duplicate(true),"history":_state().history.duplicate(true),"followers":sim.state.economy.channel.followers,"trace":sim.state.digital.trace}

func _spend(minutes: int, energy: float) -> Dictionary:
	if float(sim.state.player.needs.energy) < energy: return Rules.fail("insufficient_energy")
	sim.services.character.adjust_need("energy",-energy)
	return sim.advance(minutes)

func execute(operation: String, args: Dictionary) -> Dictionary:
	if operation == "inspect": return Rules.ok(inspect())
	if operation in ["hack_abort","stream_finish"]:
		return _hack(operation,args) if operation == "hack_abort" else _stream(operation,args)
	var reason := blocked()
	if not reason.is_empty(): return Rules.fail(reason)
	if operation in ["hack_step","hack_abort"]: return _hack(operation,args)
	if operation in ["stream_step","stream_finish"]: return _stream(operation,args)
	if not _idle(): return Rules.fail("computer_session_active")
	var id := str(args.get("id",""))
	match operation:
		"upgrade":
			if not rules().upgrades.has(id): return Rules.fail("unknown_computer_upgrade")
			var tier := _upgrade(id)
			if tier >= int(rules().upgrades[id].max_level): return Rules.fail("computer_upgrade_max")
			var cost := int(rules().upgrades[id].cost)*(tier+1)
			if int(sim.state.economy.cash) < cost: return Rules.fail("insufficient_funds")
			var result := _spend(20,2)
			if not result.ok: return result
			sim.state.economy.cash -= cost
			_state().upgrades[id] = tier+1
			_log("upgraded",{"id":id,"level":tier+1})
			return Rules.ok({"description":"Рабочее место улучшено. Бонус уже действует.","level":tier+1})
		"specialize":
			if not rules().specializations.has(id): return Rules.fail("unknown_computer_specialization")
			var track := str(rules().specializations[id].track)
			if level(track) < 2: return Rules.fail("computer_level_required")
			if _specialization(track) == id: return Rules.fail("specialization_unchanged")
			var cost := 60 if not _specialization(track).is_empty() else 0
			if int(sim.state.economy.cash) < cost: return Rules.fail("insufficient_funds")
			sim.state.economy.cash -= cost
			_state().specializations[track] = id
			return Rules.ok({"description":"Специализация выбрана. Первая бесплатна; смена стоит 60 ¤."})
		"lesson":
			if not rules().lessons.has(id): return Rules.fail("unknown_computer_lesson")
			if int(_state().lessons.get(id,-1)) == int(sim.state.clock.day_index): return Rules.fail("computer_lesson_daily_limit")
			var spec: Dictionary = rules().lessons[id]
			var result := _spend(30,4)
			if not result.ok: return result
			_state().lessons[id] = int(sim.state.clock.day_index)
			_gain(str(spec.track),12)
			sim.services.character.execute("train",{"skill":spec.skill,"xp":10})
			return Rules.ok({"description":"Практика завершена: навык +10, профессиональный опыт +12."})
		"take_project": return _take(id)
		"project_step","deliver_project","revise_project","abandon_project": return _project(operation,args)
		"hack_start": return _hack(operation,args)
		"stream_start": return _stream(operation,args)
		"publish_highlight": return _highlight(id)
	return Rules.fail("unknown_operation")

func _take(id: String) -> Dictionary:
	if _state().projects.has(id): return Rules.fail("computer_project_unavailable")
	var active := 0
	for p in _state().projects.values():
		if p.status == "active": active += 1
	if active >= 3: return Rules.fail("computer_project_capacity")
	for offer in board():
		if offer.id != id: continue
		if offer.locked: return Rules.fail("computer_skill_required")
		_state().projects[id] = {"type":offer.type,"step":0,"quality":25.0,"bugs":0,"deadline":_now()+int(offer.deadline),"status":"active","revisions":0,"paid":0,"choices":[]}
		return Rules.ok({"description":"Заказ принят. Сначала уточните задачу, затем выполните реализацию и проверку.","project":project_view(id)})
	return Rules.fail("computer_project_unavailable")

func _project(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id",""))
	var p: Dictionary = _state().projects.get(id,{})
	if p.is_empty() or p.status != "active": return Rules.fail("computer_project_not_active")
	if _now() >= int(p.deadline): return Rules.fail("computer_project_expired")
	if operation == "abandon_project":
		p.status = "abandoned"
		_log("project_abandoned",{"id":id})
		return Rules.ok({"description":"Заказ закрыт без оплаты. Выполненные шаги сохранены в истории."})
	if operation == "deliver_project":
		if not project_view(id).ready: return Rules.fail("computer_project_needs_revision")
		var pay := _project_pay(p)
		p.status = "delivered"; p.paid = pay
		sim.state.economy.cash += pay
		_gain("programmer",35)
		_state().portfolio.append({"id":id,"type":p.type,"quality":p.quality,"minute":_now(),"pay":pay})
		while _state().portfolio.size() > 24: _state().portfolio.pop_front()
		_log("project_delivered",{"id":id,"pay":pay,"quality":p.quality})
		return Rules.ok({"description":"Клиент принял работу. Оплата получена; проект добавлен в портфолио.","completed":true,"pay":pay})
	var minutes := 30
	var quality := 8.0
	var bugs := -2
	if operation == "revise_project":
		if int(p.step) != 3 or int(p.revisions) >= 2: return Rules.fail("computer_revision_unavailable")
	else:
		if int(p.step) >= 3 or not args.get("step") is String or args.step != Stages[int(p.step)]: return Rules.fail("stale_computer_step")
		var choice: Dictionary = rules().project_choices[args.step].get(str(args.get("choice","")),{})
		if choice.is_empty(): return Rules.fail("invalid_computer_choice")
		minutes = int(choice.minutes); quality = float(choice.quality); bugs = int(choice.bugs)
	minutes = maxi(10,ceili(minutes*(1.0-0.08*_upgrade("processor"))))
	if _now()+minutes >= int(p.deadline): return Rules.fail("computer_deadline_too_close")
	var result := _spend(minutes,minutes*0.12)
	if not result.ok: return result
	var skill := minf(3,float(sim.state.player.skills.get("computing",0))/100.0)
	p.quality = minf(100,float(p.quality)+quality+skill+(3.0 if _specialization("programmer") == rules().projects[p.type].kind else 0.0))
	p.bugs = maxi(0,int(p.bugs)+bugs)
	if operation == "revise_project": p.revisions += 1
	else:
		p.choices.append(str(args.choice))
		p.step += 1
	_gain("programmer",8)
	sim.services.character.execute("train",{"skill":"computing","xp":6})
	return Rules.ok({"description":"Этап выполнен. Качество: %d/100; нерешённых замечаний: %d." % [roundi(p.quality),p.bugs],"project":project_view(id),"minutes":minutes})

func digital_modifiers(id: String) -> Dictionary:
	var legal := float(sim.catalog.digital_operations.get(id,{}).get("risk",0)) == 0
	var intel := 0
	var pressure := 0
	if _state().hack.get("id","") == id:
		intel = int(_state().hack.intel); pressure = int(_state().hack.pressure)
	var bonus := 0.015*_upgrade("network")+minf(0.10,intel*0.02)-pressure*0.01
	if legal and _specialization("hacker") == "defense": bonus += 0.04
	return {"chance":bonus,"trace_scale":0.8 if not legal and _specialization("hacker") == "covert" else 1.0}

func _hack(operation: String, args: Dictionary) -> Dictionary:
	var id := str(args.get("id",""))
	if operation == "hack_start":
		var result: Dictionary = sim.services.digital.execute("scan",{"id":id})
		if not result.ok: return result
		_state().hack = {"id":id,"token":int(result.data.token),"step":0,"intel":0,"pressure":0,"expires":int(sim.state.digital.pending.expires)}
		return Rules.ok({"description":"Подготовка готова. Пройдите три этапа, затем выберите темп завершения операции.","token":result.data.token})
	var session: Dictionary = _state().hack
	if session.is_empty() or not Check.number(args.get("token")) or args.token != session.token: return Rules.fail("stale_computer_session")
	if operation == "hack_abort":
		sim.services.digital.execute("cancel",{})
		_state().hack = {}
		return Rules.ok({"description":"Операция остановлена. Уже потраченное время и накопленный след сохраняются."})
	if not Check.number(args.get("step")) or args.step != session.step: return Rules.fail("stale_computer_step")
	var choice: Dictionary = rules().hack_choices.get(str(args.get("choice","")),{})
	if choice.is_empty(): return Rules.fail("invalid_computer_choice")
	var approach := str(args.get("approach","balanced"))
	if not approach in ["careful","balanced","fast"]: return Rules.fail("invalid_digital_approach")
	# Reserve enough remaining report lifetime for the final operation as well.
	var ending := _now()+int(choice.minutes)
	if int(session.step) == 2: ending += int(sim.services.digital.preview(str(session.id),approach).data.minutes)
	if ending >= int(session.expires): return Rules.fail("computer_report_too_old")
	var advanced := _spend(int(choice.minutes),float(choice.minutes)*0.1)
	if not advanced.ok: return advanced
	session.intel += int(choice.intel)
	session.pressure = maxi(0,int(session.pressure)+int(choice.pressure))
	if float(sim.catalog.digital_operations[session.id].risk) > 0:
		sim.state.digital.trace = minf(100,float(sim.state.digital.trace)+maxi(0,int(choice.pressure)))
	if int(session.step) < 2:
		session.step += 1
		return Rules.ok({"description":"Этап завершён. Подготовка: %d; давление: %d." % [session.intel,session.pressure],"token":session.token,"step":session.step})
	var target := str(session.id)
	var resolved: Dictionary = sim.services.digital.execute("resolve",{"id":target,"token":session.token,"approach":approach})
	if not resolved.ok: return resolved
	_state().hack = {}
	_gain("hacker",25 if resolved.data.success else 8)
	_log("operation_completed",{"id":target,"success":resolved.data.success,"reward":resolved.data.reward})
	# The composite operation emits the same committed quest fact once.
	sim.services.events.observe("digital","resolve",{"id":target},resolved)
	resolved.data.completed = true
	return resolved

func stream_modifiers(topic: String) -> Dictionary:
	var recent := 0
	# Per-minute accounting prevents splitting an identical show into short clips from evading fatigue.
	for row in _state().broadcasts:
		if row.topic == topic and _now()-int(row.minute) < 1440: recent += int(row.minutes)
	var session: Dictionary = _state().broadcast
	if session.get("topic","") == topic: recent += int(session.step)*15
	var match_specialty := (_specialization("streamer") == "educator" and topic == "education") or (_specialization("streamer") == "entertainer" and topic in ["games","creative"])
	var quality := 3.0*_upgrade("studio")+_upgrade("network")+(4.0 if match_specialty else 0.0)
	if not session.is_empty(): quality += float(session.quality)+float(session.engagement)*0.25
	return {"quality":quality,"audience_scale":clampf(1.0-recent/600.0,0.6,1.0)}

func _stream(operation: String, args: Dictionary) -> Dictionary:
	if operation == "stream_start":
		var topic := str(args.get("id",""))
		var format := str(args.get("format","focused"))
		var segments: Variant = args.get("segments",4)
		var sponsor := str(args.get("sponsor",""))
		if not sim.catalog.stream_topics.has(topic) or not rules().formats.has(format) or not Check.number(segments) or int(segments) != segments or segments < 2 or segments > 6: return Rules.fail("invalid_stream_plan")
		if format == "showcase" and _state().portfolio.is_empty(): return Rules.fail("computer_portfolio_required")
		if not sponsor.is_empty():
			if not rules().sponsors.has(sponsor) or int(sim.state.economy.channel.followers) < int(rules().sponsors[sponsor].followers) or _now() < int(_state().sponsor_until): return Rules.fail("computer_sponsor_unavailable")
		var result := _spend(10,2)
		if not result.ok: return result
		_state().serial += 1
		var events: Array = []
		for i in range(int(segments)): events.append(sim.rng.randi_range(0,rules().stream_events.size()-1))
		_state().broadcast = {"token":int(_state().serial),"topic":topic,"format":format,"segments":int(segments),"step":0,"quality":0.0,"engagement":0.0,"income":0,"followers":0,"started":_now(),"expires":_now()+480,"events":events,"sponsor":sponsor,"quality_sum":0.0}
		return Rules.ok({"token":int(_state().serial),"description":"Эфир подготовлен. Каждый блок длится 15 минут; реагируйте на происходящее в чате."})
	var p: Dictionary = _state().broadcast
	if p.is_empty() or not Check.number(args.get("token")) or args.token != p.token: return Rules.fail("stale_computer_session")
	if operation == "stream_finish": return _finish_stream(false)
	if not Check.number(args.get("step")) or args.step != p.step: return Rules.fail("stale_computer_step")
	var choice := str(args.get("choice",""))
	if not rules().stream_choices.has(choice): return Rules.fail("invalid_computer_choice")
	var event: Dictionary = rules().stream_events[int(p.events[int(p.step)])]
	var spec: Dictionary = rules().stream_choices[choice]
	p.quality = clampf(float(p.quality)+float(spec.quality)+(3 if event.best == choice else -2),-10,20)
	p.engagement = clampf(float(p.engagement)+float(spec.engagement)+(2 if p.format == "community" and choice == "chat" else 0),-10,20)
	if p.format == "focused" and choice == "content": p.quality = minf(20,float(p.quality)+2)
	if p.format == "showcase" and choice == "content": p.quality = minf(20,float(p.quality)+3)
	if _now()+15 >= int(p.expires): return Rules.fail("computer_stream_expiring")
	var result: Dictionary = sim.services.careers._stream(str(p.topic),15)
	if not result.ok: return result
	p.income += int(result.data.income); p.followers += int(result.data.followers)
	p.quality_sum += float(result.data.quality)
	p.step += 1
	_gain("streamer",5)
	if int(p.step) == int(p.segments): return _finish_stream(true)
	return Rules.ok({"description":"Блок завершён: +%d зрителей-подписчиков, доход %d ¤." % [result.data.followers,result.data.income],"step":p.step,"token":p.token})

func _finish_stream(completed: bool) -> Dictionary:
	var p: Dictionary = _state().broadcast
	var quality := float(p.quality_sum)/maxi(1,int(p.step))
	var sponsor_pay := 0
	if completed and not str(p.sponsor).is_empty():
		_state().sponsor_until = _now()+10080
		if quality >= float(rules().sponsors[p.sponsor].quality):
			sponsor_pay = int(rules().sponsors[p.sponsor].pay)
			sim.state.economy.cash += sponsor_pay
	var row := {"id":"stream_%d" % p.token,"topic":p.topic,"minute":_now(),"minutes":int(p.step)*15,"quality":quality,"income":int(p.income)+sponsor_pay,"followers":p.followers,"completed":completed,"highlight":false}
	_state().broadcasts.append(row)
	while _state().broadcasts.size() > 48: _state().broadcasts.pop_front()
	_state().broadcast = {}
	_gain("streamer",15 if completed else 0)
	_log("stream_finished",row)
	return Rules.ok({"description":"Эфир завершён. Доход: %d ¤; новые подписчики: %d; качество: %d/100." % [row.income,row.followers,roundi(quality)],"completed":completed,"sponsor_pay":sponsor_pay,"broadcast":row.duplicate(true)})

func _highlight(id: String) -> Dictionary:
	for row in _state().broadcasts:
		if row.id != id: continue
		if row.highlight or not row.completed or float(row.quality) < 40: return Rules.fail("computer_highlight_unavailable")
		var result := _spend(20,3)
		if not result.ok: return result
		row.highlight = true
		var followers := maxi(1,floori(float(row.quality)/15.0))
		sim.state.economy.channel.followers += followers
		_gain("streamer",8)
		return Rules.ok({"description":"Нарезка опубликована. Новые подписчики: %d." % followers,"followers":followers})
	return Rules.fail("computer_highlight_unavailable")

func observe(module_id: String, operation: String, args: Dictionary, result: Dictionary, before: Dictionary) -> void:
	if module_id == "digital" and operation == "resolve": _gain("hacker",15 if result.data.get("success",false) else 4)
	if module_id == "careers" and operation == "claim_contract":
		if sim.catalog.contracts.get(str(args.get("id","")),{}).get("profession","") == "digital": _gain("programmer",25)
	if module_id == "livelihood" and result.data.get("completed",false) and not result.data.get("caught",false):
		var id := str(args.get("id",before.livelihood.pending.get("id","")))
		var skill := str(sim.catalog.livelihood_rules.jobs.get(id,{}).get("skill",""))
		if id == "broadcast_host": _gain("streamer",12)
		if skill in ["computing","cybersecurity"]: _gain("hacker" if skill == "cybersecurity" or id == "shadow_commission" else "programmer",12)
	if module_id in ["careers","economy"] and operation == "stream":
		_gain("streamer",maxi(1,(int(sim.state.clock.total_minutes)-int(before.clock.total_minutes))/5))
		_state().broadcasts.append({"id":"quick_%d" % int(_state().serial),"topic":str(args.get("id",args.get("topic","games"))),"minute":_now(),"minutes":int(sim.state.clock.total_minutes)-int(before.clock.total_minutes),"quality":float(result.data.get("quality",0)),"income":int(result.data.get("income",0)),"followers":int(result.data.get("followers",0)),"completed":true,"highlight":false})
		_state().serial += 1
		while _state().broadcasts.size() > 48: _state().broadcasts.pop_front()

func tick(minute: int) -> void:
	for p in _state().projects.values():
		if p.status == "active" and minute >= int(p.deadline):
			p.status = "expired"
			_log("project_expired",{"type":p.type})
	if not _state().hack.is_empty() and minute >= int(_state().hack.expires):
		_state().hack = {}
		_log("report_expired",{})
	if not _state().broadcast.is_empty() and minute >= int(_state().broadcast.expires): _finish_stream(false)
	if minute % 1440 == 0:
		# Old terminal jobs are bounded; today's identifiers remain reserved against duplicate acceptance.
		for id in _state().projects.keys():
			if _state().projects[id].status != "active" and int(str(id).get_slice(":",0)) < int(sim.state.clock.day_index)-7: _state().projects.erase(id)

func duration(operation: String, args: Dictionary) -> int:
	match operation:
		"upgrade","publish_highlight": return 20
		"lesson": return 30
		"stream_start": return 10
		"stream_step","hack_start": return 15
		"hack_step":
			var minutes := int(rules().hack_choices.get(str(args.get("choice","")),{}).get("minutes",0))
			if int(_state().hack.get("step",0)) == 2:
				minutes += int(sim.services.digital.preview(str(_state().hack.get("id","")),str(args.get("approach","balanced"))).get("data",{}).get("minutes",0))
			return minutes
		"project_step","revise_project":
			var minutes := 30 if operation == "revise_project" else int(rules().project_choices.get(str(args.get("step","")),{}).get(str(args.get("choice","")),{}).get("minutes",0))
			return maxi(10,ceili(minutes*(1.0-0.08*_upgrade("processor"))))
	return 0
