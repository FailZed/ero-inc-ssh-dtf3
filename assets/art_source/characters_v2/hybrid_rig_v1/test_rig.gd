extends SceneTree

const Character := preload("res://hybrid_character.gd")
var failed := 0
var passed := 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for sex in ["female", "male"]:
		var actor := Character.new()
		root.add_child(actor)
		actor.load_body(sex)
		actor.set_breathing(false)
		await process_frame
		check(actor.skeleton.get_bone_count() == 16, sex+": skeleton bones registered")
		check(actor.skin.get_bone_count() == 16, sex+": skin binds all bones")
		var rest_y: float = actor.bones.root.position.y
		actor.set_breathing(true)
		actor.idle_player.advance(1.6)
		check(absf(actor.bones.root.position.y - rest_y + 1.8) < .01, sex+": breathing animation moves root")
		actor.set_breathing(false)
		check(absf(actor.bones.root.position.y - rest_y) < .01, sex+": stopping breathing returns to rest")
		var weight_rows: Array = actor.data.weights
		var all_bound := true
		for i in range(actor.data.vertices.size()):
			var total := 0.0
			var influences := 0
			for row: Array in weight_rows:
				total += float(row[i])
				if float(row[i]) > 0:
					influences += 1
			if absf(total - 1.0) > 0.00001 or influences > 4:
				all_bound = false
		check(all_bound, sex+": normalized weights, max four influences, no unbound vertices")
		for pose: String in actor.available_poses():
			check(actor.set_pose(pose, true), sex+": accepts available pose "+pose)
			var drawn: bool = actor.data.redraws.has(pose)
			check(actor.redraw.visible == drawn and actor.skin.visible != drawn, sex+": exclusive renderer "+pose)
			if drawn:
				check(actor.redraw.texture != null, sex+": redraw texture loads "+pose)
			else:
				for bone_name: String in actor.data.limits_degrees:
					var limits: Array = actor.data.limits_degrees[bone_name]
					var actual: float = rad_to_deg(actor.bones[bone_name].rotation)
					check(actual >= float(limits[0]) - .001 and actual <= float(limits[1]) + .001, sex+": envelope "+bone_name+" "+pose)
		var before: String = actor.current_pose
		check(not actor.set_pose("missing_pose", true) and actor.current_pose == before, sex+": unsupported pose leaves current valid body intact")
		actor.set_pose("neutral", true)
		actor.data.redraws["missing_file"] = "res://art/not_present.png"
		check(not actor.set_pose("missing_file", true) and actor.skin.visible and actor.current_pose == "neutral", sex+": missing art leaves the valid body visible")
		actor.data.redraws.erase("missing_file")
		if sex == "male":
			check(not actor.set_pose("folded", true), "Male folded redraw must remain unavailable until art is accepted")
			check(not actor.set_pose("gesture", true), "Unreviewed male hand gesture must remain unavailable")
		check(not actor.POSES.has("gesture"), "Unsafe whole-image arm skinning must not be exposed as a rig pose")
		actor.free()
	print("Hybrid rig: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
