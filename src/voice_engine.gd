class_name VoiceEngine
extends Node
## Speaks the caller's lines. Two engines, switchable:
##  - "os":     Godot's `DisplayServer.tts_speak`. Starts after about 60 ms, but on Windows there are only three US voices
##              and they speak slowly.
##  - "kokoro": NobodyWho's Kokoro-82M. Many natural voices (British and American, men and women), about 7 times faster than
##              real time, but it returns the whole clip, so the caller starts talking after synthesis (0.4 to 0.95 s per
##              line) and the first use downloads a 326 MB model.
## `muted` plays everything silently (the timing is still real), which is how the tests run.

signal speaking_started(text: String)
signal speaking_finished(text: String)

const KOKORO_SOURCE := "hf://NobodyWho/Kokoro-82M"
const LONG_SENTENCE_WORDS := 10  ## a sentence longer than this is split at a comma, if there is a good one
## Used when a persona has no `kokoro_voice`: picked from its language code and id.
const FALLBACK_VOICES := {
	"b": ["bf_emma", "bf_isabella", "bm_george", "bm_lewis", "bf_alice", "bm_daniel"],
	"a": ["af_sarah", "am_michael", "af_heart", "am_adam", "af_bella", "am_eric"],
}

var engine := "os"  ## "os", "kokoro" or "off"
var muted := false
var kokoro_ready := false
var last_error := ""

var _tts: Node
var _player: AudioStreamPlayer
var _speak_id := 0
var _os_callbacks_set := false


## The Kokoro voice for a persona: its own `kokoro_voice`, else one picked from `voice` (en-GB gives a British voice).
static func kokoro_voice_for(persona: Dictionary) -> String:
	if persona.has("kokoro_voice"):
		return persona["kokoro_voice"]
	var british := String(persona.get("voice", "en-US")).to_lower().begins_with("en-gb")
	var pool: Array = FALLBACK_VOICES["b" if british else "a"]
	return pool[String(persona.get("id", "")).hash() % pool.size()]


## Splits a spoken line into sentences so the first can be played while the rest is still being synthesized. Fragments
## shorter than three words are joined to the sentence after them ("Oh dear." + "A warranty?").
static func split_sentences(text: String) -> PackedStringArray:
	var raw := PackedStringArray()
	var current := ""
	var chars := text.strip_edges()
	for i in chars.length():
		current += chars[i]
		var is_end := chars[i] in [".", "?", "!"]
		var next_is_break := i + 1 >= chars.length() or chars[i + 1] == " "
		if is_end and next_is_break:
			raw.append(current.strip_edges())
			current = ""
	if not current.strip_edges().is_empty():
		raw.append(current.strip_edges())
	var out := PackedStringArray()
	var carry := ""
	for s in raw:
		var candidate := (carry + " " + s).strip_edges()
		if candidate.split(" ", false).size() < 3:
			carry = candidate
		else:
			out.append(candidate)
			carry = ""
	if not carry.is_empty():
		if out.is_empty():
			out.append(carry)
		else:
			out[out.size() - 1] += " " + carry
	# A long sentence is split at a comma, so the first chunk is short and starts sooner
	var chunked := PackedStringArray()
	for sentence in out:
		var rest := sentence
		while rest.split(" ", false).size() > LONG_SENTENCE_WORDS:
			var cut := _comma_cut(rest)
			if cut < 0:
				break
			chunked.append(rest.substr(0, cut + 1).strip_edges())
			rest = rest.substr(cut + 1).strip_edges()
		chunked.append(rest)
	return chunked


## Position of the first comma or semicolon with at least four words on each side, or -1.
static func _comma_cut(sentence: String) -> int:
	for i in sentence.length():
		if sentence[i] == "," or sentence[i] == ";":
			var left := sentence.substr(0, i).split(" ", false).size()
			var right := sentence.substr(i + 1).split(" ", false).size()
			if left >= 4 and right >= 4:
				return i
	return -1


## An AudioStreamWAV from WAV bytes. 16-bit mono (what Kokoro returns) is used as it is; anything else is converted.
static func stream_from_wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var info := AudioUtil.parse_wav(bytes, false)
	if not info["ok"]:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = info["rate"]
	stream.stereo = false
	if info["bits"] == 16 and info["channels"] == 1 and not info["float"]:
		stream.data = bytes.slice(info["data_offset"], info["data_offset"] + info["data_length"])
	else:
		stream.data = AudioUtil.to_pcm16_bytes(AudioUtil.parse_wav(bytes), info["rate"])
	return stream


