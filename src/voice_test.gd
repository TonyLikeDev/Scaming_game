extends Node
## Phase 3 voice-stack test: text-to-speech and speech-to-text, timed. Nothing is played out loud.
##
## Stages (--stage=...): tts (NobodyWho Kokoro, writes WAVs), stt_nw (NobodyWho Whisper), stt_gw (godot-whisper),
## os (Godot's OS voices, needs a window: not --headless). Several can be joined with commas, "all" runs the first three.
##   python scripts/godot_run.py --timeout 900 --log voice -- --headless scenes/voice_test.tscn -- --stage=tts,stt_nw
##   python scripts/godot_run.py --timeout 300 --log voice_os -- scenes/voice_test.tscn -- --stage=os
## Output: one `VOICE_*` line per measurement, and a JSON-lines file in docs/runs/voice/ when --out is given.
##
## The sentences are typical caller lines (about 13 words). The speech-to-text test feeds back the text-to-speech audio,
## which is clean and so flatters the word error rate, plus one real human recording: .tools/voice/jfk.wav, the sample
## shipped inside the godot-whisper release (MIT licence), cut out of the cached zip by the test.

const SENTENCES := [
	"Kevin, is that you? Mr. Biscuits says hello.",
	"Three hundred dollars? Is that a deposit for Mr. Biscuits' new tuna fountain?",
	"Now hold on just a darn minute, you think you can demand payment on the first call?",
	"Oh dear, a virus? I always get so confused with this computer.",
	"Fine, you have convinced me. My card is four two four two, four two four two, four two four two, four two four two.",
	"I don't think so. Goodbye.",
	"A cumulus cloud over Devon? That sounds rather fluffy, nephew Kevin.",
	"Invisible to satellites? That sounds exactly what I need for my secret underground hideout.",
]
const JFK_TEXT := "And so, my fellow Americans, ask not what your country can do for you, ask what you can do for your country."
const VOICE_DIR := "res://.tools/voice"

var args := {}
var out_file: FileAccess
var stage_results: Array[Dictionary] = []


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


func _emit(kind: String, data: Dictionary) -> void:
	data["kind"] = kind
	stage_results.append(data)
	print("VOICE_%s %s" % [kind.to_upper(), JSON.stringify(data)])
	if out_file:
		out_file.store_line(JSON.stringify(data))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VOICE_DIR))
	var out_path: String = args.get("out", "")
	if not out_path.is_empty():
		out_path = ProjectSettings.globalize_path("res://" + out_path) if out_path.is_relative_path() else out_path
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		out_file = FileAccess.open(out_path, FileAccess.WRITE)
	var stages := String(args.get("stage", "all")).split(",")
	if "all" in stages:
		stages = PackedStringArray(["tts", "stt_nw", "stt_gw"])
	_emit("env", {"date": Time.get_datetime_string_from_system(false, true), "machine": OS.get_processor_name(), "os": OS.get_name(),
			"godot": Engine.get_version_info()["string"], "stages": Array(stages)})
	if "tts" in stages:
		await _stage_tts()
	if "stt_nw" in stages:
		await _stage_stt_nw()
	if "stt_gw" in stages:
		await _stage_stt_gw()
	if "os" in stages:
		await _stage_os()
	if out_file:
		out_file.close()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _wav_path(i: int) -> String:
	return ProjectSettings.globalize_path(VOICE_DIR + "/tts_%02d.wav" % i)


# --- NobodyWho text-to-speech (Kokoro) -------------------------------------------------------------------------

