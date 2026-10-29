extends "res://scripts/mechanics/human_agency.gd"
## Test-only timing wrapper; delegates all gameplay logic to the real agency.
var choose_us := 0
var evaluate_us := 0
var index_us := 0
var choose_calls := 0
var partner_us := 0
var route_us := 0
var agenda_us := 0
var action_spec_us := 0

func _build_index() -> void:
	var start := Time.get_ticks_usec()
	super._build_index()
	index_us += Time.get_ticks_usec()-start

func _choose(npc: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	super._choose(npc)
	choose_us += Time.get_ticks_usec()-start
	choose_calls += 1

func evaluate(npc: Dictionary) -> Array:
	var start := Time.get_ticks_usec()
	var result := super.evaluate(npc)
	evaluate_us += Time.get_ticks_usec()-start
	return result

func _partner(npc: Dictionary, action: Dictionary, action_id: String = "") -> String:
	var start := Time.get_ticks_usec()
	var result := super._partner(npc, action, action_id)
	partner_us += Time.get_ticks_usec()-start
	return result

func _route(npc: Dictionary, origin: String, destination: String, minute: int = -1, urgent_destination: bool = false, invited_destination: String = "") -> Dictionary:
	var start := Time.get_ticks_usec()
	var result := super._route(npc, origin, destination, minute, urgent_destination, invited_destination)
	route_us += Time.get_ticks_usec()-start
	return result

func _agenda(npc: Dictionary) -> Array:
	var start := Time.get_ticks_usec()
	var result := super._agenda(npc)
	agenda_us += Time.get_ticks_usec()-start
	return result

func _action_spec(npc: Dictionary, id: String) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result := super._action_spec(npc, id)
	action_spec_us += Time.get_ticks_usec()-start
	return result
