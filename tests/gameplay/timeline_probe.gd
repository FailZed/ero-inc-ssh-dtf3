extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	if "--cache-only" in OS.get_cmdline_user_args():
		print("CACHE ",DialogicResourceUtil.get_event_cache().size())
		quit(0)
		return
	if "--text-only" in OS.get_cmdline_user_args():
		var text := DialogicTextEvent.new()
		text._load_from_string("Привет.")
		print("TEXT ",text.text)
		quit(0)
		return
	var id := "chapter_one"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--timeline="): id = arg.trim_prefix("--timeline=")
	var timeline = DialogicResourceUtil.get_timeline_resource(id)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lines="):
			var lines: PackedStringArray = FileAccess.get_file_as_string(timeline.resource_path).split("\n")
			timeline = DialogicTimeline.new()
			timeline.from_text("\n".join(lines.slice(0,int(arg.trim_prefix("--lines=")))))
	if "--execute" in OS.get_cmdline_user_args():
		root.get_node("Dialogic").start(id)
		for i in range(10): await process_frame
		print("ACTIVE_TIMELINE ",root.get_node("Dialogic").current_timeline)
	else: timeline.process()
	print("TIMELINE_PROBE ",id," ",timeline.events.size())
	if "--release" in OS.get_cmdline_user_args():
		timeline.events.clear()
		timeline = null
		await process_frame
	if "--clear-cache" in OS.get_cmdline_user_args(): DialogicResourceUtil.event_cache.clear()
	quit(0)
