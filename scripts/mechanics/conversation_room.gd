extends RefCounted
## An isolated, editable resident for the Live2D room; never reads or writes game saves.
const Life = preload("res://scripts/mechanics/npc_life_simulation.gd")
const Human = preload("res://scripts/mechanics/core/human_validation.gd")
const Session = preload("res://scripts/mechanics/conversation_session.gd")

static func create() -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/conversation_room.json"))
	var template := {"name":str(config.name),"age":int(config.age),"home":"global_map","role":"worker","money":100,"personalities":["calm"],"goals":["community"],"schedule":[],"activities":[],"gender":"female","attracted_to":["female","male"],"traits":{"sociability":62}}
	var runtime := Life.new(int(config.seed),{"settings":{"start_minutes":int(config.start_minutes)},"npc_templates":{"live2d_speaker":template}})
	if not runtime.configuration_error.is_empty(): return {"ok":false,"error":runtime.configuration_error}
	runtime.command("npc_agency","enable")
	var generated: Dictionary = runtime.command("social","generate",{"id":str(config.npc_id),"template":"live2d_speaker"})
	if not generated.ok: return generated
	var facets := {}
	for key: String in Human.FACETS: facets[key] = 50
	facets.merge(config.facets,true)
	runtime.command("npc_personalities","configure",{"id":str(config.npc_id),"facets":facets})
	var npc: Dictionary = runtime.state.social.npcs[str(config.npc_id)]
	npc.name = str(config.name)
	npc.location = "global_map"
	npc.activity = "idle"
	npc.schedule = []
	npc.decision = {"committed":false}
	npc.pinned_until = int(runtime.state.clock.total_minutes)+1440
	npc.needs.merge({"energy":95,"satiety":95,"hygiene":95,"social":65,"fun":80},true)
	npc.mind.aspiration = {"id":"community","stage":0,"milestones":0,"progress":0,"completed":false}
	runtime.state.world.location = "global_map"
	runtime.services.npc_relationships._bond(str(config.npc_id),"player").merge(config.initial_bond,true)
	return {"ok":true,"simulation":runtime,"config":config,"session":Session.new(runtime,str(config.npc_id))}
