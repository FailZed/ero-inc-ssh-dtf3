extends "res://scripts/mechanics/core/module.gd"
## Fictional, configurable simulation. Scene content and real clinical guidance are absent.
const CHECK = preload("res://scripts/mechanics/core/human_validation.gd")

static func defaults() -> Dictionary:
	return {"version":1, "records":{}, "exposures":{}, "pregnancies":{}, "next_id":1, "history":[]}

func rules() -> Dictionary:
	return definition("reproduction_rules", "simulation")

func _now() -> int:
	return int(sim.state.clock.total_minutes)

func actor(id: String) -> Dictionary:
	return sim.state.player if id == "player" else sim.state.social.npcs.get(id, {})

func _new_record(id: String) -> Dictionary:
	var subject := actor(id)
	var gender := str(subject.get("gender", subject.get("appearance", {}).get("gender", "male")))
	var profile: Dictionary = subject.get("reproductive_profile", {})
	var facets: Dictionary = subject.get("psychology", {}).get("facets", {})
	var prudence := float(facets.get("prudence", 50))
	var default_desire := "avoid" if id == "player" or prudence >= 65 else "want" if float(facets.get("sentimentality", 50)) >= 60 else "open"
	return {"can_gestate":profile.get("can_gestate", gender == "female"), "produces_sperm":profile.get("produces_sperm", gender == "male"),
		"cycling":profile.get("cycling", gender == "female"), "fertility":profile.get("fertility", 1.0),
		"infertile":profile.get("infertile", false), "sterilization":"none", "effective_at":0, "recovery_until":0,
		"cycle_epoch":0, "cycle_offset":int(profile.get("cycle_offset", 0)), "cycle_days":int(rules().cycle_days),
		"period_days":int(rules().period_days), "ovulation_day":int(rules().ovulation_day),
		"desire":str(profile.get("desire", default_desire)), "requires_protection":profile.get("requires_protection", id == "player" or default_desire == "avoid" or prudence >= 55),
		"method":"none", "method_started":0, "method_effective":0, "method_until":0, "last_dose":-1}

func record(id: String) -> Dictionary:
	if not sim.state.reproduction.records.has(id): sim.state.reproduction.records[id] = _new_record(id)
	return sim.state.reproduction.records[id]

func view(id: String = "player") -> Dictionary:
	if actor(id).is_empty(): return {}
	var r: Dictionary = sim.state.reproduction.records.get(id, _new_record(id)).duplicate(true)
	var day := posmod(int((_now() - int(r.cycle_epoch)) / 1440) + int(r.cycle_offset), int(r.cycle_days))
	var active := pregnancy(id)
	r.cycle_day = day + 1
	r.phase = "pregnancy" if not active.is_empty() else "none" if not r.cycling else "menstruation" if day < int(r.period_days) else "ovulation" if day == int(r.ovulation_day) - 1 else "follicular" if day < int(r.ovulation_day) - 1 else "luteal"
	r.fertile_window = r.cycling and active.is_empty() and _now()>=int(r.recovery_until) and day >= int(r.ovulation_day) - 1 - int(rules().fertile_before) and day <= int(r.ovulation_day) - 1 + int(rules().fertile_after)
	r.method_active = r.method != "none" and _now() >= int(r.method_effective) and _now() < int(r.method_until)
	r.sterile = r.infertile or (r.sterilization != "none" and _now() >= int(r.effective_at))
	r.pregnancy = active.duplicate(true)
	return r

func pregnancy(target: String) -> Dictionary:
	for entry in sim.state.reproduction.pregnancies.values():
		if entry.target == target and entry.status == "active": return entry
	return {}

func _log(kind: String, data: Dictionary) -> void:
	sim.state.reproduction.history.append({"kind":kind, "minute":_now(), "data":data.duplicate(true)})
	while sim.state.reproduction.history.size() > int(rules().history_limit): sim.state.reproduction.history.pop_front()
	emit_event("reproduction_" + kind, data)

func _id(prefix: String) -> String:
	var result := prefix + str(int(sim.state.reproduction.next_id))
	sim.state.reproduction.next_id += 1
	return result

