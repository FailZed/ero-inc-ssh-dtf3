extends "res://scripts/portraits/layered_character_view.gd"
## The same assembler as NPCs and authored characters, with a mirror camera.
func set_appearance(value: Dictionary) -> void:
	framing = "mirror"
	mirrored = true
	set_actor(Visuals.player_actor({"appearance":value}))