func _stage_tts() -> void:
	if not ClassDB.class_exists("NobodyWhoTextToSpeech"):
		_emit("error", {"stage": "tts", "reason": "NobodyWho addon not loaded"})
		return
	var tts: Node = ClassDB.instantiate("NobodyWhoTextToSpeech")
	tts.source = String(args.get("tts_source", "hf://NobodyWho/Kokoro-82M"))
	tts.architecture = "kokoro"
	tts.voice = String(args.get("tts_voice", "bf_emma"))
	tts.language = String(args.get("tts_lang", "en-gb"))
	tts.speed = float(args.get("tts_speed", "1.0"))
	add_child(tts)
	var t0 := Time.get_ticks_msec()
	tts.start_worker()
	var started := await _wait_signal_or_fail(tts, "worker_started", "worker_failed", 600.0)
	if started != "ok":
		_emit("error", {"stage": "tts", "reason": "worker did not start: %s" % started})
		tts.queue_free()
		return
	var load_ms := Time.get_ticks_msec() - t0
	_emit("tts_load", {"source": tts.source, "voice": tts.voice, "load_ms": load_ms})
	var round := 0
	for pass_index in 2:  # the first pass includes warm-up, the second is the steady state
		round += 1
		for i in SENTENCES.size():
			var text: String = SENTENCES[i]
			var t := Time.get_ticks_msec()
			var res: Variant = await tts.synthesize(text)
			var ms := Time.get_ticks_msec() - t
			var wav_bytes := PackedByteArray()
			var ok := false
			var error := ""
			if typeof(res) == TYPE_DICTIONARY:
				ok = res.get("ok", false)
				error = str(res.get("error", ""))
				var w: Variant = res.get("wav", PackedByteArray())
				if typeof(w) == TYPE_PACKED_BYTE_ARRAY:
					wav_bytes = w
			elif typeof(res) == TYPE_PACKED_BYTE_ARRAY:
				wav_bytes = res
				ok = wav_bytes.size() > 44
			var info := AudioUtil.parse_wav(wav_bytes) if ok else {"ok": false}
			var seconds: float = info.get("seconds", 0.0)
			if pass_index == 1 and info["ok"]:
				var f := FileAccess.open(_wav_path(i), FileAccess.WRITE)
				f.store_buffer(wav_bytes)
				f.close()
			_emit("tts", {"pass": round, "i": i, "chars": text.length(), "words": text.split(" ").size(), "synth_ms": ms,
					"audio_s": snappedf(seconds, 0.01), "rtf": snappedf(float(ms) / 1000.0 / maxf(seconds, 0.01), 0.001),
					"rate": info.get("rate", 0), "ok": info["ok"], "error": error})
	tts.queue_free()
	await get_tree().create_timer(0.3).timeout


# --- NobodyWho speech-to-text (Whisper ONNX) -------------------------------------------------------------------

func _clips() -> Array[Dictionary]:
	var clips: Array[Dictionary] = []
	for i in SENTENCES.size():
		var path := _wav_path(i)
		if FileAccess.file_exists(path):
			clips.append({"name": "tts_%02d" % i, "text": SENTENCES[i], "wav": AudioUtil.parse_wav(FileAccess.get_file_as_bytes(path))})
	var jfk := ProjectSettings.globalize_path(VOICE_DIR + "/jfk.wav")
	if FileAccess.file_exists(jfk):
		clips.append({"name": "jfk_human", "text": JFK_TEXT, "wav": AudioUtil.parse_wav(FileAccess.get_file_as_bytes(jfk))})
	return clips


func _stage_stt_nw() -> void:
	if not ClassDB.class_exists("NobodyWhoSpeechToText"):
		_emit("error", {"stage": "stt_nw", "reason": "NobodyWho addon not loaded"})
		return
	var clips := _clips()
	if clips.is_empty():
		_emit("error", {"stage": "stt_nw", "reason": "no clips: run --stage=tts first, and put jfk.wav in .tools/voice/"})
		return
	var stt: Node = ClassDB.instantiate("NobodyWhoSpeechToText")
	stt.model_path = String(args.get("stt_model", "hf://onnx-community/whisper-base"))
	stt.quantization = String(args.get("stt_quant", "q4"))
	stt.language = "en"
	add_child(stt)
	var t0 := Time.get_ticks_msec()
	stt.start_worker()
	var started := await _wait_signal_or_fail(stt, "worker_started", "worker_failed", 600.0)
	if started != "ok":
		_emit("error", {"stage": "stt_nw", "reason": "worker did not start: %s" % started})
		stt.queue_free()
		return
	_emit("stt_nw_load", {"model": stt.model_path, "quant": stt.quantization, "load_ms": Time.get_ticks_msec() - t0})
	for pass_index in 2:
		for clip in clips:
			var wav: Dictionary = clip["wav"]
			if not wav.get("ok", false):
				continue
			var pcm := AudioUtil.to_pcm16_bytes(wav, 16000)
			var t := Time.get_ticks_msec()
			stt.transcribe_pcm(pcm, 16000)
			var text: String = await stt.transcription_finished
			var ms := Time.get_ticks_msec() - t
			_emit("stt_nw", {"pass": pass_index + 1, "clip": clip["name"], "audio_s": snappedf(wav["seconds"], 0.01), "ms": ms,
					"rtf": snappedf(float(ms) / 1000.0 / wav["seconds"], 0.001), "wer": snappedf(AudioUtil.wer(clip["text"], text), 0.001),
					"heard": text.strip_edges()})
	stt.queue_free()
	await get_tree().create_timer(0.3).timeout


