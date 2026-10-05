extends Node
## Hardware check for push-to-talk: records 1.5 s from the default microphone through VoiceInput and prints only the
## number of samples and the signal level. The audio is neither saved nor sent anywhere.
##
##   python scripts/godot_run.py --timeout 60 -- scenes/mic_check.tscn      (not --headless: it needs the audio driver)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var devices := AudioServer.get_input_device_list()
	print("MIC_CHECK devices: %s (current: %s, mix rate %d Hz)" % [str(devices), AudioServer.get_input_device(), int(AudioServer.get_mix_rate())])
	var vi := VoiceInput.new()
	add_child(vi)
	if not vi.setup(true):
		print("MIC_CHECK speech model not ready: %s" % vi.last_error)
	print("MIC_CHECK has_microphone=%s (%s)" % [vi.has_microphone(), vi.last_error])
	if not vi.has_microphone():
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.3).timeout  # let the microphone stream start
	vi.start_listening()
	await get_tree().create_timer(1.5).timeout
	var samples := vi.stop_listening()
	var peak := 0.0
	var sum_sq := 0.0
	for s in samples:
		peak = maxf(peak, absf(s))
		sum_sq += s * s
	var rms := sqrt(sum_sq / maxf(samples.size(), 1))
	print("MIC_CHECK captured %d samples at 16 kHz (%.2f s), peak %.4f, rms %.5f" % [samples.size(), float(samples.size()) / 16000.0, peak, rms])
	var heard := vi.transcribe(samples)
	print("MIC_CHECK transcription of the room (should be empty or a tag): '%s' in %d ms" % [String(heard["text"]).left(0), heard["ms"]])
	get_tree().quit(0)