func _patient(args: Dictionary) -> String:
	var target := str(args.get("target", "player"))
	return target if str(args.get("actor", "player")) == target else ""

func _clinic(target: String = "player") -> bool:
	var location := str(sim.state.world.location) if target == "player" else str(actor(target).get("location", ""))
	return location == "clinic" and sim.services.world.is_open(definition("locations", "clinic"))

func execute(operation: String, args: Dictionary) -> Dictionary:
	var target := str(args.get("target", "player"))
	if actor(target).is_empty(): return Rules.fail("unknown_patient")
	if operation == "inspect": return Rules.ok(view(target))
	if operation == "pregnancy_response": return _response(target, str(args.get("actor", "player")), str(args.get("response", "")))
	if _patient(args).is_empty(): return Rules.fail("patient_decision_required")
	var r := record(target)
	match operation:
		"configure":
			if not args.get("profile") is Dictionary: return Rules.fail("invalid_reproductive_profile")
			if not pregnancy(target).is_empty(): return Rules.fail("reproductive_profile_locked")
			for entry in sim.state.reproduction.exposures.values():
				if target in [entry.target, entry.partner]: return Rules.fail("reproductive_profile_locked")
			if not sim.state.intimacy.active.is_empty(): return Rules.fail("finish_active_intimacy")
			if r.sterilization != "none": return Rules.fail("reproductive_profile_locked")
			for key in args.profile:
				if not key in ["can_gestate", "produces_sperm", "cycling", "fertility", "infertile", "cycle_offset", "cycle_days", "period_days", "ovulation_day"]: return Rules.fail("invalid_reproductive_profile")
				r[key] = args.profile[key]
			return Rules.ok()
		"preference":
			if args.has("desire"):
				if not args.desire in ["avoid", "open", "want"]: return Rules.fail("invalid_pregnancy_desire")
				r.desire = args.desire
			if args.has("requires_protection"):
				if not args.requires_protection is bool: return Rules.fail("invalid_protection_preference")
				r.requires_protection = args.requires_protection
			_log("preference", {"target":target})
		"contraception": return _contraception(target, str(args.get("method", "")))
		"emergency": return _emergency(target)
		"test": return _test(target)
		"procedure": return _procedure(target, str(args.get("id", "")), args.get("confirm", false) == true)
		"pregnancy_decision": return _decision(target, str(args.get("decision", "")), args.get("confirm", false) == true)
		"parenthood": return _parenthood(target, str(args.get("member", "")), str(args.get("decision", "")), args.get("confirm", false) == true)
		_: return Rules.fail("unknown_operation")
	return Rules.ok()

func _funds(target: String) -> int:
	return int(sim.state.economy.cash) if target == "player" else int(actor(target).money)

func _pay(target: String, amount: int) -> bool:
	if _funds(target) < amount: return false
	if target == "player": sim.state.economy.cash -= amount
	else: actor(target).money -= amount
	return true

func _contraception(target: String, method: String, elapse: bool = true) -> Dictionary:
	if not sim.catalog.contraceptive_methods.has(method): return Rules.fail("unknown_contraception")
	var r := record(target)
	if not r.can_gestate: return Rules.fail("gestational_capability_required")
	if not pregnancy(target).is_empty(): return Rules.fail("active_pregnancy")
	if method == "none":
		if r.method != "none" and not sim.catalog.contraceptive_methods[r.method].daily and not _clinic(target): return Rules.fail("clinic_required")
		r.method = "none"
		r.method_until = 0
		_log("contraception", {"target":target, "method":method})
		return Rules.ok()
	var spec: Dictionary = sim.catalog.contraceptive_methods[method]
	if r.method != "none" and r.method != method: return Rules.fail("remove_existing_contraception")
	if not spec.daily and r.method == method and int(r.method_until) > _now(): return Rules.fail("contraception_already_active")
	if not spec.daily and not _clinic(target): return Rules.fail("clinic_required")
	if spec.daily and int(r.last_dose) >= 0 and _now() - int(r.last_dose) < 1440: return Rules.fail("dose_already_taken")
	if not str(spec.item).is_empty():
		if target != "player":
			if int(actor(target).inventory.get(spec.item, 0)) < 1: return Rules.fail("missing_contraception")
			actor(target).inventory[spec.item] -= 1
			if int(actor(target).inventory[spec.item]) == 0: actor(target).inventory.erase(spec.item)
		else:
			var consumed: Dictionary = sim.services.inventory.change(str(spec.item), -1)
			if not consumed.ok: return consumed
	if not _pay(target, int(spec.cost)): return Rules.fail("insufficient_funds")
	var continuous: bool = r.method == method and _now() <= int(r.method_until)
	r.method = method
	if not continuous:
		r.method_started = _now()
		r.method_effective = _now() + int(spec.onset)
	r.method_until = _now() + int(spec.duration)
	if spec.daily: r.last_dose = _now()
	_log("contraception", {"target":target, "method":method})
	return sim.advance(int(spec.minutes)) if elapse else Rules.ok()

