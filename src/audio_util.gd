class_name AudioUtil
extends RefCounted
## Small audio helpers for the voice tests: read a WAV from memory, convert it to the mono 16 kHz speech-to-text expects,
## and score a transcript against the sentence that was spoken (word error rate).


## Reads a RIFF/WAVE byte array (16-bit PCM or 32-bit float). Returns
## {ok, rate, channels, bits, float, frames, seconds, data_offset, data_length, samples: PackedFloat32Array (interleaved, -1..1)}
## or {ok: false, reason}. `decode` false skips building `samples` (a loop over every sample is slow in GDScript); the header
## fields and the position of the audio data are still filled in.
static func parse_wav(bytes: PackedByteArray, decode := true) -> Dictionary:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {"ok": false, "reason": "not a RIFF/WAVE file (%d bytes)" % bytes.size()}
	var pos := 12
	var rate := 0
	var channels := 0
	var bits := 0
	var tag := 0
	var data_start := -1
	var data_len := 0
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if id == "fmt ":
			tag = bytes.decode_u16(pos + 8)
			channels = bytes.decode_u16(pos + 10)
			rate = bytes.decode_u32(pos + 12)
			bits = bytes.decode_u16(pos + 22)
		elif id == "data":
			data_start = pos + 8
			data_len = mini(size, bytes.size() - data_start)  # streamed files may declare a huge size
			break
		pos += 8 + size + (size & 1)
	if data_start < 0 or rate == 0 or channels == 0:
		return {"ok": false, "reason": "missing fmt or data chunk"}
	var is_float := tag == 3 or (tag == 0xFFFE and bits == 32)
	var bytes_per := bits / 8
	if not (bits == 16 or (is_float and bits == 32)):
		return {"ok": false, "reason": "unsupported format: %d-bit, tag %d" % [bits, tag]}
	var count := data_len / bytes_per
	var samples := PackedFloat32Array()
	if decode:
		samples.resize(count)
		for i in count:
			var at := data_start + i * bytes_per
			samples[i] = bytes.decode_float(at) if is_float else bytes.decode_s16(at) / 32768.0
	return {"ok": true, "rate": rate, "channels": channels, "bits": bits, "float": is_float,
			"frames": count / channels, "seconds": float(count / channels) / float(rate), "samples": samples,
			"data_offset": data_start, "data_length": count * bytes_per}


## A WAV file from raw 16-bit little-endian PCM bytes.
static func build_wav(pcm: PackedByteArray, rate: int, channels: int = 1) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(44)
	out.encode_u8(0, 82)  # R
	out.encode_u8(1, 73)  # I
	out.encode_u8(2, 70)  # F
	out.encode_u8(3, 70)  # F
	out.encode_u32(4, 36 + pcm.size())
	for i in 4:
		out.encode_u8(8 + i, "WAVE".unicode_at(i))
		out.encode_u8(12 + i, "fmt ".unicode_at(i))
		out.encode_u8(36 + i, "data".unicode_at(i))
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)
	out.encode_u16(22, channels)
	out.encode_u32(24, rate)
	out.encode_u32(28, rate * channels * 2)
	out.encode_u16(32, channels * 2)
	out.encode_u16(34, 16)
	out.encode_u32(40, pcm.size())
	out.append_array(pcm)
	return out


## Mono float samples at `target_rate` (average the channels, then linear resampling).
static func to_mono_float(wav: Dictionary, target_rate: int) -> PackedFloat32Array:
	var channels: int = wav["channels"]
	var src: PackedFloat32Array = wav["samples"]
	var frames: int = wav["frames"]
	var mono := PackedFloat32Array()
	mono.resize(frames)
	for f in frames:
		var sum := 0.0
		for c in channels:
			sum += src[f * channels + c]
		mono[f] = sum / channels
	var rate: int = wav["rate"]
	if rate == target_rate:
		return mono
	var out_frames := int(float(frames) * float(target_rate) / float(rate))
	var out := PackedFloat32Array()
	out.resize(out_frames)
	var step := float(rate) / float(target_rate)
	for i in out_frames:
		var pos := float(i) * step
		var i0 := int(pos)
		var i1 := mini(i0 + 1, frames - 1)
		var frac := pos - float(i0)
		out[i] = mono[i0] * (1.0 - frac) + mono[i1] * frac
	return out


## Mono 16-bit little-endian PCM bytes at `target_rate`, the input `NobodyWhoSpeechToText.transcribe_pcm()` takes.
static func to_pcm16_bytes(wav: Dictionary, target_rate: int) -> PackedByteArray:
	var mono := to_mono_float(wav, target_rate)
	var out := PackedByteArray()
	out.resize(mono.size() * 2)
	for i in mono.size():
		out.encode_s16(i * 2, clampi(roundi(mono[i] * 32767.0), -32768, 32767))
	return out


## Lower-case words with punctuation removed, for comparing a transcript with what was spoken.
static func words_of(text: String) -> PackedStringArray:
	var cleaned := ""
	for ch in text.to_lower():
		cleaned += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "'" else " "
	return cleaned.split(" ", false)


## Word error rate: edit distance between the word lists divided by the length of the reference. 0.0 is perfect.
static func wer(reference: String, hypothesis: String) -> float:
	var r := words_of(reference)
	var h := words_of(hypothesis)
	if r.is_empty():
		return 0.0 if h.is_empty() else 1.0
	var prev := PackedInt32Array()
	prev.resize(h.size() + 1)
	for j in h.size() + 1:
		prev[j] = j
	for i in range(1, r.size() + 1):
		var cur := PackedInt32Array()
		cur.resize(h.size() + 1)
		cur[0] = i
		for j in range(1, h.size() + 1):
			var cost := 0 if r[i - 1] == h[j - 1] else 1
			cur[j] = mini(mini(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
		prev = cur
	return float(prev[h.size()]) / float(r.size())
