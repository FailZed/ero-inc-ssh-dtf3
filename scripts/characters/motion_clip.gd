extends RefCounted
## Editable parameter clips. Recording samples values; playback interpolates by time.
var recording := false
var playing := false
var loop := false
var time := 0.0
var frames: Array[Dictionary] = []
var _sample_time := 0.0
var sample_interval := 1.0/30.0
var model_id := ""

func start_recording(id: String) -> void:
	model_id = id
	frames.clear()
	time = 0.0
	_sample_time = 0.0
	playing = false
	recording = true

func record_step(delta: float, parameters: Dictionary) -> void:
	if not recording: return
	time += delta
	_sample_time -= delta
	if frames.is_empty() or _sample_time <= 0.0:
		frames.append({"time":time, "values":parameters.duplicate(true)})
		_sample_time += sample_interval

func stop() -> void:
	recording = false
	playing = false

func play(repeat: bool = false) -> bool:
	if frames.size() < 2: return false
	recording = false
	playing = true
	loop = repeat
	time = 0.0
	return true

func sample(delta: float) -> Dictionary:
	if not playing or frames.size() < 2: return {}
	time += delta
	var duration := float(frames[-1].time)
	if time > duration:
		if loop and duration > 0.0: time = fmod(time, duration)
		else:
			playing = false
			return frames[-1]["values"].duplicate(true)
	var a: Dictionary = frames[0]
	var b: Dictionary = frames[-1]
	for index in range(1, frames.size()):
		if float(frames[index].time) >= time:
			a = frames[index-1]
			b = frames[index]
			break
	var weight := clampf((time-float(a.time))/maxf(float(b.time)-float(a.time), 0.00001), 0.0, 1.0)
	var result := {}
	for id in a["values"]:
		result[id] = lerpf(float(a["values"][id]), float(b["values"].get(id, a["values"][id])), weight)
	return result

func serialize() -> Dictionary:
	return {"schema":1, "model":model_id, "frames":frames.duplicate(true)}

func load_clip(data: Dictionary) -> bool:
	if data.get("schema") != 1 or not data.get("frames") is Array: return false
	var parsed: Array[Dictionary] = []
	var previous := -1.0
	for frame: Variant in data.frames:
		if not frame is Dictionary or not frame.get("values") is Dictionary: return false
		var stamp := float(frame.get("time", -1.0))
		if not is_finite(stamp) or stamp < 0.0 or stamp <= previous: return false
		for value: Variant in frame["values"].values():
			if not (value is float or value is int) or not is_finite(float(value)): return false
		parsed.append(frame.duplicate(true))
		previous = stamp
	if parsed.size() < 2: return false
	stop()
	frames = parsed
	model_id = str(data.get("model", ""))
	time = 0.0
	return true
