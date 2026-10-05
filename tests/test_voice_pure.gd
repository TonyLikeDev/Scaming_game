extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/test_voice_pure.gd
## The parts of the voice code that need no model, microphone or speakers: voice choice, transcript cleaning, resampling.

var failures := 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


func _init() -> void:
	var gladys := Persona.load_file("res://callers/gladys.json")
	var barry := Persona.load_file("res://callers/barry.json")
	var priya := Persona.load_file("res://callers/priya.json")

	# Kokoro voice choice
	check(VoiceEngine.kokoro_voice_for(gladys) == "bf_emma", "a persona's own kokoro_voice wins")
	check(VoiceEngine.kokoro_voice_for(barry) == "am_michael" and VoiceEngine.kokoro_voice_for(priya) == "af_sarah", "the other starters keep theirs")
	var plain_gb := {"id": "mod_gb", "voice": "en-GB"}
	var plain_us := {"id": "mod_us", "voice": "en-US"}
	check(VoiceEngine.kokoro_voice_for(plain_gb).begins_with("b"), "no kokoro_voice, en-GB: a British voice (%s)" % VoiceEngine.kokoro_voice_for(plain_gb))
	check(VoiceEngine.kokoro_voice_for(plain_us).begins_with("a"), "no kokoro_voice, en-US: an American voice (%s)" % VoiceEngine.kokoro_voice_for(plain_us))
	check(VoiceEngine.kokoro_voice_for(plain_gb) == VoiceEngine.kokoro_voice_for(plain_gb), "the choice is stable between calls")
	var spread := {}
	for i in 40:
		spread[VoiceEngine.kokoro_voice_for({"id": "caller_%d" % i, "voice": "en-US"})] = true
	check(spread.size() >= 4, "different persona ids spread over several voices (%d distinct)" % spread.size())
	check(VoiceEngine.kokoro_language_for("bf_emma") == "en-gb" and VoiceEngine.kokoro_language_for("am_michael") == "en-us", "language follows the voice prefix")

	# Sentence splitting for Kokoro (the first sentence plays while the rest is synthesized)
	var s := VoiceEngine.split_sentences("Oh dear. A warranty? Hold on, let me find my glasses.")
	check(Array(s) == ["Oh dear. A warranty?", "Hold on, let me find my glasses."], "short fragments join the next sentence: %s" % str(s))
	check(Array(VoiceEngine.split_sentences("Hello there, dear.")) == ["Hello there, dear."], "one sentence stays one")
	check(Array(VoiceEngine.split_sentences("Hmm.")) == ["Hmm."], "a lone short word is kept")
	check(Array(VoiceEngine.split_sentences("Fine. Goodbye.")) == ["Fine. Goodbye."], "two short fragments become one")
	check(Array(VoiceEngine.split_sentences("Wait, what? No way! I'll pay in five minutes.")) == ["Wait, what? No way!", "I'll pay in five minutes."], "question and exclamation marks split")
	check(Array(VoiceEngine.split_sentences("Mr. Biscuits says hello.")) == ["Mr. Biscuits says hello."], "an abbreviation does not leave a stub")
	check(VoiceEngine.split_sentences("").is_empty() and VoiceEngine.split_sentences("   ").is_empty(), "nothing to say gives nothing")
	check(Array(VoiceEngine.split_sentences("No full stop at the end")) == ["No full stop at the end"], "text without a final stop is kept")
	var long_line := VoiceEngine.split_sentences("Before we do that, are you the one who handles the little silver canines, or does Cousin Kevin usually call about those?")
	check(Array(long_line) == ["Before we do that,", "are you the one who handles the little silver canines,", "or does Cousin Kevin usually call about those?"], "a long sentence is split at commas that leave four words on each side: %s" % str(long_line))
	check(Array(VoiceEngine.split_sentences("Well, yes, no, maybe so, but honestly I do not know what to say right now.")) == ["Well, yes, no, maybe so,", "but honestly I do not know what to say right now."], "commas too close to the start are skipped")
	check(Array(VoiceEngine.split_sentences("One two three four five six seven eight nine ten eleven twelve.")) == ["One two three four five six seven eight nine ten eleven twelve."], "a long sentence without a comma stays whole")
	check(Array(VoiceEngine.split_sentences("Short bit, short bit.")) == ["Short bit, short bit."], "a short sentence is never split at a comma")

	# Kokoro audio is used as it is when it is 16-bit mono
	var pcm := PackedByteArray()
	pcm.resize(4800)
	for i in 2400:
		pcm.encode_s16(i * 2, roundi(sin(TAU * 300.0 * float(i) / 24000.0) * 12000.0))
	var fast := VoiceEngine.stream_from_wav(AudioUtil.build_wav(pcm, 24000))
	check(fast != null and fast.mix_rate == 24000 and fast.data == pcm and not fast.stereo, "16-bit mono WAV becomes a stream without conversion")
	check(is_equal_approx(fast.get_length(), 0.1), "the stream is 0.1 s long (%f)" % fast.get_length())
	var stereo := VoiceEngine.stream_from_wav(AudioUtil.build_wav(pcm, 24000, 2))
	check(stereo != null and stereo.data.size() == 2400, "a stereo WAV is converted to mono (%d bytes)" % stereo.data.size())
	check(VoiceEngine.stream_from_wav(PackedByteArray([1, 2, 3])) == null, "garbage audio gives null, not an error")

	# Whisper's bracketed tags are not speech
	check(VoiceInput.clean("[BLANK_AUDIO]") == "", "[BLANK_AUDIO] is silence")
	check(VoiceInput.clean(" Hello there. [MUSIC] ") == "Hello there.", "a music tag is removed")
	check(VoiceInput.clean("(sighs) I want the money") == "I want the money", "a parenthesised sound is removed")
	check(VoiceInput.clean("Plain words") == "Plain words", "plain words are kept")

	# Resampling keeps the duration
	var one_second_48k := PackedFloat32Array()
	one_second_48k.resize(48000)
	for i in 48000:
		one_second_48k[i] = sin(TAU * 440.0 * float(i) / 48000.0)
	var down := VoiceInput._resample(one_second_48k, 48000.0, 16000.0)
	check(down.size() == 16000, "48 kHz to 16 kHz gives 16000 samples (%d)" % down.size())
	check(absf(down[100] - sin(TAU * 440.0 * 300.0 / 48000.0)) < 0.01, "the waveform survives resampling")
	check(VoiceInput._resample(down, 16000.0, 16000.0).size() == 16000, "same rate is a no-op")

	# VoiceInput without a model or microphone must fail politely, not crash
	var vi := VoiceInput.new()
	check(vi.transcribe(PackedFloat32Array([0.1, 0.2])) == {"text": "", "ms": 0}, "transcribe before setup returns empty text")
	check(vi.stop_listening().is_empty(), "stop_listening without listening returns nothing")
	vi.start_listening()
	check(not vi.listening, "start_listening without a microphone does nothing")
	vi.free()

	# The OS voice picker gives each starter persona a deterministic voice or nothing, never an error
	check(CallerVoice.pick(gladys) == CallerVoice.pick(gladys), "OS voice choice is stable")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
