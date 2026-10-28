extends SceneTree
## Deterministic pacing fixtures. These are simulated policies, not human playtests.
const Simulation = preload("res://scripts/mechanics/simulation.gd")
var errors: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _command(sim, module: String, operation: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim.command(module, operation, args)
	if not result.ok: errors.append(module + "." + operation + ":" + str(result.error))
	return result

func _fresh(seed_value: int = 42):
	return Simulation.new(seed_value, {"settings": {"start_minutes": 1920}})

func _run() -> void:
	var report := {"combat": {}, "daily_loop": {}, "stream_split": {}}
	for difficulty in ["easy", "normal", "hard"]:
		var turns: Array = []
		var wins := 0
		var unfinished := 0
		for seed_value in range(1, 65):
			var sim = _fresh(seed_value)
			_command(sim, "preferences", "difficulty", {"id": difficulty})
			_command(sim, "social", "generate", {"id": "opponent"})
			for key in sim.state.player.stats:
				sim.state.player.stats[key] = 10
				sim.state.social.npcs.opponent.stats[key] = 10
			sim.state.social.npcs.opponent.location = sim.state.world.location
			if not _command(sim, "combat", "start", {"npc": "opponent"}).ok: continue
			var steps := 0
			while sim.state.encounters.combat.status == "active" and steps < 160:
				var fight: Dictionary = sim.state.encounters.combat
				if fight.phase == "defence":
					_command(sim,"combat","action",{"action":"guard","part":"body"})
					steps += 1
					continue
				if fight.stamina.player < 16: _command(sim, "combat", "action", {"action": "recover"})
				elif fight.ap >= 2: _command(sim, "combat", "action", {"action": "attack", "move": "jab"})
				else: _command(sim, "combat", "action", {"action": "end_turn"})
				steps += 1
			var fight: Dictionary = sim.state.encounters.combat
			turns.append(int(fight.turn))
			if fight.status == "won": wins += 1
			if fight.status == "active": unfinished += 1
		turns.sort()
		report.combat[difficulty] = {"seeds": 64, "wins": wins, "median_turns": turns[32], "p90_turns": turns[57], "unfinished": unfinished}
		var sim = _fresh()
		_command(sim, "preferences", "difficulty", {"id": difficulty})
		# Fixture grants equipment only; daily money, food and activity use real commands.
		sim.state.world.equipment = ["computer"]
		var first_level_day := 0
		var food_failures := 0
		for day in range(1, 29):
			_command(sim, "economy", "work", {"id": "freelance"})
			_command(sim, "activities", "practice", {"id": "strength" if day % 2 == 0 else "speech"})
			_command(sim, "careers", "stream", {"id": "games", "minutes": 60})
			if sim.state.player.needs.satiety < 55:
				sim.state.world.location = "global_map" # Presentation/travel outside this policy fixture.
				var portions := int(ceil((70.0 - float(sim.state.player.needs.satiety)) / 35.0))
				var food: Dictionary = sim.command("inventory", "buy", {"id": "meal", "shop": "market", "quantity": portions})
				if food.ok:
					for portion in range(portions): _command(sim, "inventory", "use", {"id": "meal"})
				else: food_failures += 1
			if sim.state.player.level > 1 and first_level_day == 0: first_level_day = day
			var remaining := (day + 1) * 1440 + 480 - int(sim.state.clock.total_minutes)
			# Active fixture is 2.5h/day; remaining time includes idle time and 8h sleep.
			_command(sim, "clock", "advance", {"minutes": remaining - 480})
			_command(sim, "character", "rest", {"minutes": 480})
		report.daily_loop[difficulty] = {"days": 28, "first_level_day": first_level_day, "level": sim.state.player.level, "cash": sim.state.economy.cash, "health": sim.state.player.needs.health, "mood": sim.state.player.needs.mood, "energy": sim.state.player.needs.energy, "followers": sim.state.economy.channel.followers, "food_failures": food_failures}
	for chunk in [1, 15, 60]:
		var sim = _fresh()
		sim.state.world.equipment = ["computer"]
		var accepted := 0
		for i in range(60 / chunk):
			if sim.command("economy", "stream", {"minutes": chunk}).ok: accepted += 1
		report.stream_split[str(chunk)] = {"accepted": accepted, "followers": sim.state.economy.channel.followers, "income": sim.state.economy.cash - 250, "skill": sim.state.player.skills.get("computing", 0)}
	# Broad pacing bands: changing a seed or balancing a move should not require exact traces.
	for difficulty in report.combat:
		var fight: Dictionary = report.combat[difficulty]
		if fight.unfinished != 0 or fight.median_turns < 4 or fight.p90_turns > 18: errors.append("combat_pacing:" + difficulty)
		var daily: Dictionary = report.daily_loop[difficulty]
		if daily.health < 70 or daily.food_failures != 0 or daily.cash < 250 or daily.first_level_day > 5 or daily.level < 4: errors.append("daily_viability:" + difficulty)
	if not (report.combat.easy.wins > report.combat.normal.wins and report.combat.normal.wins > report.combat.hard.wins): errors.append("difficulty_order")
	if report.stream_split["1"].accepted != 0 or report.stream_split["15"].followers != report.stream_split["60"].followers or report.stream_split["15"].income != report.stream_split["60"].income or report.stream_split["15"].skill != report.stream_split["60"].skill: errors.append("stream_partition")
	report.errors = errors
	print("BALANCE_REPORT ", JSON.stringify(report))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var output := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			output.store_string(JSON.stringify(report, "  ") + "\n")
	quit(0 if errors.is_empty() else 1)
