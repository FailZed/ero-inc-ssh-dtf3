extends "res://tests/gameplay/capture_pregnancy_materials.gd"
const OUTPUT_V2 := "res://docs/art/verification/pregnancy-fit-v2-2026-10-27"
const Painted = preload("res://data/art/materials/pregnancy_v2/casual_late.tres")

func improved(actor: Dictionary, rect: Rect2, crop: bool = false):
	var item = view(actor,rect,false,crop)
	for layer in item.composition.layers:
		if layer.slot == "top": item._sprites[layer.id].material = Painted.duplicate()
	return item

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600,1000)
	var actor := Visuals.story_actor("asuka")
	actor.id = "pregnancy_fit_fixture"
	actor.age = 30
	actor.appearance.pregnancy_stage = 4
	actor.appearance.pregnancy_visual_variant = 9
	var bg := ColorRect.new()
	bg.color = Color("080f1a")
	bg.size = Vector2(1600,1000)
	root.add_child(bg)
	label("EroInc · доработка одежды по форме живота",Rect2(44,18,1500,44),30)
	label("Один взрослый персонаж, 30 лет · та же поза, лицо и руки · поздний срок",Rect2(44,65,1500,30),18,Color("9db3c4"))
	panel(Rect2(32,114,570,810))
	panel(Rect2(618,114,570,810))
	panel(Rect2(1204,114,364,810))
	label("БЫЛО · слой + материал",Rect2(56,127,520,40),25)
	label("НОВАЯ ПРОРИСОВКА",Rect2(642,127,520,40),25)
	label("Проверка ткани",Rect2(1222,127,340,40),22)
	view(actor,Rect2(42,178,550,724))
	improved(actor,Rect2(628,178,550,724))
	improved(actor,Rect2(1214,220,344,560),true)
	label("Предыдущая версия слоёв",Rect2(56,886,530,28),17,Color("9db3c4"))
	label("Объём и складки нарисованы в одежде",Rect2(642,886,530,28),17,Color("9db3c4"))
	label("Лицо и руки исходные",Rect2(1222,832,330,28),18,Color("a9c8dd"))
	label("Реальный рендер Godot 4.7.2 · проба нового слоя одежды · один срок и один костюм",Rect2(44,947,1500,30),18,Color("a3aebc"))
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_V2))
	var error := root.get_texture().get_image().save_png(OUTPUT_V2+"/comparison-v2.png")
	print("PREGNANCY_FIT_CAPTURE ",error)
	quit(error)
