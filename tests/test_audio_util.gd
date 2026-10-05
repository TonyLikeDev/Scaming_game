extends SceneTree
## Run: python scripts/godot_run.py --import -- --headless --script tests/test_audio_util.gd
## Checks the WAV reader, the resampler and the word error rate used by the voice tests.

var failures := 0


func check(condition: bool, label: String) -> void:
	if condition:
		print("ok    ", label)
	else:
		failures += 1
		print("FAIL  ", label)


func _init() -> void:
	# A 0.1 s, 440 Hz, mono 16-bit WAV built byte by byte, so the header layout the reader expects is explicit.
	var rate := 24000
	var frames := 2400
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in frames:
		pcm.encode_s16(i * 2, roundi(sin(TAU * 440.0 * float(i) / float(rate)) * 16000.0))
	var wav := PackedByteArray()
	wav.append_array("RIFF".to_ascii_buffer())
	wav.resize(8)
	wav.encode_u32(4, 36 + pcm.size())
	wav.append_array("WAVE".to_ascii_buffer())
	wav.append_array("fmt ".to_ascii_buffer())
	var head := PackedByteArray()
	head.resize(20)
	head.encode_u32(0, 16)
	head.encode_u16(4, 1)
	head.encode_u16(6, 1)
	head.encode_u32(8, rate)
	head.encode_u32(12, rate * 2)
	head.encode_u16(16, 2)
	head.encode_u16(18, 16)
	wav.append_array(head)
	wav.append_array("data".to_ascii_buffer())
	var size_bytes := PackedByteArray()
	size_bytes.resize(4)
	size_bytes.encode_u32(0, pcm.size())
	wav.append_array(size_bytes)
	wav.append_array(pcm)

	var parsed := AudioUtil.parse_wav(wav)
	check(parsed["ok"], "valid WAV parses")
	check(parsed["rate"] == 24000 and parsed["channels"] == 1 and parsed["bits"] == 16, "header fields read")
	check(parsed["frames"] == 2400 and absf(parsed["seconds"] - 0.1) < 0.0001, "length is 0.1 s (%s)" % parsed.get("seconds"))
	check(absf(parsed["samples"][6] - sin(TAU * 440.0 * 6.0 / 24000.0) * 16000.0 / 32768.0) < 0.001, "sample values decode")

	var mono16 := AudioUtil.to_mono_float(parsed, 16000)
	check(mono16.size() == 1600, "24 kHz to 16 kHz keeps the duration (%d samples)" % mono16.size())
	var bytes16 := AudioUtil.to_pcm16_bytes(parsed, 16000)
	check(bytes16.size() == 3200, "PCM16 bytes are two per sample (%d)" % bytes16.size())

	var header_only := AudioUtil.parse_wav(wav, false)
	check(header_only["ok"] and header_only["samples"].is_empty() and header_only["frames"] == 2400, "header-only parse skips the samples but keeps the length")
	check(header_only["data_offset"] == 44 and header_only["data_length"] == 4800, "the position of the audio data is reported (%d, %d)" % [header_only["data_offset"], header_only["data_length"]])
	var rebuilt := AudioUtil.build_wav(pcm, rate)
	check(rebuilt == wav, "build_wav writes the same bytes as the hand-built file")
	var again := AudioUtil.parse_wav(AudioUtil.build_wav(pcm, 16000, 1))
	check(again["ok"] and again["rate"] == 16000 and again["frames"] == 2400, "a built WAV reads back")

	check(not AudioUtil.parse_wav(PackedByteArray([1, 2, 3]))["ok"], "garbage is rejected")
	check(not AudioUtil.parse_wav("RIFF0000WAVEjunk".to_ascii_buffer())["ok"], "truncated header is rejected")

	check(AudioUtil.wer("hello there dear", "hello there dear") == 0.0, "identical text has WER 0")
	check(absf(AudioUtil.wer("hello there dear", "hello dear") - 1.0 / 3.0) < 0.001, "one missing word is 1/3")
	check(AudioUtil.wer("Hello, there! Dear.", "hello there dear") == 0.0, "case and punctuation are ignored")
	check(AudioUtil.wer("a b c d", "x y z w") == 1.0, "all wrong is 1.0")
	check(AudioUtil.wer("", "") == 0.0 and AudioUtil.wer("", "word") == 1.0, "empty reference")

	print("\n%s" % ("ALL PASSED" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
