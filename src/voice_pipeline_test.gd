extends Node
## Phase 3 end-to-end latency: from the key being released to the caller starting to talk.
## A recorded clip stands in for the microphone, so no person or microphone is needed; playback is silent.
##
## release -> godot-whisper (speech to text) -> CallSession (director + model) -> VoiceEngine (OS voice or Kokoro) -> sound starts
## Two modes per engine: "late" speaks when the whole reply is in, "early" speaks as soon as the spoken line is complete
## (the reply's action and suspicion fields are still being generated at that moment).
##
##   python scripts/godot_run.py --timeout 900 --log voice_pipe -- scenes/voice_pipeline_test.tscn -- \
##       [--engines=os,kokoro] [--modes=late,early] [--model=models/x.gguf] [--out=docs/runs/voice/name.jsonl]
## Not --headless: the OS voices need a window.

const SCRIPT_LINES := [
	"Good evening ma'am, I'm calling from the Moon Warranty Department. Your extended warranty on the Moon is about to expire.",
	"Yes, the Moon. Without coverage, any crater damage would come out of your own pocket. For just three hundred dollars today we can renew it.",
	"It's a limited time offer, ma'am. The line closes in five minutes and I would hate for you to lose your lunar protection.",
	"All I need is your card number to put the Moon back under warranty.",
	"I'm still here and ready whenever you are. I just need the card number and the three digits on the back.",
]
const PLAYER_VOICE := "am_adam"  # the "player" in the recorded clips

var args := {}
var out_file: FileAccess
var rows: Array[Dictionary] = []


func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	_run.call_deferred()


func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _emit(data: Dictionary) -> void:
	print("VOICE_PIPE ", JSON.stringify(data))
	if out_file:
		out_file.store_line(JSON.stringify(data))


func _fail(reason: String) -> void:
	print("VOICE_PIPE_ERROR ", reason)
	get_tree().quit(2)