func _procedure(target: String, id: String, confirmed: bool, elapse: bool = true) -> Dictionary:
	if not confirmed: return Rules.fail("confirmation_required")
	if not _clinic(target): return Rules.fail("clinic_required")
	var spec := definition("reproductive_procedures", id)
	if spec.is_empty(): return Rules.fail("unknown_reproductive_procedure")
	var r := record(target)
	if not r.get(spec.capability, false): return Rules.fail("incompatible_reproductive_procedure")
	if r.sterilization != "none": return Rules.fail("already_sterilized")
	if not pregnancy(target).is_empty(): return Rules.fail("active_pregnancy")
	if not _pay(target, int(spec.cost)): return Rules.fail("insufficient_funds")
	r.sterilization = id
	r.effective_at = _now() + (int(spec.minutes) if elapse else 0) + (int(rules().vasectomy_delay_minutes) if id == "vasectomy" else 0)
	r.recovery_until = _now() + (int(spec.minutes) if elapse else 0) + int(rules().recovery_minutes)
	_log("procedure", {"target":target, "id":id})
	return sim.advance(int(spec.minutes)) if elapse else Rules.ok()

func _emergency(target: String, elapse: bool = true) -> Dictionary:
	if not pregnancy(target).is_empty(): return Rules.fail("active_pregnancy")
	var pending: Array = []
	for entry in sim.state.reproduction.exposures.values():
		if entry.target == target and entry.status == "pending" and _now() < int(entry.resolve_at) and _now() - int(entry.minute) < int(rules().emergency_minutes) and not entry.emergency:
			pending.append(entry)
	if pending.is_empty(): return Rules.fail("no_recent_exposure")
	if target == "player":
		var consumed: Dictionary = sim.services.inventory.change("emergency_contraception", -1)
		if not consumed.ok: return consumed
	else:
		if int(actor(target).inventory.get("emergency_contraception", 0)) < 1: return Rules.fail("missing_contraception")
		actor(target).inventory.emergency_contraception -= 1
		if actor(target).inventory.emergency_contraception == 0: actor(target).inventory.erase("emergency_contraception")
	for entry in pending:
		entry.emergency = true
		entry.chance *= float(rules().emergency_residual)
	_log("emergency", {"target":target, "exposures":pending.size()})
	return sim.advance(1) if elapse else Rules.ok()

func _test(target: String, elapse: bool = true) -> Dictionary:
	if not record(target).can_gestate: return Rules.fail("gestational_capability_required")
	if not _pay(target, int(rules().test_cost)): return Rules.fail("insufficient_funds")
	var p := pregnancy(target)
	var positive := not p.is_empty() and _now() >= int(p.detected_at)
	if positive: p.known = true
	_log("test", {"target":target, "positive":positive})
	var result: Dictionary = sim.advance(int(rules().test_minutes)) if elapse else Rules.ok()
	return Rules.ok({"positive":positive}) if result.ok else result

