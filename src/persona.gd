class_name Persona
extends RefCounted
## Caller personas: one JSON file per caller in `callers/` (and later `user://callers/`).
## A bad file is skipped with a warning and never crashes the game.

const REQUIRED_KEYS := ["id", "name", "age", "savings", "gullibility", "quirks", "voice", "is_scambaiter"]
const MAX_QUIRKS := 6
const MAX_AGE := 999  ## only used in the prompt, so aliens and ghosts are welcome
const BUILTIN_DIR := "res://callers"
const USER_DIR := "user://callers"  ## the player's own callers (mods); see MODDING.md
## Optional key `kokoro_voice`: a NobodyWho/Kokoro voice id such as bf_emma (British woman), am_michael (American man).
## Without it the voice is chosen from `voice` (the language code) and the persona id.
const KOKORO_VOICE_PATTERN := "^[a-z]{2}_[a-z]+$"


## Returns "" when `data` is a usable persona, otherwise a short reason.
static func validate(data: Variant) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "top level is not a JSON object"
	for key in REQUIRED_KEYS:
		if not data.has(key):
			return "missing key '%s'" % key
	if typeof(data["id"]) != TYPE_STRING or not (data["id"] as String).strip_edges().is_valid_identifier():
		return "'id' must be a word made of letters, digits and underscores"
	if typeof(data["name"]) != TYPE_STRING or (data["name"] as String).strip_edges().is_empty():
		return "'name' must be a non-empty string"
	for key in ["age", "savings", "gullibility"]:
		if typeof(data[key]) != TYPE_FLOAT and typeof(data[key]) != TYPE_INT:
			return "'%s' must be a number" % key
	if typeof(data["quirks"]) != TYPE_ARRAY:
		return "'quirks' must be a list of strings"
	for q in data["quirks"]:
		if typeof(q) != TYPE_STRING:
			return "'quirks' must be a list of strings"
	if typeof(data["voice"]) != TYPE_STRING:
		return "'voice' must be a language code string such as en-GB"
	if typeof(data["is_scambaiter"]) != TYPE_BOOL:
		return "'is_scambaiter' must be true or false"
	if data.has("kokoro_voice") and (typeof(data["kokoro_voice"]) != TYPE_STRING or not RegEx.create_from_string(KOKORO_VOICE_PATTERN).search(data["kokoro_voice"])):
		return "'kokoro_voice' must look like bf_emma (two letters, an underscore, a name)"
	return ""


## Clean copy of a valid persona: numbers clamped, strings trimmed, extra quirks dropped.
static func normalize(data: Dictionary) -> Dictionary:
	var quirks: Array[String] = []
	for q in data["quirks"]:
		var s := (q as String).strip_edges()
		if not s.is_empty() and quirks.size() < MAX_QUIRKS:
			quirks.append(s)
	var out := {
		"id": (data["id"] as String).strip_edges(),
		"name": (data["name"] as String).strip_edges(),
		"age": clampi(int(data["age"]), 1, MAX_AGE),
		"savings": maxi(int(data["savings"]), 0),
		"gullibility": clampf(float(data["gullibility"]), 0.0, 1.0),
		"quirks": quirks,
		"voice": (data["voice"] as String).strip_edges(),
		"is_scambaiter": data["is_scambaiter"],
	}
	if data.has("kokoro_voice"):
		out["kokoro_voice"] = data["kokoro_voice"]
	return out


## Loads one persona file. Returns {} (and warns) when the file is missing or invalid.
static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Persona %s: cannot open (%s)" % [path, error_string(FileAccess.get_open_error())])
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("Persona %s: invalid JSON at line %d (%s)" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	var reason := validate(json.data)
	if not reason.is_empty():
		push_warning("Persona %s: %s" % [path, reason])
		return {}
	return normalize(json.data)


## The built-in callers plus the player's own from `user://callers/`. A mod file whose `id` matches a built-in caller replaces it
## (so a mod can retune Gladys); new ids are added; bad files are skipped with a warning and never crash the game. Callers that
## came from the player's folder carry `"mod": true`.
static func load_all(builtin_dir: String = BUILTIN_DIR, user_dir: String = USER_DIR) -> Array[Dictionary]:
	var mods := load_dir(user_dir)
	var replaced := {}
	for m in mods:
		m["mod"] = true
		replaced[m["id"]] = true
	var out: Array[Dictionary] = []
	for p in load_dir(builtin_dir):
		if replaced.has(p["id"]):
			continue
		out.append(p)
	out.append_array(mods)
	return out


## Makes sure the player's folder exists and returns its real path on disk, so the game can say where to put files.
static func ensure_user_dir(user_dir: String = USER_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(user_dir)
	return ProjectSettings.globalize_path(user_dir)


## Loads every `*.json` file in a folder, skipping bad ones and files whose id was already loaded.
static func load_dir(dir_path: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen := {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return found
	var names := DirAccess.get_files_at(dir_path)
	names.sort()
	for file_name in names:
		if not file_name.ends_with(".json"):
			continue
		var persona := load_file(dir_path.path_join(file_name))
		if persona.is_empty():
			continue
		if seen.has(persona["id"]):
			push_warning("Persona %s: id '%s' is already loaded, skipped" % [file_name, persona["id"]])
			continue
		seen[persona["id"]] = true
		found.append(persona)
	return found
