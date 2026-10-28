extends "res://scripts/mechanics/core/module.gd"

func execute(operation: String, args: Dictionary) -> Dictionary:
	var economy: Dictionary = sim.state.economy
	var amount := int(args.get("amount", 0))
	var id := str(args.get("id", ""))
	match operation:
		"deposit", "withdraw", "repay":
			if amount <= 0: return Rules.fail("invalid_amount")
			var source := "bank" if operation == "withdraw" else "cash"
			if int(economy[source]) < amount: return Rules.fail("insufficient_funds")
			if operation == "repay" and amount > int(economy.debt): return Rules.fail("overpayment")
			economy[source] -= amount
			if operation == "repay": economy.debt -= amount
			else: economy["cash" if operation == "withdraw" else "bank"] += amount
		"borrow":
			if amount <= 0 or economy.debt + amount > int(sim.catalog.settings.credit_limit): return Rules.fail("credit_limit")
			economy.debt += amount
			economy.cash += amount
		"work": return _work(id)
		"buy_asset", "upgrade_asset", "sell_asset": return _asset(operation, id)
		"project": return _project(id, int(args.get("minutes", 60)))
		"stream":
			return sim.services.careers.execute("stream", {"id": str(args.get("topic", "games")), "minutes": int(args.get("minutes", 60))})
		_:
			return Rules.fail("unknown_operation")
	return Rules.ok()

func _work(id: String) -> Dictionary:
	var job := definition("jobs", id)
	if job.is_empty() or not Rules.check(sim.state, job.get("requirements", {})): return Rules.fail("job_requirements")
	if job.has("home_room_kind"):
		if not sim.is_player_home_location(str(sim.state.world.location)) or sim.room_kind(str(sim.state.world.location)) != job.home_room_kind: return Rules.fail("wrong_location")
	elif job.has("location") and job.location != sim.state.world.location: return Rules.fail("wrong_location")
	if not sim.services.world.is_open(job): return Rules.fail("job_closed")
	var key := "%s:%d" % [id, sim.state.clock.day_index]
	var count := int(sim.state.economy.job_counts.get(key, 0))
	if count >= int(job.get("daily_limit", 3)): return Rules.fail("job_daily_limit")
	var energy_cost: float = float(job.get("energy", 0)) * sim.multiplier("resource_cost")
	if float(sim.state.player.needs.energy) < energy_cost: return Rules.fail("insufficient_energy")
	sim.services.character.adjust_need("energy", -energy_cost)
	sim.state.economy.job_counts[key] = count + 1
	sim.state.economy.cash += int(job.get("pay", 0))
	var result: Dictionary = sim.advance(int(job.get("minutes", 60)))
	if not result.ok: return result
	return sim.services.character.execute("train", {"skill": job.get("skill", "computing"), "xp": int(job.get("xp", 5))})

func _asset(operation: String, id: String) -> Dictionary:
	var asset := definition("assets", id)
	var economy: Dictionary = sim.state.economy
	if asset.is_empty(): return Rules.fail("unknown_asset")
	if operation == "buy_asset":
		if economy.assets.has(id): return Rules.fail("already_owned")
		if economy.cash < int(asset.price): return Rules.fail("insufficient_funds")
		economy.cash -= int(asset.price)
		economy.assets[id] = {"level": 1, "invested": int(asset.price)}
	elif not economy.assets.has(id):
		return Rules.fail("asset_not_owned")
	elif operation == "upgrade_asset":
		var level := int(economy.assets[id].level)
		if level >= int(asset.get("max_level", 5)): return Rules.fail("asset_max_level")
		var price := int(asset.get("upgrade_cost", asset.price)) * level
		if economy.cash < price: return Rules.fail("insufficient_funds")
		economy.cash -= price
		economy.assets[id].level += 1
		economy.assets[id].invested += price
	else:
		economy.cash += int(economy.assets[id].invested * float(asset.get("sell_ratio", 0.6)))
		economy.assets.erase(id)
	return Rules.ok()

func _project(id: String, minutes: int) -> Dictionary:
	var project := definition("projects", id)
	if project.is_empty() or minutes <= 0 or minutes > 480: return Rules.fail("invalid_project")
	if not Rules.check(sim.state, project.get("requirements", {})): return Rules.fail("project_requirements")
	var progress: Dictionary = sim.state.economy.projects.get(id, {"progress": 0, "completed": false})
	if progress.completed: return Rules.fail("project_completed")
	var effort := mini(minutes, int(project.get("effort", 120)) - int(progress.progress))
	var energy_cost: float = float(effort) / 10.0 * sim.multiplier("resource_cost")
	if sim.state.player.needs.energy < energy_cost: return Rules.fail("insufficient_energy")
	sim.services.character.adjust_need("energy", -energy_cost)
	progress.progress += effort
	if int(progress.progress) >= int(project.get("effort", 120)):
		progress.completed = true
		sim.state.economy.cash += int(project.get("pay", 0))
		emit_event("project_completed", {"id": id})
	sim.state.economy.projects[id] = progress
	var result: Dictionary = sim.advance(effort)
	if not result.ok: return result
	return Rules.ok({"id":id,"completed":progress.completed,"progress":progress.progress,"minutes":effort})

func tick(minute: int) -> void:
	if minute % 1440 != 0: return
	var economy: Dictionary = sim.state.economy
	for id in economy.assets:
		var asset := definition("assets", id)
		economy.bank += int(asset.get("daily_income", 0)) * int(economy.assets[id].level)
		economy.bank -= int(asset.get("daily_expense", 0))
	if economy.bank < 0:
		economy.debt -= economy.bank
		economy.bank = 0
	if sim.state.clock.weekday == 1:
		economy.bank += int(floor(economy.bank * float(sim.catalog.settings.weekly_interest)))
		economy.debt += int(ceil(economy.debt * float(sim.catalog.settings.weekly_debt_interest)))