func risk(first: String, second: String, protection: String = "unprotected") -> Dictionary:
	var target := ""
	var partner := ""
	for pair in [[first, second], [second, first]]:
		var a := view(pair[0])
		var b := view(pair[1])
		if a.is_empty() or b.is_empty(): continue
		if a.can_gestate and b.produces_sperm:
			target = pair[0]
			partner = pair[1]
			break
	if target.is_empty(): return {"chance":0.0,"target":"","partner":"","reason":"no_reproductive_pairing"}
	var a := view(target)
	var b := view(partner)
	var chance := float(rules().conception_chance) * float(a.fertility) * float(b.fertility)
	if "pregnancy" in sim.state.preferences.disabled_tags: chance = 0.0
	var condition: Dictionary = sim.state.conditions.get(target + ":pregnancy", {})
	if a.sterile or b.sterile or not a.fertile_window or condition.get("status", "") == "active": chance = 0.0
	if a.method_active: chance *= float(sim.catalog.contraceptive_methods[a.method].residual)
	if protection == "barrier": chance *= float(sim.catalog.reproduction_protection.barrier.residual)
	return {"chance":clampf(chance, 0, 1), "target":target, "partner":partner, "reason":""}

func expose(first: String, second: String, protection: String, intended: bool, session: String) -> String:
	# Called only by the encounter's single completion edge, never by a scene callback directly.
	for entry in sim.state.reproduction.exposures.values():
		if entry.session == session: return str(entry.id)
	var forecast := risk(first, second, protection)
	if str(forecast.target).is_empty(): return ""
	var id := _id("exposure_")
	sim.state.reproduction.exposures[id] = {"id":id, "target":forecast.target, "partner":forecast.partner, "session":session,
		"minute":_now(), "resolve_at":_now() + int(rules().exposure_minutes), "chance":forecast.chance,
		"roll":sim.rng.randf(), "emergency":false, "intended":intended, "status":"pending", "protection":protection}
	_log("exposure", {"id":id, "target":forecast.target, "partner":forecast.partner, "protection":protection})
	return id

func _conceive(exposure: Dictionary) -> void:
	var target := str(exposure.target)
	if not pregnancy(target).is_empty() or sim.state.conditions.get(target + ":pregnancy", {}).get("status", "") == "active":
		exposure.status = "superseded"
		return
	if float(exposure.roll) >= float(exposure.chance):
		exposure.status = "no_conception"
		return
	var result: Dictionary = sim.services.lifecycle.execute("start", {"id":"pregnancy", "target":target, "partner":exposure.partner})
	if not result.ok:
		exposure.status = "superseded"
		return
	var id := _id("pregnancy_")
	sim.state.reproduction.pregnancies[id] = {"id":id, "target":target, "partner":exposure.partner, "exposure":exposure.id,
		"started":_now(), "detected_at":_now() + int(rules().detection_minutes), "known":false,
		"intended":exposure.intended, "status":"active", "decision":"undecided", "partner_response":"unasked", "outcome_at":0}
	sim.state.conditions[target + ":pregnancy"].reproduction_id = id
	exposure.status = "conceived"
	_log("conceived", {"id":id, "target":target, "partner":exposure.partner, "intended":exposure.intended})

func _decision(target: String, decision: String, confirmed: bool, elapse: bool = true) -> Dictionary:
	var p := pregnancy(target)
	if p.is_empty(): return Rules.fail("no_active_pregnancy")
	if not p.known: return Rules.fail("pregnancy_not_confirmed")
	if not decision in ["continue", "terminate", "adoption"]: return Rules.fail("invalid_pregnancy_decision")
	if p.decision == decision: return Rules.fail("pregnancy_decision_unchanged")
	if decision == "terminate":
		if not confirmed: return Rules.fail("confirmation_required")
		if not _clinic(target): return Rules.fail("clinic_required")
		if _now() - int(p.started) >= int(rules().termination_limit_days) * 1440: return Rules.fail("termination_unavailable")
		if not _pay(target, int(rules().termination_cost)): return Rules.fail("insufficient_funds")
		var result: Dictionary = sim.services.lifecycle.execute("remove", {"id":"pregnancy", "target":target})
		if not result.ok: return result
		p.status = "terminated"
		p.outcome_at = _now()
		record(target).recovery_until = _now() + (int(rules().termination_minutes) if elapse else 0) + int(rules().recovery_minutes)
		record(target).cycle_epoch = _now()
		record(target).cycle_offset = 0
	p.decision = decision
	_log("pregnancy_decision", {"id":p.id, "target":target, "decision":decision})
	return sim.advance(int(rules().termination_minutes)) if decision == "terminate" and elapse else Rules.ok()

