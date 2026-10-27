extends Control
## Development-only inspection of all supported face/eye registrations.
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
const Portrait = preload("res://scripts/portraits/layered_character_view.gd")
const UI = preload("res://scripts/ui/gameplay/ui_factory.gd")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("14202b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var expression := "neutral"
	var expressions := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expression="): expression = arg.trim_prefix("--expression=")
		if arg == "--expressions": expressions = true
	var columns := 5 if expressions else 6
	var rows := 2 if expressions else 3
	for index in range(10 if expressions else 18):
		var sex := "male" if index < (5 if expressions else 9) else "female"
		var variant := index % 9
		if expressions: expression = Visuals.EXPRESSIONS[index%5]
		var cell := Control.new()
		cell.anchor_left = float(index%columns)/columns
		cell.anchor_right = float(index%columns+1)/columns
		cell.anchor_top = float(index/columns)/rows
		cell.anchor_bottom = float(index/columns+1)/rows
		add_child(cell)
		var actor := {"id":"face_study_"+str(index),"gender":sex,"appearance":{"morphology":"human"}}
		actor.appearance.visual = Visuals.generate(actor,42)
		actor.appearance.visual.face = variant/3+1
		actor.appearance.visual.eyes = variant%3+1
		actor.appearance.visual.skin_color = ["ffffff","efcfb8","d4a584"][variant%3]
		actor.appearance.visual.hair = "short"
		if expressions:
			actor = Visuals.story_actor("oliver" if sex=="male" else "ellie")
		var portrait := Portrait.new()
		portrait.framing = "face"
		portrait.expression = expression
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		portrait.anchor_bottom = 0.9
		cell.add_child(portrait)
		portrait.set_actor(actor)
		var label := UI.label(cell,(str(actor.name) if expressions else ("М · основа тела" if sex=="male" else "Ж · лицо "+str(variant/3+1))+" · глаза "+str(variant%3+1))+" · "+expression,17)
		label.anchor_top = 0.9
		label.anchor_right = 1.0
		label.anchor_bottom = 1.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
