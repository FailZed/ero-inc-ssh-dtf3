extends "res://scripts/mechanics/simulation.gd"
## NPC life runtime: continuous human personalities and directed social relationships.
const Agency = preload("res://scripts/mechanics/human_agency.gd")
const Personalities = preload("res://scripts/mechanics/npc_personalities.gd")
const Social = preload("res://scripts/mechanics/human_social.gd")
const SocialRules = preload("res://scripts/mechanics/human_social_rules.gd")
const Relationships = preload("res://scripts/mechanics/npc_relationships.gd")
const Dialogue = preload("res://scripts/mechanics/npc_dialogue.gd")
const Planner = preload("res://scripts/mechanics/npc_planner.gd")

func _init(random_seed: int = 1, extensions: Dictionary = {}) -> void:
	super(random_seed, extensions)
	services["npc_personalities"] = Personalities.new(self)
	services["npc_agency"] = Agency.new(self)
	services.social = Social.new(self)
	services.social_rules = SocialRules.new(self)
	services["npc_relationships"] = Relationships.new(self)
	services["npc_dialogue"] = Dialogue.new(self)
	services["npc_planner"] = Planner.new(self)
	state_restored.connect(services.npc_planner.clear)

func after_minute(minute: int) -> void:
	services.npc_planner.resolve(minute)

func finish_command() -> void:
	services.npc_planner.clear()

func validate_state(candidate: Dictionary) -> Dictionary:
	var result := super.validate_state(candidate)
	if not result.ok: return result
	var error := Planner.state_error(candidate,catalog)
	return Rules.fail(error) if not error.is_empty() else result

func _load_catalog() -> Dictionary:
	var result := super._load_catalog()
	for path in ["npc_life", "human_social", "npc_dialogue", "npc_employment", "conversation_options"]:
		var additions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechanics/%s.json" % path))
		for group in additions:
			if not result.has(group): result[group] = {}
			result[group].merge(additions[group], true)
	for action in result.agency_actions.values():
		action.traits = {}
		action.erase("trait_min")
		action.erase("trait_max")
	result.agency_actions.reconcile.erase("negative_sentiment")
	return result
