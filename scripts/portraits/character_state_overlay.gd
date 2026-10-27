extends Node2D
var canvas := Vector2(1920,2596)
var injuries: Dictionary = {}
var rig_id := "prototype_female"

func _draw() -> void:
	if float(injuries.get("head",0)) >= 15:
		var anchor := Vector2(0.47,0.13) if rig_id == "prototype_female" else Vector2(0.472,0.092)
		var dimensions := Vector2(0.075,0.018) if rig_id == "prototype_female" else Vector2(0.062,0.014)
		var band := Rect2(canvas*anchor,canvas*dimensions)
		draw_rect(band,Color("ddd9ca"))
		draw_line(band.position,band.end,Color("aeb6b6"),2,true)
	if float(injuries.get("arms",0)) >= 15:
		# Each current rig has a different idle pose. Anchor to the hanging
		# forearm, rather than the empty space inside the bent right arm.
		var anchor := Vector2(0.379,0.38) if rig_id == "prototype_female" else Vector2(0.318,0.42)
		var band := Rect2(canvas*anchor,canvas*Vector2(0.025,0.022))
		draw_rect(band,Color("ddd9ca"))
		for i in range(1,4):
			var stripe := band.size.y*float(i)/4.0
			draw_line(band.position+Vector2(0,stripe),band.position+Vector2(band.size.x,stripe),Color("aeb6b6"),2,true)