static func kokoro_language_for(voice_id: String) -> String:
	return "en-gb" if voice_id.begins_with("b") else "en-us"


func use_os() -> void:
	engine = "os"


## Loads Kokoro (downloads it the first time) and switches to it. Returns false, with `last_error`, if that fails.
func use_kokoro(timeout_s := 600.0) -> bool:
	if kokoro_ready:
		engine = "kokoro"
		return true
	if not ClassDB.class_exists("NobodyWhoTextToSpeech"):
		last_error = "NobodyWho addon is not loaded"
		return false
	_tts = ClassDB.instantiate("NobodyWhoTextToSpeech")
	_tts.source = KOKORO_SOURCE
	_tts.architecture = "kokoro"
	_tts.voice = "bf_emma"
	_tts.language = "en-gb"
	add_child(_tts)
	var state := {"result": ""}
	_tts.worker_started.connect(func(): state["result"] = "ok", CONNECT_ONE_SHOT)
	_tts.worker_failed.connect(func(error): state["result"] = str(error), CONNECT_ONE_SHOT)
	_tts.start_worker()
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while state["result"] == "" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if state["result"] != "ok":
		last_error = state["result"] if state["result"] != "" else "timeout while loading Kokoro"
		_tts.queue_free()
		_tts = null
		return false
	_player = AudioStreamPlayer.new()
	add_child(_player)
	kokoro_ready = true
	engine = "kokoro"
	return true


## Synthesizes a line with Kokoro and returns the WAV bytes (empty on failure). Used by `speak` and by the tests.
func synthesize_wav(text: String, voice_id: String) -> PackedByteArray:
	if not kokoro_ready:
		return PackedByteArray()
	_tts.voice = voice_id
	_tts.language = kokoro_language_for(voice_id)
	var res: Variant = await _tts.synthesize(text)
	if typeof(res) == TYPE_DICTIONARY:
		if not res.get("ok", false):
			last_error = str(res.get("error", "synthesis failed"))
			return PackedByteArray()
		var wav: Variant = res.get("wav", PackedByteArray())
		return wav if typeof(wav) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray()
	return res if typeof(res) == TYPE_PACKED_BYTE_ARRAY else PackedByteArray()


## Speaks one line. A newer line replaces an older one that has not started yet. Emits `speaking_started` when sound begins.
func speak(text: String, persona: Dictionary) -> void:
	if engine == "off" or text.strip_edges().is_empty():
		return
	_speak_id += 1
	var id := _speak_id
	if engine == "kokoro" and kokoro_ready:
		await _speak_kokoro(text, persona, id)
	else:
		_speak_os(text, persona, id)


func stop() -> void:
	_speak_id += 1
	if _player != null:
		_player.stop()
	DisplayServer.tts_stop()


func _speak_os(text: String, persona: Dictionary, id: int) -> void:
	var v := CallerVoice.pick(persona)
	if v.is_empty():
		last_error = "no OS voices"
		return
	if not _os_callbacks_set:
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_STARTED, func(uid): if uid == _speak_id: speaking_started.emit(text))
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, func(uid): if uid == _speak_id: speaking_finished.emit(text))
		_os_callbacks_set = true
	DisplayServer.tts_speak(text, v["id"], 0 if muted else 80, v["pitch"], v["rate"], id, true)


## Speaks sentence by sentence: the first sentence starts as soon as it is synthesized (about 0.4 s) and the next one is
## synthesized while it plays, so a long line does not delay the start.
func _speak_kokoro(text: String, persona: Dictionary, id: int) -> void:
	var voice_id := kokoro_voice_for(persona)
	var sentences := split_sentences(text)
	var started := false
	for sentence in sentences:
		var bytes := await synthesize_wav(sentence, voice_id)
		if id != _speak_id:
			return  # replaced by a newer line, or stopped, while synthesizing
		var stream := stream_from_wav(bytes)
		if stream == null:
			last_error = "bad audio from Kokoro"
			return
		while _player.playing:  # the previous sentence is still being said
			await get_tree().process_frame
			if id != _speak_id:
				return
		_player.stream = stream
		_player.volume_db = -80.0 if muted else 0.0
		_player.play()
		if not started:
			started = true
			speaking_started.emit(text)
	while _player.playing and id == _speak_id:
		await get_tree().process_frame
	if id == _speak_id:
		speaking_finished.emit(text)
