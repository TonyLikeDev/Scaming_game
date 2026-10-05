class_name VoiceInput
extends Node
## Push-to-talk input: records the microphone while the key is held, then turns the audio into text with godot-whisper.
## `transcribe()` also takes samples directly, which is how the tests run without a microphone or a person.
##
## Needs `audio/driver/enable_input=true` in project.godot. Windows may ask for microphone access; macOS needs the
## microphone entitlement when the game is exported.

const WHISPER_MODEL := "res://addons/godot_whisper/models/ggml-base.en.bin"
const BUS := "Record"
const WHISPER_RATE := 16000
const MIN_SPEECH_S := 0.25  ## anything shorter is a key bump, not speech

var stt: Node  ## godot-whisper SpeechToText
var model_ready := false
var listening := false
var last_error := ""

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _frames := PackedVector2Array()


## Loads the speech model and warms it up (the first transcription is slow: 4.9 s measured, then about 150 ms).
## `with_microphone` false skips the audio hardware (tests, or a machine without a microphone).
func setup(with_microphone := true) -> bool:
	if not ClassDB.class_exists("SpeechToText"):
		last_error = "godot-whisper is not loaded"
		return false
	if not FileAccess.file_exists(WHISPER_MODEL):
		last_error = "speech model missing: %s (see scripts/setup_addons.py and the ROADMAP)" % WHISPER_MODEL
		return false
	stt = ClassDB.instantiate("SpeechToText")
	stt.language_model = load(WHISPER_MODEL)
	add_child(stt)
	var silence := PackedFloat32Array()
	silence.resize(WHISPER_RATE)
	stt.transcribe(silence, "", 0)
	model_ready = true
	if with_microphone:
		_setup_microphone()
	return true


func _setup_microphone() -> void:
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		last_error = "microphone input is off (audio/driver/enable_input)"
		return
	var index := AudioServer.get_bus_index(BUS)
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_mute(index, true)  # recorded, never played back, so there is no feedback
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 5.0
		AudioServer.add_bus_effect(index, _capture)
	else:
		_capture = AudioServer.get_bus_effect(index, 0) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS
	add_child(_mic_player)
	_mic_player.play()


func has_microphone() -> bool:
	return _capture != null and not AudioServer.get_input_device_list().is_empty()


func start_listening() -> void:
	if _capture == null:
		return
	_frames.clear()
	_capture.clear_buffer()
	listening = true


## Stops recording and returns what was heard as mono 16 kHz samples (empty when too short to be speech).
func stop_listening() -> PackedFloat32Array:
	if not listening:
		return PackedFloat32Array()
	_drain()
	listening = false
	var mix_rate := float(AudioServer.get_mix_rate())
	var frames := _frames
	_frames = PackedVector2Array()
	if float(frames.size()) / mix_rate < MIN_SPEECH_S:
		return PackedFloat32Array()
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	return _resample(mono, mix_rate, float(WHISPER_RATE))


func _process(_delta: float) -> void:
	if listening:
		_drain()


func _drain() -> void:
	var available := _capture.get_frames_available()
	if available > 0:
		_frames.append_array(_capture.get_buffer(available))


## Speech to text. `samples` are mono 16 kHz floats. Returns {text, ms}; the text is "" for silence.
func transcribe(samples: PackedFloat32Array) -> Dictionary:
	if not model_ready or samples.is_empty():
		return {"text": "", "ms": 0}
	var t := Time.get_ticks_msec()
	var tokens: Array = stt.transcribe(samples, "", 0)
	return {"text": clean(String(tokens[0]) if not tokens.is_empty() else ""), "ms": Time.get_ticks_msec() - t}


## Whisper marks silence and noise with bracketed tags such as [BLANK_AUDIO]; those are not speech.
static func clean(text: String) -> String:
	var rx := RegEx.create_from_string("\\[[^\\]]*\\]|\\([^)]*\\)")
	return rx.sub(text, "", true).strip_edges()


static func _resample(input: PackedFloat32Array, from_rate: float, to_rate: float) -> PackedFloat32Array:
	if is_equal_approx(from_rate, to_rate):
		return input
	var out_size := int(float(input.size()) * to_rate / from_rate)
	var out := PackedFloat32Array()
	out.resize(out_size)
	var step := from_rate / to_rate
	for i in out_size:
		var pos := float(i) * step
		var i0 := int(pos)
		var i1 := mini(i0 + 1, input.size() - 1)
		out[i] = input[i0] * (1.0 - (pos - float(i0))) + input[i1] * (pos - float(i0))
	return out
