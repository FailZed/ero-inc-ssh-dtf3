extends Node2D

signal pose_changed(pose: String, mode: String)

var data: Dictionary = {}
var bones: Dictionary = {}
var bone_paths: Dictionary = {}
var skeleton: Skeleton2D
var skin: Polygon2D
var redraw: Sprite2D
var idle_player: AnimationPlayer
var transition: Tween
var current_pose := "neutral"
var show_bones := false
var breathing := true
var overlay_time := 0.0

const POSES := {
	"neutral": {},
	"head_tilt": {"head": 4.0},
	"lean": {"spine": -1.5, "head": 1.0},
}

func _vec(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func load_body(sex: String) -> void:
	if transition and transition.is_running():
		transition.kill()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	bones.clear()
	bone_paths.clear()
	data = JSON.parse_string(FileAccess.get_file_as_string("res://rigs/" + sex + ".json"))
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton"
	add_child(skeleton)
	for item: Dictionary in data.bones:
		var b := Bone2D.new()
		b.name = item.name
		b.set_autocalculate_length_and_angle(false)
		var parent: Node2D = skeleton if item.parent == "" else bones[item.parent]
		parent.add_child(b)
		var parent_origin := Vector2.ZERO
		if item.parent != "":
			parent_origin = _vec(_bone_info(item.parent).start)
		b.position = _vec(item.start) - parent_origin
		b.rest = b.transform
		b.set_length(_vec(item.end).distance_to(_vec(item.start)))
		b.set_bone_angle((_vec(item.end) - _vec(item.start)).angle())
		bones[item.name] = b
		bone_paths[item.name] = skeleton.get_path_to(b)
	skin = Polygon2D.new()
	skin.name = "SkinMesh"
	skin.show_behind_parent = true
	add_child(skin)
	skin.skeleton = skin.get_path_to(skeleton)
	var vertices := PackedVector2Array()
	for vertex: Array in data.vertices:
		vertices.append(_vec(vertex))
	skin.polygon = vertices
	skin.uv = vertices
	var faces: Array[PackedInt32Array] = []
	for triangle: Array in data.triangles:
		faces.append(PackedInt32Array(triangle))
	skin.polygons = faces
	skin.texture = load(data.texture)
	for i in range(data.bones.size()):
		skin.add_bone(bone_paths[data.bones[i].name], PackedFloat32Array(data.weights[i]))
	redraw = Sprite2D.new()
	redraw.name = "RedrawnView"
	redraw.centered = false
	redraw.visible = false
	add_child(redraw)
	_build_breathing()
	set_pose("neutral", true)

func _bone_info(bone_name: String) -> Dictionary:
	for item: Dictionary in data.bones:
		if item.name == bone_name:
			return item
	return {}

func _build_breathing() -> void:
	idle_player = AnimationPlayer.new()
	add_child(idle_player)
	var library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 3.2
	idle.loop_mode = Animation.LOOP_LINEAR
	var index := idle.add_track(Animation.TYPE_VALUE)
	idle.track_set_path(index, NodePath(str(get_path_to(bones.root)) + ":position:y"))
	var base_y: float = bones.root.position.y
	idle.track_insert_key(index, 0.0, base_y)
	idle.track_insert_key(index, 1.6, base_y - 1.8)
	idle.track_insert_key(index, 3.2, base_y)
	idle.track_set_interpolation_type(index, Animation.INTERPOLATION_CUBIC)
	library.add_animation("breathing", idle)
	idle_player.add_animation_library("", library)
	if breathing:
		idle_player.play("breathing")

func available_poses() -> Array:
	var result: Array = POSES.keys()
	result.append_array(data.redraws.keys())
	return result

func set_pose(pose: String, instant: bool = false) -> bool:
	if not pose in available_poses():
		return false
	var drawn: bool = data.redraws.has(pose)
	var next_texture: Texture2D
	if drawn:
		if not ResourceLoader.exists(data.redraws[pose]):
			return false
		next_texture = load(data.redraws[pose]) as Texture2D
		if next_texture == null:
			return false
	current_pose = pose
	skin.visible = not drawn
	redraw.visible = drawn
	if drawn:
		redraw.texture = next_texture
		pose_changed.emit(pose, "redraw")
		queue_redraw()
		return true
	if transition and transition.is_running():
		transition.kill()
	var settings: Dictionary = POSES[pose]
	if not instant:
		transition = create_tween().set_parallel(true)
	for bone_name: String in bones:
		var angle := float(settings.get(bone_name, 0.0))
		if data.limits_degrees.has(bone_name):
			var limits: Array = data.limits_degrees[bone_name]
			angle = clampf(angle, float(limits[0]), float(limits[1]))
		if instant:
			bones[bone_name].rotation = deg_to_rad(angle)
		else:
			transition.tween_property(bones[bone_name], "rotation", deg_to_rad(angle), 0.28).set_trans(Tween.TRANS_SINE)
	pose_changed.emit(pose, "rig")
	queue_redraw()
	return true

func set_breathing(enabled: bool) -> void:
	breathing = enabled
	if enabled:
		idle_player.play("breathing")
	else:
		idle_player.stop()
		bones.root.position = _vec(_bone_info("root").start)

func _process(delta: float) -> void:
	if show_bones:
		overlay_time += delta
		if overlay_time > 0.04:
			overlay_time = 0.0
			queue_redraw()

func _draw() -> void:
	if not show_bones or not is_instance_valid(skin) or not skin.visible:
		return
	for item: Dictionary in data.bones:
		var b: Bone2D = bones[item.name]
		var start := to_local(b.global_position)
		var direction := _vec(item.end) - _vec(item.start)
		var end := to_local(b.to_global(direction))
		draw_line(start, end, Color("9ec8dc"), 2.4, true)
		draw_circle(start, 5.0, Color("e2a566"))