# --- godot-whisper ---------------------------------------------------------------------------------------------

func _stage_stt_gw() -> void:
	if not ClassDB.class_exists("SpeechToText"):
		_emit("error", {"stage": "stt_gw", "reason": "godot-whisper not loaded"})
		return
	var model_file := String(args.get("gw_model", "res://addons/godot_whisper/models/ggml-base.en.bin"))
	if not FileAccess.file_exists(model_file):
		_emit("error", {"stage": "stt_gw", "reason": "model file missing: %s (download it from huggingface.co/ggerganov/whisper.cpp)" % model_file})
		return
	var clips := _clips()
	if clips.is_empty():
		_emit("error", {"stage": "stt_gw", "reason": "no clips"})
		return
	var t0 := Time.get_ticks_msec()
	var stt: Node = ClassDB.instantiate("SpeechToText")
	stt.language_model = load(model_file)
	add_child(stt)
	_emit("stt_gw_load", {"model": model_file.get_file(), "load_ms": Time.get_ticks_msec() - t0})
	for pass_index in 2:
		for clip in clips:
			var wav: Dictionary = clip["wav"]
			if not wav.get("ok", false):
				continue
			var samples := AudioUtil.to_mono_float(wav, 16000)
			var t := Time.get_ticks_msec()
			var tokens: Array = stt.transcribe(samples, "", 0)
			var ms := Time.get_ticks_msec() - t
			var text := String(tokens[0]) if not tokens.is_empty() else ""
			_emit("stt_gw", {"pass": pass_index + 1, "clip": clip["name"], "audio_s": snappedf(wav["seconds"], 0.01), "ms": ms,
					"rtf": snappedf(float(ms) / 1000.0 / wav["seconds"], 0.001), "wer": snappedf(AudioUtil.wer(clip["text"], text), 0.001),
					"heard": text.strip_edges()})
	stt.queue_free()


# --- OS voices ---------------------------------------------------------------------------------------------------

var _tts_events: Array[Dictionary] = []


func _on_tts_event(kind: String, id: int) -> void:
	_tts_events.append({"kind": kind, "id": id, "t": Time.get_ticks_msec()})


func _stage_os() -> void:
	var voices := CallerVoice.voices()
	_emit("os_voices", {"count": voices.size(), "voices": voices.map(func(v): return "%s (%s)" % [v["name"], v["language"]])})
	if voices.is_empty():
		_emit("error", {"stage": "os", "reason": "no OS voices (headless run, or none installed)"})
		return
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, func(id): _on_tts_event("started", id))
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, func(id): _on_tts_event("ended", id))
	var voice: Dictionary = voices[0]
	for i in SENTENCES.size():
		_tts_events.clear()
		var t := Time.get_ticks_msec()
		DisplayServer.tts_speak(SENTENCES[i], voice["id"], 0, 1.0, 1.0, i + 1, true)  # volume 0: silent, events still fire
		var deadline := t + 30000
		while Time.get_ticks_msec() < deadline and not _tts_events.any(func(e): return e["kind"] == "ended"):
			await get_tree().process_frame
		var started: Variant = _tts_events.filter(func(e): return e["kind"] == "started")
		var ended: Variant = _tts_events.filter(func(e): return e["kind"] == "ended")
		_emit("os_tts", {"i": i, "voice": voice["name"], "chars": SENTENCES[i].length(),
				"start_ms": (started[0]["t"] - t) if not started.is_empty() else -1,
				"total_ms": (ended[0]["t"] - t) if not ended.is_empty() else -1})


## Waits for `ok_signal` on `node` or `fail_signal` (whichever comes first). Returns "ok", the failure text, or "timeout".
func _wait_signal_or_fail(node: Node, ok_signal: String, fail_signal: String, timeout_s: float) -> String:
	var state := {"result": ""}
	node.connect(ok_signal, func(): state["result"] = "ok", CONNECT_ONE_SHOT)
	node.connect(fail_signal, func(error): state["result"] = str(error), CONNECT_ONE_SHOT)
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while state["result"] == "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return state["result"] if state["result"] != "" else "timeout"
