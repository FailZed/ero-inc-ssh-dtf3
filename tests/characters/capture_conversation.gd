extends SceneTree
## Captures the actual conversation controls; does not operate the desktop mouse.
var destination := "E:/Ai/ComfyUI-EroInc/runtime/cubism/conversation-matrix"

func _initialize() -> void:
	_run.call_deferred()

func frames(count: int = 4) -> void:
	for frame in range(count): await process_frame
	await RenderingServer.frame_post_draw

func save_frame(path: String, viewport: Viewport) -> void:
	var result := viewport.get_texture().get_image().save_png(path)
	print("CONVERSATION_SCREEN ",path," error=",result)

func _run() -> void:
	root.size = Vector2i(1440,900)
	root.gui_embed_subwindows = true
	var screen := load("res://scenes/characters/conversation_room.tscn").instantiate() as Control
	root.add_child(screen)
	await frames(18)
	screen.puppet.finish_speech()
	screen._select_tab("conflict")
	await frames()
	save_frame(destination+"-aggression.png",root)
	screen._select_tab("dialogue")
	screen._open_folder("Повседневные темы")
	await frames()
	save_frame(destination+"-topics.png",root)
	screen._show_matrix()
	await frames()
	save_frame(destination+"-relations.png",root)
	screen.free()
	await process_frame
	quit()
