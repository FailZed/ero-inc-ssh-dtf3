extends RefCounted
const Main = preload("res://scripts/gameplay/main_simulation.gd")
const Presentation = preload("res://scripts/gameplay/presentation.gd")
const Driver = preload("res://tests/gameplay/work_driver.gd")
var t
func _init(parent) -> void: t = parent
func fresh():
	var sim = Main.new(42,Presentation.extensions())
	sim.state.clock = sim.calendar.snapshot(480)
	sim.state.economy.cash = 2000
	sim.state.world.location = "bedroom"
	sim.state.world.equipment = ["computer"]
	return sim
func same(sim) -> Dictionary: return JSON.parse_string(JSON.stringify(sim.export_snapshot()))
func command(sim, op: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = sim.command("computer",op,args)
	t.check(result.ok,"computer.%s: %s" % [op,result.get("error","")])
	return result
func refused(sim, op: String, args: Dictionary, text: String) -> void:
	var before := same(sim)
	t.check(not sim.command("computer",op,args).ok and same(sim) == before,text)
func run() -> void:
	_programmer()
	_hacker()
	_streamer()
	_professions()
	_validation()

func _project(sim) -> String:
	var offer: Dictionary = sim.services.computer.board()[0]
	if offer.locked:
		for other in sim.services.computer.board():
			if not other.locked: offer = other; break
	command(sim,"take_project",{"id":offer.id})
	return str(offer.id)

func _programmer() -> void:
	var sim = fresh()
	var before := same(sim)
	var desktop: Dictionary = sim.services.computer.inspect()
	t.check(desktop.tracks.size() == 3 and desktop.board.size() == 3 and same(sim) == before,"desktop describes three professional paths without side effects")
	sim.state.world.location = "bathroom"
	refused(sim,"lesson",{"id":"code_review"},"computer work requires the actual desk")
	sim.state.world.location = "bedroom"
	command(sim,"lesson",{"id":"code_review"})
	refused(sim,"lesson",{"id":"code_review"},"repeating a course cannot farm daily XP")
	t.check(sim.command("events","start_quest",{"id":"home_with_purpose"}).ok,"home project quest accepts computer work")
	var id := _project(sim)
	refused(sim,"take_project",{"id":id},"same offer cannot be accepted twice")
	refused(sim,"deliver_project",{"id":id},"project cannot be sold before work")
	refused(sim,"project_step",{"id":id,"step":"test","choice":"coverage"},"stale or out-of-order project stage is atomic")
	for stage in ["design","build","test"]:
		command(sim,"project_step",{"id":id,"step":stage,"choice":{"design":"clarify","build":"robust","test":"coverage"}[stage]})
	var project: Dictionary = sim.services.computer.project_view(id)
	t.check(project.ready and project.bugs == 0,"careful implementation and test coverage meet acceptance criteria")
	t.check(sim.services.planning.opportunities().any(func(row): return row.kind == "computer_project" and row.id == id),"ready computer project appears in daily opportunities")
	t.check(sim.state.journal.quests.home_with_purpose.objectives.get("project",0) == 0,"unfinished client handoff does not complete a project objective")
	var wallet := int(sim.state.economy.cash)
	var delivered := command(sim,"deliver_project",{"id":id})
	t.check(sim.state.economy.cash == wallet+int(delivered.data.pay) and sim.state.computer.portfolio.size() == 1,"delivery pays once and adds concrete portfolio entry")
	t.check(sim.state.journal.quests.home_with_purpose.objectives.get("project",0) == 1,"delivered computer project advances the shared quest exactly once")
	refused(sim,"deliver_project",{"id":id},"delivered work cannot be paid twice")
	var snapshot := same(sim)
	var replay = fresh()
	t.check(replay.restore_snapshot(snapshot).ok and same(replay) == snapshot,"portfolio and professional XP survive JSON restore")
	sim = fresh()
	id = _project(sim)
	for stage in ["design","build","test"]:
		command(sim,"project_step",{"id":id,"step":stage,"choice":{"design":"prototype","build":"reuse","test":"smoke"}[stage]})
	refused(sim,"deliver_project",{"id":id},"fast shortcuts require visible revision instead of unconditional payout")
	command(sim,"revise_project",{"id":id})
	command(sim,"revise_project",{"id":id})
	command(sim,"deliver_project",{"id":id})
	t.check(sim.state.computer.projects[id].revisions == 2,"revision is bounded and recorded")
	sim = fresh()
	id = _project(sim)
	var base: int = sim.services.computer.duration("project_step",{"step":"build","choice":"robust"})
	command(sim,"upgrade",{"id":"processor"})
	t.check(sim.services.computer.duration("project_step",{"step":"build","choice":"robust"}) < base,"processor upgrade changes actual working duration")
	t.check(sim.services.computer.project_view(id).choices.clarify.minutes == sim.services.computer.duration("project_step",{"step":"design","choice":"clarify"}),"project choice displays the actual upgraded duration")
	refused(sim,"specialize",{"id":"web"},"specialization requires professional experience")
	sim.state.computer.tracks.programmer = 100
	wallet = int(sim.state.economy.cash)
	command(sim,"specialize",{"id":"web"})
	command(sim,"specialize",{"id":"tools"})
	t.check(sim.state.economy.cash == wallet-60,"first specialization is free and changing it has a stated cost")
	var due := int(sim.state.computer.projects[id].deadline)
	sim.state.clock = sim.calendar.snapshot(due-1)
	t.check(sim.services.planning.priorities().any(func(row): return row.kind == "computer_project" and row.id == id),"approaching computer deadline appears among daily commitments")
	t.check(sim.command("clock","advance",{"minutes":1}).ok and sim.state.computer.projects[id].status == "expired","unattended project expires on the shared clock")
	refused(sim,"deliver_project",{"id":id},"expired project has no payout")

func _hacker() -> void:
	var sim = fresh()
	sim.state.player.skills.computing = 150
	var start := command(sim,"hack_start",{"id":"recovery"})
	var token: int = start.data.token
	refused(sim,"hack_step",{"token":token+1,"step":0,"choice":"careful"},"stale digital session preserves prepared report and RNG")
	command(sim,"hack_step",{"token":token,"step":0,"choice":"careful"})
	refused(sim,"hack_step",{"token":true,"step":1,"choice":"careful"},"boolean token cannot stand in for a numbered session")
	var snapshot := same(sim)
	var replay = fresh()
	t.check(replay.restore_snapshot(snapshot).ok,"partially prepared operation restores")
	for peer in [sim,replay]:
		command(peer,"hack_step",{"token":token,"step":1,"choice":"careful"})
		command(peer,"hack_step",{"token":token,"step":2,"choice":"careful","approach":"careful"})
	t.check(same(sim) == same(replay) and sim.state.computer.hack.is_empty() and sim.state.digital.pending.is_empty(),"final prepared operation uses shared outcome and replays exactly")
	refused(sim,"hack_step",{"token":token,"step":2,"choice":"careful"},"finished operation cannot be claimed twice")
	sim = fresh()
	sim.state.player.skills.computing = 150
	start = command(sim,"hack_start",{"id":"bank"})
	token = int(start.data.token)
	command(sim,"hack_step",{"token":token,"step":0,"choice":"fast"})
	t.check(sim.state.digital.trace > 0,"risky preparation leaves a real trace before settlement")
	var trace := float(sim.state.digital.trace)
	command(sim,"hack_abort",{"token":token})
	t.check(sim.state.digital.trace == trace and sim.state.digital.pending.is_empty(),"abort keeps accumulated consequences and clears report")
	sim.command("preferences","content_tag",{"id":"crime","enabled":false})
	refused(sim,"hack_start",{"id":"bank"},"crime content toggle gates the complete staged operation")
	command(sim,"hack_start",{"id":"training"})
	t.check(sim.command("clock","advance",{"minutes":1440}).ok and sim.state.computer.hack.is_empty(),"report expiry closes the computer session without blocking the player")
	sim = fresh()
	start = command(sim,"hack_start",{"id":"training"})
	token = int(start.data.token)
	for step in range(2): command(sim,"hack_step",{"token":token,"step":step,"choice":"careful"})
	sim.state.player.needs.energy = 3
	refused(sim,"hack_step",{"token":token,"step":2,"choice":"careful","approach":"careful"},"failed final settlement rolls back preparation, time and RNG when remaining energy is insufficient")
	sim.state.world.location = "bathroom"
	command(sim,"hack_abort",{"token":token})

func _streamer() -> void:
	var sim = fresh()
	sim.state.player.skills.computing = 300
	sim.state.economy.channel.followers = 100
	command(sim,"upgrade",{"id":"studio"})
	var start := command(sim,"stream_start",{"id":"games","format":"community","segments":4,"sponsor":"local"})
	var token: int = start.data.token
	var before := same(sim)
	t.check(not sim.command("careers","stream",{"id":"games","minutes":30}).ok and same(sim) == before,"two broadcasting paths cannot run overlapping shows")
	refused(sim,"stream_step",{"token":token,"step":1,"choice":"chat"},"stale stream step is atomic")
	var replay = fresh()
	var checkpoint := same(sim)
	t.check(replay.restore_snapshot(checkpoint).ok,"stream agenda and current event survive a save")
	for index in range(4):
		var event: Dictionary = sim.catalog.computer_rules.stream_events[int(sim.state.computer.broadcast.events[index])]
		var shown: Dictionary = sim.services.computer.inspect().broadcast
		t.check(not shown.has("events") and not shown.event.has("best"),"desktop shows the current situation without revealing future events or the answer")
		for peer in [sim,replay]: command(peer,"stream_step",{"token":token,"step":index,"choice":event.best})
	t.check(same(sim) == same(replay),"stream audience, sponsor and choices replay after restore")
	var row: Dictionary = sim.state.computer.broadcasts.back()
	t.check(row.completed and row.minutes == 60 and row.followers > 0 and sim.state.computer.sponsor_until > sim.state.clock.total_minutes,"completed show has real audience and settles sponsor cooldown")
	var count := int(sim.state.economy.channel.followers)
	command(sim,"publish_highlight",{"id":row.id})
	t.check(sim.state.economy.channel.followers > count,"highlight attracts shared channel audience")
	refused(sim,"publish_highlight",{"id":row.id},"one recording cannot generate unlimited highlights")
	refused(sim,"stream_start",{"id":"games","sponsor":"local"},"sponsor cannot be paid again during its cooldown")
	var modifier: Dictionary = sim.services.computer.stream_modifiers("games")
	t.check(modifier.audience_scale < sim.services.computer.stream_modifiers("education").audience_scale,"repeating the same topic has visible diminishing returns")
	start = command(sim,"stream_start",{"id":"education","segments":2})
	command(sim,"stream_finish",{"token":start.data.token})
	t.check(not sim.state.computer.broadcasts.back().completed and sim.state.computer.broadcasts.back().income == 0,"ending before the first segment grants no fabricated income")
	sim = fresh()
	start = command(sim,"stream_start",{"id":"games","segments":2})
	command(sim,"stream_step",{"token":start.data.token,"step":0,"choice":"content"})
	var earned := int(sim.state.economy.cash)
	t.check(sim.command("clock","advance",{"minutes":480}).ok and sim.state.computer.broadcast.is_empty(),"abandoned broadcast expires with completed segments retained")
	t.check(not sim.state.computer.broadcasts.back().completed and sim.state.economy.cash == earned,"expiry pays no sponsor or second copy of segment revenue")
	sim = fresh()
	start = command(sim,"stream_start",{"id":"games","segments":2})
	sim.state.player.needs.energy = 0
	refused(sim,"stream_step",{"token":start.data.token,"step":0,"choice":"content"},"failed stream segment rolls back quality and engagement as well as income")
	sim.state.world.location = "bathroom"
	command(sim,"stream_finish",{"token":start.data.token})

func _professions() -> void:
	for id in ["junior_developer","broadcast_host"]:
		var sim = fresh()
		t.check(sim.command("livelihood","work",{"id":id}).ok and Driver.finish(sim),"computer profession is playable through existing work UI: "+id)
		t.check(sim.state.livelihood.totals.shifts == 1 and sim.validate_state(sim.state).ok,"computer profession commits one valid shift: "+id)
		t.check(sim.state.computer.tracks["programmer" if id == "junior_developer" else "streamer"] == 12,"completed job advances the matching computer profession: "+id)
	var sim = fresh()
	t.check(sim.command("careers","stream",{"id":"games","minutes":30}).ok,"existing stream entry remains playable")
	t.check(sim.state.computer.tracks.streamer > 0 and sim.state.computer.broadcasts.size() == 1,"existing stream advances the same computer career and recording history")

func _validation() -> void:
	var sim = fresh()
	for malformed in ["tracks","upgrade","broadcast","project","lesson"]:
		var bad := same(sim)
		match malformed:
			"tracks": bad.state.computer.tracks.programmer = -1
			"upgrade": bad.state.computer.upgrades.processor = 99
			"broadcast": bad.state.computer.broadcast = {"token":1}
			"project": bad.state.computer.projects["forged"] = {}
			"lesson": bad.state.computer.lessons.code_review = 999999
		var before := same(sim)
		t.check(not sim.restore_snapshot(bad).ok and before == same(sim),"corrupt computer snapshot rejected atomically: "+malformed)
	var bad_catalog := {"computer_rules":{"upgrades":{"processor":{"label":"bad","cost":-10,"max_level":1,"description":"bad"}}}}
	var invalid = Main.new(1,bad_catalog)
	t.check(not invalid.configuration_error.is_empty() and not invalid.command("computer","upgrade",{"id":"processor"}).ok,"malformed computer catalog cannot execute paid actions")
