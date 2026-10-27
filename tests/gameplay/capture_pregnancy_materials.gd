extends SceneTree
## Real Godot rendering of the same adult fixture, never a user's save.
const View = preload("res://scripts/portraits/layered_character_view.gd")
const Visuals = preload("res://scripts/portraits/character_visuals.gd")
const Legacy = preload("res://tests/fixtures/legacy_pregnancy.gdshader")
const OUTPUT := "res://docs/art/verification/pregnancy-materials-2026-10-27"

func _initialize() -> void:
	call_deferred("_run")

func label(text: String, rect: Rect2, font_size: int = 24, color: Color = Color("e3e9ec")) -> void:
	var item := Label.new()
	item.text = text
	item.position = rect.position
	item.size = rect.size
	item.add_theme_font_size_override("font_size",font_size)
	item.add_theme_color_override("font_color",color)
	root.add_child(item)

func panel(rect: Rect2) -> void:
	var item := Panel.new()
	item.position = rect.position
	item.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111d2b")
	style.border_color = Color("425c73")
	style.set_border_width_all(1)
	item.add_theme_stylebox_override("panel",style)
	root.add_child(item)

func view(actor: Dictionary, rect: Rect2, old: bool = false, crop: bool = false):
	var item := View.new()
	item.position = rect.position
	item.size = rect.size
	item.use_pregnancy_layers = not old
	root.add_child(item)
	item.set_actor(actor)
	item.composition.rig = item.composition.rig.duplicate(true)
	item.composition.rig.comparison_frame = [680,820,640,820] if crop else [550,50,920,1870]
	item.framing = "comparison"
	item._layout()
	if old:
		for layer in item.composition.layers:
			var sprite: Sprite2D = item._sprites[layer.id]
			var material := ShaderMaterial.new()
			material.shader = Legacy
			material.set_shader_parameter("pregnancy",4.0)
			material.set_shader_parameter("tint_enabled",layer.get("tint","") in ["hair","eyes"])
			material.set_shader_parameter("tint",layer.color)
			sprite.material = material
	return item

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600,1000)
	var actor := Visuals.story_actor("asuka")
	if actor.is_empty():
		actor = {"id":"pregnancy_visual_fixture","age":30,"gender":"female","appearance":{"morphology":"human"}}
		actor.appearance.visual = Visuals.generate(actor,2026)
	actor.age = 30
	actor.id = "pregnancy_visual_fixture"
	actor.appearance.pregnancy_stage = 4
	actor.appearance.pregnancy_visual_variant = 9
	if "--detail" in OS.get_cmdline_user_args():
		await _detail(actor)
		return
	var bg := ColorRect.new()
	bg.color = Color("080f1a")
	bg.size = Vector2(1600,1000)
	root.add_child(bg)
	label("EroInc · сравнение сборки персонажа",Rect2(44,18,1500,44),30)
	label("Один взрослый персонаж, 30 лет · одна поза и одежда · поздний срок",Rect2(44,65,1500,30),18,Color("9db3c4"))
	panel(Rect2(32,114,570,810))
	panel(Rect2(618,114,570,810))
	panel(Rect2(1204,114,364,810))
	label("РАНЬШЕ · шейдер",Rect2(56,127,520,40),25)
	label("ТЕПЕРЬ · отдельные слои",Rect2(642,127,520,40),25)
	label("Объём под одеждой",Rect2(1222,127,340,40),22)
	view(actor,Rect2(42,178,550,724),true)
	view(actor,Rect2(628,178,550,724))
	view(actor,Rect2(1214,220,344,560),false,true)
	label("Общее растяжение по горизонтали",Rect2(56,886,530,28),17,Color("9db3c4"))
	label("Нарисованный живот + материал одежды",Rect2(642,886,530,28),17,Color("9db3c4"))
	label("9 вариантов по сроку",Rect2(1222,832,330,28),18,Color("a9c8dd"))
	label("Реальный рендер Godot 4.7.2 · тестовая сборка из игровых слоёв · временные ассеты School",Rect2(44,947,1500,30),18,Color("a3aebc"))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var error := root.get_texture().get_image().save_png(OUTPUT+"/comparison.png")
	print("PREGNANCY_CAPTURE ",error)
	quit(error)

func _detail(actor: Dictionary) -> void:
	# A second, cropped assembly check exposes the abdomen while keeping adult
	# clothing layers on. This makes the actual painted asset legible separately
	# from the provisional fit of the dress material.
	var bg := ColorRect.new()
	bg.color = Color("080f1a")
	bg.size = Vector2(1600,1000)
	root.add_child(bg)
	label("EroInc · проверка нарисованного слоя живота",Rect2(44,18,1500,44),30)
	label("Технический крупный план · взрослый персонаж, 30 лет · один и тот же исходный портрет",Rect2(44,65,1500,30),18,Color("9db3c4"))
	panel(Rect2(32,114,752,810))
	panel(Rect2(800,114,768,810))
	label("РАНЬШЕ · растяжение основы",Rect2(56,127,700,40),25)
	label("ТЕПЕРЬ · отдельный нарисованный слой",Rect2(824,127,720,40),25)
	var old = view(actor,Rect2(50,186,716,700),true,true)
	var fresh = view(actor,Rect2(818,186,732,700),false,true)
	for item in [old,fresh]:
		for layer in item.composition.layers:
			if layer.slot in ["top","bottom","outerwear"]: item._sprites[layer.id].visible = false
	label("Только слой живота и базовая одежда · реальный рендер Godot 4.7.2 · временные ассеты School",Rect2(44,947,1500,30),18,Color("a3aebc"))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var error := root.get_texture().get_image().save_png(OUTPUT+"/abdomen-detail.png")
	print("PREGNANCY_DETAIL_CAPTURE ",error)
	quit(error)