func _run() -> void:
	var out_path: String = args.get("out", "")
	if not out_path.is_empty():
		out_path = ProjectSettings.globalize_path("res://" + out_path) if out_path.is_relative_path() else out_path
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		out_file = FileAccess.open(out_path, FileAccess.WRITE)
	_emit({"kind": "env", "date": Time.get_datetime_string_from_system(false, true), "machine": OS.get_processor_name(), "os": OS.get_name(),
			"godot": Engine.get_version_info()["string"]})

	var model_path := LlmService.first_existing([args.get("model", "models/gemma-4-E4B-it-Q4_K_M.gguf")])
	if model_path.is_empty():
		return _fail("model not found")
	var gladys := Persona.load_file("res://callers/gladys.json")

	# Speech to text
	var vi := VoiceInput.new()
	add_child(vi)
	var t := Time.get_ticks_msec()
	if not vi.setup(false):
		return _fail("speech-to-text: %s" % vi.last_error)
	_emit({"kind": "stt_ready", "ms": Time.get_ticks_msec() - t})

	# Voices: Kokoro is needed in any case, to make the "microphone" clips
	var engine := VoiceEngine.new()
	engine.muted = true
	add_child(engine)
	t = Time.get_ticks_msec()
	if not await engine.use_kokoro():
		return _fail("kokoro: %s" % engine.last_error)
	_emit({"kind": "kokoro_ready", "ms": Time.get_ticks_msec() - t})

	# The recorded "player" clips: scripted lines spoken by another Kokoro voice, as 16 kHz mono like the microphone path
	var clips: Array[PackedFloat32Array] = []
	for line in SCRIPT_LINES:
		var wav := await engine.synthesize_wav(line, PLAYER_VOICE)
		var info := AudioUtil.parse_wav(wav)
		if not info["ok"]:
			return _fail("could not make a clip: %s" % info.get("reason", ""))
		clips.append(AudioUtil.to_mono_float(info, 16000))
	_emit({"kind": "clips", "count": clips.size(), "seconds": clips.map(func(c): return snappedf(float(c.size()) / 16000.0, 0.01))})

	# The language model
	var llm := LlmService.new()
	add_child(llm)
	llm.model_path = model_path
	llm.options = {"context_length": 4096, "allow_thinking": false}

	var engines := String(args.get("engines", "os,kokoro")).split(",")
	var modes := String(args.get("modes", "late,early")).split(",")
	for engine_name in engines:
		if engine_name == "os":
			engine.use_os()
		else:
			await engine.use_kokoro()
		for mode in modes:
			await _run_call(llm, vi, engine, gladys, clips, engine_name, mode)

	_summarize()
	llm.shutdown()
	if out_file:
		out_file.close()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _run_call(llm: LlmService, vi: VoiceInput, engine: VoiceEngine, persona: Dictionary, clips: Array[PackedFloat32Array], engine_name: String, mode: String) -> void:
	var session := CallSession.new()
	add_child(session)
	await session.start(llm, persona)
	if not session.active:
		_emit({"kind": "error", "reason": "call did not start: %s" % llm.last_error})
		return
	var state := {"started_at": -1, "say_at": -1}
	engine.speaking_started.connect(func(_text): if state["started_at"] < 0: state["started_at"] = Time.get_ticks_msec())
	session.brain.say_ready.connect(func(text):
		if state["say_at"] < 0:
			state["say_at"] = Time.get_ticks_msec()
			if mode == "early":
				engine.speak(ReplyParser.clean_say(text), persona))
	for turn in clips.size():
		if not session.active:
			break
		state["started_at"] = -1
		state["say_at"] = -1
		var t_release := Time.get_ticks_msec()
		var heard := vi.transcribe(clips[turn])
		var t_stt := Time.get_ticks_msec()
		session.player_says(heard["text"])
		while session.thinking:
			await get_tree().process_frame
		var t_reply := Time.get_ticks_msec()
		var said := String(session.last_reply.get("say", ""))
		if mode == "late" and not said.is_empty():
			engine.speak(said, persona)
		var deadline := Time.get_ticks_msec() + 15000
		while state["started_at"] < 0 and not said.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		var t_audio: int = state["started_at"]
		var row := {
			"kind": "pipeline", "engine": engine_name, "mode": mode, "turn": turn + 1, "heard": heard["text"],
			"clip_s": snappedf(float(clips[turn].size()) / 16000.0, 0.01),
			"stt_ms": t_stt - t_release, "reply_ms": t_reply - t_stt,
			"say_ms": (state["say_at"] - t_stt) if state["say_at"] >= 0 else -1,
			"tts_ms": (t_audio - (t_reply if mode == "late" else state["say_at"])) if t_audio >= 0 else -1,
			"total_ms": (t_audio - t_release) if t_audio >= 0 else -1,
			"reply_ok": session.last_reply.get("ok", false), "action": session.last_reply.get("action", ""),
			"said": said,
		}
		rows.append(row)
		_emit(row)
		await get_tree().create_timer(0.2).timeout
		if engine_name == "kokoro":
			await get_tree().create_timer(0.3).timeout
		engine.stop()
	if session.active:
		session.player_hangs_up()
	session.queue_free()
	await get_tree().create_timer(0.6).timeout


func _summarize() -> void:
	var groups := {}
	for r in rows:
		var key := "%s/%s" % [r["engine"], r["mode"]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(r)
	for key in groups:
		var g: Array = groups[key]
		var warm := g.filter(func(r): return r["turn"] > 1 and r["total_ms"] >= 0)
		var all_ok := g.filter(func(r): return r["total_ms"] >= 0)
		var totals: Array = warm.map(func(r): return r["total_ms"])
		totals.sort()
		var first: Array = g.filter(func(r): return r["turn"] == 1 and r["total_ms"] >= 0).map(func(r): return r["total_ms"])
		var summary := {"kind": "pipeline_summary", "engine_mode": key, "turns": g.size(), "with_sound": all_ok.size(),
				"first_turn_total_ms": first[0] if not first.is_empty() else -1,
				"warm_total_ms_median": totals[totals.size() / 2] if not totals.is_empty() else -1,
				"warm_total_ms_max": totals[-1] if not totals.is_empty() else -1,
				"stt_ms_median": _median(g, "stt_ms"), "reply_ms_median": _median(g, "reply_ms"), "tts_ms_median": _median(g, "tts_ms")}
		_emit(summary)


func _median(group: Array, key: String) -> float:
	var values: Array = group.filter(func(r): return r[key] >= 0).map(func(r): return r[key])
	values.sort()
	return float(values[values.size() / 2]) if not values.is_empty() else -1.0