func _response(target: String, respondent: String, response: String) -> Dictionary:
	var p := pregnancy(target)
	if p.is_empty() or not p.known: return Rules.fail("pregnancy_not_confirmed")
	if respondent != p.partner: return Rules.fail("pregnancy_partner_required")
	if not response in ["support", "decline_parenthood"]: return Rules.fail("invalid_parenthood_decision")
	if p.partner_response == response: return Rules.fail("pregnancy_decision_unchanged")
	if p.partner_response != "unasked": return Rules.fail("parenthood_response_already_recorded")
	p.partner_response = response
	if target != "player": sim.services.social.remember(target, "pregnancy_response", {"partner":respondent,"response":response})
	_log("partner_response", {"id":p.id,"target":target,"partner":respondent,"response":response})
	return Rules.ok()

func on_birth(index: int) -> void:
	var birth: Dictionary = sim.state.healthcare.family[index]
	var p := pregnancy(str(birth.parent))
	if p.is_empty(): return
	p.status = "born"
	p.outcome_at = _now()
	birth.reproduction_id = p.id
	birth.custody = "adoption" if p.decision == "adoption" else "parents"
	if p.partner_response == "decline_parenthood": birth.declined_parent = p.partner
	if p.get("gestator_parenthood", "retain") == "relinquish":
		birth.declined_parents = [p.target]
		if p.partner_response == "decline_parenthood": birth.declined_parents.append(p.partner)
	var parent_record:=record(str(p.target))
	parent_record.cycle_epoch = _now()
	parent_record.cycle_offset = 0
	parent_record.recovery_until = maxi(int(parent_record.recovery_until),_now()+int(rules().recovery_minutes))
	_log("birth", {"id":p.id, "target":p.target, "index":index})

func _parenthood(target: String, member_id: String, decision: String, confirmed: bool) -> Dictionary:
	if not confirmed: return Rules.fail("confirmation_required")
	var member: Dictionary = sim.state.family.members.get(member_id, {})
	if member.is_empty() or not target in member.parents: return Rules.fail("not_family_guardian")
	if member.stage == "adult": return Rules.fail("custody_already_ended")
	if decision != "relinquish": return Rules.fail("invalid_parenthood_decision")
	var guardians: Array = member.get("guardians", member.parents).duplicate()
	if not target in guardians: return Rules.fail("parenthood_already_relinquished")
	if not member.task.is_empty(): sim.services.family._release_caregiver(member.task)
	member.task = {}
	guardians.erase(target)
	member.guardians = guardians
	member.custody = "other_parent" if not guardians.is_empty() else "public_care"
	if not guardians.is_empty():
		for need in member.assignments: member.assignments[need] = guardians[0]
	_log("parenthood", {"target":target, "member":member_id, "custody":member.custody})
	return Rules.ok()

func tick(minute: int) -> void:
	for entry in sim.state.reproduction.exposures.values():
		if entry.status == "pending" and minute >= int(entry.resolve_at): _conceive(entry)
	for p in sim.state.reproduction.pregnancies.values():
		if p.status != "active": continue
		if sim.state.conditions.get(str(p.target) + ":pregnancy", {}).get("status", "") != "active":
			p.status = "ended"
			p.outcome_at = minute
			_log("ended", {"id":p.id,"target":p.target})
		elif not p.known and minute >= int(p.detected_at):
			p.known = true
			_log("pregnancy_detected", {"id":p.id, "target":p.target, "partner":p.partner, "intended":p.intended})
