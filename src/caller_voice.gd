class_name CallerVoice
extends RefCounted
## The caller's voice: the operating system's text-to-speech through `DisplayServer.tts_speak`, one voice per persona.
## Robotic is on purpose, it fits the comedy. Windows only exposes the older SAPI voices, so there may be only a few.

static var muted := false  ## tests set this so nothing plays out loud


## Every voice the OS offers: [{id, name, language}], sorted by id so the choice below never changes between runs.
static func voices() -> Array:
	var list: Array = DisplayServer.tts_get_voices()
	list.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return list


## The voice, pitch and rate for a persona. Prefers an exact language match (en-GB), then the same language (en), then
## anything. The persona's id picks the voice, so two callers with the same language usually sound different.
static func pick(persona: Dictionary) -> Dictionary:
	var all := voices()
	if all.is_empty():
		return {}
	var wanted := String(persona.get("voice", "en")).replace("_", "-").to_lower()
	var primary := wanted.split("-")[0]
	var exact := all.filter(func(v): return String(v["language"]).replace("_", "-").to_lower() == wanted)
	var same := all.filter(func(v): return String(v["language"]).replace("_", "-").to_lower().split("-")[0] == primary)
	var pool: Array = exact if not exact.is_empty() else (same if not same.is_empty() else all)
	var h := String(persona.get("id", "")).hash()
	var voice: Dictionary = pool[h % pool.size()]
	return {
		"id": voice["id"], "name": voice["name"], "language": voice["language"],
		"pitch": 0.85 + float((h >> 3) % 7) * 0.05,  # 0.85 to 1.15
		"rate": 0.95 + float((h >> 7) % 4) * 0.05,  # 0.95 to 1.10
	}


static func speak(text: String, persona: Dictionary) -> void:
	var v := pick(persona)
	if v.is_empty():
		return  # no voices on this system: the transcript is the fallback
	DisplayServer.tts_speak(text, v["id"], 0 if muted else 80, v["pitch"], v["rate"], 0, true)  # volume 0 when muted: silent, same timing


static func stop() -> void:
	DisplayServer.tts_stop()
